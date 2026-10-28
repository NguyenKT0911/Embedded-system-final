param(
    [string]$ZigExe = "",
    [string]$PythonExe = "python"
)

$ErrorActionPreference = "Stop"
$firmwareRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildDir = Join-Path $firmwareRoot "build"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

if (-not $ZigExe) {
    if ($env:ZIG_EXE -and (Test-Path -LiteralPath $env:ZIG_EXE)) {
        $ZigExe = $env:ZIG_EXE
    } else {
        $localZig = Join-Path $firmwareRoot ".tools\ziglang\zig.exe"
        if (Test-Path -LiteralPath $localZig) {
            $ZigExe = $localZig
        } else {
            $command = Get-Command zig.exe -ErrorAction SilentlyContinue
            if ($command) { $ZigExe = $command.Source }
        }
    }
}
if (-not $ZigExe -or -not (Test-Path -LiteralPath $ZigExe)) {
    throw "Zig not found. Run bootstrap_toolchain.ps1 or pass -ZigExe <path>."
}

$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $buildDir "zig-global-cache"
$env:ZIG_LOCAL_CACHE_DIR = Join-Path $buildDir "zig-local-cache"

$isaFlags = @(
    "-Xclang", "-target-feature", "-Xclang", "-m",
    "-Xclang", "-target-feature", "-Xclang", "-a",
    "-Xclang", "-target-feature", "-Xclang", "-c",
    "-Xclang", "-target-feature", "-Xclang", "-zmmul",
    "-Xclang", "-target-feature", "-Xclang", "-zaamo",
    "-Xclang", "-target-feature", "-Xclang", "-zalrsc",
    "-Xclang", "-target-feature", "-Xclang", "-zca"
)
$common = @(
    "cc", "-target", "riscv32-freestanding-none"
) + $isaFlags + @(
    "-mabi=ilp32", "-Oz", "-mno-relax",
    "-ffreestanding", "-fno-builtin",
    "-fno-unwind-tables", "-fno-asynchronous-unwind-tables",
    "-ffunction-sections", "-fdata-sections", "-fomit-frame-pointer",
    "-nostdlib", "-msmall-data-limit=0", "-Iinclude",
    "-Wl,-T,linker.ld", "-Wl,--gc-sections"
)
$sources = @(
    "src/start.S", "src/mulsi3.S", "src/runtime.c", "src/uart.c",
    "src/accelerator.c", "src/sd_spi.c", "src/model_image.c",
    "src/runtime_protocol.c", "src/cnn.c", "src/main.c"
)

function Build-Firmware([string]$Name, [string[]]$Definitions) {
    $elf = Join-Path $buildDir "$Name.elf"
    $binary = Join-Path $buildDir "$Name.bin"
    $hex = Join-Path $buildDir "$Name.hex"
    $dmemBinary = Join-Path $buildDir "$($Name)_dmem.bin"
    $dmemHex = Join-Path $buildDir "$($Name)_dmem.hex"
    & $ZigExe @common @Definitions @sources "-o" $elf
    if ($LASTEXITCODE -ne 0) { throw "$Name C compilation failed" }
    & $PythonExe (Join-Path $firmwareRoot "tools\verify_rv32i.py") $elf
    if ($LASTEXITCODE -ne 0) { throw "$Name contains unsupported instructions" }
    & $PythonExe (Join-Path $firmwareRoot "tools\elf_to_mem_hex.py") $elf --imem-bin $binary --imem-hex $hex --dmem-bin $dmemBinary --dmem-hex $dmemHex --imem-words 2048 --dmem-words 2048
    if ($LASTEXITCODE -ne 0) { throw "$Name memory image conversion failed" }
}

Push-Location $firmwareRoot
try {
    Build-Firmware "firmware_c_hello" @("-DFIRMWARE_UART_SELFTEST=1")
    Build-Firmware "firmware_c_preview_diag" @("-DFIRMWARE_PREVIEW_DIAGNOSTIC=1")
    Build-Firmware "firmware_c_dataset_manager" @("-DFIRMWARE_DATASET_MANAGER=1")
    Build-Firmware "firmware_c_full" @()
}
finally {
    Pop-Location
}

Write-Host "RESULT: RV32I C FIRMWARE BUILD PASSED"
Write-Host (Join-Path $buildDir "firmware_c_full.hex")

