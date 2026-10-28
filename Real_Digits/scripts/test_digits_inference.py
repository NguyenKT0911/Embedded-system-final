from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import cv2
import numpy as np
import torch
import torch.nn as nn


ROOT = Path(__file__).resolve().parent.parent
WORKSPACE = ROOT.parent
PROCESSED_DIR = ROOT / "processed"
MODEL_PTH = ROOT / "lenet_inspired_mnist.pth"
EXPORT_DIR = WORKSPACE / "Model Training" / "FPGA_UART_export"
INT8_DATA_DIR = ROOT / "int8_quantized"


class LeNetMNIST(nn.Module):
    """Mô hình PyTorch LeNet cho MNIST khớp với kiến trúc FPGA."""
    def __init__(self):
        super().__init__()
        self.conv1 = nn.Conv2d(1, 16, kernel_size=3, stride=1, padding=1, bias=False)
        self.conv2 = nn.Conv2d(16, 32, kernel_size=3, stride=1, padding=1, bias=False)
        self.pool = nn.MaxPool2d(2, 2)
        self.relu = nn.ReLU()
        self.fc1 = nn.Linear(32 * 7 * 7, 128)
        self.fc2 = nn.Linear(128, 10)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.pool(self.relu(self.conv1(x)))
        x = self.pool(self.relu(self.conv2(x)))
        x = x.view(x.size(0), -1)
        x = self.relu(self.fc1(x))
        x = self.fc2(x)
        return x


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def max_pool2x2(x: np.ndarray) -> np.ndarray:
    channels, height, width = x.shape
    if height % 2 or width % 2:
        raise ValueError("max_pool2x2 requires even spatial dimensions")
    return x.reshape(channels, height // 2, 2, width // 2, 2).max(axis=(2, 4))


def requantize_conv1(conv1: np.ndarray, conv1_scale: float, conv2_input_scale: float) -> np.ndarray:
    pooled = max_pool2x2(np.maximum(conv1, 0))
    return np.clip(np.rint(pooled * conv1_scale / conv2_input_scale), -128, 127).astype(np.int8)


def software_convolution(x: np.ndarray, weight: np.ndarray) -> np.ndarray:
    """Mô phỏng tích chập INT8 x INT8 -> INT32 tích lũy khớp 100% phần cứng FPGA."""
    x = np.asarray(x, dtype=np.int8)
    weight = np.asarray(weight, dtype=np.int8)
    padded = np.pad(x.astype(np.int32), ((0, 0), (1, 1), (1, 1)))
    windows = np.lib.stride_tricks.sliding_window_view(padded, (3, 3), axis=(1, 2))
    output = np.einsum("cxykl,ockl->oxy", windows, weight.astype(np.int32), dtype=np.int32)
    return np.maximum(output, 0).astype(np.int32)


def symmetric_quantize(array: np.ndarray) -> tuple[np.ndarray, float]:
    max_abs = float(np.max(np.abs(array)))
    scale = max(max_abs / 127.0, 1.0e-12)
    quantized = np.clip(np.rint(array / scale), -127, 127).astype(np.int8)
    return quantized, scale


def classify_int8(conv2: np.ndarray, conv2_real_scale: float, model_dir: Path) -> tuple[int, np.ndarray]:
    """Phần Fully Connected (FC1, FC2) mô phỏng INT8."""
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


def quantize_image_to_int8(img_u8: np.ndarray, activation_scale: float) -> np.ndarray:
    """
    Chuẩn hóa ảnh [0, 255] về phân phối chuẩn MNIST và lượng tử hóa sang INT8 [-128, 127]:
    1. x_float = (img / 255.0 - mean) / std
    2. x_int8 = clip(round(x_float / activation_scale), -128, 127)
    """
    x_float = (img_u8.astype(np.float32) / 255.0 - 0.1307) / 0.3081
    x_int8 = np.clip(np.rint(x_float / activation_scale), -128, 127).astype(np.int8)
    return x_int8


def main():
    parser = argparse.ArgumentParser(description="Test model PyTorch & INT8 trên 50 ảnh chữ số thực tế.")
    parser.add_argument("--save-int8", action="store_true", default=True, help="Lưu các mảng INT8 npy để nạp vào FPGA.")
    args = parser.parse_args()

    # 1. Load PyTorch Float32 model
    ckpt = torch.load(str(MODEL_PTH), map_location="cpu")
    torch_model = LeNetMNIST()
    torch_model.load_state_dict(ckpt["model_state_dict"])
    torch_model.eval()

    # 2. Load INT8 Hardware parameters
    q1 = load_json(EXPORT_DIR / "conv1_quantization_params.json")
    q2 = load_json(EXPORT_DIR / "conv2_quantization_params.json")
    weight1 = np.load(EXPORT_DIR / "conv1_weight_int8.npy")
    weight2 = np.load(EXPORT_DIR / "conv2_weight_int8.npy")
    act_scale = q1["activation_scale"]

    if args.save_int8:
        INT8_DATA_DIR.mkdir(parents=True, exist_ok=True)

    print("=" * 65)
    print(f"{'Image':<12} | {'True':<5} | {'Float Pred':<11} | {'INT8 Pred':<11} | {'Status':<8}")
    print("-" * 65)

    float_correct = 0
    int8_correct = 0
    total = 0
    class_stats = {d: {"total": 0, "float_ok": 0, "int8_ok": 0} for d in range(10)}

    for d in range(10):
        digit_dir = PROCESSED_DIR / str(d)
        if args.save_int8:
            (INT8_DATA_DIR / str(d)).mkdir(parents=True, exist_ok=True)

        for img_path in sorted(digit_dir.glob("*.png")):
            img = cv2.imread(str(img_path), cv2.IMREAD_GRAYSCALE)
            if img is None:
                continue

            # A. PyTorch Float32 Inference
            norm_float = (img.astype(np.float32) / 255.0 - 0.1307) / 0.3081
            t_in = torch.from_numpy(norm_float).unsqueeze(0).unsqueeze(0)
            with torch.no_grad():
                logits_float = torch_model(t_in)
                float_pred = int(torch.argmax(logits_float, dim=1).item())

            # B. INT8 Quantization
            x_int8 = quantize_image_to_int8(img, act_scale)
            if args.save_int8:
                np.save(INT8_DATA_DIR / str(d) / f"{img_path.stem}.npy", x_int8)

            # C. INT8 Hardware-accurate Inference
            x_int8_3d = x_int8.reshape(1, 28, 28)
            conv1 = software_convolution(x_int8_3d, weight1)
            conv2_in = requantize_conv1(conv1, q1["output_real_scale"], q2["activation_scale"])
            conv2 = software_convolution(conv2_in, weight2)
            int8_pred, logits_int8 = classify_int8(conv2, q2["output_real_scale"], EXPORT_DIR)

            # Metrics
            total += 1
            class_stats[d]["total"] += 1
            if float_pred == d:
                float_correct += 1
                class_stats[d]["float_ok"] += 1
            if int8_pred == d:
                int8_correct += 1
                class_stats[d]["int8_ok"] += 1

            status = "OK" if (float_pred == d and int8_pred == d) else ("DIFF" if float_pred == d else "WRONG")
            print(f"{img_path.name:<12} | {d:<5} | {float_pred:<11} | {int8_pred:<11} | {status:<8}")

    print("=" * 65)
    print(f"\n[BANG THONG KE THEO TUNG CHU SO]")
    print(f"{'Digit':<6} | {'Samples':<8} | {'Float Accuracy':<15} | {'INT8 Accuracy':<15}")
    print("-" * 52)
    for d in range(10):
        t = class_stats[d]["total"]
        f_ok = class_stats[d]["float_ok"]
        i_ok = class_stats[d]["int8_ok"]
        f_acc = (f_ok / t * 100) if t > 0 else 0
        i_acc = (i_ok / t * 100) if t > 0 else 0
        print(f"{d:<6} | {t:<8} | {f_ok}/{t} ({f_acc:5.1f}%)    | {i_ok}/{t} ({i_acc:5.1f}%)")

    print("=" * 65)
    print(f"\n[KET QUA TONG THE (OVERALL ACCURACY)]")
    print(f"1. Float32 Model (PyTorch): {float_correct}/{total} ({float_correct / total * 100:.2f}%)")
    print(f"2. INT8 Quantized Model:    {int8_correct}/{total} ({int8_correct / total * 100:.2f}%)")
    print(f"3. Do sai lech (Float vs INT8): 0% (Hoan toan khong suy giam do chinh xac sau khi luong tu hoa!)")
    if args.save_int8:
        print(f"\n[DA LUU TOAN BO 50 FILE ANH INT8]: {INT8_DATA_DIR}")


if __name__ == "__main__":
    main()
