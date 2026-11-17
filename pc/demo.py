"""Send one encrypted control command and validate its 16-byte FPGA reply.

Run from the repository root, for example:
    python pc/demo.py --port COM3 --command on
    python pc/demo.py --port COM3 --command arm  # secure_alarm revision
"""

import argparse
import sys
import time

import serial

try:
    from .reference import request, transform
except ImportError:  # Direct execution: python pc/demo.py
    from reference import request, transform

FRAME_SIZE = 16
BAUD_RATE = 115200
TIMEOUT_SECONDS = 2.0
RECOVERY_HINT = (
    "恢复步骤：复位 FPGA，重新运行本程序以清空电脑端串口缓存，"
    "再发送一条完整命令；每次调用只发送一次。"
)


class CommunicationError(Exception):
    """The serial request could not be completed."""


class ReplyError(Exception):
    """A complete reply was received but did not match the request."""


def receive_frame(port, timeout=TIMEOUT_SECONDS, clock=None):
    """Read one frame, limiting the whole receive operation to timeout seconds."""
    if clock is None:
        clock = time.monotonic
    received = bytearray()
    deadline = clock() + timeout

    while len(received) < FRAME_SIZE:
        remaining = deadline - clock()
        if remaining <= 0:
            break
        # pyserial's timeout is per read, so reduce it to the remaining budget.
        port.timeout = min(TIMEOUT_SECONDS, remaining)
        chunk = port.read(FRAME_SIZE - len(received))
        if chunk:
            received.extend(chunk)

    if len(received) != FRAME_SIZE:
        raise CommunicationError(
            f"等待回执超时（{timeout:g} 秒）：已收到 {len(received)}/{FRAME_SIZE} "
            f"字节，数据为 {bytes(received).hex() or '（无）'}。"
        )
    # pyserial 的 timeout 只约束单次 read；设置超时到真正开始读取之间还有开销，
    # 最后一段可能在截止时刻之后才返回。收满 16 字节后仍要按同一个绝对截止时刻
    # 复核，避免把迟到的回执判为成功（退出码应为 2 而不是 0）。
    if clock() > deadline:
        raise CommunicationError(
            f"等待回执超时（{timeout:g} 秒）：回执在截止时刻之后才收满 "
            f"{FRAME_SIZE}/{FRAME_SIZE} 字节，数据为 {bytes(received).hex()}。"
        )
    return bytes(received)


def reply_error(plaintext, command):
    """Return a validation error, or None for the expected successful reply."""
    if len(plaintext) != FRAME_SIZE:
        return f"回执明文长度应为 16 字节，实际为 {len(plaintext)} 字节。"
    if plaintext[0] not in (0xA0, 0xE0):
        return f"回执首字节应为 A0 或 E0，实际为 {plaintext[0]:02X}。"
    if plaintext[1] not in (0x00, 0x01):
        return f"回执灯状态应为 00 或 01，实际为 {plaintext[1]:02X}。"
    if plaintext[2:] != bytes(14):
        return "回执末 14 字节必须全为 00。"
    if plaintext[0] == 0xE0:
        return (
            "FPGA 返回非法命令回执 E0；"
            f"灯保持{'亮' if plaintext[1] else '灭'}。"
        )

    expected = int(command in ("on", "arm"))
    if plaintext[1] != expected:
        return (
            f"回执灯状态与 {command} 命令不一致："
            f"期望 {expected:02X}，实际 {plaintext[1]:02X}。"
        )
    return None


def run(port_name, command):
    """Open a serial port, exchange exactly one frame, and always close it."""
    try:
        with serial.Serial(
            port=port_name,
            baudrate=BAUD_RATE,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=TIMEOUT_SECONDS,
            write_timeout=TIMEOUT_SECONDS,
            xonxoff=False,
            rtscts=False,
            dsrdtr=False,
        ) as port:
            port.reset_input_buffer()
            ciphertext = request(command in ("on", "arm"))
            written = port.write(ciphertext)
            if written != FRAME_SIZE:
                raise CommunicationError(
                    f"请求未完整写出：已写入 {written}/{FRAME_SIZE} 字节。"
                )
            print(f"发送密文（{FRAME_SIZE} 字节）：{ciphertext.hex()}")

            encrypted_reply = receive_frame(port)
            print(f"接收密文（{FRAME_SIZE} 字节）：{encrypted_reply.hex()}")
            plaintext = transform(encrypted_reply, decrypt=True)
            print(f"回执明文：{plaintext.hex()}")
            error = reply_error(plaintext, command)
            if error is not None:
                raise ReplyError(error)
    except (serial.SerialException, OSError) as error:
        raise CommunicationError(f"串口 {port_name} 通信失败：{error}") from error

    if command in ("arm", "disarm"):
        print(
            f"判定：PASS，FPGA 报告已{'布防' if command == 'arm' else '撤防'}。"
            "请确认下载的是 secure_alarm，并核对板上 D6。"
            "该回执不包含按键报警、消音或事件计数状态。"
        )
    else:
        print(
            f"判定：PASS，{command} 命令回执有效，"
            f"FPGA 报告灯已{'打开' if command == 'on' else '关闭'}。"
            "请同时人工核对板上 D6 的实际状态。"
        )
    return 0


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="发送一次 AES-128 加密指令：on/off 控灯，报警版用 arm/disarm 布防/撤防。"
    )
    parser.add_argument("--port", required=True, help="串口名称，例如 COM3")
    parser.add_argument("--command", required=True, choices=("on", "off", "arm", "disarm"))
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    try:
        return run(args.port, args.command)
    except ReplyError as error:
        print(f"判定：FAIL，{error}")
        print(RECOVERY_HINT)
        return 1
    except CommunicationError as error:
        print(f"判定：FAIL，{error}", file=sys.stderr)
        print(RECOVERY_HINT, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
