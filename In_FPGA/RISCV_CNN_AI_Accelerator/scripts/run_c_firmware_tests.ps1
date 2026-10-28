param(
    [string]$ModelSimBin = "A:\ModelSim\modelsim_ase\win32aloem",
    [string]$ZigExe = "",
    [string]$PythonExe = "python",
    [switch]$Quick
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$bigProject = Resolve-Path (Join-Path $projectRoot "..\..")
$modelDir = Join-Path $bigProject "Model Training\FPGA_UART_export"
$sdImageDir = Join-Path $projectRoot "sd_image"

& (Join-Path $projectRoot "firmware_c\build_firmware.ps1") -ZigExe $ZigExe -PythonExe $PythonExe
if ($LASTEXITCODE -ne 0) { throw "C firmware build failed" }

& $PythonExe (Join-Path $projectRoot "tools\export_sd_image.py") $modelDir $sdImageDir
if ($LASTEXITCODE -ne 0) { throw "SD image export failed" }

$vlib = Join-Path $ModelSimBin "vlib.exe"
$vlog = Join-Path $ModelSimBin "vlog.exe"
$vsim = Join-Path $ModelSimBin "vsim.exe"
foreach ($tool in @($vlib, $vlog, $vsim)) {
    if (-not (Test-Path -LiteralPath $tool)) { throw "Missing ModelSim tool: $tool" }
}

$library = Join-Path $projectRoot "build\modelsim_c_firmware\work"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $library) | Out-Null
if (-not (Test-Path -LiteralPath $library)) { & $vlib $library | Out-Null }

$sources = Get-ChildItem (Join-Path $projectRoot "src\*.v") |
    Where-Object { $_.Name -ne "tang_nano_20k_top.v" } |
    Sort-Object Name |
    ForEach-Object FullName
$testSources = @(
    (Join-Path $projectRoot "tb\sd_card_spi_model.v"),
    (Join-Path $projectRoot "tb\tb_sd_spi_mmio.v"),
    (Join-Path $projectRoot "tb\tb_firmware_c_hello.v"),
    (Join-Path $projectRoot "tb\tb_firmware_c_full_inference.v")
)
foreach ($source in $sources + $testSources) {
    & $vlog -quiet -work $library $source
    if ($LASTEXITCODE -ne 0) { throw "ModelSim compile failed: $source" }
}

function Run-Test([string]$Top, [string]$Sentinel) {
    $output = & $vsim -c -lib $library $Top -do "run -all; quit -f" 2>&1 | Out-String
    Write-Host $output.TrimEnd()
    if ($LASTEXITCODE -ne 0 -or $output -notmatch [regex]::Escape($Sentinel)) {
        throw "$Top failed"
    }
}

Push-Location $projectRoot
try {
    Run-Test "tb_sd_spi_mmio" "RESULT: SD SPI MMIO TEST PASSED"
    Run-Test "tb_firmware_c_hello" "RESULT: RV32I C UART HELLO TEST PASSED"
    if (-not $Quick) {
        Run-Test "tb_firmware_c_full_inference" "RESULT: RV32I C FULL CNN FROM SD PASSED"
    }
}
finally {
    Pop-Location
}

Write-Host "RESULT: C FIRMWARE/SD REGRESSION PASSED"
