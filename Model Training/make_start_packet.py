import struct
import zlib

OUTPUT_FILE = "conv1_start_packet.bin"

MAGIC = bytes([0xA5, 0x5A])
CMD_START = 0x04

# START command has no payload
data = b""

length = len(data)

header = (
    MAGIC
    + bytes([CMD_START])
    + struct.pack("<I", length)
)

crc = zlib.crc32(data) & 0xFFFFFFFF
crc_bytes = struct.pack("<I", crc)

packet = header + data + crc_bytes

with open(OUTPUT_FILE, "wb") as f:
    f.write(packet)

print("===== UART START PACKET =====")
print("CMD          :", hex(CMD_START))
print("Data bytes   :", length)
print("Header bytes :", len(header))
print("CRC bytes    :", len(crc_bytes))
print("Packet bytes :", len(packet))
print("CRC32        :", hex(crc))
print("Output file  :", OUTPUT_FILE)

print()
print("Packet bytes:")
print(" ".join(f"{b:02X}" for b in packet))