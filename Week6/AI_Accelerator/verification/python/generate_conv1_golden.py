#!/usr/bin/env python3
"""
Generate Conv1 RTL golden vectors for the AI Accelerator.

Supported Conv1 shape:
    Input   : [CIN=1, H=28, W=28] signed INT8
    Weights : [COUT=16, CIN=1, KH=3, KW=3] signed INT8
    Stride  : 1
    Padding : 1
    Output  : [COUT=16, H=28, W=28] signed INT32
    ReLU    : optional, enabled by default

The script can:
1) Load real exported NumPy arrays from Python/Colab, OR
2) Generate deterministic synthetic vectors for the first full-size RTL test.

Outputs:
    conv1_input_int8.hex
    conv1_weight_int8.hex
    conv1_input_packed32.hex
    conv1_weight_packed32.hex
    conv1_golden_int32.hex
    conv1_config.txt
"""

import argparse
from pathlib import Path
import numpy as np


H = 28
W = 28
CIN = 1
COUT = 16
K = 3
STRIDE = 1
PADDING = 1


def to_u8(v: int) -> int:
    return int(v) & 0xFF


def to_u32(v: int) -> int:
    return int(v) & 0xFFFFFFFF


def flatten_input_chw(x: np.ndarray) -> np.ndarray:
    # [C,H,W] -> flat [C][H][W]
    return x.reshape(-1)


def flatten_weight_oihw(w: np.ndarray) -> np.ndarray:
    # [COUT,CIN,KH,KW] -> flat [COUT][CIN][KH][KW]
    return w.reshape(-1)


def flatten_output_chw(y: np.ndarray) -> np.ndarray:
    # [COUT,H,W] -> flat [COUT][H][W]
    return y.reshape(-1)


def pack_int8_words(flat: np.ndarray) -> np.ndarray:
    """
    MMIO packing:
      bits  7:0  = value n
      bits 15:8  = value n+1
      bits 23:16 = value n+2
      bits 31:24 = value n+3
    """
    assert flat.size % 4 == 0
    words = []
    for i in range(0, flat.size, 4):
        b0 = to_u8(flat[i + 0])
        b1 = to_u8(flat[i + 1])
        b2 = to_u8(flat[i + 2])
        b3 = to_u8(flat[i + 3])
        word = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        words.append(word)
    return np.asarray(words, dtype=np.uint32)


def conv2d_int8_int32(x: np.ndarray, w: np.ndarray, relu: bool) -> np.ndarray:
    """
    Exact integer convolution:
      INT8 activation * INT8 weight -> INT32 accumulation
      bias = 0
      stride = 1
      padding = 1
    """
    assert x.shape == (CIN, H, W), x.shape
    assert w.shape == (COUT, CIN, K, K), w.shape

    out_h = (H + 2 * PADDING - K) // STRIDE + 1
    out_w = (W + 2 * PADDING - K) // STRIDE + 1

    y = np.zeros((COUT, out_h, out_w), dtype=np.int32)

    for oc in range(COUT):
        for oh in range(out_h):
            for ow in range(out_w):
                acc = np.int64(0)

                for ic in range(CIN):
                    for kh in range(K):
                        for kw in range(K):
                            ih = oh * STRIDE + kh - PADDING
                            iw = ow * STRIDE + kw - PADDING

                            if 0 <= ih < H and 0 <= iw < W:
                                acc += (
                                    np.int64(x[ic, ih, iw])
                                    * np.int64(w[oc, ic, kh, kw])
                                )

                # Hardware accumulator is signed INT32.
                value = np.int32(acc)

                if relu and value < 0:
                    value = np.int32(0)

                y[oc, oh, ow] = value

    return y


def load_or_generate(args):
    if args.input_npy:
        x = np.load(args.input_npy)
        x = np.asarray(x, dtype=np.int8)
    else:
        # Deterministic full-size pattern, not random.
        # Values stay small so debugging is easy.
        vals = ((np.arange(CIN * H * W) * 7 + 3) % 17) - 8
        x = vals.astype(np.int8).reshape(CIN, H, W)

    if args.weight_npy:
        w = np.load(args.weight_npy)
        w = np.asarray(w, dtype=np.int8)
    else:
        vals = ((np.arange(COUT * CIN * K * K) * 5 + 1) % 9) - 4
        w = vals.astype(np.int8).reshape(COUT, CIN, K, K)

    if x.shape != (CIN, H, W):
        raise ValueError(
            f"Input shape must be {(CIN, H, W)}, got {x.shape}. "
            "Expected layout [C,H,W]."
        )

    if w.shape != (COUT, CIN, K, K):
        raise ValueError(
            f"Weight shape must be {(COUT, CIN, K, K)}, got {w.shape}. "
            "Expected layout [COUT,CIN,KH,KW]."
        )

    return x, w


def write_hex_lines(path: Path, values, digits: int):
    with path.open("w", encoding="utf-8") as f:
        for v in values:
            if digits == 2:
                f.write(f"{to_u8(v):02X}\n")
            elif digits == 8:
                f.write(f"{to_u32(v):08X}\n")
            else:
                raise ValueError("Unsupported hex width")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--input-npy",
        type=str,
        default=None,
        help="Optional real Conv1 INT8 activation .npy in shape [1,28,28]",
    )
    parser.add_argument(
        "--weight-npy",
        type=str,
        default=None,
        help="Optional real Conv1 INT8 weight .npy in shape [16,1,3,3]",
    )
    parser.add_argument(
        "--out-dir",
        type=str,
        default="golden/conv1",
        help="Output directory",
    )
    parser.add_argument(
        "--relu",
        type=int,
        choices=[0, 1],
        default=1,
        help="Apply ReLU to golden output (default: 1)",
    )
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    x, w = load_or_generate(args)
    y = conv2d_int8_int32(x, w, relu=bool(args.relu))

    x_flat = flatten_input_chw(x)
    w_flat = flatten_weight_oihw(w)
    y_flat = flatten_output_chw(y)

    x_words = pack_int8_words(x_flat)
    w_words = pack_int8_words(w_flat)

    write_hex_lines(out_dir / "conv1_input_int8.hex", x_flat, 2)
    write_hex_lines(out_dir / "conv1_weight_int8.hex", w_flat, 2)
    write_hex_lines(out_dir / "conv1_golden_int32.hex", y_flat, 8)

    with (out_dir / "conv1_input_packed32.hex").open("w", encoding="utf-8") as f:
        for word in x_words:
            f.write(f"{int(word):08X}\n")

    with (out_dir / "conv1_weight_packed32.hex").open("w", encoding="utf-8") as f:
        for word in w_words:
            f.write(f"{int(word):08X}\n")

    out_h = y.shape[1]
    out_w = y.shape[2]

    config = f"""CONV1 GOLDEN CONFIG
===================
INPUT_H={H}
INPUT_W={W}
CIN={CIN}
COUT={COUT}
KERNEL_SIZE={K}
STRIDE={STRIDE}
PADDING={PADDING}
RELU_EN={args.relu}
OUT_H={out_h}
OUT_W={out_w}

INPUT_VALUES={x_flat.size}
INPUT_PACKED_WORDS={x_words.size}

WEIGHT_VALUES={w_flat.size}
WEIGHT_PACKED_WORDS={w_words.size}

OUTPUT_VALUES={y_flat.size}

LAYOUT_INPUT=[C][H][W]
LAYOUT_WEIGHT=[COUT][CIN][KH][KW]
LAYOUT_OUTPUT=[COUT][OUT_H][OUT_W]

PACKING_32BIT:
bits[7:0]   = value n
bits[15:8]  = value n+1
bits[23:16] = value n+2
bits[31:24] = value n+3
"""
    (out_dir / "conv1_config.txt").write_text(config, encoding="utf-8")

    print("Conv1 golden vectors generated successfully.")
    print(f"Input values       : {x_flat.size}")
    print(f"Input packed words : {x_words.size}")
    print(f"Weight values      : {w_flat.size}")
    print(f"Weight packed words: {w_words.size}")
    print(f"Output values      : {y_flat.size}")
    print(f"Output directory   : {out_dir.resolve()}")
    print()
    print("First 8 input values :", x_flat[:8].tolist())
    print("First 8 weights      :", w_flat[:8].tolist())
    print("First 8 golden output:", y_flat[:8].tolist())


if __name__ == "__main__":
    main()
