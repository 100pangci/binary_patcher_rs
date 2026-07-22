$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Path $PSScriptRoot -Parent
$RELEASES = Join-Path $ROOT "Releases"

Write-Host "=== Binary Patcher Build Script ===" -ForegroundColor Cyan

# Step 1: Build
Write-Host "[1/2] Building release binaries (HDiffPatch will be downloaded by build.rs)..." -ForegroundColor Green
Set-Location -Path $ROOT
cargo build --release
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed"
    exit 1
}

# Step 2: Package
Write-Host "[2/2] Packaging toolkit..." -ForegroundColor Green
if (Test-Path $RELEASES) { Remove-Item -Path "$RELEASES\*.exe" -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $RELEASES -Force | Out-Null

Copy-Item (Join-Path $ROOT "target\release\binary_patcher.exe") -Destination $RELEASES
Copy-Item (Join-Path $ROOT "target\release\apply_patch.exe") -Destination $RELEASES
Copy-Item (Join-Path $ROOT "target\release\rollback_patch.exe") -Destination $RELEASES

$zipPath = Join-Path $RELEASES "binary_patcher_toolkit.zip"
Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
Compress-Archive -Path "$RELEASES\*.exe" -DestinationPath $zipPath

Write-Host "`n=== Build completed ===" -ForegroundColor Cyan
Write-Host "Output directory: $RELEASES"
Write-Host "  binary_patcher.exe"
Write-Host "  apply_patch.exe"
Write-Host "  rollback_patch.exe"
Write-Host "  binary_patcher_toolkit.zip"
