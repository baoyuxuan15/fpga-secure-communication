"""Unit tests for pc/demo.py; no FPGA or physical serial port is needed."""

import contextlib
import io
import pathlib
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import demo
import serial
from reference import reply, request, transform


class FakeSerial:
    """The test double replaces pyserial, not reference.py or demo.py."""

    instances = []
    constructor_error = None
    write_error = None

    def __init__(self, **settings):
        self.settings = settings
        self.timeout = settings["timeout"]
        self.closed = False
        self.clear_count = 0
        self.writes = []
        self.read_sizes = []
        self.read_chunks = [reply(settings.pop("reply_led_on", True))]
        type(self).instances.append(self)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.closed = True

    def reset_input_buffer(self):
        self.clear_count += 1

    def write(self, data):
        if type(self).write_error is not None:
            raise type(self).write_error
        self.writes.append(data)
        return len(data)

    def read(self, size):
        self.read_sizes.append(size)
        return self.read_chunks.pop(0) if self.read_chunks else b""


class ReceiveTests(unittest.TestCase):
    def test_segmented_read_accumulates_exact_frame(self):
        data = bytes(range(16))
        port = mock.Mock()
        timeouts = []
        def read(_size):
            timeouts.append(port.timeout)
            return [data[:1], b"", data[1:8], data[8:]][len(timeouts) - 1]
        port.read.side_effect = read
        self.assertEqual(demo.receive_frame(port), data)
        self.assertEqual(port.read.call_args_list, [
            mock.call(16), mock.call(15), mock.call(15), mock.call(8)
        ])
        for timeout in timeouts:
            self.assertGreater(timeout, 0)
            self.assertLessEqual(timeout, demo.TIMEOUT_SECONDS)

    def test_all_reads_share_one_deadline(self):
        port = mock.Mock()
        port.read.return_value = b""
        now = iter([0.0, 1.5, 1.8, 2.1])
        with self.assertRaisesRegex(demo.CommunicationError, "0/16"):
            demo.receive_frame(port, clock=lambda: next(now))
        self.assertAlmostEqual(port.timeout, 0.2)

    def test_short_read_timeout_reports_partial_bytes(self):
        port = mock.Mock()
        port.read.side_effect = [b"\x01\x02", b""]
        with self.assertRaisesRegex(demo.CommunicationError, "2/16.*0102"):
            demo.receive_frame(port, clock=mock.Mock(side_effect=[0, 0, 0.1, 2.1]))
        self.assertEqual(port.read.call_count, 2)


class ReplyTests(unittest.TestCase):
    def test_expected_success_replies(self):
        for command, state in (("on", 1), ("off", 0)):
            plain = bytes([0xA0, state]) + bytes(14)
            self.assertIsNone(demo.reply_error(plain, command))

    def test_rejects_bad_marker_state_padding_mismatch_and_error(self):
        cases = [
            (bytes([0xB0, 1]) + bytes(14), "首字节"),
            (bytes([0xA0, 2]) + bytes(14), "灯状态"),
            (bytes([0xA0, 1]) + bytes(13) + b"\x01", "末 14"),
            (bytes([0xA0, 0]) + bytes(14), "不一致"),
            (bytes([0xE0, 1]) + bytes(14), "非法命令"),
        ]
        for plain, message in cases:
            with self.subTest(message=message):
                self.assertIn(message, demo.reply_error(plain, "on"))

    def test_common_encrypted_vectors(self):
        self.assertEqual(
            request(True).hex(), "e37cd363dd7c87a09aff0e3e60e09c82"
        )
        self.assertEqual(
            request(False).hex(), "c6a13b37878f5b826f4f8162a1c8d879"
        )
        for state in (False, True):
            plain = bytes([0xA0, int(state)]) + bytes(14)
            self.assertEqual(transform(reply(state), decrypt=True), plain)


@mock.patch.object(demo.serial, "Serial", FakeSerial)
class ExchangeTests(unittest.TestCase):
    def setUp(self):
        FakeSerial.instances.clear()
        FakeSerial.constructor_error = None
        FakeSerial.write_error = None
        self.addCleanup(setattr, FakeSerial, "write", FakeSerial.write)
        self.addCleanup(setattr, FakeSerial, "read", FakeSerial.read)
        self.addCleanup(setattr, FakeSerial, "__init__", FakeSerial.__init__)

    def exchange(self, command, reply_data, read_impl=None):
        def read(self, size):
            self.read_sizes.append(size)
            return self.read_chunks.pop(0) if self.read_chunks else b""

        def init(self, **settings):
            self.settings = settings
            self.timeout = settings["timeout"]
            self.closed = False
            self.clear_count = 0
            self.writes = []
            self.read_sizes = []
            self.read_chunks = list(reply_data) if isinstance(reply_data, list) else [reply_data]
            type(self).instances.append(self)

        FakeSerial.read = read_impl or read
        FakeSerial.__init__ = init
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            with mock.patch.object(demo.sys, "argv", ["demo.py", "--port", "COM3", "--command", command]):
                result = demo.main()
        return result, FakeSerial.instances[-1], stdout.getvalue(), stderr.getvalue()

    def test_on_exchange_and_serial_settings(self):
        result, port, output, errors = self.exchange(
            "on", [reply(True)[:5], reply(True)[5:11], reply(True)[11:]]
        )
        self.assertEqual(result, 0)
        self.assertEqual(errors, "")
        self.assertEqual(port.writes, [request(True)])
        self.assertEqual(port.read_sizes, [16, 11, 5])
        self.assertEqual(port.clear_count, 1)
        self.assertTrue(port.closed)
        self.assertEqual(port.settings["baudrate"], 115200)
        self.assertEqual(port.settings["bytesize"], serial.EIGHTBITS)
        self.assertEqual(port.settings["parity"], serial.PARITY_NONE)
        self.assertEqual(port.settings["stopbits"], serial.STOPBITS_ONE)
        self.assertFalse(port.settings["xonxoff"])
        self.assertFalse(port.settings["rtscts"])
        self.assertFalse(port.settings["dsrdtr"])
        self.assertIn("e37cd363dd7c87a09aff0e3e60e09c82", output)
        self.assertIn("b026dbf27fcdfabeeab01ed0cb78ac66", output)
        self.assertIn("a0010000000000000000000000000000", output)
        self.assertIn("PASS", output)

    def test_off_exchange(self):
        result, port, output, _ = self.exchange("off", reply(False))
        self.assertEqual(result, 0)
        self.assertEqual(port.writes, [request(False)])
        self.assertIn("966aab7bda958e77dd00c494cfc001d6", output)
        self.assertIn("a0000000000000000000000000000000", output)

    def test_malformed_reply_fails_and_closes(self):
        bad_reply = transform(bytes([0xB0]) + bytes(15))
        result, port, output, _ = self.exchange("on", bad_reply)
        self.assertEqual(result, 1)
        self.assertIn("首字节", output)
        self.assertIn("恢复步骤", output)
        self.assertTrue(port.closed)

    def test_error_reply_and_wrong_state_fail(self):
        for command, plain, text in (
            ("on", bytes([0xE0, 1]) + bytes(14), "非法命令"),
            ("on", bytes([0xA0, 0]) + bytes(14), "不一致"),
        ):
            result, port, output, _ = self.exchange(command, transform(plain))
            self.assertEqual(result, 1)
            self.assertIn(text, output)
            self.assertTrue(port.closed)

    def test_short_read_timeout_and_zero_reply(self):
        result, port, _, errors = self.exchange("on", [b"\x12\x34", b""])
        self.assertEqual(result, 2)
        self.assertIn("2/16", errors)
        self.assertIn("1234", errors)
        self.assertIn("恢复步骤", errors)
        self.assertEqual(len(port.writes), 1)
        self.assertTrue(port.closed)

        result, _, _, errors = self.exchange("on", [])
        self.assertEqual(result, 2)
        self.assertIn("0/16", errors)

    def test_serial_open_and_read_failures_are_clear(self):
        FakeSerial.__init__ = lambda self, **settings: (_ for _ in ()).throw(
            serial.SerialException("cannot open port")
        )
        with self.assertRaisesRegex(demo.CommunicationError, "通信失败"):
            demo.run("COM3", "on")

        def fail_read(self, size):
            raise serial.SerialException("device disconnected")
        FakeSerial.read = fail_read
        result, port, _, errors = self.exchange("on", [], read_impl=fail_read)
        self.assertEqual(result, 2)
        self.assertIn("device disconnected", errors)
        self.assertTrue(port.closed)

    def test_short_write_fails_without_reading(self):
        FakeSerial.write = lambda self, data: len(data) - 1
        result, port, _, errors = self.exchange("on", reply(True))
        self.assertEqual(result, 2)
        self.assertIn("15/16", errors)
        self.assertEqual(port.read_sizes, [])
        self.assertTrue(port.closed)

    def test_write_timeout_is_handled(self):
        FakeSerial.write_error = serial.SerialTimeoutException("write timeout")
        result, port, _, errors = self.exchange("on", reply(True))
        self.assertEqual(result, 2)
        self.assertIn("write timeout", errors)
        self.assertTrue(port.closed)


if __name__ == "__main__":
    unittest.main(verbosity=2)
