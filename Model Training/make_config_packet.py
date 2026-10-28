import json
import struct
import zlib

CONFIG_FILE = "conv1_config.json"
OUTPUT_FILE = "conv1_config_packet.bin"

MAGIC = bytes([0xA5, 0x5A])
CMD_CONFIG = 0x03

# Load config JSON
with open(CONFIG_FILE, "r") as f:
    cfg = json.load(f)

# Read values
input_h = int(cfg["input_h"])
input_w = int(cfg["input_w"])
cin = int(cfg["cin"])
cout = int(cfg["cout"])
kernel_size = int(cfg["kernel"])
stride = int(cfg["stride"])
padding = int(cfg["padding"])
relu_en = 1 if cfg["relu"] else 0

# Pack 8 x uint32 little-endian
data = struct.pack(
    "<8I",
    input_h,
    input_w,
    cin,
    cout,
    kernel_size,
    stride,
    padding,
    relu_en
)

length = len(data)

header = (
    MAGIC
    + bytes([CMD_CONFIG])
    + struct.pack("<I", length)
)

crc = zlib.crc32(data) & 0xFFFFFFFF
crc_bytes = struct.pack("<I", crc)

packet = header + data + crc_bytes

with open(OUTPUT_FILE, "wb") as f:
    f.write(packet)

print("===== UART CONFIG PACKET =====")
print("H           :", input_h)
print("W           :", input_w)
print("Cin         :", cin)
print("Cout        :", cout)
print("Kernel      :", kernel_size)
print("Stride      :", stride)
print("Padding     :", padding)
print("ReLU        :", relu_en)

print()
print("Config bytes :", length)
print("Header bytes :", len(header))
print("CRC bytes    :", len(crc_bytes))
print("Packet bytes :", len(packet))
print("CRC32        :", hex(crc))
print("Output file  :", OUTPUT_FILE)

print()
print("Packet bytes:")
print(" ".join(f"{b:02X}" for b in packet))