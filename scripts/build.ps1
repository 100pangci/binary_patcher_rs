param(
    [switch]$SkipHdiffpatch
)

$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Path $PSScriptRoot -Parent
$RELEASES = Join-Path $ROOT "Releases"
$STAGING = Join-Path $RELEASES "binary_patcher_toolkit"

Write-Host "=== Binary Patcher Build Script ===" -ForegroundColor Cyan

# Step 1: Build
Write-Host "[1/3] Building release binaries..." -ForegroundColor Green
Set-Location -Path $ROOT
cargo build --release
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed"
    exit 1
}

# Step 2: Download HDiffPatch
if (-not $SkipHdiffpatch) {
    Write-Host "[2/3] Downloading HDiffPatch..." -ForegroundColor Green
    $repo = "sisong/HDiffPatch"
    $attempts = 0
    $maxAttempts = 3
    $downloaded = $false

    while ($attempts -lt $maxAttempts -and -not $downloaded) {
        $attempts++
        try {
            $api = "https://api.github.com/repos/$repo/releases/latest"
            $release = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "BinaryPatcher-BuildScript/2.0" }
            $asset = $release.assets | Where-Object { $_.name -like "*windows64*" -or $_.name -like "*win64*" } | Select-Object -First 1
            if (-not $asset) {
                throw "No windows64 asset found in latest release"
            }
            $zipPath = Join-Path $env:TEMP "hdiffpatch.zip"
            Write-Host "  Downloading $($asset.name)..."
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
            $extractPath = Join-Path $env:TEMP "hdiffpatch_extract"
            if (Test-Path $extractPath) { Remove-Item -Path $extractPath -Recurse -Force }
            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
            $found = $false
            Get-ChildItem -Path $extractPath -Recurse -Include "hdiffz.exe", "hpatchz.exe" | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination (Join-Path $ROOT "target\release\$($_.Name)") -Force
                $found = $true
                Write-Host "  Copied $($_.Name) to target/release/"
            }
            if (-not $found) {
                throw "hdiffz.exe or hpatchz.exe not found in extracted archive"
            }
            $downloaded = $true
        }
        catch {
            Write-Warning "Attempt $attempts/$maxAttempts failed: $_"
            if ($attempts -ge $maxAttempts) {
                Write-Warning "All download attempts failed. Trying fallback URL..."
                try {
                    $fallbackUrl = "https://github.com/sisong/HDiffPatch/releases/latest/download/HDiffPatch_win64.zip"
                    Invoke-WebRequest -Uri $fallbackUrl -OutFile $zipPath
                    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
                    Get-ChildItem -Path $extractPath -Recurse -Include "hdiffz.exe", "hpatchz.exe" | ForEach-Object {
                        Copy-Item -Path $_.FullName -Destination (Join-Path $ROOT "target\release\$($_.Name)") -Force
                        Write-Host "  Copied $($_.Name) from fallback"
                    }
                    $downloaded = $true
                }
                catch {
                    Write-Warning "Fallback also failed. Build will continue without HDiffPatch binaries."
                }
            }
        }
    }
} else {
    Write-Host "[2/3] Skipping HDiffPatch download (-SkipHdiffpatch)" -ForegroundColor Yellow
}

# Step 3: Package
Write-Host "[3/3] Packaging toolkit..." -ForegroundColor Green
if (Test-Path $STAGING) { Remove-Item -Path $STAGING -Recurse -Force }
New-Item -ItemType Directory -Path $STAGING -Force | Out-Null

Copy-Item (Join-Path $ROOT "target\release\binary_patcher.exe") -Destination $STAGING
Copy-Item (Join-Path $ROOT "target\release\apply_patch.exe") -Destination $STAGING
Copy-Item (Join-Path $ROOT "target\release\rollback_patch.exe") -Destination $STAGING

if (Test-Path (Join-Path $ROOT "target\release\hdiffz.exe")) {
    Copy-Item (Join-Path $ROOT "target\release\hdiffz.exe") -Destination $STAGING
    Copy-Item (Join-Path $ROOT "target\release\hpatchz.exe") -Destination $STAGING
}

$zipPath = Join-Path $RELEASES "binary_patcher_toolkit.zip"
if (Test-Path $zipPath) { Remove-Item -Path $zipPath -Force }
Compress-Archive -Path "$STAGING\*" -DestinationPath $zipPath

Write-Host "`n=== Build completed ===" -ForegroundColor Cyan
Write-Host "Output directory: $RELEASES"
Write-Host "  binary_patcher.exe"
Write-Host "  apply_patch.exe"
Write-Host "  rollback_patch.exe"
if (Test-Path (Join-Path $ROOT "target\release\hdiffz.exe")) {
    Write-Host "  hdiffz.exe / hpatchz.exe (in toolkit)"
}
Write-Host "  binary_patcher_toolkit.zip"
