#!/usr/bin/env python3
"""Run one JavaScript expression inside the signed-in Letterboxd page on the NAS browser.

This is how a Letterboxd endpoint gets *measured* rather than guessed. The expression is evaluated
in the page, so it carries the browser's real cookies and fingerprint because it IS the browser's
request — Cloudflare refuses every scripted client outright, with a full valid session and Chrome's
exact User-Agent, so there is no other way to exercise a signed-in call.

It found the watchlist contract: `PATCH /api/v0/me/watchlist/{lid}` with `{"inWatchlist": false}`.
Note that shape — the site's own component calls its state `isInWatchlist` and maps it on the way
out, and sending that name back gets `400 {"error":true,"message":"Unknown property at:
isInWatchlist"}`. The obvious guess is wrong, which is the whole argument for this script existing.

    ssh nas 'cd ~/seret-probe && python3 letterboxd-cdp-eval.py' <<'JS'
    (async () => {
      const meta = await (await fetch('/film/speed/json/', { credentials: 'include' })).json();
      return { lid: meta.lid, hasCsrf: !!meta.csrf };
    })()
    JS

    python3 letterboxd-cdp-eval.py --navigate https://letterboxd.com/film/speed/ < probe.js

Top-level `await` works: the expression is awaited, so an async IIFE returns its resolved value.

RUN IT ON THE NAS. CDP is published on `127.0.0.1:9223` only, and DSM's sshd refuses TCP
forwarding, so it cannot be reached from the Mac. Getting a file there needs a pipe, not scp —
sftp is disabled and there is no writable `/tmp`:

    cat Scripts/letterboxd-cdp-eval.py | ssh nas 'mkdir -p ~/seret-probe && cat > ~/seret-probe/letterboxd-cdp-eval.py'

Pure stdlib, and self-contained despite sharing its websocket plumbing with
`letterboxd-inspect-form.py`: the NAS has no node and no websocket-client, and these scripts are
piped over one at a time, so a shared module would be a file that silently is not there.
"""
import argparse, base64, json, os, socket, struct, sys, time, urllib.request

CDP = "http://127.0.0.1:9223"


def page_target(require_letterboxd=True):
    """The websocket URL of a page target, preferring one already on Letterboxd."""
    with urllib.request.urlopen(CDP + "/json", timeout=10) as r:
        targets = json.load(r)
    pages = [t for t in targets
             if t.get("type") == "page" and "letterboxd.com" in (t.get("url") or "")]
    if not pages and not require_letterboxd:
        pages = [t for t in targets if t.get("type") == "page"]
    if not pages:
        sys.exit("no Letterboxd page open in the browser — is the container signed in?")
    return pages[0]["webSocketDebuggerUrl"]


class WS:
    """The smallest client that can carry CDP: handshake, masked text frames, read frames."""

    def __init__(self, url):
        _, rest = url.split("://", 1)
        hostport, path = rest.split("/", 1)
        host, port = hostport.split(":")
        self.sock = socket.create_connection((host, int(port)), timeout=30)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((
            f"GET /{path} HTTP/1.1\r\nHost: {hostport}\r\n"
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
        n = len(payload)
        header = bytes([0x81])
        if n < 126:
            header += bytes([0x80 | n])
        elif n < 1 << 16:
            header += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            header += bytes([0x80 | 127]) + struct.pack(">Q", n)
        mask = os.urandom(4)
        self.sock.sendall(header + mask
                          + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))

    def recv(self):
        b0, b1 = self._recv(2)
        n = b1 & 0x7F
        if n == 126:
            n = struct.unpack(">H", self._recv(2))[0]
        elif n == 127:
            n = struct.unpack(">Q", self._recv(8))[0]
        frame = self._recv(n)
        if (b0 & 0x0F) != 1:          # not a text frame — ping/pong/binary, skip it
            return None
        return json.loads(frame.decode())

    def call(self, msg_id, method, params=None):
        self.send({"id": msg_id, "method": method, "params": params or {}})
        while True:
            msg = self.recv()
            if msg and msg.get("id") == msg_id:
                return msg


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--navigate", metavar="URL",
                        help="load this page first (a film page carries the session metadata)")
    parser.add_argument("--wait", type=float, default=6.0,
                        help="seconds to let a navigation settle (default 6)")
    parser.add_argument("expression_file", nargs="?",
                        help="file holding the expression; omit to read stdin")
    args = parser.parse_args()

    source = open(args.expression_file, encoding="utf-8") if args.expression_file else sys.stdin
    expression = source.read().strip()
    if not expression:
        sys.exit("no expression given (pass a file, or pipe one in)")

    ws = WS(page_target())
    if args.navigate:
        ws.call(1, "Page.enable")
        ws.call(2, "Page.navigate", {"url": args.navigate})
        # Crude, but a readiness probe is its own round trip and this script is for one-off
        # measurements, not a hot path.
        time.sleep(args.wait)

    reply = ws.call(3, "Runtime.evaluate",
                    {"expression": expression, "awaitPromise": True,
                     "returnByValue": True, "timeout": 30000})

    result = reply.get("result", {})
    # A thrown exception is the interesting case as often as a value is, so surface it whole
    # rather than printing a confusing `undefined`.
    if "exceptionDetails" in result:
        print(json.dumps(result["exceptionDetails"], indent=2))
        sys.exit(1)

    value = result.get("result", {})
    print(json.dumps(value.get("value", value), indent=2))


if __name__ == "__main__":
    main()
