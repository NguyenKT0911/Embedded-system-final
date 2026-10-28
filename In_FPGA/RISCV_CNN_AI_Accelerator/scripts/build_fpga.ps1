param(
    [string]$GowinBin = "C:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$gwsh = Join-Path $GowinBin "gw_sh.exe"
if (-not (Test-Path -LiteralPath $gwsh)) {
    $command = Get-Command gw_sh.exe -ErrorAction SilentlyContinue
    if (-not $command) { throw "gw_sh.exe not found. Pass -GowinBin <Gowin IDE bin directory>." }
    $gwsh = $command.Source
}

Push-Location $projectRoot
try {
    & $gwsh ".\scripts\build_fpga.tcl"
    if ($LASTEXITCODE -ne 0) { throw "Gowin build failed with exit code $LASTEXITCODE" }
    $bitstream = Join-Path $projectRoot "impl\pnr\TangNano20K_RISCV_CNN.fs"
    if (-not (Test-Path -LiteralPath $bitstream)) { throw "Gowin did not generate $bitstream" }
    Write-Host "RESULT: FPGA BITSTREAM BUILD PASSED"
    Write-Host $bitstream
}
finally {
    Pop-Location
}
