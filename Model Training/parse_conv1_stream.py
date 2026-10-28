import struct
import zlib

STREAM_FILE = "conv1_uart_stream.bin"

MAGIC = bytes([0xA5, 0x5A])

CMD_NAMES = {
    0x01: "LOAD_INPUT",
    0x02: "LOAD_WEIGHT",
    0x03: "CONFIG",
    0x04: "START",
}


with open(STREAM_FILE, "rb") as f:
    stream = f.read()


print("===== PARSE CONV1 UART STREAM =====")
print("Total bytes:", len(stream))
print()

offset = 0
packet_number = 0
all_ok = True


while offset < len(stream):

    packet_number += 1

    print(f"---------- PACKET {packet_number} ----------")

    # Check minimum header
    if offset + 7 > len(stream):
        print("ERROR: incomplete header")
        all_ok = False
        break

    # MAGIC
    magic = stream[offset:offset + 2]

    if magic != MAGIC:
        print("ERROR: wrong MAGIC")
        all_ok = False
        break

    # CMD
    cmd = stream[offset + 2]

    # LENGTH
    length = struct.unpack(
        "<I",
        stream[offset + 3:offset + 7]
    )[0]

    data_start = offset + 7
    data_end = data_start + length

    crc_start = data_end
    crc_end = crc_start + 4

    if crc_end > len(stream):
        print("ERROR: incomplete packet")
        all_ok = False
        break

    data = stream[data_start:data_end]

    received_crc = struct.unpack(
        "<I",
        stream[crc_start:crc_end]
    )[0]

    calculated_crc = zlib.crc32(data) & 0xFFFFFFFF

    print("CMD    :", hex(cmd), CMD_NAMES.get(cmd, "UNKNOWN"))
    print("LENGTH :", length)
    print("CRC RX :", hex(received_crc))
    print("CRC CAL:", hex(calculated_crc))

    if received_crc != calculated_crc:
        print("CRC    : FAIL")
        all_ok = False
        break
    else:
        print("CRC    : PASS")

    # -------------------------
    # Decode each command
    # -------------------------

    if cmd == 0x01:

        print("Input data received:", len(data), "bytes")

        if len(data) == 784:
            print("INPUT COUNT: PASS")
        else:
            print("INPUT COUNT: FAIL")
            all_ok = False


    elif cmd == 0x02:

        print("Weight data received:", len(data), "bytes")

        if len(data) == 144:
            print("WEIGHT COUNT: PASS")
        else:
            print("WEIGHT COUNT: FAIL")
            all_ok = False


    elif cmd == 0x03:

        if len(data) != 32:
            print("CONFIG SIZE: FAIL")
            all_ok = False
            break

        (
            input_h,
            input_w,
            cin,
            cout,
            kernel,
            stride,
            padding,
            relu
        ) = struct.unpack("<8I", data)

        print()
        print("CONFIG:")
        print("H       =", input_h)
        print("W       =", input_w)
        print("Cin     =", cin)
        print("Cout    =", cout)
        print("Kernel  =", kernel)
        print("Stride  =", stride)
        print("Padding =", padding)
        print("ReLU    =", relu)


    elif cmd == 0x04:

        if length == 0:
            print("START command received")
        else:
            print("START LENGTH: FAIL")
            all_ok = False


    else:

        print("ERROR: Unknown command")
        all_ok = False
        break


    # Move to next packet
    offset = crc_end

    print()


print("================================")

if all_ok and offset == len(stream):

    print("ALL STREAM PACKETS: PASS")
    print("Packets parsed     :", packet_number)
    print("Bytes consumed     :", offset)

else:

    print("STREAM CHECK: FAIL")

print("================================")