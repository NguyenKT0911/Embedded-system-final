from __future__ import annotations

import argparse
from pathlib import Path
import struct
import sys
import zlib

import numpy as np


ROOT = Path(__file__).resolve().parent.parent
WORKSPACE = ROOT.parent
INT8_DIR = ROOT / "int8_quantized"
FPGA_EXPORT_DIR = ROOT / "fpga_ready_data"

# Định nghĩa giao thức UART Frame (khớp với UART_Host/protocol.py)
MAGIC = b"\xA5\x5A"
CMD_LOAD_INPUT = 0x01
CMD_START = 0x04


def build_frame(command: int, payload: bytes = b"") -> bytes:
    """Tạo gói tin UART chuẩn có CRC32."""
    payload = bytes(payload)
    crc = zlib.crc32(payload) & 0xFFFFFFFF
    return MAGIC + bytes([command & 0xFF]) + struct.pack("<I", len(payload)) + payload + struct.pack("<I", crc)


def pack_int8_to_words32(flat_int8: np.ndarray) -> np.ndarray:
    """Đóng gói 4 byte INT8 thành 1 word 32-bit (Little-Endian) cho RAM FPGA."""
    u8 = flat_int8.astype(np.uint8)
    pad_len = (4 - (len(u8) % 4)) % 4
    if pad_len > 0:
        u8 = np.pad(u8, (0, pad_len))
    return u8.view("<u4")


def export_all_fpga_data():
    """
    Xuất toàn bộ 50 ảnh sang 3 định dạng dữ liệu cho FPGA:
    1. .bin (784 bytes INT8 thô)
    2. .hex (Dùng cho mô phỏng Verilog Testbench với $readmemh)
    3. .uart_pkt (Gói tin đóng sẵn Header + Payload + CRC32 để nạp trực tiếp qua UART)
    """
    FPGA_EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    raw_bin_dir = FPGA_EXPORT_DIR / "raw_bin"
    hex_dir = FPGA_EXPORT_DIR / "verilog_hex"
    uart_pkt_dir = FPGA_EXPORT_DIR / "uart_packets"

    for d in [raw_bin_dir, hex_dir, uart_pkt_dir]:
        d.mkdir(parents=True, exist_ok=True)

    total = 0

    for digit in range(10):
        src_digit_dir = INT8_DIR / str(digit)
        if not src_digit_dir.exists():
            continue

        (raw_bin_dir / str(digit)).mkdir(parents=True, exist_ok=True)
        (hex_dir / str(digit)).mkdir(parents=True, exist_ok=True)
        (uart_pkt_dir / str(digit)).mkdir(parents=True, exist_ok=True)

        for npy_file in sorted(src_digit_dir.glob("*.npy")):
            arr = np.load(npy_file)
            flat = arr.flatten().astype(np.int8)
            bytes_data = flat.tobytes()

            name = npy_file.stem  # vd: 0_01

            # 1. Xuất file .bin thô (784 bytes)
            bin_path = raw_bin_dir / str(digit) / f"{name}.bin"
            bin_path.write_bytes(bytes_data)

            # 2. Xuất file .hex (32-bit words hex cho Verilog $readmemh)
            words32 = pack_int8_to_words32(flat)
            hex_path = hex_dir / str(digit) / f"{name}.hex"
            with open(hex_path, "w", encoding="utf-8") as f:
                for w in words32:
                    f.write(f"{w:08x}\n")

            # 3. Xuất gói tin UART Packet hoàn chỉnh có CRC32
            uart_frame = build_frame(CMD_LOAD_INPUT, bytes_data)
            pkt_path = uart_pkt_dir / str(digit) / f"{name}_packet.bin"
            pkt_path.write_bytes(uart_frame)

            total += 1

    print("=" * 65)
    print(f"PACKAGED {total} FPGA DATA SAMPLES SUCCESSFULLY!")
    print(f"Output directory: {FPGA_EXPORT_DIR}")
    print("  1. raw_bin/      : Raw INT8 binary files (784 bytes each)")
    print("  2. verilog_hex/  : 32-bit packed hex files for Verilog $readmemh simulation")
    print("  3. uart_packets/ : Complete UART frames (Magic + Cmd + Data + CRC32)")
    print("=" * 65)


if __name__ == "__main__":
    export_all_fpga_data()
