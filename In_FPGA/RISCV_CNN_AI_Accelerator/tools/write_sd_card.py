"""Safely write the Tang Nano 20K raw model image to a Windows SD card."""

import argparse
import ctypes
import sys
import zlib
from ctypes import wintypes
from pathlib import Path


GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
FILE_SHARE_READ = 0x00000001
FILE_SHARE_WRITE = 0x00000002
OPEN_EXISTING = 3
DRIVE_REMOVABLE = 2
FILE_FLAG_WRITE_THROUGH = 0x80000000
FSCTL_LOCK_VOLUME = 0x00090018
FSCTL_DISMOUNT_VOLUME = 0x00090020
IOCTL_STORAGE_GET_DEVICE_NUMBER = 0x002D1080
IOCTL_DISK_GET_LENGTH_INFO = 0x0007405C
INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value
KERNEL32 = ctypes.WinDLL("kernel32", use_last_error=True)
KERNEL32.CreateFileW.argtypes = [
    wintypes.LPCWSTR,
    wintypes.DWORD,
    wintypes.DWORD,
    wintypes.LPVOID,
    wintypes.DWORD,
    wintypes.DWORD,
    wintypes.HANDLE,
]
KERNEL32.CreateFileW.restype = wintypes.HANDLE
KERNEL32.CloseHandle.argtypes = [wintypes.HANDLE]
KERNEL32.CloseHandle.restype = wintypes.BOOL
KERNEL32.DeviceIoControl.argtypes = [
    wintypes.HANDLE,
    wintypes.DWORD,
    wintypes.LPVOID,
    wintypes.DWORD,
    wintypes.LPVOID,
    wintypes.DWORD,
    ctypes.POINTER(wintypes.DWORD),
    wintypes.LPVOID,
]
KERNEL32.DeviceIoControl.restype = wintypes.BOOL
KERNEL32.WriteFile.argtypes = [
    wintypes.HANDLE,
    wintypes.LPCVOID,
    wintypes.DWORD,
    ctypes.POINTER(wintypes.DWORD),
    wintypes.LPVOID,
]
KERNEL32.WriteFile.restype = wintypes.BOOL
KERNEL32.ReadFile.argtypes = [
    wintypes.HANDLE,
    wintypes.LPVOID,
    wintypes.DWORD,
    ctypes.POINTER(wintypes.DWORD),
    wintypes.LPVOID,
]
KERNEL32.ReadFile.restype = wintypes.BOOL
KERNEL32.SetFilePointerEx.argtypes = [
    wintypes.HANDLE,
    ctypes.c_longlong,
    ctypes.POINTER(ctypes.c_longlong),
    wintypes.DWORD,
]
KERNEL32.SetFilePointerEx.restype = wintypes.BOOL
KERNEL32.FlushFileBuffers.argtypes = [wintypes.HANDLE]
KERNEL32.FlushFileBuffers.restype = wintypes.BOOL


class StorageDeviceNumber(ctypes.Structure):
    _fields_ = [
        ("device_type", wintypes.DWORD),
        ("device_number", wintypes.DWORD),
        ("partition_number", wintypes.DWORD),
    ]


def open_handle(path: str, access: int, flags: int = 0):
    handle = KERNEL32.CreateFileW(
        path, access, FILE_SHARE_READ | FILE_SHARE_WRITE, None, OPEN_EXISTING, flags, None
    )
    if handle == INVALID_HANDLE_VALUE or handle == -1:
        raise ctypes.WinError(ctypes.get_last_error())
    return handle


def device_io_control(handle, code: int, output=None) -> None:
    returned = wintypes.DWORD()
    output_ptr = ctypes.byref(output) if output is not None else None
    output_size = ctypes.sizeof(output) if output is not None else 0
    ok = KERNEL32.DeviceIoControl(
        handle, code, None, 0, output_ptr, output_size, ctypes.byref(returned), None
    )
    if not ok:
        raise ctypes.WinError(ctypes.get_last_error())


def resolve_physical_drive(letter: str) -> int:
    handle = open_handle(rf"\\.\{letter}:", 0)
    try:
        number = StorageDeviceNumber()
        device_io_control(handle, IOCTL_STORAGE_GET_DEVICE_NUMBER, number)
        return number.device_number
    finally:
        KERNEL32.CloseHandle(handle)


def get_disk_length(path: str) -> int:
    handle = open_handle(path, GENERIC_READ)
    try:
        length = ctypes.c_longlong()
        device_io_control(handle, IOCTL_DISK_GET_LENGTH_INFO, length)
        return length.value
    finally:
        KERNEL32.CloseHandle(handle)


def write_all(handle, data: bytes) -> None:
    buffer = ctypes.create_string_buffer(data)
    written = wintypes.DWORD()
    ok = KERNEL32.WriteFile(handle, buffer, len(data), ctypes.byref(written), None)
    if not ok or written.value != len(data):
        raise ctypes.WinError(ctypes.get_last_error())


def read_exact(handle, length: int) -> bytes:
    buffer = ctypes.create_string_buffer(length)
    read = wintypes.DWORD()
    ok = KERNEL32.ReadFile(handle, buffer, length, ctypes.byref(read), None)
    if not ok or read.value != length:
        raise ctypes.WinError(ctypes.get_last_error())
    return buffer.raw[:length]


def seek_start(handle) -> None:
    position = ctypes.c_longlong()
    if not KERNEL32.SetFilePointerEx(handle, 0, ctypes.byref(position), 0):
        raise ctypes.WinError(ctypes.get_last_error())


def find_removable_drives():
    import string
    bitmask = KERNEL32.GetLogicalDrives()
    drives = []
    for i, letter in enumerate(string.ascii_uppercase):
        if (bitmask >> i) & 1:
            root = f"{letter}:\\"
            if KERNEL32.GetDriveTypeW(root) == DRIVE_REMOVABLE:
                drives.append(letter)
    return drives


def main() -> int:
    default_image = Path(__file__).resolve().parents[1] / "sd_image" / "model_sd.img"
    parser = argparse.ArgumentParser()
    target = parser.add_mutually_exclusive_group(required=False)
    target.add_argument("--drive-letter")
    target.add_argument("--physical-drive", type=int)
    parser.add_argument("--expected-size", type=int)
    parser.add_argument("--image", type=Path, default=default_image)
    parser.add_argument("--yes", action="store_true")
    args = parser.parse_args()

    letter = None
    root = None
    if args.drive_letter:
        letter = args.drive_letter.rstrip(":\\/").upper()
        if len(letter) != 1 or not letter.isalpha():
            parser.error("--drive-letter must look like G or G:")
        root = f"{letter}:\\"
        if KERNEL32.GetDriveTypeW(root) != DRIVE_REMOVABLE:
            print(f"[ERROR] {root} is not reported by Windows as a removable drive.")
            return 2
    elif args.physical_drive is None:
        removables = find_removable_drives()
        if len(removables) == 1:
            letter = removables[0]
            root = f"{letter}:\\"
            print(f"[INFO] Auto-detected removable drive: {root}")
        elif len(removables) > 1:
            print(f"[ERROR] Multiple removable drives detected: {removables}. Please specify --drive-letter.")
            return 2
        else:
            print("[ERROR] No removable drive was detected.")
            print("Insert the microSD reader and run this tool again.")
            print("For a card without a drive letter, pass --physical-drive N explicitly.")
            return 2

    image = args.image.resolve()
    data = image.read_bytes()
    if len(data) % 512 != 0 or data[:4] != b"RCN1":
        print("[ERROR] Image is not a sector-aligned RCN1 model image.")
        return 2

    drive_number = (
        resolve_physical_drive(letter) if letter is not None else args.physical_drive
    )
    if drive_number is None or drive_number <= 0:
        print("[ERROR] Refusing to write PhysicalDrive0 or an invalid disk number.")
        return 2
    physical_path = rf"\\.\PhysicalDrive{drive_number}"
    disk_size = get_disk_length(physical_path)
    if args.expected_size is not None and disk_size != args.expected_size:
        print(
            f"[ERROR] Disk size changed: expected {args.expected_size}, got {disk_size}."
        )
        return 2
    crc = zlib.crc32(data) & 0xFFFFFFFF

    print(f"Image : {image}")
    print(f"Target: {root + ' -> ' if root else ''}{physical_path} ({disk_size} bytes)")
    print(f"Size  : {len(data)} bytes ({len(data) // 512} sectors)")
    print(f"CRC32 : 0x{crc:08X}")
    if not args.yes:
        confirmation = letter if letter is not None else f"DISK {drive_number}"
        answer = input(f"Type ERASE {confirmation} to continue: ").strip()
        if answer != f"ERASE {confirmation}":
            print("Cancelled.")
            return 1

    volume_handle = None
    disk_handle = None
    try:
        if letter is not None:
            volume_handle = open_handle(
                rf"\\.\{letter}:", GENERIC_READ | GENERIC_WRITE
            )
            print("[1/3] Locking and dismounting the SD volume...")
            device_io_control(volume_handle, FSCTL_LOCK_VOLUME)
            device_io_control(volume_handle, FSCTL_DISMOUNT_VOLUME)
        else:
            print("[1/3] No mounted volume; writing the verified physical disk...")

        print("[2/3] Writing raw sectors...")
        disk_handle = open_handle(
            physical_path, GENERIC_READ | GENERIC_WRITE, FILE_FLAG_WRITE_THROUGH
        )
        before = read_exact(disk_handle, len(data))
        print(
            f"      Before: CRC32 0x{zlib.crc32(before) & 0xFFFFFFFF:08X}, "
            f"header {before[:16].hex(' ')}"
        )
        seek_start(disk_handle)
        write_all(disk_handle, data)
        if not KERNEL32.FlushFileBuffers(disk_handle):
            raise ctypes.WinError(ctypes.get_last_error())

        print("[3/3] Reading back and verifying every byte...")
        KERNEL32.CloseHandle(disk_handle)
        disk_handle = open_handle(physical_path, GENERIC_READ)
        actual = read_exact(disk_handle, len(data))
    finally:
        if disk_handle is not None:
            KERNEL32.CloseHandle(disk_handle)
        if volume_handle is not None:
            KERNEL32.CloseHandle(volume_handle)

    actual_crc = zlib.crc32(actual) & 0xFFFFFFFF
    if actual != data:
        first_diff = next(
            (index for index, pair in enumerate(zip(data, actual)) if pair[0] != pair[1]),
            min(len(data), len(actual)),
        )
        print(f"[ERROR] Verify failed: expected 0x{crc:08X}, got 0x{actual_crc:08X}")
        print(f"        First differing byte: {first_diff}")
        print(f"        Expected header: {data[:16].hex(' ')}")
        print(f"        Actual header  : {actual[:16].hex(' ')}")
        return 3

    print(f"[OK] Raw image written and verified successfully (CRC32 0x{actual_crc:08X}).")
    return 0


if __name__ == "__main__":
    if sys.platform != "win32":
        raise SystemExit("This tool only supports Windows.")
    raise SystemExit(main())
