files = [
    "conv1_input_packet.bin",
    "conv1_weight_packet.bin",
    "conv1_config_packet.bin",
    "conv1_start_packet.bin",
]

OUTPUT_FILE = "conv1_uart_stream.bin"

stream = b""

print("===== BUILD CONV1 UART STREAM =====")

for filename in files:
    with open(filename, "rb") as f:
        data = f.read()

    stream += data

    print(f"{filename:28s}: {len(data)} bytes")

with open(OUTPUT_FILE, "wb") as f:
    f.write(stream)

print()
print("Total stream bytes :", len(stream))
print("Output file        :", OUTPUT_FILE)

print()
print("First 32 bytes:")
print(" ".join(f"{b:02X}" for b in stream[:32]))