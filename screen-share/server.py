#!/usr/bin/env python3
"""Local screen-share signaling. Media travels directly between browsers."""
import json, secrets, threading
from qr import png
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlsplit, parse_qs

KEY = secrets.token_urlsafe(18)
LOCK = threading.Lock()
MESSAGES = []
NEXT = 0
ROOT = Path(__file__).parent

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # Keep the pairing key out of access logs.

    def reply(self, code, data, mime='application/json'):
        if not isinstance(data, bytes):
            data = json.dumps(data).encode()
        self.send_response(code)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(data)

    def params(self):
        u = urlsplit(self.path)
        return u.path, parse_qs(u.query)

    def authorized(self, q):
        role = q.get('role', ['viewer'])[0]
        return (secrets.compare_digest(q.get('key', [''])[0], KEY)
                and role in ('sender', 'viewer')
                and (role != 'sender' or self.client_address[0] == '127.0.0.1'))

    def do_GET(self):
        path, q = self.params()
        if path == '/qr.png' and self.client_address[0] == '127.0.0.1':
            return self.reply(200, png('http://192.168.0.214:8765/?key=' + KEY), 'image/png')
        if path == '/sender' and self.client_address[0] == '127.0.0.1':
            body = (ROOT / 'index.html').read_text().replace('__ROLE__', 'sender').replace('__KEY__', KEY)
            return self.reply(200, body.encode(), 'text/html; charset=utf-8')
        if path == '/' and self.authorized(q):
            body = (ROOT / 'index.html').read_text().replace('__ROLE__', 'viewer').replace('__KEY__', KEY)
            return self.reply(200, body.encode(), 'text/html; charset=utf-8')
        if path == '/api/poll' and self.authorized(q):
            try:
                after = int(q.get('after', ['0'])[0])
            except ValueError:
                return self.reply(400, {'error':'Invalid cursor'})
            with LOCK:
                result = [m for m in MESSAGES if m['to'] == q.get('role',['viewer'])[0] and m['id'] > after]
            return self.reply(200, result)
        return self.reply(403, {'error':'Open the pairing link displayed on the laptop.'})

    def do_POST(self):
        global NEXT
        path, q = self.params()
        if path != '/api/send' or not self.authorized(q):
            return self.reply(403, {})
        # Browser requests must originate from this server.
        origin = self.headers.get('Origin')
        if origin and urlsplit(origin).netloc != self.headers.get('Host'):
            return self.reply(403, {})
        try:
            length = int(self.headers.get('Content-Length','0'))
            if not 0 < length <= 262144:
                return self.reply(413, {})
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict) or data.get('type') not in ('ready','offer','answer','ice','stop'):
                return self.reply(400, {})
        except (ValueError, json.JSONDecodeError):
            return self.reply(400, {})
        with LOCK:
            NEXT += 1
            MESSAGES.append({'id':NEXT, 'to':'viewer' if q.get('role', ['viewer'])[0] == 'sender' else 'sender', 'data':data})
            del MESSAGES[:-256]
        self.reply(200, {'ok':True})

if __name__ == '__main__':
    print('Laptop: http://localhost:8765/sender', flush=True)
    print('iPad: http://192.168.0.214:8765/?key=' + KEY, flush=True)
    ThreadingHTTPServer(('0.0.0.0',8765), Handler).serve_forever()
