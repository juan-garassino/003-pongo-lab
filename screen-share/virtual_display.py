"""GNOME virtual monitor capture, using the laptop's existing system libraries."""
import gi

gi.require_version('Gio', '2.0')
gi.require_version('Gst', '1.0')
from gi.repository import Gio, GLib, Gst

class VirtualDisplay:
    def __init__(self, on_frame, width=1024, height=768):
        Gst.init(None)
        self.on_frame = on_frame
        self.width, self.height = width, height
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.session = None
        self.pipeline = None
        self.subscription = None

    def call(self, path, interface, method, args=None):
        return self.bus.call_sync('org.gnome.Mutter.ScreenCast', path, interface,
                                  method, args, None, Gio.DBusCallFlags.NONE, 5000, None)

    def start(self):
        self.session = self.call('/org/gnome/Mutter/ScreenCast',
            'org.gnome.Mutter.ScreenCast', 'CreateSession', GLib.Variant('(a{sv})', ({},))).unpack()[0]
        stream = self.call(self.session, 'org.gnome.Mutter.ScreenCast.Session',
            'RecordVirtual', GLib.Variant('(a{sv})', ({
                'cursor-mode': GLib.Variant('u', 1),
                'is-platform': GLib.Variant('b', True),
            },))).unpack()[0]
        self.subscription = self.bus.signal_subscribe('org.gnome.Mutter.ScreenCast',
            'org.gnome.Mutter.ScreenCast.Stream', 'PipeWireStreamAdded', stream,
            None, Gio.DBusSignalFlags.NONE, self.stream_added)
        self.call(self.session, 'org.gnome.Mutter.ScreenCast.Session', 'Start')

    def stream_added(self, connection, sender, path, interface, signal, args):
        node = args.unpack()[0]
        print('Virtual display PipeWire node:', node, flush=True)
        self.pipeline = Gst.parse_launch(
            f'pipewiresrc path={node} keepalive-time=1000 ! '
            f'video/x-raw,width={self.width},height={self.height},framerate=0/1,max-framerate=20/1 ! '
            'videoconvert ! jpegenc quality=75 ! fakesink name=frames signal-handoffs=true sync=false')
        self.pipeline.get_by_name('frames').connect('handoff', self.frame)
        bus = self.pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect('message::error', self.error)
        self.pipeline.set_state(Gst.State.PLAYING)

    def frame(self, sink, buffer, pad):
        self.on_frame(buffer.extract_dup(0, buffer.get_size()))

    def error(self, bus, message):
        err, debug = message.parse_error()
        print('Capture error:', err, debug, flush=True)

    def stop(self):
        if self.pipeline:
            self.pipeline.set_state(Gst.State.NULL)
            self.pipeline = None
        if self.subscription:
            self.bus.signal_unsubscribe(self.subscription)
            self.subscription = None
        if self.session:
            try:
                self.call(self.session, 'org.gnome.Mutter.ScreenCast.Session', 'Stop')
            except GLib.Error:
                pass
            self.session = None

if __name__ == '__main__':
    count = [0]
    def frame(data):
        count[0] += 1
        if count[0] == 1:
            print('First JPEG received:', len(data), 'bytes', flush=True)
    display = VirtualDisplay(frame)
    loop = GLib.MainLoop()
    def finish():
        display.stop()
        print('Frames received:', count[0], flush=True)
        loop.quit()
        return False
    try:
        display.start()
        GLib.timeout_add_seconds(15, finish)
        loop.run()
    finally:
        display.stop()
