#!/usr/bin/env python3
"""Build the raw-sector deployment image consumed by the RV32I firmware.

The image deliberately uses a tiny fixed layout instead of FAT.  This keeps
the firmware small, deterministic, and testable without pulling a filesystem
into the FPGA design.  Every payload is sector aligned and protected by CRC32.
"""

from __future__ import annotations

import argparse
import json
import struct
import zlib
from dataclasses import dataclass
from pathlib import Path

import numpy as np

SECTOR_SIZE = 512
MAGIC = b"RCN1"
VERSION = 3

TYPE_CONV1_WEIGHT = 1
TYPE_CONV2_WEIGHT = 2
TYPE_FC1_WEIGHT = 3
TYPE_FC1_BIAS_K = 4
TYPE_FC2_WEIGHT = 5
TYPE_FC2_BIAS_K = 6
TYPE_SAMPLE = 7
SAMPLE_HEADER_SIZE = 32
SAMPLE_IMAGE_SIZE = 28 * 28
SAMPLE_RECORD_SIZE = SAMPLE_HEADER_SIZE + SAMPLE_IMAGE_SIZE


@dataclass
class Section:
    type_id: int
    name: str
    data: bytes
    sector: int = 0

    @property
    def sectors(self) -> int:
        return (len(self.data) + SECTOR_SIZE - 1) // SECTOR_SIZE

    @property
    def crc32(self) -> int:
        # The dataset is mutable in-place.  Each slot has its own CRC, so the
        # section-wide CRC is deliberately zero and is not checked by firmware.
        if self.type_id == TYPE_SAMPLE:
            return 0
        return zlib.crc32(self.data) & 0xFFFFFFFF


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def round_div_signed(numerator: np.ndarray, denominator: int) -> np.ndarray:
    values = np.asarray(numerator, dtype=np.int64)
    positive = (np.abs(values) + denominator // 2) // denominator
    return np.where(values < 0, -positive, positive)


def max_pool2x2(x: np.ndarray) -> np.ndarray:
    channels, height, width = x.shape
    return x.reshape(channels, height // 2, 2, width // 2, 2).max(axis=(2, 4))


def software_convolution(x: np.ndarray, weight: np.ndarray) -> np.ndarray:
    x = np.asarray(x, dtype=np.int8)
    padded = np.pad(x.astype(np.int32), ((0, 0), (1, 1), (1, 1)))
    windows = np.lib.stride_tricks.sliding_window_view(
        padded, (3, 3), axis=(1, 2)
    )
    output = np.einsum(
        "cxykl,ockl->oxy",
        windows,
        np.asarray(weight, dtype=np.int32),
        dtype=np.int32,
    )
    return np.maximum(output, 0).astype(np.int32)


def symmetric_quantize(values: np.ndarray) -> tuple[np.ndarray, float]:
    array = np.asarray(values, dtype=np.float32)
    maximum = float(np.max(np.abs(array)))
    scale = maximum / 127.0 if maximum else 1.0
    quantized = np.clip(np.rint(array / scale), -128, 127).astype(np.int8)
    return quantized, scale


def host_classify(conv2: np.ndarray, conv2_scale: float, model_dir: Path) -> tuple[int, np.ndarray]:
    features = (max_pool2x2(conv2) * conv2_scale).astype(np.float32).reshape(-1)
    fc1_weight = np.load(model_dir / "fc1_weight_float.npy")
    fc1_bias = np.load(model_dir / "fc1_bias_float.npy")
    fc2_weight = np.load(model_dir / "fc2_weight_float.npy")
    fc2_bias = np.load(model_dir / "fc2_bias_float.npy")
    q_features, feature_scale = symmetric_quantize(features)
    q_fc1, fc1_scale = symmetric_quantize(fc1_weight)
    hidden_acc = q_features.astype(np.int32) @ q_fc1.astype(np.int32).T
    hidden = np.maximum(
        hidden_acc.astype(np.float32) * (feature_scale * fc1_scale) + fc1_bias,
        0,
    )
    q_hidden, hidden_scale = symmetric_quantize(hidden)
    q_fc2, fc2_scale = symmetric_quantize(fc2_weight)
    logits_acc = q_hidden.astype(np.int32) @ q_fc2.astype(np.int32).T
    logits = logits_acc.astype(np.float32) * (hidden_scale * fc2_scale) + fc2_bias
    return int(np.argmax(logits)), logits


def build_sample_set(
    model_dir: Path,
    samples_dir: Path,
    reference: dict,
) -> tuple[bytes, list[dict]]:
    q1 = load_json(model_dir / "conv1_quantization_params.json")
    q2 = load_json(model_dir / "conv2_quantization_params.json")
    weight1 = np.load(model_dir / "conv1_weight_int8.npy").astype(np.int8)
    weight2 = np.load(model_dir / "conv2_weight_int8.npy").astype(np.int8)
    fc1_weight = np.load(model_dir / "fc1_weight_int8.npy").astype(np.int32)
    fc2_weight = np.load(model_dir / "fc2_weight_int8.npy").astype(np.int32)
    records = bytearray()
    metadata: list[dict] = []

    for digit in range(10):
        paths = sorted((samples_dir / str(digit)).glob("*.npy"))
        if len(paths) != 10:
            raise ValueError(f"digit {digit} needs exactly 10 samples, found {len(paths)}")
        for slot, path in enumerate(paths):
            activation = np.load(path).astype(np.int8)
            if activation.shape != (28, 28):
                raise ValueError(f"unexpected sample shape {activation.shape}: {path}")
            conv1 = software_convolution(activation[None, :, :], weight1)
            pooled1 = max_pool2x2(conv1)
            conv2_input = np.clip(
                np.rint(
                    pooled1
                    * float(q1["output_real_scale"])
                    / float(q2["activation_scale"])
                ),
                -128,
                127,
            ).astype(np.int8)
            conv2 = software_convolution(conv2_input, weight2)
            pooled2 = max_pool2x2(conv2)
            calibration_max = int(pooled2.max())
            if calibration_max <= 0:
                raise ValueError(f"zero Conv2 calibration maximum: {path}")

            # Exact integer path used by the standalone RV32I firmware.
            features = np.clip(
                (pooled2.astype(np.int64) * 127 + calibration_max // 2)
                // calibration_max,
                0,
                127,
            ).astype(np.int8).reshape(-1)
            fc1_bias_acc = round_div_signed(
                reference["fc1_bias_k"], calibration_max
            )
            hidden = np.maximum(
                features.astype(np.int32) @ fc1_weight.T + fc1_bias_acc,
                0,
            ).astype(np.int64)
            hidden_max = int(hidden.max())
            hidden_q = np.clip(
                (hidden * 127 + hidden_max // 2) // hidden_max, 0, 127
            ).astype(np.int8)
            denominator = calibration_max * hidden_max
            fc2_bias_acc = round_div_signed(reference["fc2_bias_k"], denominator)
            integer_logits = (
                hidden_q.astype(np.int32) @ fc2_weight.T + fc2_bias_acc
            )
            integer_prediction = int(np.argmax(integer_logits))

            host_prediction, host_logits = host_classify(
                conv2, float(q2["output_real_scale"]), model_dir
            )
            stable = host_logits - np.max(host_logits)
            probabilities = np.exp(stable) / np.exp(stable).sum()
            confidence_by_class = np.clip(
                np.rint(probabilities * 100.0), 0, 100
            ).astype(np.uint8)

            image_bytes = activation.tobytes()
            image_crc = zlib.crc32(image_bytes) & 0xFFFFFFFF
            sample_id = digit * 10 + slot
            # 32-byte mutable-slot metadata: ID, label, valid, reserved,
            # image CRC, record CRC, calibration max, 10 confidences, reserve.
            record = bytearray(struct.pack(
                "<IBBHIII10B2x",
                sample_id, digit, 1, 0, image_crc, 0, calibration_max,
                *confidence_by_class,
            ))
            record.extend(image_bytes)
            record_crc = zlib.crc32(record) & 0xFFFFFFFF
            struct.pack_into("<I", record, 12, record_crc)
            records.extend(record)
            metadata.append(
                {
                    "index": sample_id,
                    "sample_id": sample_id,
                    "valid": True,
                    "image_crc32": f"0x{image_crc:08x}",
                    "record_crc32": f"0x{record_crc:08x}",
                    "file": path.name,
                    "label": digit,
                    "integer_prediction": integer_prediction,
                    "host_prediction": host_prediction,
                    "confidence": int(confidence_by_class[integer_prediction]),
                    "conv2_calibration_max": calibration_max,
                }
            )

    return bytes(records), metadata


def integer_reference(model_dir: Path) -> dict:
    conv2 = np.load(model_dir / "conv2_golden_relu_int32.npy").astype(np.int32)
    if conv2.shape != (32, 14, 14):
        raise ValueError(f"unexpected Conv2 shape: {conv2.shape}")
    pooled = conv2.reshape(32, 7, 2, 7, 2).max(axis=(2, 4))
    pooled_max = int(pooled.max())
    if pooled_max <= 0:
        raise ValueError("Conv2 pooled maximum must be positive")

    features = ((pooled.astype(np.int64) * 127 + pooled_max // 2) // pooled_max)
    features = np.clip(features, 0, 127).astype(np.int8).reshape(-1)

    q2 = load_json(model_dir / "conv2_quantization_params.json")
    fcq = load_json(model_dir / "fc_quantization_params.json")
    fc1_w = np.load(model_dir / "fc1_weight_int8.npy").astype(np.int8)
    fc1_b = np.load(model_dir / "fc1_bias_float.npy").astype(np.float64)
    fc2_w = np.load(model_dir / "fc2_weight_int8.npy").astype(np.int8)
    fc2_b = np.load(model_dir / "fc2_bias_float.npy").astype(np.float64)

    fc1_unit = (
        float(q2["output_real_scale"])
        * float(fcq["fc1_weight_scale"])
        / 127.0
    )
    fc1_bias_k = np.rint(fc1_b / fc1_unit).astype("<i4")
    fc1_acc = features.astype(np.int32) @ fc1_w.astype(np.int32).T
    fc1_bias_acc = round_div_signed(fc1_bias_k, pooled_max)
    hidden = np.maximum(fc1_acc.astype(np.int64) + fc1_bias_acc, 0)
    hidden_max = int(hidden.max())
    if hidden_max <= 0:
        raise ValueError("FC1 maximum must be positive")
    hidden_q = ((hidden * 127 + hidden_max // 2) // hidden_max)
    hidden_q = np.clip(hidden_q, 0, 127).astype(np.int8)

    fc2_unit = (
        float(q2["output_real_scale"])
        * float(fcq["fc1_weight_scale"])
        * float(fcq["fc2_weight_scale"])
        / float(127 * 127)
    )
    fc2_bias_k = np.rint(fc2_b / fc2_unit).astype("<i8")
    fc2_acc = hidden_q.astype(np.int32) @ fc2_w.astype(np.int32).T
    denominator = pooled_max * hidden_max
    fc2_bias_acc = round_div_signed(fc2_bias_k, denominator)
    logits = fc2_acc.astype(np.int64) + fc2_bias_acc
    prediction = int(np.argmax(logits))

    return {
        "pooled_max": pooled_max,
        "feature_int8": features,
        "fc1_bias_k": fc1_bias_k,
        "hidden_max": hidden_max,
        "hidden_int8": hidden_q,
        "fc2_bias_k": fc2_bias_k,
        "integer_logits": logits,
        "prediction": prediction,
    }


def build_image(model_dir: Path, output_dir: Path, samples_dir: Path) -> dict:
    manifest = load_json(model_dir / "manifest.json")
    reference = integer_reference(model_dir)
    expected = int(manifest["sample_prediction"])
    if reference["prediction"] != expected:
        raise RuntimeError(
            f"integer deployment pipeline predicts {reference['prediction']}, expected {expected}"
        )

    conv1_q = load_json(model_dir / "conv1_quantization_params.json")
    conv2_q = load_json(model_dir / "conv2_quantization_params.json")
    conv1_ratio = (
        float(conv1_q["output_real_scale"])
        / float(conv2_q["activation_scale"])
    )
    conv1_mul_q20 = int(round(conv1_ratio * (1 << 20)))

    sample_data, sample_metadata = build_sample_set(model_dir, samples_dir, reference)
    sections = [
        Section(TYPE_CONV1_WEIGHT, "conv1_weight", np.load(model_dir / "conv1_weight_int8.npy").astype(np.int8).tobytes()),
        Section(TYPE_CONV2_WEIGHT, "conv2_weight", np.load(model_dir / "conv2_weight_int8.npy").astype(np.int8).tobytes()),
        Section(TYPE_FC1_WEIGHT, "fc1_weight", np.load(model_dir / "fc1_weight_int8.npy").astype(np.int8).tobytes()),
        Section(TYPE_FC1_BIAS_K, "fc1_bias_k", reference["fc1_bias_k"].tobytes()),
        Section(TYPE_FC2_WEIGHT, "fc2_weight", np.load(model_dir / "fc2_weight_int8.npy").astype(np.int8).tobytes()),
        Section(TYPE_FC2_BIAS_K, "fc2_bias_k", reference["fc2_bias_k"].tobytes()),
        Section(TYPE_SAMPLE, "sample_set", sample_data),
    ]

    next_sector = 1
    for section in sections:
        section.sector = next_sector
        next_sector += section.sectors

    header = bytearray(SECTOR_SIZE)
    struct.pack_into(
        "<4s7I",
        header,
        0,
        MAGIC,
        VERSION,
        SECTOR_SIZE,
        0,
        len(sample_metadata),
        10,
        conv1_mul_q20,
        len(sections),
    )
    struct.pack_into("<I", header, 32, next_sector)
    struct.pack_into("<I", header, 36, reference["pooled_max"])
    struct.pack_into("<I", header, 40, SAMPLE_RECORD_SIZE)
    for index, section in enumerate(sections):
        struct.pack_into(
            "<4I",
            header,
            64 + index * 16,
            section.type_id,
            section.sector,
            len(section.data),
            section.crc32,
        )
    struct.pack_into("<I", header, 56, 0)
    struct.pack_into("<I", header, 56, zlib.crc32(header) & 0xFFFFFFFF)

    image = bytearray(header)
    for section in sections:
        target = section.sector * SECTOR_SIZE
        if len(image) < target:
            image.extend(b"\x00" * (target - len(image)))
        image.extend(section.data)
        padding = (-len(image)) % SECTOR_SIZE
        image.extend(b"\x00" * padding)

    output_dir.mkdir(parents=True, exist_ok=True)
    image_path = output_dir / "model_sd.img"
    image_path.write_bytes(image)
    (output_dir / "model_sd.hex").write_text(
        "\n".join(f"{byte:02x}" for byte in image) + "\n",
        encoding="ascii",
    )

    layout = {
        "format": "RCN1 raw sector image",
        "version": VERSION,
        "sector_size": SECTOR_SIZE,
        "total_sectors": len(image) // SECTOR_SIZE,
        "sample_count": len(sample_metadata),
        "samples_per_digit": 10,
        "sample_record_size": SAMPLE_RECORD_SIZE,
        "conv1_requant_multiplier_q20": conv1_mul_q20,
        "conv2_feature_calibration_max": reference["pooled_max"],
        "sections": [
            {
                "type": section.type_id,
                "name": section.name,
                "sector": section.sector,
                "byte_length": len(section.data),
                "sector_count": section.sectors,
                "crc32": f"0x{section.crc32:08x}",
            }
            for section in sections
        ],
        "sample_integer_accuracy": sum(
            item["integer_prediction"] == item["label"] for item in sample_metadata
        ),
        "sample_host_accuracy": sum(
            item["host_prediction"] == item["label"] for item in sample_metadata
        ),
        "samples": sample_metadata,
    }
    (output_dir / "model_layout.json").write_text(
        json.dumps(layout, indent=2), encoding="utf-8"
    )
    golden = {
        "pooled_max": reference["pooled_max"],
        "hidden_max": reference["hidden_max"],
        "integer_logits": [int(value) for value in reference["integer_logits"]],
        "prediction": reference["prediction"],
    }
    (output_dir / "golden_integer.json").write_text(
        json.dumps(golden, indent=2), encoding="utf-8"
    )
    return layout


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("model_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument(
        "--samples-dir",
        type=Path,
        default=Path(__file__).resolve().parents[3] / "Real_Digits" / "int8_quantized",
    )
    args = parser.parse_args()
    layout = build_image(
        args.model_dir.resolve(), args.output_dir.resolve(), args.samples_dir.resolve()
    )
    print(json.dumps(layout, indent=2))
    print("RESULT: SD DEPLOYMENT IMAGE EXPORTED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
