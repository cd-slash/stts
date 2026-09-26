"""Authenticated bridge for a Linux USB gadget or serial-controlled keyboard.

Serial protocol: PING\n -> PONG\n; TYPE <byte-count>\n<ASCII bytes> -> OK\n.
The device acknowledges only after sending all HID key reports.
"""

import hmac
import json
import os
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAX_TEXT = 4096
VALID_TEXT = re.compile(r"^[\x20-\x7e\t\n]+$")
PORT = os.environ.get("STTS_KEYBOARD_PORT")
HIDG = os.environ.get("STTS_KEYBOARD_HIDG")
if not bool(PORT) ^ bool(HIDG):
    raise ValueError("Set exactly one of STTS_KEYBOARD_PORT or STTS_KEYBOARD_HIDG")
TOKEN = os.environ["STTS_KEYBOARD_TOKEN"]
if not TOKEN:
    raise ValueError("STTS_KEYBOARD_TOKEN must not be empty")
BAUD = int(os.environ.get("STTS_KEYBOARD_BAUD", "921600"))
LOCK = threading.Lock()

# Standard boot-keyboard report: modifier, reserved, keycode, five zeroes.
LOWER = {chr(97 + i): 4 + i for i in range(26)}
LOWER.update({str(i): 0x1D + i for i in range(1, 10)})
LOWER["0"] = 0x27
LOWER.update({
    "\n": 0x28, "\t": 0x2B, " ": 0x2C, "-": 0x2D, "=": 0x2E,
    "[": 0x2F, "]": 0x30, "\\": 0x31, ";": 0x33, "'": 0x34,
    "`": 0x35, ",": 0x36, ".": 0x37, "/": 0x38,
})
SHIFTED = dict(zip("!@#$%^&*()_+{}|:\"~<>?", "1234567890-=[]\\;'`,./"))


def report(character: str) -> bytes:
    base = SHIFTED.get(character, character.lower())
    modifier = 2 if character in SHIFTED or character.isupper() else 0
    return bytes((modifier, 0, LOWER[base], 0, 0, 0, 0, 0))


def type_gadget(text: str):
    with open(HIDG, "wb", buffering=0) as device:
        try:
            for character in text:
                if device.write(report(character)) != 8 or device.write(bytes(8)) != 8:
                    raise OSError("Short HID report")
                # Allow the host's keyboard polling interval to observe both reports.
                time.sleep(0.002)
        finally:
            # Best effort: never intentionally leave a modifier held after failure.
            try:
                device.write(bytes(8))
            except OSError:
                pass


def gadget_ready() -> bool:
    try:
        with open("/sys/kernel/config/usb_gadget/stts_keyboard/UDC", encoding="ascii") as bound:
            return bool(bound.read().strip()) and os.access(HIDG, os.W_OK)
    except OSError:
        return False


def exchange(command: bytes, payload: bytes = b"", timeout: float = 30) -> bytes:
    import serial  # pyserial is required only in serial mode.
    # Open only for a request: reconnection after hotplug is automatic.
    with serial.Serial(PORT, BAUD, timeout=timeout, write_timeout=5) as device:
        device.write(command + payload)
        response = device.readline(128)
        if not response.endswith(b"\n"):
            raise OSError("Keyboard did not acknowledge")
        return response.strip()


class Handler(BaseHTTPRequestHandler):
    def reply(self, status: int, body: dict):
        content = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(content)

    def authorized(self) -> bool:
        received = self.headers.get("Authorization", "")
        if not hmac.compare_digest(received.encode("latin-1"), ("Bearer " + TOKEN).encode("utf-8")):
            self.reply(401, {"code": "AUTH_REQUIRED"})
            return False
        return True

    def execute(self, command: bytes, payload: bytes = b""):
        if not LOCK.acquire(blocking=False):
            self.reply(409, {"code": "KEYBOARD_BUSY"})
            return
        try:
            if HIDG:
                if command == b"PING\n":
                    response = b"PONG" if gadget_ready() else b"ERR"
                else:
                    type_gadget(payload.decode("ascii"))
                    response = b"OK"
            else:
                response = exchange(command, payload)
            expected = b"PONG" if command == b"PING\n" else b"OK"
            if response != expected:
                self.reply(503, {"code": "KEYBOARD_UNAVAILABLE"})
            else:
                self.reply(200, {"status": "ok"})
        except (OSError, ValueError):
            self.reply(503, {"code": "KEYBOARD_UNAVAILABLE"})
        finally:
            LOCK.release()

    def do_GET(self):
        if not self.authorized():
            return
        if self.path != "/health":
            return self.reply(404, {"code": "NOT_FOUND"})
        self.execute(b"PING\n")

    def do_POST(self):
        if not self.authorized():
            return
        if self.path != "/type":
            return self.reply(404, {"code": "NOT_FOUND"})
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if size <= 0 or size > 6 * 1024:
                return self.reply(413, {"code": "PAYLOAD_TOO_LARGE"})
            body = json.loads(self.rfile.read(size))
            text = body.get("text") if isinstance(body, dict) else None
            if not isinstance(text, str):
                raise ValueError("Invalid text")
            text = text.replace("\r\n", "\n").replace("\r", "\n")
            if not 0 < len(text) <= MAX_TEXT or not VALID_TEXT.fullmatch(text):
                raise ValueError("Invalid text")
        except (ValueError, UnicodeError):
            return self.reply(400, {"code": "INVALID_REQUEST"})
        encoded = text.encode("ascii")
        self.execute(f"TYPE {len(encoded)}\n".encode("ascii"), encoded)


if __name__ == "__main__":
    # Default loopback; a USB-gadget installation binds only to its private USB IP.
    ThreadingHTTPServer((os.environ.get("STTS_KEYBOARD_LISTEN_HOST", "127.0.0.1"),
                         int(os.environ.get("STTS_KEYBOARD_LISTEN_PORT", "8778"))), Handler).serve_forever()
