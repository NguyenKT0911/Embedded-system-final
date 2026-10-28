#!/usr/bin/env python3
"""Load RV32I IMEM/DMEM through the Tang Nano 20K onboard UART."""

from __future__ import annotations

import argparse
import struct
import sys
import time
import zlib
from pathlib import Path

import serial
from serial.tools import list_ports


SOF = bytes((0x55, 0xAA))
CMD_WRITE_IMEM = 0x01
CMD_WRITE_DMEM = 0x02
CMD_RUN = 0x03
CMD_PING = 0x04
ACK = 0x79
PONG = 0xA5
NACK = 0x1F


def parse_mem_hex(path: Path, default_word: int, max_words: int) -> list[int]:
    words: list[int] = []
    cursor = 0
    for line_number, raw in enumerate(path.read_text(encoding="ascii").splitlines(), 1):
        text = raw.split("//", 1)[0].split("#", 1)[0].strip()
        if not text:
            continue
        if text.startswith("@"):
            cursor = int(text[1:], 16)
            while len(words) < cursor:
                words.append(default_word)
            continue
        for token in text.split():
            value = int(token, 16)
            if value > 0xFFFFFFFF:
                raise ValueError(f"{path}:{line_number}: word exceeds 32 bits")
            if cursor >= max_words:
                raise ValueError(f"{path}: image exceeds {max_words} words")
            if cursor == len(words):
                words.append(value)
            else:
                words[cursor] = value
            cursor += 1

    while words and words[-1] == default_word:
        words.pop()
    return words


def build_frame(command: int, byte_address: int = 0, payload: bytes = b"") -> bytes:
    if len(payload) > 256:
        raise ValueError("UART packet payload exceeds 256 bytes")
    body = struct.pack("<BIH", command, byte_address, len(payload)) + payload
    return SOF + body + struct.pack("<I", zlib.crc32(body) & 0xFFFFFFFF)


def transact(port: serial.Serial, frame: bytes, expected: int, retries: int = 5) -> None:
    for attempt in range(1, retries + 1):
        port.write(frame)
        port.flush()
        reply = port.read(1)
        if reply and reply[0] == expected:
            return
        if reply and reply[0] == NACK:
            reason = "FPGA returned NACK"
        elif reply:
            reason = f"unexpected reply 0x{reply[0]:02X}"
        else:
            reason = "reply timeout"
        if attempt == retries:
            raise RuntimeError(reason)
        port.reset_input_buffer()
        time.sleep(0.03)


def load_region(port: serial.Serial, command: int, words: list[int], name: str) -> None:
    if not words:
        print(f"{name}: no non-default words")
        return
    started = time.monotonic()
    image = b"".join(value.to_bytes(4, "little") for value in words)
    for offset in range(0, len(image), 256):
        chunk = image[offset:offset + 256]
        transact(port, build_frame(command, offset, chunk), ACK)
        completed = min(offset + len(chunk), len(image)) // 4
        print(f"{name}: {completed}/{len(words)} words", flush=True)
    elapsed = time.monotonic() - started
    print(f"{name}: completed in {elapsed:.2f} s")


def choose_port(requested: str | None) -> str:
    if requested:
        return requested
    ports = list(list_ports.comports())
    preferred_terms = ("BL616", "SPEED", "SERIAL", "UART", "JTAG")
    candidates = [item for item in ports if any(
        term in f"{item.description} {item.manufacturer} {item.hwid}".upper()
        for term in preferred_terms
    )]
    uart_b = [item for item in candidates
              if item.vid == 0x0403 and item.pid == 0x6010
              and (item.serial_number or "").upper().endswith("B")]
    if len(uart_b) == 1:
        print(f"Auto-detected onboard UART {uart_b[0].device}: interface B")
        return uart_b[0].device
    if not candidates and len(ports) == 1:
        candidates = ports
    if len(candidates) == 1:
        print(f"Auto-detected {candidates[0].device}: {candidates[0].description}")
        return candidates[0].device
    available = ", ".join(
        f"{item.device} ({item.description})" for item in list_ports.comports()
    ) or "none"
    raise RuntimeError(
        "Could not select the onboard UART automatically. "
        f"Use --port COMx. Available ports: {available}"
    )


def monitor_runtime(port: serial.Serial) -> None:
    print("Runtime monitor active; press Ctrl+C to stop.")
    print("Full CNN firmware is silent after boot; hello/batch builds may emit status bytes.")
    labels = {
        0xEE: "error record follows",
        0xA5: "inference record follows",
    }
    try:
        while True:
            byte = port.read(1)
            if not byte:
                continue
            value = byte[0]
            label = labels.get(value)
            if label:
                print(f"UART 0x{value:02X}: {label}")
            else:
                print(f"UART 0x{value:02X}")
    except KeyboardInterrupt:
        print("\nMonitor stopped.")


def open_uart(port_name: str, baud: int, timeout: float) -> serial.Serial:
    port = serial.Serial(
        port=port_name,
        baudrate=baud,
        bytesize=8,
        parity=serial.PARITY_NONE,
        stopbits=1,
        timeout=timeout,
        write_timeout=1.0,
    )
    port.dtr = False
    port.rts = False
    port.reset_input_buffer()
    port.reset_output_buffer()
    return port


def load_payload(
    port: serial.Serial,
    imem: list[int],
    dmem: list[int],
    no_run: bool,
) -> None:
    load_region(port, CMD_WRITE_IMEM, imem, "IMEM")
    load_region(port, CMD_WRITE_DMEM, dmem, "DMEM")
    if no_run:
        print("Images loaded; CPU remains in reset (--no-run).")
        return
    transact(port, build_frame(CMD_RUN), ACK)
    print("RUN acknowledged; UART is now owned by the firmware.")


def watch_and_load(
    port_name: str,
    baud: int,
    imem: list[int],
    dmem: list[int],
) -> None:
    print("UART AUTO LOADER ACTIVE")
    print("Hold the external pin-72 UART BOOT button for 0.5 s, then release.")
    print("Press Ctrl+C to stop the auto loader.")
    while True:
        try:
            with open_uart(port_name, baud, 0.15) as port:
                try:
                    transact(port, build_frame(CMD_PING), PONG, retries=1)
                except RuntimeError:
                    pass
                else:
                    print("\nBootloader detected; loading firmware automatically.", flush=True)
                    port.timeout = 1.0
                    try:
                        load_payload(port, imem, dmem, no_run=False)
                    except (OSError, RuntimeError, serial.SerialException) as exc:
                        print(
                            f"Load interrupted ({exc}); retrying automatically.\n",
                            flush=True,
                        )
                    else:
                        print("Auto loader armed for the next button press.\n", flush=True)
        except (OSError, serial.SerialException) as exc:
            # COM can be briefly unavailable while USB reconnects or another
            # tool is closing it. Keep the watcher alive and retry quietly.
            _ = exc
        time.sleep(0.75)


def main() -> int:
    project_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="Load firmware_c_full IMEM/DMEM over the onboard UART"
    )
    parser.add_argument("--port", help="Onboard UART COM port, for example COM5")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument(
        "--imem",
        type=Path,
        default=project_root / "firmware_c/build/firmware_c_full.hex",
    )
    parser.add_argument(
        "--dmem",
        type=Path,
        default=project_root / "firmware_c/build/firmware_c_full_dmem.hex",
    )
    parser.add_argument("--imem-words", type=int, default=2048)
    parser.add_argument("--dmem-words", type=int, default=2048)
    parser.add_argument("--no-run", action="store_true")
    parser.add_argument("--monitor", action="store_true")
    parser.add_argument(
        "--watch",
        action="store_true",
        help="wait and auto-load after holding the external pin-72 UART button",
    )
    args = parser.parse_args()

    imem_path = args.imem.resolve()
    dmem_path = args.dmem.resolve()
    imem = parse_mem_hex(imem_path, 0x00000013, args.imem_words)
    dmem = parse_mem_hex(dmem_path, 0x00000000, args.dmem_words)
    if not imem:
        raise ValueError("IMEM image contains no executable words")
    # RUN deliberately requires evidence that both memories were addressed.
    # A diagnostic firmware can legitimately have an all-zero data image, so
    # still write one zero word rather than making an otherwise valid image
    # impossible to start.
    if not dmem:
        dmem = [0]
    port_name = choose_port(args.port)

    print(f"IMEM source: {imem_path} ({len(imem)} words)")
    print(f"DMEM source: {dmem_path} ({len(dmem)} words)")
    print(f"Opening {port_name} at {args.baud} baud")

    if args.watch:
        if args.no_run or args.monitor:
            raise ValueError("--watch cannot be combined with --no-run or --monitor")
        try:
            watch_and_load(port_name, args.baud, imem, dmem)
        except KeyboardInterrupt:
            print("\nUART auto loader stopped.")
        return 0

    with open_uart(port_name, args.baud, 0.8) as port:
        transact(port, build_frame(CMD_PING), PONG)
        print("Bootloader responded to PING")
        load_payload(port, imem, dmem, args.no_run)
        if args.monitor:
            monitor_runtime(port)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, serial.SerialException) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
