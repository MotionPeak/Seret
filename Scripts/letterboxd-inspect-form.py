#!/usr/bin/env python3
"""Read the Letterboxd diary form's field names out of the NAS browser.

Drives the signed-in Chromium over the DevTools protocol and dumps the fields of
`form[action="/s/save-diary-entry"]`. Read-only: it navigates and reads the DOM. It submits
nothing, so no diary entry is created.

Pure stdlib — the NAS has no node and no websocket-client.

    python3 letterboxd-inspect-form.py [film-url]
"""
import base64, json, os, socket, struct, sys, time, urllib.request

CDP = "http://127.0.0.1:9223"
FILM = sys.argv[1] if len(sys.argv) > 1 else "https://letterboxd.com/film/speed/"


def page_target():
    with urllib.request.urlopen(CDP + "/json", timeout=10) as r:
        targets = json.load(r)
    pages = [t for t in targets
             if t.get("type") == "page" and "letterboxd.com" in (t.get("url") or "")]
    if not pages:
        pages = [t for t in targets if t.get("type") == "page"]
    if not pages:
        sys.exit("no page target on the browser")
    return pages[0]["webSocketDebuggerUrl"]


class WS:
    """The smallest client that can carry CDP: handshake, masked text frames, read frames."""

    def __init__(self, url):
        _, rest = url.split("://", 1)
        hostport, path = rest.split("/", 1)
        host, port = hostport.split(":")
        self.path = "/" + path
        self.sock = socket.create_connection((host, int(port)), timeout=20)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((
            f"GET {self.path} HTTP/1.1\r\nHost: {hostport}\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        ).encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            buf += self.sock.recv(4096)
        if b"101" not in buf.split(b"\r\n")[0]:
            sys.exit("websocket upgrade refused: " + buf.split(b"\r\n")[0].decode())
        self.buf = buf.split(b"\r\n\r\n", 1)[1]

    def _recv(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                sys.exit("connection closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def send(self, obj):
        payload = json.dumps(obj).encode()
        header = bytes([0x81])
        n = len(payload)
        mask = os.urandom(4)
        if n < 126:
            header += bytes([0x80 | n])
        elif n < 1 << 16:
            header += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            header += bytes([0x80 | 127]) + struct.pack(">Q", n)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(header + mask + masked)

    def recv(self):
        b0, b1 = self._recv(2)
        n = b1 & 0x7F
        if n == 126:
            n = struct.unpack(">H", self._recv(2))[0]
        elif n == 127:
            n = struct.unpack(">Q", self._recv(8))[0]
        return json.loads(self._recv(n).decode())

    def call(self, msg_id, method, params=None, wait=True):
        self.send({"id": msg_id, "method": method, "params": params or {}})
        if not wait:
            return None
        while True:
            msg = self.recv()
            if msg.get("id") == msg_id:
                return msg


EXPRESSION = r"""
(() => {
  const f = document.querySelector('form[action="/s/save-diary-entry"]');
  if (!f) {
    return { found: false,
             forms: [...document.querySelectorAll('form')].map(x => x.getAttribute('action')).slice(0, 12) };
  }
  const fields = [...f.querySelectorAll('input, select, textarea')].map(e => ({
    tag: e.tagName,
    type: e.getAttribute('type'),
    name: e.getAttribute('name'),
    id: e.getAttribute('id'),
    value: (e.getAttribute('value') || '').slice(0, 30)
  }));
  const steps = [...f.querySelectorAll('[data-js-wizard-step]')]
                  .map(e => e.getAttribute('data-js-wizard-step'));
  return { found: true, method: f.getAttribute('method'), action: f.getAttribute('action'),
           steps, fields };
})()
"""

ws = WS(page_target())
ws.call(1, "Page.enable")
ws.call(2, "Page.navigate", {"url": FILM})
time.sleep(8)
result = ws.call(3, "Runtime.evaluate", {"expression": EXPRESSION, "returnByValue": True})
print(json.dumps(result.get("result", {}).get("result", {}).get("value", result), indent=2))
