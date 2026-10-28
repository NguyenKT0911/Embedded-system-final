import struct
import zlib


def check_packet(filename, expected_cmd):
    print(f"\n===== CHECK {filename} =====")

    with open(filename, "rb") as f:
        packet = f.read()

    # Minimum:
    # 2 bytes MAGIC
    # 1 byte CMD
    # 4 bytes LENGTH
    # 4 bytes CRC
    if len(packet) < 11:
        print("FAIL: packet too short")
        return False

    magic = packet[0:2]
    cmd = packet[2]

    length = struct.unpack("<I", packet[3:7])[0]

    data = packet[7:7 + length]

    received_crc = struct.unpack(
        "<I",
        packet[7 + length: 11 + length]
    )[0]

    calculated_crc = zlib.crc32(data) & 0xFFFFFFFF

    print("MAGIC          :", magic.hex(" ").upper())
    print("CMD            :", hex(cmd))
    print("LENGTH         :", length)
    print("DATA bytes     :", len(data))
    print("Received CRC   :", hex(received_crc))
    print("Calculated CRC :", hex(calculated_crc))
    print("Total bytes    :", len(packet))

    ok = True

    if magic != bytes([0xA5, 0x5A]):
        print("MAGIC : FAIL")
        ok = False
    else:
        print("MAGIC : PASS")

    if cmd != expected_cmd:
        print("CMD   : FAIL")
        ok = False
    else:
        print("CMD   : PASS")

    if len(data) != length:
        print("LENGTH: FAIL")
        ok = False
    else:
        print("LENGTH: PASS")

    if received_crc != calculated_crc:
        print("CRC   : FAIL")
        ok = False
    else:
        print("CRC   : PASS")

    if len(packet) != 7 + length + 4:
        print("SIZE  : FAIL")
        ok = False
    else:
        print("SIZE  : PASS")

    if ok:
        print("RESULT: PASS")
    else:
        print("RESULT: FAIL")

    return ok


input_ok = check_packet(
    "conv1_input_packet.bin",
    0x01
)

weight_ok = check_packet(
    "conv1_weight_packet.bin",
    0x02
)

config_ok = check_packet(
    "conv1_config_packet.bin",
    0x03
)

print("\n==============================")

if input_ok and weight_ok and config_ok:
    print("ALL UART PACKETS: PASS")
else:
    print("SOME UART PACKETS: FAIL")

print("==============================")