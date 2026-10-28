#!/usr/bin/env python3
"""Desktop control center for the Tang Nano 20K RISC-V CNN system."""

from __future__ import annotations

import queue
import struct
import subprocess
import sys
import threading
import time
import zlib
from pathlib import Path
from tkinter import filedialog, messagebox, simpledialog
import tkinter as tk
from tkinter import ttk

import serial
from serial.tools import list_ports
from PIL import Image, ImageChops, ImageEnhance, ImageFilter, ImageOps, ImageTk


ROOT = Path(__file__).resolve().parents[1]
TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))
MODEL_DIR = ROOT.parents[1] / "Model Training" / "FPGA_UART_export"
BUILD = ROOT / "firmware_c" / "build"
FULL_IMEM = BUILD / "firmware_c_full.hex"
FULL_DMEM = BUILD / "firmware_c_full_dmem.hex"
MANAGER_IMEM = BUILD / "firmware_c_dataset_manager.hex"
MANAGER_DMEM = BUILD / "firmware_c_dataset_manager_dmem.hex"
BITSTREAM = ROOT / "impl" / "pnr" / "TangNano20K_RISCV_CNN.fs"
APP_ICON = ROOT.parents[1] / "assets" / "icons" / "mo-ai-fpga-app.ico"
APP_ICON_PNG = ROOT.parents[1] / "assets" / "icons" / "mo-ai-fpga.png"
PROGRAMMER = Path(
    r"C:\Gowin\Gowin_V1.9.11.03_Education_x64\Programmer\bin\programmer_cli.exe"
)

SOF = b"\x55\xAA"
ACK, PONG, NACK = 0x79, 0xA5, 0x1F
CMD_IMEM, CMD_DMEM, CMD_RUN, CMD_PING = 1, 2, 3, 4
CMD_STATUS, CMD_SLOT_INFO = 0x20, 0x21
CMD_SLOT_BEGIN, CMD_SLOT_WRITE, CMD_SLOT_COMMIT = 0x22, 0x23, 0x24
CMD_REBOOT_LOADER = 0x26

MNIST_MEAN = 0.1307
MNIST_STD = 0.3081
INPUT_INT8_SCALE = 0.02221643079922894


def frame(command: int, address: int = 0, payload: bytes = b"") -> bytes:
    body = struct.pack("<BIH", command, address, len(payload)) + payload
    return SOF + body + struct.pack("<I", zlib.crc32(body) & 0xFFFFFFFF)


def parse_mem_hex(path: Path, default: int, maximum: int) -> list[int]:
    words: list[int] = []
    cursor = 0
    for line_no, raw in enumerate(path.read_text(encoding="ascii").splitlines(), 1):
        text = raw.split("//", 1)[0].split("#", 1)[0].strip()
        if not text:
            continue
        if text.startswith("@"):
            cursor = int(text[1:], 16)
            while len(words) < cursor:
                words.append(default)
            continue
        for token in text.split():
            if cursor >= maximum:
                raise ValueError(f"{path.name}:{line_no}: RAM capacity exceeded")
            value = int(token, 16)
            if cursor == len(words):
                words.append(value)
            else:
                words[cursor] = value
            cursor += 1
    while words and words[-1] == default:
        words.pop()
    return words


def _otsu_threshold(image: Image.Image) -> int:
    """Return an Otsu threshold without requiring OpenCV or NumPy."""
    histogram = image.histogram()
    total = image.width * image.height
    weighted_total = sum(level * count for level, count in enumerate(histogram))
    background_weight = 0
    background_sum = 0
    best_variance = -1.0
    best_level = 0
    for level, count in enumerate(histogram):
        background_weight += count
        if background_weight == 0:
            continue
        foreground_weight = total - background_weight
        if foreground_weight == 0:
            break
        background_sum += level * count
        background_mean = background_sum / background_weight
        foreground_mean = (weighted_total - background_sum) / foreground_weight
        variance = background_weight * foreground_weight * (
            background_mean - foreground_mean
        ) ** 2
        if variance > best_variance:
            best_variance = variance
            best_level = level
    return best_level


def _center_mnist(canvas: Image.Image) -> Image.Image:
    pixels = list(canvas.getdata())
    mass = sum(pixels)
    if mass == 0:
        return canvas
    cx = sum((index % 28) * value for index, value in enumerate(pixels)) / mass
    cy = sum((index // 28) * value for index, value in enumerate(pixels)) / mass
    dx = max(-2, min(2, round(13.5 - cx)))
    dy = max(-2, min(2, round(13.5 - cy)))
    return canvas.transform(
        (28, 28), Image.Transform.AFFINE, (1, 0, -dx, 0, 1, -dy),
        resample=Image.Resampling.NEAREST, fillcolor=0,
    )


def preprocess_mnist(path: Path) -> tuple[Image.Image, Image.Image, bytes]:
    original = Image.open(path).convert("RGB")
    gray = ImageOps.grayscale(original)
    border = []
    border.extend(gray.crop((0, 0, gray.width, 1)).getdata())
    border.extend(gray.crop((0, gray.height - 1, gray.width, gray.height)).getdata())
    border.extend(gray.crop((0, 0, 1, gray.height)).getdata())
    border.extend(gray.crop((gray.width - 1, 0, gray.width, gray.height)).getdata())
    if sum(border) / max(1, len(border)) > 127:
        gray = ImageOps.invert(gray)
    gray = ImageOps.autocontrast(gray, cutoff=1)
    gray = gray.filter(ImageFilter.GaussianBlur(radius=0.6))
    threshold = max(12, _otsu_threshold(gray))
    mask = gray.point(lambda value: 255 if value > threshold else 0)
    # Close one-pixel gaps while retaining the topology of 0, 6, 8 and 9.
    mask = mask.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    bbox = mask.getbbox()
    if bbox is None:
        raise ValueError("No digit was detected in the selected image.")
    digit = mask.crop(bbox)
    scale = min(20.0 / digit.width, 20.0 / digit.height)
    size = (max(1, round(digit.width * scale)), max(1, round(digit.height * scale)))
    digit = digit.resize(size, Image.Resampling.LANCZOS)
    digit = ImageOps.autocontrast(digit)

    # Thin pen strokes can almost disappear when a large photo is reduced to
    # 20 pixels.  Add only a soft fraction of a one-pixel dilation; applying a
    # full 3x3 maximum filter here makes loops close and joins nearby strokes.
    digit = digit.point(
        lambda value: 0 if value <= 18 else min(255, round((value - 18) * 255 / 237))
    )
    foreground = sum(value >= 128 for value in digit.getdata())
    coverage = foreground / max(1, digit.width * digit.height)
    if coverage < 0.22:
        expanded = digit.filter(ImageFilter.MaxFilter(3))
        blend = min(0.42, max(0.16, (0.22 - coverage) * 2.2))
        digit = Image.blend(digit, expanded, blend)
    digit = ImageEnhance.Contrast(digit).enhance(1.35)

    canvas = Image.new("L", (28, 28), 0)
    canvas.paste(digit, ((28 - size[0]) // 2, (28 - size[1]) // 2))
    canvas = _center_mnist(canvas)

    # Match the exact normalization used during model training.  Bytes carry
    # signed INT8 in two's-complement form: black background becomes -19 and
    # a full white stroke saturates at +127.
    quantized = []
    for value in canvas.getdata():
        normalized = (value / 255.0 - MNIST_MEAN) / MNIST_STD
        signed = max(-128, min(127, round(normalized / INPUT_INT8_SCALE)))
        quantized.append(signed & 0xFF)
    values = bytes(quantized)
    return original, canvas, values


def calculate_ai_metadata(image_data: bytes) -> tuple[int, bytes, int]:
    """Return per-image Conv2 calibration, ten confidences and host class."""
    import numpy as np
    from export_sd_image import (
        host_classify,
        load_json,
        max_pool2x2,
        software_convolution,
    )

    q1 = load_json(MODEL_DIR / "conv1_quantization_params.json")
    q2 = load_json(MODEL_DIR / "conv2_quantization_params.json")
    weight1 = np.load(MODEL_DIR / "conv1_weight_int8.npy").astype(np.int8)
    weight2 = np.load(MODEL_DIR / "conv2_weight_int8.npy").astype(np.int8)
    activation = np.frombuffer(image_data, dtype=np.int8).reshape(28, 28)
    conv1 = software_convolution(activation[None, :, :], weight1)
    pooled1 = max_pool2x2(conv1)
    conv2_input = np.clip(
        np.rint(
            pooled1 * float(q1["output_real_scale"])
            / float(q2["activation_scale"])
        ),
        -128,
        127,
    ).astype(np.int8)
    conv2 = software_convolution(conv2_input, weight2)
    pooled2 = max_pool2x2(conv2)
    calibration_max = int(pooled2.max())
    if calibration_max <= 0:
        raise RuntimeError("The image did not produce valid CNN features.")
    prediction, logits = host_classify(
        conv2, float(q2["output_real_scale"]), MODEL_DIR
    )
    stable = logits - np.max(logits)
    probabilities = np.exp(stable) / np.exp(stable).sum()
    confidences = np.clip(
        np.rint(probabilities * 100.0), 0, 100
    ).astype(np.uint8).tobytes()
    return calibration_max, confidences, prediction


class Link:
    def __init__(self, port: serial.Serial):
        self.port = port

    def boot_transaction(self, command: int, address: int = 0,
                         payload: bytes = b"", expected: int = ACK,
                         retries: int = 4) -> None:
        for attempt in range(retries):
            self.port.reset_input_buffer()
            self.port.write(frame(command, address, payload))
            self.port.flush()
            reply = self.port.read(1)
            if reply and reply[0] == expected:
                return
            if attempt + 1 < retries:
                time.sleep(0.05)
        got = "timeout" if not reply else f"0x{reply[0]:02X}"
        raise RuntimeError(
            f"The bootloader did not acknowledge the request (received {got}). "
            "Hold the UART button on pin 72 for about 0.5 seconds, release it, "
            "and try again."
        )

    def load_firmware(self, imem_path: Path, dmem_path: Path, progress,
                      run_address: int = 0) -> None:
        imem = parse_mem_hex(imem_path, 0x00000013, 2048)
        dmem = parse_mem_hex(dmem_path, 0, 2048) or [0]
        regions = ((CMD_IMEM, imem, "IMEM"), (CMD_DMEM, dmem, "DMEM"))
        total = len(imem) * 4 + len(dmem) * 4
        done = 0
        self.boot_transaction(CMD_PING, expected=PONG)
        for command, words, name in regions:
            data = b"".join(word.to_bytes(4, "little") for word in words)
            for offset in range(0, len(data), 256):
                chunk = data[offset:offset + 256]
                self.boot_transaction(command, offset, chunk)
                done += len(chunk)
                progress(done, total, name)
        if not 0 <= run_address < 100:
            raise ValueError("The RUN slot address must be between 0 and 99.")
        self.boot_transaction(CMD_RUN, run_address)

    def wait_for_loader(self, timeout: float, progress=None) -> None:
        """Wait for the pin-72 reset instead of failing on the first PING."""
        started = time.monotonic()
        deadline = started + timeout
        while time.monotonic() < deadline:
            try:
                self.boot_transaction(CMD_PING, expected=PONG, retries=1)
                return
            except RuntimeError:
                elapsed = time.monotonic() - started
                if progress is not None:
                    progress(elapsed, timeout)
                time.sleep(0.25)
        raise RuntimeError(
            "UART Loader was not detected. Start the operation again, then hold "
            "the UART button on pin 72 for about 0.5 seconds and release it while "
            "the application is waiting."
        )

    def runtime_transaction(self, command: int, address: int = 0,
                            payload: bytes = b"") -> bytes:
        self.port.reset_input_buffer()
        self.port.write(frame(command, address, payload))
        self.port.flush()
        deadline = time.monotonic() + 6.0
        sync = bytearray()
        while time.monotonic() < deadline:
            byte = self.port.read(1)
            if not byte:
                continue
            sync += byte
            if sync.endswith(SOF):
                break
            if len(sync) > 2:
                del sync[:-2]
        else:
            raise RuntimeError("The firmware did not respond to the packet.")
        header = self.port.read(7)
        if len(header) != 7:
            raise RuntimeError("The response packet is missing its header.")
        response, status, length = struct.unpack("<BIH", header)
        data = self.port.read(length)
        crc_raw = self.port.read(4)
        if len(data) != length or len(crc_raw) != 4:
            raise RuntimeError("The response packet contains incomplete data.")
        body = header + data
        if struct.unpack("<I", crc_raw)[0] != zlib.crc32(body) & 0xFFFFFFFF:
            raise RuntimeError("The response packet CRC is invalid.")
        if response != (command | 0x80):
            raise RuntimeError("The firmware returned an unexpected command.")
        if status != 0:
            descriptions = {
                1: "unsupported command",
                2: "invalid packet",
                3: "invalid slot or offset",
                4: "microSD read/write failure",
                5: "image CRC verification failed after reading from microSD",
                6: "the model or microSD is not ready",
            }
            detail = descriptions.get(status, "unknown error")
            raise RuntimeError(f"Firmware error {status}: {detail}")
        return data


class StatusLamp(ttk.Frame):
    def __init__(self, parent, name: str):
        super().__init__(parent)
        self.canvas = tk.Canvas(self, width=16, height=16, highlightthickness=0,
                                background="#111827")
        self.dot = self.canvas.create_oval(3, 3, 13, 13, fill="#4b5563", outline="")
        self.canvas.pack(side="left", padx=(0, 5))
        ttk.Label(self, text=name).pack(side="left")

    def set(self, state: bool | None):
        color = "#22c55e" if state else "#ef4444" if state is False else "#4b5563"
        self.canvas.itemconfigure(self.dot, fill=color)


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Tang Nano 20K · RISC-V CNN Control Center")
        if APP_ICON_PNG.is_file():
            try:
                self._app_icon = tk.PhotoImage(file=str(APP_ICON_PNG))
                self.iconphoto(True, self._app_icon)
            except tk.TclError:
                self._app_icon = None
        if APP_ICON.is_file():
            try:
                self.iconbitmap(str(APP_ICON))
            except tk.TclError:
                pass
        self._apply_windows_icons()
        self.geometry("1120x760")
        self.minsize(980, 680)
        self.configure(background="#0b1220")
        self.option_add("*Font", ("Segoe UI", 10))
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure(".", background="#111827", foreground="#e5e7eb",
                        fieldbackground="#1f2937")
        style.configure("TFrame", background="#111827")
        style.configure("TLabel", background="#111827", foreground="#e5e7eb")
        style.configure("TLabelframe", background="#111827", foreground="#93c5fd")
        style.configure("TLabelframe.Label", background="#111827", foreground="#93c5fd")
        style.configure("TButton", padding=7)
        style.configure("Accent.TButton", background="#2563eb", foreground="white")
        style.configure("Treeview", background="#0f172a", fieldbackground="#0f172a",
                        foreground="#e5e7eb", rowheight=25)
        style.configure("Treeview.Heading", background="#1f2937", foreground="#e5e7eb")

        self.events: queue.Queue = queue.Queue()
        self.serial: serial.Serial | None = None
        self.link: Link | None = None
        self.processed: bytes | None = None
        self.calibration_max: int | None = None
        self.confidences: bytes | None = None
        self.original_photo = None
        self.mnist_photo = None
        self.busy = False
        self._build_ui()
        self.refresh_ports()
        self.after(80, self._drain_events)

    def _apply_windows_icons(self) -> None:
        """Set both Win32 window icons so the taskbar does not use pythonw.exe."""
        if sys.platform != "win32" or not APP_ICON.is_file():
            return
        try:
            import ctypes

            user32 = ctypes.windll.user32
            user32.GetParent.argtypes = [ctypes.c_void_p]
            user32.GetParent.restype = ctypes.c_void_p
            user32.LoadImageW.argtypes = [
                ctypes.c_void_p,
                ctypes.c_wchar_p,
                ctypes.c_uint,
                ctypes.c_int,
                ctypes.c_int,
                ctypes.c_uint,
            ]
            user32.LoadImageW.restype = ctypes.c_void_p
            user32.SendMessageW.argtypes = [
                ctypes.c_void_p,
                ctypes.c_uint,
                ctypes.c_size_t,
                ctypes.c_void_p,
            ]
            user32.SendMessageW.restype = ctypes.c_void_p

            image_icon = 1
            load_from_file = 0x0010
            wm_seticon = 0x0080
            icon_small, icon_big = 0, 1
            small = user32.LoadImageW(
                None, str(APP_ICON), image_icon, 16, 16, load_from_file
            )
            big = user32.LoadImageW(
                None, str(APP_ICON), image_icon, 32, 32, load_from_file
            )
            if not small or not big:
                return

            self.update_idletasks()
            inner = self.winfo_id()
            outer = user32.GetParent(inner)
            for handle in {inner, outer}:
                if handle:
                    user32.SendMessageW(handle, wm_seticon, icon_small, small)
                    user32.SendMessageW(handle, wm_seticon, icon_big, big)
            self._native_icon_handles = (small, big)
        except (AttributeError, OSError, tk.TclError):
            self._native_icon_handles = ()

    def _build_ui(self):
        header = ttk.Frame(self, padding=14)
        header.pack(fill="x")
        ttk.Label(header, text="AI FPGA CONTROL CENTER",
                  font=("Segoe UI Semibold", 19), foreground="#60a5fa").pack(side="left")
        ttk.Label(header, text="Tang Nano 20K · RV32I · CNN · microSD · HDMI",
                  foreground="#9ca3af").pack(side="left", padx=18)

        connection = ttk.LabelFrame(self, text=" Board Connection ", padding=10)
        connection.pack(fill="x", padx=14, pady=(0, 9))
        ttk.Label(connection, text="COM Port").pack(side="left")
        self.port_var = tk.StringVar()
        self.port_box = ttk.Combobox(connection, textvariable=self.port_var,
                                     state="readonly", width=42)
        self.port_box.pack(side="left", padx=8)
        ttk.Button(connection, text="Refresh", command=self.refresh_ports).pack(side="left")
        self.connect_button = ttk.Button(connection, text="Connect",
                                         style="Accent.TButton", command=self.toggle_connect)
        self.connect_button.pack(side="left", padx=8)
        self.mode_var = tk.StringVar(value="Not connected")
        ttk.Label(connection, textvariable=self.mode_var, foreground="#fbbf24").pack(side="right")

        lamps = ttk.Frame(self, padding=(14, 4))
        lamps.pack(fill="x")
        self.lamps = {}
        for name in ("FPGA", "UART", "CPU", "microSD", "CNN", "HDMI"):
            lamp = StatusLamp(lamps, name)
            lamp.pack(side="left", padx=(0, 22))
            self.lamps[name] = lamp

        notebook = ttk.Notebook(self)
        notebook.pack(fill="both", expand=True, padx=14, pady=9)
        control = ttk.Frame(notebook, padding=12)
        dataset = ttk.Frame(notebook, padding=12)
        notebook.add(control, text="  Firmware & Status  ")
        notebook.add(dataset, text="  microSD Dataset  ")

        actions = ttk.LabelFrame(control, text=" Operations ", padding=12)
        actions.pack(fill="x")
        ttk.Button(actions, text="Load AI Runtime", style="Accent.TButton",
                   command=lambda: self.start(self.load_runtime)).pack(side="left", padx=4)
        ttk.Button(actions, text="Load Dataset Manager",
                   command=lambda: self.start(self.load_manager)).pack(side="left", padx=4)
        ttk.Button(actions, text="Read Status",
                   command=lambda: self.start(self.query_status)).pack(side="left", padx=4)
        ttk.Button(actions, text="Program Hardware (.fs)",
                   command=lambda: self.start(self.flash_hardware)).pack(side="left", padx=4)
        ttk.Button(actions, text="Initialize microSD",
                   command=self.ask_initialize_sd).pack(side="left", padx=4)
        self.progress = ttk.Progressbar(control, mode="determinate")
        self.progress.pack(fill="x", pady=12)
        self.progress_text = tk.StringVar(value="Ready")
        ttk.Label(control, textvariable=self.progress_text).pack(anchor="w")

        log_frame = ttk.LabelFrame(control, text=" UART / System Log ", padding=8)
        log_frame.pack(fill="both", expand=True, pady=(12, 0))
        self.log_widget = tk.Text(log_frame, height=18, bg="#020617", fg="#d1fae5",
                                  insertbackground="white", relief="flat",
                                  font=("Cascadia Mono", 9), state="disabled")
        self.log_widget.pack(fill="both", expand=True)

        left = ttk.Frame(dataset)
        left.pack(side="left", fill="both", expand=True)
        form = ttk.LabelFrame(left, text=" Replace Dataset Image (100 Slots Full) ", padding=10)
        form.pack(fill="x")
        ttk.Button(form, text="Select JPG / PNG", command=self.choose_image).grid(row=0, column=0, padx=4)
        ttk.Label(form, text="Target Slot 0–99").grid(row=0, column=1, padx=(18, 4))
        self.slot_var = tk.IntVar(value=0)
        ttk.Spinbox(form, from_=0, to=99, textvariable=self.slot_var, width=6).grid(row=0, column=2)
        ttk.Label(form, text="ID").grid(row=0, column=3, padx=(18, 4))
        self.id_var = tk.IntVar(value=1000)
        ttk.Entry(form, textvariable=self.id_var, width=9).grid(row=0, column=4)
        ttk.Label(form, text="Class 0–9").grid(row=0, column=5, padx=(18, 4))
        self.label_var = tk.IntVar(value=0)
        ttk.Spinbox(form, from_=0, to=9, textvariable=self.label_var, width=5).grid(row=0, column=6)
        ttk.Button(form, text="Replace Image on microSD", style="Accent.TButton",
                   command=lambda: self.start(self.update_dataset_automatic)).grid(row=0, column=7, padx=12)
        self.dataset_hint = tk.StringVar(
            value="If AI Runtime is active: click Replace Image, then hold the UART button on pin 72 for about 0.5 seconds."
        )
        ttk.Label(form, textvariable=self.dataset_hint, foreground="#fbbf24").grid(
            row=1, column=0, columnspan=8, sticky="w", padx=4, pady=(9, 0)
        )

        preview = ttk.Frame(left, padding=(0, 12))
        preview.pack(fill="x")
        self.original_label = ttk.Label(preview, text="Original Image", anchor="center")
        self.original_label.pack(side="left", fill="both", expand=True, padx=5)
        self.mnist_label = ttk.Label(preview, text="MNIST 28×28 INT8", anchor="center")
        self.mnist_label.pack(side="left", fill="both", expand=True, padx=5)

        table_frame = ttk.LabelFrame(left, text=" 100 microSD Slots ", padding=8)
        table_frame.pack(fill="both", expand=True)
        ttk.Button(table_frame, text="Read Slot List",
                   command=lambda: self.start(self.refresh_slots)).pack(anchor="w", pady=(0, 7))
        self.slot_tree = ttk.Treeview(table_frame,
                                      columns=("slot", "id", "label", "valid", "crc"),
                                      show="headings")
        for column, title, width in (("slot", "Slot", 60), ("id", "ID", 100),
                                     ("label", "Class", 70), ("valid", "Valid", 70),
                                     ("crc", "Image CRC32", 140)):
            self.slot_tree.heading(column, text=title)
            self.slot_tree.column(column, width=width, anchor="center")
        self.slot_tree.pack(fill="both", expand=True)

    def emit(self, kind: str, *args):
        self.events.put((kind, args))

    def _drain_events(self):
        try:
            while True:
                kind, args = self.events.get_nowait()
                if kind == "log": self.log(args[0])
                elif kind == "progress":
                    done, total, text = args
                    self.progress["value"] = 100 * done / max(1, total)
                    self.progress_text.set(text)
                elif kind == "lamp": self.lamps[args[0]].set(args[1])
                elif kind == "mode": self.mode_var.set(args[0])
                elif kind == "dataset_hint": self.dataset_hint.set(args[0])
                elif kind == "slots": self._show_slots(args[0])
                elif kind == "done":
                    self.busy = False
                    self.progress_text.set(args[0])
                elif kind == "error":
                    self.busy = False
                    self.log("ERROR: " + args[0])
                    self.progress_text.set("Failed")
                    messagebox.showerror("AI FPGA", args[0])
        except queue.Empty:
            pass
        self.after(80, self._drain_events)

    def log(self, text: str):
        self.log_widget.configure(state="normal")
        self.log_widget.insert("end", time.strftime("[%H:%M:%S] ") + text + "\n")
        self.log_widget.see("end")
        self.log_widget.configure(state="disabled")

    def start(self, target):
        if self.busy:
            messagebox.showinfo("AI FPGA", "Another operation is already in progress.")
            return
        self.busy = True
        threading.Thread(target=self._worker, args=(target,), daemon=True).start()

    def _worker(self, target):
        try:
            target()
            self.emit("done", "Completed")
        except Exception as exc:
            self.emit("error", str(exc))

    def refresh_ports(self):
        ports = list(list_ports.comports())
        values = [f"{p.device} — {p.description}" for p in ports]
        self.port_box["values"] = values
        if values:
            def score(p):
                info = f"{p.description} {p.manufacturer} {p.hwid}".upper()
                value = sum(term in info for term in ("BL616", "SPEED", "UART", "SERIAL"))
                # Tang Nano 20K exposes an FTDI-compatible dual channel: A is
                # JTAG and B is the FPGA UART. Both otherwise have identical
                # Windows descriptions, so prefer the serial suffix B.
                if p.vid == 0x0403 and p.pid == 0x6010:
                    value += 100 if (p.serial_number or "").upper().endswith("B") else -50
                return value
            preferred = max(range(len(ports)), key=lambda i: score(ports[i]))
            self.port_box.current(preferred)

    def toggle_connect(self):
        if self.serial and self.serial.is_open:
            self.serial.close()
            self.serial = None
            self.link = None
            self.connect_button.configure(text="Connect")
            self.mode_var.set("Disconnected")
            for lamp in self.lamps.values(): lamp.set(None)
            return
        if not self.port_var.get():
            messagebox.showwarning("AI FPGA", "No COM port is available.")
            return
        device = self.port_var.get().split(" — ", 1)[0]
        try:
            self.serial = serial.Serial(device, 115200, timeout=0.8, write_timeout=2)
            self.serial.dtr = False
            self.serial.rts = False
            self.link = Link(self.serial)
            self.connect_button.configure(text="Disconnect")
            self.mode_var.set(f"Connected to {device}")
            self.lamps["UART"].set(True)
            self.log(f"Opened {device} at 115200 baud")
        except Exception as exc:
            messagebox.showerror("AI FPGA", str(exc))

    def require_link(self) -> Link:
        if not self.link or not self.serial or not self.serial.is_open:
            raise RuntimeError("Connect to the board's integrated UART COM port first.")
        return self.link

    def _load(self, imem: Path, dmem: Path, title: str, run_sample: int = 0):
        link = self.require_link()
        self.emit("log", f"Loading {title} with CRC32-protected packets...")
        link.load_firmware(imem, dmem,
            lambda done, total, name: self.emit("progress", done, total,
                                                f"{title}: {name} {done}/{total} bytes"),
            run_address=run_sample)
        self.emit("lamp", "FPGA", True)
        self.emit("lamp", "CPU", True)
        self.emit("mode", title)
        self.emit("log", f"RUN acknowledged: {title} started (slot {run_sample})")

    def load_runtime(self):
        self._load(FULL_IMEM, FULL_DMEM, "AI Runtime")

    def load_manager(self):
        self._load(MANAGER_IMEM, MANAGER_DMEM, "Dataset Manager")
        time.sleep(0.8)
        self.query_status()

    def query_status(self):
        link = self.require_link()
        try:
            data = link.runtime_transaction(CMD_STATUS)
            if len(data) < 8:
                raise RuntimeError("The status packet is too short.")
            flags = data[1]
            for name, bit in (("FPGA", 0), ("UART", 1), ("CPU", 2),
                              ("microSD", 3), ("CNN", 4), ("HDMI", 5)):
                self.emit("lamp", name, bool(flags & (1 << bit)))
            count, record = struct.unpack_from("<HH", data, 2)
            self.emit("mode", "Dataset Manager")
            self.emit("log", f"Manager: {count} slots, {record}-byte records, RCN1 v{data[6]}")
        except Exception:
            # AI Runtime reserves almost all IMEM for inference, so it does not
            # include the dataset-management protocol. Avoid arbitrary probe
            # bytes that could disrupt a valid UART session; detailed status is
            # available only while Dataset Manager is running.
            self.emit("log", "Dataset Manager STATUS is unavailable. This is normal while AI Runtime is active; hold the UART button on pin 72 for about 0.5 seconds before reloading.")

    def choose_image(self):
        name = filedialog.askopenfilename(filetypes=[
            ("Image Files", "*.png *.jpg *.jpeg *.bmp"), ("All Files", "*.*")])
        if not name:
            return
        try:
            original, mnist, self.processed = preprocess_mnist(Path(name))
            self.calibration_max, self.confidences, host_prediction = (
                calculate_ai_metadata(self.processed)
            )
            op = original.copy(); op.thumbnail((320, 260))
            mp = mnist.resize((252, 252), Image.Resampling.NEAREST)
            self.original_photo = ImageTk.PhotoImage(op)
            self.mnist_photo = ImageTk.PhotoImage(mp)
            self.original_label.configure(image=self.original_photo, text="")
            self.mnist_label.configure(image=self.mnist_photo, text="")
            confidence = self.confidences[host_prediction]
            self.log(
                f"Processed {Path(name).name} → MNIST 28×28 INT8; "
                f"host prediction: {host_prediction} ({confidence}%)"
            )
        except Exception as exc:
            messagebox.showerror("Image Processing", str(exc))

    def update_dataset_automatic(self):
        if (self.processed is None or self.calibration_max is None
                or self.confidences is None):
            raise RuntimeError("Select a JPG or PNG image first.")
        slot = int(self.slot_var.get())
        label = int(self.label_var.get())
        sample_id = int(self.id_var.get())
        if not 0 <= slot < 100 or not 0 <= label <= 9:
            raise RuntimeError("The slot must be 0–99 and the class must be 0–9.")
        link = self.require_link()
        # Accept either a loader (load Manager now) or an already-running Manager.
        try:
            link.runtime_transaction(CMD_STATUS)
        except Exception:
            self.emit(
                "dataset_hint",
                "Waiting for UART Loader — hold the pin-72 button for about 0.5 seconds, then release it...",
            )
            self.emit("log", "AI Runtime currently owns the UART; waiting for the pin-72 button to return the CPU to Loader mode.")
            link.wait_for_loader(
                20.0,
                lambda done, total: self.emit(
                    "progress", done, total,
                    f"Waiting for UART Loader: {done:0.1f}/{total:0.0f} seconds",
                ),
            )
            self.emit("dataset_hint", "UART Loader detected; loading Dataset Manager...")
            self._load(MANAGER_IMEM, MANAGER_DMEM, "Dataset Manager")
            time.sleep(0.8)
            link.runtime_transaction(CMD_STATUS)
        self.emit("log", f"Opening slot {slot}: ID={sample_id}, class={label}")
        begin_payload = struct.pack(
            "<IBI10B",
            sample_id,
            label,
            self.calibration_max,
            *self.confidences,
        )
        link.runtime_transaction(CMD_SLOT_BEGIN, slot, begin_payload)
        for offset in range(0, 784, 112):
            chunk = self.processed[offset:offset + 112]
            link.runtime_transaction(CMD_SLOT_WRITE, (slot << 16) | offset, chunk)
            self.emit("progress", offset + len(chunk), 784,
                      f"Writing image to microSD: {offset + len(chunk)}/784 bytes")
        crc = zlib.crc32(self.processed) & 0xFFFFFFFF
        link.runtime_transaction(CMD_SLOT_COMMIT, slot, struct.pack("<I", crc))
        self.emit("log", f"Slot {slot} written, read back, and verified with CRC32 0x{crc:08X}")
        self.emit("dataset_hint", f"Slot {slot} verified; reloading AI Runtime...")
        try:
            link.runtime_transaction(CMD_REBOOT_LOADER)
        except Exception:
            pass
        time.sleep(0.7)
        for attempt in range(10):
            try:
                link.boot_transaction(CMD_PING, expected=PONG, retries=1)
                break
            except Exception:
                time.sleep(0.3)
        else:
            raise RuntimeError("The system did not return to Loader mode after the dataset update.")
        self._load(FULL_IMEM, FULL_DMEM, "AI Runtime", run_sample=slot)
        self.emit(
            "dataset_hint",
            f"Completed: slot {slot} was replaced and is now displayed. Press S1 to run inference.",
        )

    def refresh_slots(self):
        link = self.require_link()
        link.runtime_transaction(CMD_STATUS)
        rows = []
        for slot in range(100):
            data = link.runtime_transaction(CMD_SLOT_INFO, slot)
            sample_id = struct.unpack_from("<I", data, 0)[0]
            label, valid = data[4], data[5]
            image_crc = struct.unpack_from("<I", data, 8)[0]
            rows.append((slot, sample_id, label, "Yes" if valid else "No",
                         f"{image_crc:08X}"))
            if slot % 5 == 4:
                self.emit("progress", slot + 1, 100, f"Reading slot {slot + 1}/100")
        self.emit("slots", rows)

    def _show_slots(self, rows):
        self.slot_tree.delete(*self.slot_tree.get_children())
        for row in rows:
            self.slot_tree.insert("", "end", values=row)

    def ask_initialize_sd(self):
        drive = simpledialog.askstring(
            "Initialize microSD",
            "Enter the microSD drive letter (for example, G). ALL data on the card will be overwritten:",
            parent=self,
        )
        if not drive:
            return
        drive = drive.strip().rstrip(":\\/").upper()
        if len(drive) != 1 or not drive.isalpha():
            messagebox.showerror("microSD", "Invalid drive letter.")
            return
        if not messagebox.askyesno(
            "Confirm microSD Write",
            f"Write model_sd.img to the entire {drive}: drive? All existing data will be lost.",
        ):
            return
        self.start(lambda: self.initialize_sd(drive))

    def initialize_sd(self, drive: str):
        script = ROOT / "tools" / "write_sd_card.py"
        image = ROOT / "sd_image" / "model_sd.img"
        command = [sys.executable, str(script), "--drive-letter", drive,
                   "--image", str(image), "--yes"]
        self.emit("log", f"Writing RCN1 v3 to drive {drive}: ...")
        result = subprocess.run(command, capture_output=True, text=True)
        self.emit("log", (result.stdout + result.stderr).strip())
        if result.returncode:
            raise RuntimeError(
                "Unable to write the microSD card. Run AI_FPGA_Control.pyw as Administrator."
            )
        self.emit("log", "The initial model and dataset were written to and verified on microSD.")

    def flash_hardware(self):
        if not PROGRAMMER.exists():
            raise RuntimeError(f"Gowin Programmer was not found: {PROGRAMMER}")
        if not BITSTREAM.exists():
            raise RuntimeError("No .fs bitstream was found. Build the FPGA project first.")
        if self.serial and self.serial.is_open:
            self.serial.close()
            self.serial = None
            self.link = None
        self.emit("log", "Erasing, programming, and verifying hardware in external Flash...")
        command = [str(PROGRAMMER), "--cable-index", "1", "--device", "GW2AR-18C",
                   "--operation_index", "37", "--spiaddr", "0x000000",
                   "--fsFile", str(BITSTREAM)]
        result = subprocess.run(command, capture_output=True, text=True)
        self.emit("log", (result.stdout + result.stderr).strip())
        if result.returncode:
            raise RuntimeError("Flash programming failed. Check the USB-C/JTAG connection.")
        self.emit("lamp", "FPGA", True)
        self.emit("log", "The hardware .fs is stored in Flash and will be restored automatically at power-up.")


if __name__ == "__main__":
    if sys.platform == "win32":
        try:
            import ctypes

            ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(
                "Nhom7.TangNano20K.RISCVCNN.ControlCenter"
            )
        except (AttributeError, OSError):
            pass
    App().mainloop()
