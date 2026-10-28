import struct
import zlib

WEIGHT_FILE = "conv1_weight.bin"
OUTPUT_FILE = "conv1_weight_packet.bin"

MAGIC = bytes([0xA5, 0x5A])
CMD_LOAD_WEIGHT = 0x02

with open(WEIGHT_FILE, "rb") as f:
    data = f.read()

length = len(data)

header = MAGIC + bytes([CMD_LOAD_WEIGHT]) + struct.pack("<I", length)

crc = zlib.crc32(data) & 0xFFFFFFFF
crc_bytes = struct.pack("<I", crc)

packet = header + data + crc_bytes

with open(OUTPUT_FILE, "wb") as f:
    f.write(packet)

print("===== UART WEIGHT PACKET =====")
print("Weight bytes  :", length)
print("Header bytes  :", len(header))
print("CRC bytes     :", len(crc_bytes))
print("Packet bytes  :", len(packet))
print("CRC32         :", hex(crc))
print("Output file   :", OUTPUT_FILE)

print()
print("First 16 packet bytes:")
print(" ".join(f"{b:02X}" for b in packet[:16]))