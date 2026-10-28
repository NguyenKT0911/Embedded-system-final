#!/usr/bin/env python3
from __future__ import annotations

import argparse
import struct
from pathlib import Path


def write_hex(path: Path, data: bytes) -> None:
    words = [
        int.from_bytes(data[offset : offset + 4], "little")
        for offset in range(0, len(data), 4)
    ]
    path.write_text(
        "\n".join(f"{word:08x}" for word in words) + "\n",
        encoding="ascii",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("elf", type=Path)
    parser.add_argument("--imem-bin", type=Path, required=True)
    parser.add_argument("--imem-hex", type=Path, required=True)
    parser.add_argument("--dmem-bin", type=Path, required=True)
    parser.add_argument("--dmem-hex", type=Path, required=True)
    parser.add_argument("--imem-words", type=int, required=True)
    parser.add_argument("--dmem-words", type=int, required=True)
    args = parser.parse_args()

    elf = args.elf.read_bytes()
    if elf[:4] != b"\x7fELF" or elf[4] != 1 or elf[5] != 1:
        raise SystemExit("expected little-endian ELF32")
    imem = bytearray(b"\x13\x00\x00\x00" * args.imem_words)
    dmem = bytearray(args.dmem_words * 4)
    imem_used = 0
    dmem_used = 0
    section_offset = struct.unpack_from("<I", elf, 32)[0]
    section_size = struct.unpack_from("<H", elf, 46)[0]
    section_count = struct.unpack_from("<H", elf, 48)[0]

    for index in range(section_count):
        header = section_offset + index * section_size
        section_type, flags, address, file_offset, byte_count = struct.unpack_from(
            "<IIIII", elf, header + 4
        )
        if section_type != 1 or (flags & 0x2) == 0 or byte_count == 0:
            continue
        payload = elf[file_offset : file_offset + byte_count]
        if address < len(imem):
            end = address + byte_count
            if end > len(imem):
                raise SystemExit("IMEM section exceeds configured capacity")
            imem[address:end] = payload
            imem_used = max(imem_used, end)
        elif 0x80000000 <= address < 0x80000000 + len(dmem):
            offset = address - 0x80000000
            end = offset + byte_count
            if end > len(dmem):
                raise SystemExit("DMEM section exceeds configured capacity")
            dmem[offset:end] = payload
            dmem_used = max(dmem_used, end)
        else:
            raise SystemExit(f"allocated section at unsupported address 0x{address:08x}")

    imem_binary_size = (imem_used + 3) & ~3
    dmem_binary_size = (dmem_used + 3) & ~3
    args.imem_bin.write_bytes(imem[:imem_binary_size])
    args.dmem_bin.write_bytes(dmem[:dmem_binary_size])
    write_hex(args.imem_hex, imem)
    write_hex(args.dmem_hex, dmem)
    print(f"IMEM image: {imem_used}/{len(imem)} bytes")
    print(f"DMEM image: {dmem_used}/{len(dmem)} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
