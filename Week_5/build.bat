@echo off

echo ========================================
echo        BUILDING RV32I PROGRAM
echo ========================================

echo.
echo [1/4] Compiling Assembly...
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -Wl,-Ttext=0x0 program.S -o program.elf

if errorlevel 1 goto error

echo.
echo [2/4] Creating disassembly...
riscv-none-elf-objdump -d -M no-aliases program.elf > program.dump

if errorlevel 1 goto error

echo.
echo [3/4] Creating binary...
riscv-none-elf-objcopy -O binary -j .text program.elf program.bin

if errorlevel 1 goto error

echo.
echo [4/4] Creating HEX file...
powershell -ExecutionPolicy Bypass -File bin2hex.ps1

if errorlevel 1 goto error

echo.
echo ========================================
echo            BUILD SUCCESS
echo ========================================
echo.
echo Generated:
echo   program.elf
echo   program.dump
echo   program.bin
echo   program.hex
echo.
goto end

:error
echo.
echo ========================================
echo             BUILD FAILED
echo ========================================

:end
pause