#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    parser.add_argument("hex_file", type=Path)
    parser.add_argument("--words", type=int, required=True)
    args = parser.parse_args()

    data = bytearray(args.binary.read_bytes())
    if len(data) > args.words * 4:
        raise SystemExit(
            f"firmware is {len(data)} bytes; IMEM capacity is {args.words * 4} bytes"
        )
    data.extend(b"\x13\x00\x00\x00" * ((args.words * 4 - len(data) + 3) // 4))
    data = data[: args.words * 4]
    words = [
        int.from_bytes(data[offset : offset + 4], "little")
        for offset in range(0, len(data), 4)
    ]
    args.hex_file.write_text(
        "\n".join(f"{word:08x}" for word in words) + "\n", encoding="ascii"
    )
    print(f"IMEM image: {len(args.binary.read_bytes())}/{args.words * 4} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

