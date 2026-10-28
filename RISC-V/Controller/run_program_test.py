import time
import serial

PORT = "COM8"  # Change this if the board's onboard UART enumerates differently.
BAUD = 115200
LOAD_GAP_SECONDS = 0.100
RESULT_TIMEOUT_SECONDS = 30

TEST_NAMES = {
    "1": "Arithmetic and Logic",
    "2": "Shift and Comparison",
    "3": "Data Memory",
    "4": "Branch",
    "5": "LUI and AUIPC",
    "6": "JAL and JALR",
}

with open("program.bin", "rb") as program_file:
    program = program_file.read()

if not program or len(program) % 4:
    raise SystemExit("program.bin must contain a non-empty whole number of instructions.")
if len(program) > 1024:
    raise SystemExit("program.bin exceeds the 1 KiB instruction-memory capacity.")

print(f"Program: {len(program)} bytes ({len(program) // 4} instructions)")
print(f"Opening {PORT} at {BAUD} baud...")

with serial.Serial(PORT, BAUD, timeout=0.2, write_timeout=5) as ser:
    # Give the configured FPGA time to complete its power-on reset.
    time.sleep(0.5)
    ser.reset_input_buffer()
    print("Sending program; keep this COM connection open for the results...")
    sent = ser.write(program)
    ser.flush()
    if sent != len(program):
        raise SystemExit(f"Only wrote {sent}/{len(program)} bytes to {PORT}.")

    print(f"Sent {sent} bytes. FPGA starts automatically after about {LOAD_GAP_SECONDS:g} s of UART silence.")
    print("Waiting for test results...\n")
    last_activity = time.monotonic()
    passed = set()

    while time.monotonic() - last_activity < RESULT_TIMEOUT_SECONDS:
        data = ser.read(1)
        if not data:
            continue
        last_activity = time.monotonic()
        command = chr(data[0])

        if command in ("P", "F"):
            number = ser.read(1)
            if not number:
                print("Incomplete UART test message.")
                break
            test_id = chr(number[0])
            name = TEST_NAMES.get(test_id, "Unknown test")
            if command == "P":
                passed.add(test_id)
                print(f"[PASS] Test {test_id}: {name}")
            else:
                print(f"[FAIL] Test {test_id}: {name}")
                break
        elif command == "D":
            print("\nAll tests completed.")
            print(f"Passed: {len(passed)}/{len(TEST_NAMES)}")
            if len(passed) == len(TEST_NAMES):
                print("All 6 test groups PASSED.")
            break
        else:
            print(f"Unexpected byte: 0x{data[0]:02X}")
    else:
        print("Timeout: no complete test result received.")
        print("Check COM port selection, UART transfer, or program execution.")
