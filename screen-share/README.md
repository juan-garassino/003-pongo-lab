# Local screen sharing

Run `python3 screen-share/server.py` from the project root. This uses Python's
standard library and browser WebRTC; there are no external app dependencies.

On the laptop, open http://localhost:8765/sender in Chrome and select a window.
Open the private pairing link shown there in iPad Safari on the same Wi-Fi.
The current LAN address is configured as 192.168.0.214 in the server and page;
update both if the laptop changes address. Only one sender and viewer are supported.
The pairing link changes when the server restarts.

The first version shares video only, without audio or remote input. It mirrors
a selected window or screen, not an extended desktop. No cloud signaling or
external ICE servers are used. Use Stop sharing or Chrome's sharing control
to stop capture. Screen data uses the browser's encrypted WebRTC transport;
local HTTP carries pairing and signaling, so use a trusted local network.

Verified: JavaScript syntax, HTTP serving, pairing-key checks, signaling message
routing, and rejection of cross-origin POSTs. Actual iOS 12 playback is pending.
