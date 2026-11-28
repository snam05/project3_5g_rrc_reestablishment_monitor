"""Tạo một lần suy hao downlink trong RFsimulator để gây RLF cho NR-UE.

Script chạy bên trong container oai-nr-ue (lab.sh đẩy nó qua stdin vào python3) và nói chuyện
với telnet server của nr-uesoftmodem ở 127.0.0.1:9090. Model 0 (rfsimu_channel_enB0) là kênh
AWGN mà UE áp lên tín hiệu downlink nhận từ gNB.

Thời gian giữ suy hao tính theo đồng hồ mẫu của RFsimulator (lệnh "rfsimu vtime"), không theo
đồng hồ máy, vì RFsimulator có thể chạy chậm hoặc nhanh hơn thời gian thực tùy CPU.
"""

import re
import socket
import time
from argparse import ArgumentParser

TELNET = ("127.0.0.1", 9090)
DOWNLINK_MODEL = 0
DOWNLINK_MODEL_NAME = "rfsimu_channel_enB0"
WALL_TIMEOUT_S = 60


def command(conn, text):
    """Gửi một lệnh telnet và đọc đến prompt "softmodem_5Gue> " mà server gửi sau mỗi lệnh.

    Luôn đọc hết tới prompt: đóng socket sớm đã làm nr-uesoftmodem abort (buffer overflow detected).
    """
    conn.sendall((text + "\n").encode())
    reply = b""
    while not reply.endswith(b"> "):
        chunk = conn.recv(8192)
        if not chunk:
            raise RuntimeError("telnet server của UE đã đóng kết nối")
        reply += chunk
    out = reply.decode(errors="replace")
    if "is not a softmodem command" in out:
        raise RuntimeError(f"lệnh không được hỗ trợ: {text}\n{out}")
    return out


def virtual_time(conn):
    """Trả về (số mẫu, tốc độ lấy mẫu) hiện tại của RFsimulator."""
    out = command(conn, "rfsimu vtime")
    m = re.search(r"TS (\d+) sample_rate ([\d.]+)", out)
    if not m:
        raise RuntimeError(f"RFsimulator không trả về thời gian ảo\n{out}")
    return int(m[1]), float(m[2])


def path_loss(conn):
    """Đọc path loss hiện tại của model downlink từ "channelmod show current"."""
    out = command(conn, "channelmod show current")
    blocks = re.split(r"(?=^model \d+ )", out, flags=re.M)
    block = next((b for b in blocks if b.startswith(f"model {DOWNLINK_MODEL} {DOWNLINK_MODEL_NAME} ")), None)
    if block is None:
        raise RuntimeError(f"không thấy model {DOWNLINK_MODEL} {DOWNLINK_MODEL_NAME}; chanmod đã bật chưa?\n{out}")
    m = re.search(r"path loss: (-?[\d.]+)", block)
    if not m:
        raise RuntimeError(f"không đọc được path loss\n{block}")
    return float(m[1])


def set_path_loss(conn, db):
    command(conn, f"channelmod modify {DOWNLINK_MODEL} ploss {db:g}")
    print(f"ploss={db:g} dB", flush=True)


def main():
    parser = ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("seconds", nargs="?", type=float, default=2.0, help="thời gian giữ suy hao, tính bằng giây ảo")
    parser.add_argument("--loss", type=float, default=65.0, help="path loss khi fade (dB)")
    parser.add_argument("--nominal", type=float, default=10.0, help="path loss bình thường (dB), như nrue.uicc.yaml")
    args = parser.parse_args()
    if not 0 < args.seconds < 600:
        parser.error("seconds phải nằm trong (0, 600)")

    with socket.create_connection(TELNET, timeout=5) as conn:
        before = path_loss(conn)
        if abs(before - args.nominal) > 1e-6:
            raise SystemExit(f"path loss đang là {before} dB, không phải {args.nominal} dB; dừng để không chồng hai lần fade")
        wall_start = time.monotonic()
        try:
            set_path_loss(conn, args.loss)
            ts_start, rate = virtual_time(conn)
            ts_target = ts_start + round(args.seconds * rate)
            ts = ts_start
            while ts < ts_target:
                if time.monotonic() - wall_start > WALL_TIMEOUT_S:
                    raise TimeoutError("RFsimulator không chạy tới thời điểm ảo mong muốn")
                time.sleep(0.02)
                ts, _ = virtual_time(conn)
            print(f"fade virtual={(ts - ts_start) / rate:.3f}s wall={time.monotonic() - wall_start:.3f}s", flush=True)
        finally:
            set_path_loss(conn, args.nominal)
        after = path_loss(conn)
        print(f"path loss after: {after:.6f}", flush=True)
        if abs(after - args.nominal) > 1e-6:
            raise SystemExit("không trả được path loss về mức bình thường")


if __name__ == "__main__":
    main()
