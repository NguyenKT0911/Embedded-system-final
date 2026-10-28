param(
    [string]$PythonExe = "python"
)

$ErrorActionPreference = "Stop"
$firmwareRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsDir = Join-Path $firmwareRoot ".tools"
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
& $PythonExe -m pip install --upgrade --target $toolsDir "ziglang==0.16.0"
if ($LASTEXITCODE -ne 0) { throw "Unable to install the Zig/LLVM RV32I toolchain" }
$zig = Join-Path $toolsDir "ziglang\zig.exe"
if (-not (Test-Path -LiteralPath $zig)) { throw "zig.exe was not installed" }
Write-Host "Toolchain ready: $zig"
Write-Host "Run build_firmware.ps1 with -ZigExe $zig"
