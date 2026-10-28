import struct
import zlib

INPUT_FILE = "conv1_input.bin"
OUTPUT_FILE = "conv1_input_packet.bin"

MAGIC = bytes([0xA5, 0x5A])
CMD_LOAD_INPUT = 0x01

# Read raw Conv1 input
with open(INPUT_FILE, "rb") as f:
    data = f.read()

length = len(data)

# Header:
# A5 5A
# CMD
# LENGTH = uint32 little-endian
header = MAGIC + bytes([CMD_LOAD_INPUT]) + struct.pack("<I", length)

# CRC32 of payload
crc = zlib.crc32(data) & 0xFFFFFFFF
crc_bytes = struct.pack("<I", crc)

packet = header + data + crc_bytes

with open(OUTPUT_FILE, "wb") as f:
    f.write(packet)

print("===== UART INPUT PACKET =====")
print("Input bytes   :", length)
print("Header bytes  :", len(header))
print("CRC bytes     :", len(crc_bytes))
print("Packet bytes  :", len(packet))
print("CRC32         :", hex(crc))
print("Output file   :", OUTPUT_FILE)

print()
print("First 16 packet bytes:")
print(" ".join(f"{b:02X}" for b in packet[:16]))