"""Run with: STTS_KEYBOARD_PORT=/dev/null STTS_KEYBOARD_TOKEN=test python3 -m unittest test_bridge.py"""

import http.client
import os
import sys
import threading
import types
import unittest
from http.server import ThreadingHTTPServer
from unittest.mock import patch

os.environ.setdefault("STTS_KEYBOARD_PORT", "/dev/null")
os.environ.setdefault("STTS_KEYBOARD_TOKEN", "test")
sys.modules.setdefault("serial", types.SimpleNamespace(SerialException=OSError))
import bridge  # noqa: E402


class BridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), bridge.Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def request(self, method, path, body=b"", token="Bearer test"):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port)
        connection.request(method, path, body, {"Authorization": token})
        response = connection.getresponse()
        code = response.status
        response.read()
        connection.close()
        return code

    def test_unauthorized_requests_do_not_touch_serial(self):
        with patch.object(bridge, "exchange") as exchange:
            self.assertEqual(self.request("POST", "/type", b'{"text":"hi"}', "wrong"), 401)
            exchange.assert_not_called()

    def test_valid_text_is_length_framed_and_acknowledged(self):
        with patch.object(bridge, "exchange", return_value=b"OK") as exchange:
            self.assertEqual(self.request("POST", "/type", b'{"text":"Hi\\n!"}'), 200)
            exchange.assert_called_once_with(b"TYPE 4\n", b"Hi\n!")

    def test_rejects_invalid_input_before_emitting_keypresses(self):
        with patch.object(bridge, "exchange") as exchange:
            self.assertEqual(self.request("POST", "/type", b'{"text":"\\u00e9"}'), 400)
            self.assertEqual(self.request("POST", "/type", b'{"text":""}'), 400)
            exchange.assert_not_called()

    def test_health_requires_firmware_pong(self):
        with patch.object(bridge, "exchange", return_value=b"PONG") as exchange:
            self.assertEqual(self.request("GET", "/health"), 200)
            exchange.assert_called_once_with(b"PING\n", b"")

    def test_gadget_reports_us_layout_and_releases_each_key(self):
        self.assertEqual(bridge.report("A"), bytes([2, 0, 4, 0, 0, 0, 0, 0]))
        self.assertEqual(bridge.report("!"), bytes([2, 0, 0x1E, 0, 0, 0, 0, 0]))
        self.assertEqual(bridge.report("\n"), bytes([0, 0, 0x28, 0, 0, 0, 0, 0]))
        with patch.object(bridge, "HIDG", "/dev/hidg0"), \
             patch.object(bridge, "open", create=True) as device, \
             patch.object(bridge.time, "sleep"):
            device.return_value.__enter__.return_value.write.return_value = 8
            bridge.type_gadget("A!")
            self.assertEqual(device.return_value.__enter__.return_value.write.call_count, 5)


if __name__ == "__main__":
    unittest.main()
