import json
import random
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SAMPLES_DIR = os.path.join(BASE_DIR, "mnist_samples")

json_path = os.path.join(SAMPLES_DIR, "samples.json")

with open(json_path, "r", encoding="utf-8") as f:
    samples = json.load(f)

sample = random.choice(samples)

image_path = os.path.join(
    SAMPLES_DIR,
    "images",
    sample["file_name"]
)

print("==============================")
print(" RANDOM MNIST SAMPLE")
print("==============================")
print("Sample ID      :", sample["sample_id"])
print("Image file     :", sample["file_name"])
print("Expected label :", sample["label"])
print("Image size     :", f'{sample["width"]} x {sample["height"]}')
print("Channels       :", sample["channels"])
print("Image path     :", image_path)