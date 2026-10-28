from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent


def run_step(title: str, command: list[str], *, stdout_file: Path | None = None) -> bool:
    print(f"\n{title}", flush=True)
    try:
        if stdout_file is None:
            result = subprocess.run(command, cwd=ROOT, check=False)
        else:
            with stdout_file.open("w", encoding="utf-8", newline="") as output:
                result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=False, text=True)
    except FileNotFoundError:
        print(f"Command not found: {command[0]}")
        return False
    return result.returncode == 0


def main() -> int:
    print("========================================")
    print("       BUILDING RV32I PROGRAM")
    print("========================================")

    steps = [
        ("[1/4] Compiling Assembly...", [
            "riscv-none-elf-gcc", "-march=rv32i", "-mabi=ilp32", "-nostdlib", "-nostartfiles",
            "-Wl,-Ttext=0x0", "program.S", "-o", "program.elf",
        ], None),
        ("[2/4] Creating disassembly...", [
            "riscv-none-elf-objdump", "-d", "-M", "no-aliases", "program.elf",
        ], ROOT / "program.dump"),
        ("[3/4] Creating binary...", [
            "riscv-none-elf-objcopy", "-O", "binary", "-j", ".text", "program.elf", "program.bin",
        ], None),
        ("[4/4] Creating HEX file...", [
            "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "bin2hex.ps1"),
        ], None),
    ]

    for title, command, output_file in steps:
        if not run_step(title, command, stdout_file=output_file):
            print("\n========================================")
            print("            BUILD FAILED")
            print("========================================")
            return 1

    print("\n========================================")
    print("            BUILD SUCCESS")
    print("========================================")
    print("\nGenerated:")
    for name in ("program.elf", "program.dump", "program.bin", "program.hex"):
        print(f"  {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
