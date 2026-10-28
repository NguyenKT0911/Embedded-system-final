#!/usr/bin/env python3
"""Reject compressed, M-extension, atomic, and SYSTEM instructions."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

ALLOWED_OPCODES = {
    0x03,  # loads
    0x0F,  # fence
    0x13,  # immediate ALU
    0x17,  # auipc
    0x23,  # stores
    0x33,  # register ALU
    0x37,  # lui
    0x63,  # branches
    0x67,  # jalr
    0x6F,  # jal
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("elf", type=Path)
    args = parser.parse_args()
    elf = args.elf.read_bytes()
    if elf[:4] != b"\x7fELF" or elf[4] != 1 or elf[5] != 1:
        raise SystemExit("expected a little-endian ELF32 file")
    section_offset = struct.unpack_from("<I", elf, 32)[0]
    section_size = struct.unpack_from("<H", elf, 46)[0]
    section_count = struct.unpack_from("<H", elf, 48)[0]
    checked = 0
    for section_index in range(section_count):
        header = section_offset + section_index * section_size
        section_type, flags = struct.unpack_from("<II", elf, header + 4)
        file_offset, byte_count = struct.unpack_from("<II", elf, header + 16)
        if section_type != 1 or (flags & 0x4) == 0:
            continue
        data = elf[file_offset : file_offset + byte_count]
        if len(data) % 4:
            raise SystemExit("executable section size is not a multiple of four bytes")
        for offset in range(0, len(data), 4):
            instruction = int.from_bytes(data[offset : offset + 4], "little")
            if instruction & 0x3 != 0x3:
                raise SystemExit(
                    f"compressed instruction in section {section_index} "
                    f"at +0x{offset:04x}: 0x{instruction:08x}"
                )
            opcode = instruction & 0x7F
            if opcode not in ALLOWED_OPCODES:
                raise SystemExit(
                    f"unsupported opcode in section {section_index} "
                    f"at +0x{offset:04x}: 0x{instruction:08x}"
                )
            if opcode == 0x33 and ((instruction >> 25) & 0x7F) == 0x01:
                raise SystemExit(
                    f"RV32M instruction in section {section_index} "
                    f"at +0x{offset:04x}: 0x{instruction:08x}"
                )
            checked += 1
    if checked == 0:
        raise SystemExit("ELF contains no executable instructions")
    print(f"RESULT: {checked} executable instructions are RV32I-only")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
