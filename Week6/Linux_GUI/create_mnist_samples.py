import os
import csv
import json
import gzip
import struct
import random
import urllib.request
import zlib
import binascii

# =========================================================
# CONFIG
# =========================================================
OUTPUT_DIR = "."
IMAGE_DIR = os.path.join(OUTPUT_DIR, "images")
DATA_DIR = os.path.join(OUTPUT_DIR, "mnist_raw")

SAMPLES_PER_DIGIT = 10
SEED = 2026

os.makedirs(IMAGE_DIR, exist_ok=True)
os.makedirs(DATA_DIR, exist_ok=True)

IMAGE_URL = (
    "https://storage.googleapis.com/cvdf-datasets/mnist/"
    "t10k-images-idx3-ubyte.gz"
)

LABEL_URL = (
    "https://storage.googleapis.com/cvdf-datasets/mnist/"
    "t10k-labels-idx1-ubyte.gz"
)

IMAGE_GZ = os.path.join(DATA_DIR, "t10k-images.gz")
LABEL_GZ = os.path.join(DATA_DIR, "t10k-labels.gz")


# =========================================================
# DOWNLOAD
# =========================================================
def download(url, path):
    if os.path.exists(path):
        print(f"[OK] Already exists: {path}")
        return

    print(f"[DOWNLOAD] {url}")
    urllib.request.urlretrieve(url, path)
    print(f"[OK] Saved: {path}")


# =========================================================
# SIMPLE PNG WRITER
# No Pillow required
# =========================================================
def png_chunk(chunk_type, data):
    chunk = chunk_type + data
    return (
        struct.pack(">I", len(data))
        + chunk
        + struct.pack(">I", binascii.crc32(chunk) & 0xFFFFFFFF)
    )


def save_grayscale_png(path, pixels, width=28, height=28):
    # PNG signature
    png = b"\x89PNG\r\n\x1a\n"

    # IHDR: 8-bit grayscale
    ihdr = struct.pack(
        ">IIBBBBB",
        width,
        height,
        8,  # bit depth
        0,  # grayscale
        0,
        0,
        0
    )

    png += png_chunk(b"IHDR", ihdr)

    # Each scanline starts with filter byte 0
    raw = bytearray()

    for y in range(height):
        raw.append(0)
        start = y * width
        raw.extend(pixels[start:start + width])

    compressed = zlib.compress(bytes(raw))
    png += png_chunk(b"IDAT", compressed)
    png += png_chunk(b"IEND", b"")

    with open(path, "wb") as f:
        f.write(png)


# =========================================================
# LOAD MNIST IDX FILES
# =========================================================
def load_images(path):
    with gzip.open(path, "rb") as f:
        magic, count, rows, cols = struct.unpack(">IIII", f.read(16))

        if magic != 2051:
            raise ValueError("Invalid MNIST image file")

        images = []

        for _ in range(count):
            images.append(f.read(rows * cols))

        return images, rows, cols


def load_labels(path):
    with gzip.open(path, "rb") as f:
        magic, count = struct.unpack(">II", f.read(8))

        if magic != 2049:
            raise ValueError("Invalid MNIST label file")

        return list(f.read(count))


# =========================================================
# MAIN
# =========================================================
download(IMAGE_URL, IMAGE_GZ)
download(LABEL_URL, LABEL_GZ)

print("\n[INFO] Reading MNIST...")
images, rows, cols = load_images(IMAGE_GZ)
labels = load_labels(LABEL_GZ)

print(f"[INFO] Test images: {len(images)}")
print(f"[INFO] Image size : {rows} x {cols}")

# Group dataset indices by digit
indices_by_digit = {digit: [] for digit in range(10)}

for i, label in enumerate(labels):
    indices_by_digit[label].append(i)

random.seed(SEED)

selected = []

# Exactly 10 random samples for each digit
for digit in range(10):
    chosen = random.sample(
        indices_by_digit[digit],
        SAMPLES_PER_DIGIT
    )

    for dataset_index in chosen:
        selected.append((digit, dataset_index))

# Shuffle the 100 samples so IDs do not directly reveal labels
random.shuffle(selected)

samples = []

for sample_number, (digit, dataset_index) in enumerate(selected):

    sample_id = f"{sample_number:04d}"
    filename = f"sample_{sample_id}.png"

    output_path = os.path.join(IMAGE_DIR, filename)

    save_grayscale_png(
        output_path,
        images[dataset_index],
        rows,
        cols
    )

    samples.append({
        "sample_id": sample_id,
        "file_name": filename,
        "label": digit,
        "width": cols,
        "height": rows,
        "channels": 1
    })


# =========================================================
# SAVE CSV
# =========================================================
csv_path = os.path.join(OUTPUT_DIR, "samples.csv")

with open(csv_path, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)

    writer.writerow([
        "sample_id",
        "file_name",
        "label",
        "width",
        "height",
        "channels"
    ])

    for s in samples:
        writer.writerow([
            s["sample_id"],
            s["file_name"],
            s["label"],
            s["width"],
            s["height"],
            s["channels"]
        ])


# =========================================================
# SAVE JSON
# =========================================================
json_path = os.path.join(OUTPUT_DIR, "samples.json")

with open(json_path, "w", encoding="utf-8") as f:
    json.dump(samples, f, indent=4)


# =========================================================
# SUMMARY
# =========================================================
print("\n====================================")
print(" MNIST SAMPLE SET CREATED")
print("====================================")
print(f"Total samples: {len(samples)}")

for digit in range(10):
    count = sum(1 for s in samples if s["label"] == digit)
    print(f"Digit {digit}: {count} samples")

print()
print("Images :", os.path.abspath(IMAGE_DIR))
print("CSV    :", os.path.abspath(csv_path))
print("JSON   :", os.path.abspath(json_path))
print("====================================")