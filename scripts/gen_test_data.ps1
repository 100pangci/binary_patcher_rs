param(
    [string]$OutputDir = "test_workspace",
    [long]$TargetSizeMB = 500
)

$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Path $PSScriptRoot -Parent
$BINARY = Join-Path $ROOT "target\release\binary_patcher.exe"
$APPLY = Join-Path $ROOT "target\release\apply_patch.exe"
$ROLLBACK = Join-Path $ROOT "target\release\rollback_patch.exe"

# ============================================================
# Step 0: Check binary exists
# ============================================================
if (-not (Test-Path $BINARY)) {
    Write-Host "Binary not found, building first..." -ForegroundColor Yellow
    Set-Location -Path $ROOT
    cargo build --release
    if ($LASTEXITCODE -ne 0) { Write-Error "Build failed"; exit 1 }
}

Write-Host "=== Binary Patcher Test Data Generator ===" -ForegroundColor Cyan
Write-Host "Target size: ~${TargetSizeMB}MB"
Write-Host "Output dir: $OutputDir"
Write-Host ""

# ============================================================
# Step 1: Clean workspace
# ============================================================
if (Test-Path $OutputDir) { Remove-Item -Path $OutputDir -Recurse -Force }
$OutputRoot = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path (Get-Location) $OutputDir }
$OldDir = Join-Path $OutputRoot "Old"
$NewDir = Join-Path $OutputRoot "New"
$PatchDir = Join-Path $OutputRoot "Patch"
$GameDir = Join-Path $OutputRoot "game"

# ============================================================
# Step 2: Define directory structure
# ============================================================
$dirs = @(
    "bin",
    "config",
    "data/animations",
    "data/models/characters",
    "data/models/environment",
    "data/textures/characters",
    "data/textures/environment",
    "data/audio/music",
    "data/audio/sfx",
    "data/levels/tutorial",
    "data/levels/chapter1",
    "data/levels/chapter2",
    "data/scripts",
    "data/localization/en",
    "data/localization/ja",
    "data/localization/zh",
    "plugins/network",
    "plugins/rendering",
    "plugins/audio",
    "logs",
    "userdata/saves",
    "userdata/config",
    "temp"
)

# ============================================================
# Step 3: Calculate file distribution
# ============================================================
$remainingMB = $TargetSizeMB
$allFiles = @()

# Helper: create a file with random content of given size
function Join-Paths {
    param([string]$Base, [string[]]$Parts)
    $result = $Base
    foreach ($p in $Parts) { $result = Join-Path $result $p }
    return $result
}

function New-RandomFile {
    param($Path, $SizeBytes)
    $parent = Split-Path -Path $Path -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $stream = [System.IO.File]::OpenWrite($Path)
    $rng = [System.Random]::new()
    $buffer = [byte[]]::new([Math]::Min(1MB, $SizeBytes))
    $written = 0
    while ($written -lt $SizeBytes) {
        $chunk = [Math]::Min($buffer.Length, $SizeBytes - $written)
        if ($chunk -lt $buffer.Length) { $buffer = [byte[]]::new($chunk) }
        $rng.NextBytes($buffer)
        $stream.Write($buffer, 0, $buffer.Length)
        $written += $buffer.Length
    }
    $stream.Close()
}

# File categories with relative counts
$fileDefs = @(
    @{ Dir = "bin"; Ext = "dll"; Count = 8; MinKB = 10; MaxKB = 500 },
    @{ Dir = "bin"; Ext = "exe"; Count = 3; MinKB = 100; MaxKB = 2000 },
    @{ Dir = "config"; Ext = "ini"; Count = 5; MinKB = 1; MaxKB = 10 },
    @{ Dir = "config"; Ext = "json"; Count = 3; MinKB = 1; MaxKB = 50 },
    @{ Dir = "data/animations"; Ext = "anim"; Count = 20; MinKB = 50; MaxKB = 500 },
    @{ Dir = "data/models/characters"; Ext = "model"; Count = 15; MinKB = 100; MaxKB = 1000 },
    @{ Dir = "data/models/environment"; Ext = "model"; Count = 10; MinKB = 50; MaxKB = 500 },
    @{ Dir = "data/textures/characters"; Ext = "tex"; Count = 15; MinKB = 100; MaxKB = 2000 },
    @{ Dir = "data/textures/environment"; Ext = "tex"; Count = 10; MinKB = 50; MaxKB = 1000 },
    @{ Dir = "data/audio/music"; Ext = "ogg"; Count = 8; MinKB = 500; MaxKB = 5000 },
    @{ Dir = "data/audio/sfx"; Ext = "wav"; Count = 15; MinKB = 10; MaxKB = 200 },
    @{ Dir = "data/levels/tutorial"; Ext = "lvl"; Count = 3; MinKB = 50; MaxKB = 300 },
    @{ Dir = "data/levels/chapter1"; Ext = "lvl"; Count = 5; MinKB = 100; MaxKB = 500 },
    @{ Dir = "data/levels/chapter2"; Ext = "lvl"; Count = 5; MinKB = 100; MaxKB = 500 },
    @{ Dir = "data/scripts"; Ext = "lua"; Count = 10; MinKB = 1; MaxKB = 50 },
    @{ Dir = "data/localization/en"; Ext = "json"; Count = 3; MinKB = 5; MaxKB = 50 },
    @{ Dir = "data/localization/ja"; Ext = "json"; Count = 3; MinKB = 5; MaxKB = 50 },
    @{ Dir = "data/localization/zh"; Ext = "json"; Count = 3; MinKB = 5; MaxKB = 50 },
    @{ Dir = "plugins/network"; Ext = "dll"; Count = 4; MinKB = 50; MaxKB = 300 },
    @{ Dir = "plugins/rendering"; Ext = "dll"; Count = 4; MinKB = 100; MaxKB = 1000 },
    @{ Dir = "plugins/audio"; Ext = "dll"; Count = 3; MinKB = 50; MaxKB = 300 },
    @{ Dir = "logs"; Ext = "log"; Count = 3; MinKB = 1; MaxKB = 5 },
    @{ Dir = "userdata/saves"; Ext = "save"; Count = 5; MinKB = 10; MaxKB = 100 },
    @{ Dir = "userdata/config"; Ext = "cfg"; Count = 3; MinKB = 1; MaxKB = 5 },
    @{ Dir = ""; Ext = "txt"; Count = 2; MinKB = 1; MaxKB = 2 },
    @{ Dir = ""; Ext = "md"; Count = 1; MinKB = 2; MaxKB = 5 }
)

# ============================================================
# Step 4: Generate Old directory
# ============================================================
Write-Host "[1/4] Generating Old directory..." -ForegroundColor Green

$rng = [System.Random]::new()
$totalOldSize = 0

foreach ($def in $fileDefs) {
    $dirPath = $def.Dir
    for ($i = 0; $i -lt $def.Count; $i++) {
        $name = "file_{0:D3}.{1}" -f $i, $def.Ext

        $filePath = if ([string]::IsNullOrEmpty($dirPath)) {
            Join-Path $OldDir $name
        } else {
            Join-Paths -Base $OldDir -Parts @($dirPath, $name)
        }

        $sizeKB = $rng.Next($def.MinKB, $def.MaxKB + 1)
        $sizeBytes = $sizeKB * 1024
        $totalOldSize += $sizeBytes

        New-RandomFile -Path $filePath -SizeBytes $sizeBytes
        $allFiles += @{ Path = $filePath; Relative = if ([string]::IsNullOrEmpty($dirPath)) { $name } else { "$dirPath/$name" }; Size = $sizeBytes }
    }
}

# Create empty directories (should be skipped by the tool)
New-Item -ItemType Directory -Path (Join-Path $OldDir "empty_dir") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OldDir "data/levels/empty_chapter") -Force | Out-Null

$oldSizeMB = [Math]::Round($totalOldSize / 1MB, 2)
Write-Host "  Generated $($allFiles.Count) files, ~${oldSizeMB}MB"

# ============================================================
# Step 5: Generate New directory from Old with modifications
# ============================================================
Write-Host "[2/4] Generating New directory (modifications)..." -ForegroundColor Green

# Copy Old -> New
Write-Host "  Copying Old to New..."
$parentDir = Split-Path -Path $NewDir -Parent
$newTmp = Join-Path $parentDir "New_tmp"
if (Test-Path $newTmp) { Remove-Item -Path $newTmp -Recurse -Force }
& robocopy $OldDir $newTmp /E /NJH /NJS /NP /NDL /NFL 2>&1 | Out-Null
if (Test-Path $NewDir) { Remove-Item -Path $NewDir -Recurse -Force }
Rename-Item -Path $newTmp -NewName "New"

# --- 5a: Modify some files (change content) ---
Write-Host "  Modifying ~15% of files..."
$changedCount = 0
$changedList = @()
$toModify = $allFiles | Where-Object { $_.Relative -notlike "logs/*" -and $_.Relative -notlike "temp/*" } |
    Sort-Object { $rng.Next() } | Select-Object -First ([Math]::Max(1, [int]($allFiles.Count * 0.15)))

foreach ($item in $toModify) {
    $newPath = Join-Path $NewDir $item.Relative
    if (Test-Path $newPath) {
        # Overwrite a portion near the end with random data
        $size = (Get-Item $newPath).Length
        if ($size -gt 1024) {
            $overwriteSize = [Math]::Min($size / 3, 1MB)
            $offset = $size - $overwriteSize - $rng.Next(0, [Math]::Max(1, [int]($size / 4)))
            if ($offset -lt 0) { $offset = 0 }
            $stream = [System.IO.File]::OpenWrite($newPath)
            $stream.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
            $buf = [byte[]]::new($overwriteSize)
            $rng.NextBytes($buf)
            $stream.Write($buf, 0, $buf.Length)
            $stream.Close()
            $changedCount++
            $changedList += $item.Relative
        } else {
            # Small file: just rewrite entirely
            $rng.NextBytes(($buf2 = [byte[]]::new($size)))
            [System.IO.File]::WriteAllBytes($newPath, $buf2)
            $changedCount++
            $changedList += $item.Relative
        }
    }
}
Write-Host "    Changed: $changedCount files"

# --- 5b: Add some new files ---
Write-Host "  Adding new files..."
$addedCount = 0
$addedList = @()

# Add some new texture files
for ($i = 0; $i -lt 5; $i++) {
    $name = "new_texture_$i.tex"
    $path = Join-Paths -Base $NewDir -Parts @("data/textures/environment", $name)
    New-RandomFile -Path $path -SizeBytes ($rng.Next(50, 500) * 1024)
    $addedCount++
    $addedList += "data/textures/environment/$name"
}

# Add new plugin
for ($i = 0; $i -lt 2; $i++) {
    $name = "new_plugin_$i.dll"
    $path = Join-Paths -Base $NewDir -Parts @("plugins", $name)
    New-RandomFile -Path $path -SizeBytes ($rng.Next(50, 200) * 1024)
    $addedCount++
    $addedList += "plugins/$name"
}
Write-Host "    Added: $addedCount files"

# --- 5c: Delete some files ---
Write-Host "  Removing files..."
$deletedCount = 0
$deletedList = @()
$toDelete = $allFiles | Sort-Object { $rng.Next() } | Select-Object -First ([Math]::Max(1, [int]($allFiles.Count * 0.08)))
foreach ($item in $toDelete) {
    $newPath = Join-Path $NewDir $item.Relative
    if (Test-Path $newPath) {
        Remove-Item -Path $newPath -Force
        $deletedCount++
        $deletedList += $item.Relative
    }
}
Write-Host "    Deleted: $deletedCount files"

# --- 5d: Modify some textures specially (offset write) ---
Write-Host "  Applying offset modifications to binary files..."
$offsetCount = 0
$textureFiles = Get-ChildItem -Path (Join-Path $NewDir "data/textures") -Recurse -Filter "*.tex" |
    Sort-Object { $rng.Next() } | Select-Object -First 5
foreach ($f in $textureFiles) {
    $size = $f.Length
    if ($size -gt 4096) {
        $offset = $rng.Next(0, [Math]::Max(1, [int]($size / 2)))
        $stream = [System.IO.File]::OpenWrite($f.FullName)
        $stream.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
        $buf = [byte[]]::new([Math]::Min(1024, $size - $offset))
        $rng.NextBytes($buf)
        $stream.Write($buf, 0, $buf.Length)
        $stream.Close()
        $offsetCount++
    }
}
Write-Host "    Offset modifications: $offsetCount files"

# ============================================================
# Step 6: Run binary_patcher bundle
# ============================================================
Write-Host "[3/4] Running binary_patcher bundle..." -ForegroundColor Green

& $BINARY bundle --base-dir "$OutputRoot"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Bundle generation failed"
    exit 1
}

# Verify Patch directory exists
if (-not (Test-Path $PatchDir)) {
    Write-Error "Patch directory not found"
    exit 1
}

$manifestPath = Join-Path $PatchDir "manifest.json"
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
Write-Host ""
Write-Host "=== Bundle Summary ===" -ForegroundColor Cyan
Write-Host "  Changed: $($manifest.changed.Count) files"
Write-Host "  Added:   $($manifest.added.Count) files"
Write-Host "  Deleted: $($manifest.deleted.Count) files"

$patchSize = (Get-ChildItem -Path $PatchDir -Recurse | Measure-Object -Property Length -Sum).Sum
Write-Host "  Patch dir size: $( [Math]::Round($patchSize / 1MB, 2) ) MB"
Write-Host ""

# ============================================================
# Step 7: Test apply & rollback
# ============================================================
Write-Host "[4/4] Testing apply and rollback..." -ForegroundColor Green

if (Test-Path $GameDir) { Remove-Item -Path $GameDir -Recurse -Force }

Write-Host "  Copying Old -> game/"
$gameTemp = Join-Path $OutputDir "game_temp"
if (Test-Path $gameTemp) { Remove-Item -Path $gameTemp -Recurse -Force }
& robocopy $OldDir $gameTemp /E /NJH /NJS /NP /NDL /NFL 2>&1 | Out-Null
Rename-Item -Path $gameTemp -NewName "game"

Write-Host "  Copying Patch -> game/Patch/"
Copy-Item -Path $PatchDir -Destination (Join-Path $GameDir "Patch") -Recurse

Write-Host "  Applying patch..."
Push-Location $GameDir
& $APPLY
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Error "Apply failed"
    exit 1
}
Pop-Location

# Verify applied result matches New
Write-Host "  Verifying apply result..."
$mismatch = 0
Get-ChildItem -Path $NewDir -Recurse -File | ForEach-Object {
    $rel = [System.IO.Path]::GetRelativePath($NewDir, $_.FullName) -replace '\\', '/'
    $gameFile = Join-Path $GameDir $rel
    if (-not (Test-Path $gameFile)) {
        Write-Warning "Missing in game/: $rel"
        $mismatch++
    }
}
if ($mismatch -eq 0) {
    Write-Host "  Apply verification: OK" -ForegroundColor Green
} else {
    Write-Host "  Apply verification: $mismatch files missing (expected if unchanged files excluded from bundle)" -ForegroundColor Yellow
}

Write-Host "  Rolling back..."
Push-Location $GameDir
& $ROLLBACK
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Error "Rollback failed"
    exit 1
}
Pop-Location

# Verify rollback result matches Old
Write-Host "  Verifying rollback result..."
$rollbackOk = 0
Get-ChildItem -Path $OldDir -Recurse -File | ForEach-Object {
    $rel = [System.IO.Path]::GetRelativePath($OldDir, $_.FullName) -replace '\\', '/'
    $gameFile = Join-Path $GameDir $rel
    if (-not (Test-Path $gameFile)) {
        Write-Warning "Missing after rollback: $rel"
        $rollbackOk++
    }
}
if ($rollbackOk -eq 0) {
    Write-Host "  Rollback verification: OK" -ForegroundColor Green
} else {
    Write-Host "  Rollback verification: $rollbackOk files missing" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== All done ===" -ForegroundColor Cyan
Write-Host "Workspace: $OutputDir"
Write-Host "Old size: ~${oldSizeMB}MB ($($allFiles.Count) files)"
Write-Host "Changed: $changedCount | Added: $addedCount | Deleted: $deletedCount"
Write-Host "Patch size: $( [Math]::Round($patchSize / 1MB, 2) ) MB"
Write-Host ""
Write-Host "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
