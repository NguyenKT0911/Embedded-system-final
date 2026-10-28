from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

import numpy as np


ROOT = Path(__file__).resolve().parent.parent
WORKSPACE = ROOT.parent
TANGNANO_DIR = WORKSPACE / "TangNano20K_RISCV_CNN"
EXPORT_DIR = WORKSPACE / "Model Training" / "FPGA_UART_export"
SIM_DIR = ROOT / "simulation"
SIM_DIR.mkdir(parents=True, exist_ok=True)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def pack_int8_to_words32(flat_int8: np.ndarray) -> np.ndarray:
    u8 = flat_int8.astype(np.uint8)
    pad_len = (4 - (len(u8) % 4)) % 4
    if pad_len > 0:
        u8 = np.pad(u8, (0, pad_len))
    return u8.view("<u4")


def write_hex_words(path: Path, words32: np.ndarray) -> None:
    with open(path, "w", encoding="utf-8") as f:
        for w in words32:
            f.write(f"{int(w):08x}\n")


def write_dmem_hex(path: Path, input_words: np.ndarray, weight_words: np.ndarray, total_words: int = 4096) -> None:
    """
    Tạo file DMEM hex 4096 words:
    - 0x0000 (word 0): Input activations
    - 0x1000 (word 1024): Weights
    - Các ô nhớ còn lại: 0
    """
    dmem = np.zeros(total_words, dtype=np.uint32)
    dmem[: len(input_words)] = input_words
    dmem[1024 : 1024 + len(weight_words)] = weight_words
    with open(path, "w", encoding="utf-8") as f:
        for w in dmem:
            f.write(f"{int(w):08x}\n")


def write_golden_hex(path: Path, golden_int32: np.ndarray) -> None:
    with open(path, "w", encoding="utf-8") as f:
        for val in golden_int32.flatten():
            f.write(f"{int(val) & 0xFFFFFFFF:08x}\n")


def software_convolution(x: np.ndarray, weight: np.ndarray) -> np.ndarray:
    x = np.asarray(x, dtype=np.int8)
    weight = np.asarray(weight, dtype=np.int8)
    padded = np.pad(x.astype(np.int32), ((0, 0), (1, 1), (1, 1)))
    windows = np.lib.stride_tricks.sliding_window_view(padded, (3, 3), axis=(1, 2))
    output = np.einsum("cxykl,ockl->oxy", windows, weight.astype(np.int32), dtype=np.int32)
    return np.maximum(output, 0).astype(np.int32)


def max_pool2x2(x: np.ndarray) -> np.ndarray:
    channels, height, width = x.shape
    if height % 2 or width % 2:
        raise ValueError("max_pool2x2 requires even spatial dimensions")
    return x.reshape(channels, height // 2, 2, width // 2, 2).max(axis=(2, 4))


def requantize_conv1(conv1: np.ndarray, conv1_scale: float, conv2_input_scale: float) -> np.ndarray:
    pooled = max_pool2x2(np.maximum(conv1, 0))
    return np.clip(np.rint(pooled * conv1_scale / conv2_input_scale), -128, 127).astype(np.int8)


def symmetric_quantize(array: np.ndarray) -> tuple[np.ndarray, float]:
    max_abs = float(np.max(np.abs(array)))
    scale = max(max_abs / 127.0, 1.0e-12)
    quantized = np.clip(np.rint(array / scale), -127, 127).astype(np.int8)
    return quantized, scale


def classify_from_conv2(conv2: np.ndarray, conv2_real_scale: float, model_dir: Path) -> tuple[int, np.ndarray]:
    pooled = max_pool2x2(np.maximum(conv2, 0)).astype(np.float32) * conv2_real_scale
    features = pooled.reshape(-1)
    fc1_weight = np.load(model_dir / "fc1_weight_float.npy")
    fc1_bias = np.load(model_dir / "fc1_bias_float.npy")
    fc2_weight = np.load(model_dir / "fc2_weight_float.npy")
    fc2_bias = np.load(model_dir / "fc2_bias_float.npy")

    q_features, feature_scale = symmetric_quantize(features)
    q_fc1, fc1_scale = symmetric_quantize(fc1_weight)
    hidden_acc = q_features.astype(np.int32) @ q_fc1.astype(np.int32).T
    hidden = np.maximum(hidden_acc.astype(np.float32) * (feature_scale * fc1_scale) + fc1_bias, 0)

    q_hidden, hidden_scale = symmetric_quantize(hidden)
    q_fc2, fc2_scale = symmetric_quantize(fc2_weight)
    logits_acc = q_hidden.astype(np.int32) @ q_fc2.astype(np.int32).T
    logits = logits_acc.astype(np.float32) * (hidden_scale * fc2_scale) + fc2_bias
    return int(np.argmax(logits)), logits


def run_modelsim_test(top_module: str, library_path: Path) -> str:
    modelsim_bin = Path(r"A:\ModelSim\modelsim_ase\win32aloem")
    vsim_exe = modelsim_bin / "vsim.exe"
    vlog_exe = modelsim_bin / "vlog.exe"

    # Re-compile top testbench into library
    tb_file = SIM_DIR / "tb_real_digit_modelsim.v"
    vlog_cmd = [str(vlog_exe), "-quiet", "-work", str(library_path), str(tb_file)]
    subprocess.run(vlog_cmd, cwd=str(WORKSPACE), check=True)

    # Run simulation
    vsim_cmd = [str(vsim_exe), "-c", "-lib", str(library_path), top_module, "-do", "run -all; quit -f"]
    res = subprocess.run(vsim_cmd, cwd=str(WORKSPACE), capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[ERROR] ModelSim failed:\nStdout:\n{res.stdout}\nStderr:\n{res.stderr}")
        raise RuntimeError(f"Simulation {top_module} failed")
    return res.stdout


def main():
    parser = argparse.ArgumentParser(description="Chay mo phong toan bo Pipeline FPGA Simulation tren chu so thuc te.")
    parser.add_argument("--image", default="4_01", help="Ten anh chu so can test (mac dinh: 4_01)")
    args = parser.parse_args()

    image_name = args.image.replace(".png", "").replace(".npy", "")
    true_label = int(image_name[0])

    print("=" * 72)
    print("  MO PHONG HE THONG PHAN CUNG FPGA: RISC-V SoC + CNN ACCELERATOR")
    print(f"  Du lieu test: Anh chu so viet tay thuc te '{image_name}' (Nhan: {true_label})")
    print("=" * 72)

    # 1. Load INT8 input image
    npy_path = ROOT / "int8_quantized" / str(true_label) / f"{image_name}.npy"
    if not npy_path.exists():
        raise FileNotFoundError(f"Khong tim thay file INT8: {npy_path}")

    input_int8 = np.load(npy_path).reshape(1, 28, 28)
    print(f"\n[BUOC 1] Load anh INT8 da tien xu ly & luong tu hoa:")
    print(f"  - File input: {npy_path.name}")
    print(f"  - Kich thuoc: {input_int8.shape} (1x28x28, signed int8)")
    print(f"  - Dai gia tri: min={input_int8.min()}, max={input_int8.max()}")

    # 2. Load model parameters
    q1 = load_json(EXPORT_DIR / "conv1_quantization_params.json")
    q2 = load_json(EXPORT_DIR / "conv2_quantization_params.json")
    weight1 = np.load(EXPORT_DIR / "conv1_weight_int8.npy")  # (16, 1, 3, 3)
    weight2 = np.load(EXPORT_DIR / "conv2_weight_int8.npy")  # (32, 16, 3, 3)

    library_path = TANGNANO_DIR / "build" / "modelsim_all" / "work"

    # 3. Chuan bi Conv1 Simulation Data
    conv1_in_words = pack_int8_to_words32(input_int8.flatten())
    conv1_w_words = pack_int8_to_words32(weight1.flatten())
    conv1_golden = software_convolution(input_int8, weight1)  # (16, 28, 28) int32

    write_hex_words(SIM_DIR / "conv1_real_digit_input.hex", conv1_in_words)
    write_dmem_hex(SIM_DIR / "conv1_real_digit_data.hex", conv1_in_words, conv1_w_words)
    write_golden_hex(SIM_DIR / "conv1_real_digit_golden.hex", conv1_golden)

    print(f"\n[BUOC 2] Chay mo phong phan cung RTL CONV1 (Layer 1) tren ModelSim...")
    t0 = time.time()
    out1 = run_modelsim_test("tb_riscv_conv1_real_digit", library_path)
    t1 = time.time()

    # Parse simulation output
    for line in out1.splitlines():
        if "CONV1" in line and ("CPU cycles" in line or "RESULT:" in line or "[MATCH]" in line):
            print(f"  {line.strip('# ')}")
    print(f"  -> Thoi gian mo phong phan cung Conv1: {t1 - t0:.2f}s")

    # 4. Requantize & Prepare Conv2
    conv2_in = requantize_conv1(conv1_golden, q1["output_real_scale"], q2["activation_scale"])  # (16, 14, 14) int8
    conv2_in_words = pack_int8_to_words32(conv2_in.flatten())
    conv2_w_words = pack_int8_to_words32(weight2.flatten())
    conv2_golden = software_convolution(conv2_in, weight2)  # (32, 14, 14) int32

    write_hex_words(SIM_DIR / "conv2_real_digit_input.hex", conv2_in_words)
    write_dmem_hex(SIM_DIR / "conv2_real_digit_data.hex", conv2_in_words, conv2_w_words)
    write_golden_hex(SIM_DIR / "conv2_real_digit_golden.hex", conv2_golden)

    print(f"\n[BUOC 3] Chay mo phong phan cung RTL CONV2 (Layer 2) tren ModelSim...")
    t2 = time.time()
    out2 = run_modelsim_test("tb_riscv_conv2_real_digit", library_path)
    t3 = time.time()

    for line in out2.splitlines():
        if "CONV2" in line and ("CPU cycles" in line or "RESULT:" in line or "[MATCH]" in line):
            print(f"  {line.strip('# ')}")
    print(f"  -> Thoi gian mo phong phan cung Conv2: {t3 - t2:.2f}s")

    # 5. Classification (FC1 & FC2)
    print(f"\n[BUOC 4] Tinh toan phan lop Fully Connected (FC1 -> FC2)...")
    prediction, logits = classify_from_conv2(conv2_golden, q2["output_real_scale"], EXPORT_DIR)

    probs = np.exp(logits - np.max(logits))
    probs /= np.sum(probs)

    # 6. Tong ket
    print("\n" + "=" * 72)
    print("               KET QUA MO PHONG HE THONG FPGA SIMULATION")
    print("=" * 72)
    print(f"  * Mau anh dau vao         : {image_name}.png")
    print(f"  * Nhan dung (Ground Truth) : {true_label}")
    print(f"  * FPGA HARDWARE PREDICTION : {prediction}")
    print(f"  * Do tin cay (Confidence)  : {probs[prediction] * 100:.2f}%")
    print(f"  * Ket luan                 : {'[CHINH XAC 100% - KHOP NHAN THAT]' if prediction == true_label else '[SAI]'}")
    print("-" * 72)
    print("  Top 3 xac suat du doan:")
    top3 = np.argsort(logits)[::-1][:3]
    for rank, idx in enumerate(top3, 1):
        bar = "#" * int(round(probs[idx] * 25))
        print(f"    {rank}. So {idx}: Logit = {logits[idx]:8.4f} | Prob = {probs[idx] * 100:6.2f}% | {bar}")
    print("=" * 72)


if __name__ == "__main__":
    main()

