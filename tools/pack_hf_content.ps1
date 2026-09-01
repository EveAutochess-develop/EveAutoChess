# Build split content PCKs + HF staging (does NOT push HF).
# - Unchanged packs keep existing packs/*.pck (source fingerprint).
# - Models split by tonnage: models_env / frigate / cruiser / battleship / capital.
# - -Only logic,data  → rebuild only those packs (others reused from staging).
param(
  [string]$Only = "",
  [string]$Godot = "H:\game_dev\eveautochess-dev\tools\godot\Godot_v4.7.1-stable_win64.exe"
)

$ErrorActionPreference = "Stop"
$proj = "H:\game_dev\eveautochess-dev\godot_project"
$hfRoot = "H:\game_dev\eveautochess-hf\_hf_publish_root"
$packsDir = Join-Path $hfRoot "packs"
$projData = Join-Path $proj "data"
$fpPath = Join-Path $packsDir ".pack_fingerprints.json"
$exportPresets = Join-Path $proj "export_presets.cfg"
New-Item -ItemType Directory -Force -Path $packsDir | Out-Null

$checkScript = Join-Path $PSScriptRoot "check_gdscript.ps1"
Write-Host "Running GDScript check gate..."
& $checkScript -Godot $Godot -Project $proj
if ($LASTEXITCODE -ne 0) {
  throw "check_gdscript.ps1 failed (exit=$LASTEXITCODE) — fix per-file blocks above before packing"
}

$legacy = Join-Path $packsDir "game.pck"
if (Test-Path $legacy) {
  Remove-Item $legacy -Force
  Write-Host "Removed legacy packs/game.pck from staging"
}
$legacyModels = Join-Path $packsDir "models.pck"
if (Test-Path $legacyModels) {
  Remove-Item $legacyModels -Force
  Write-Host "Removed legacy packs/models.pck (tonnage split)"
}

function Get-RequiredRelPaths {
  $rels = New-Object System.Collections.Generic.List[string]
  foreach ($sub in @("ships", "equipment")) {
    $dir = Join-Path $projData $sub
    if (-not (Test-Path $dir)) { continue }
    Get-ChildItem -Path $dir -Filter "*.json" -File | ForEach-Object {
      $rels.Add("$sub/$($_.Name)")
    }
  }
  return , $rels.ToArray()
}

function Get-SourceFingerprint {
  param([string[]]$RelGlobs)
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($glob in $RelGlobs) {
    $fullGlob = Join-Path $proj ($glob -replace "/", "\")
    $parent = Split-Path $fullGlob -Parent
    $leaf = Split-Path $fullGlob -Leaf
    if (-not (Test-Path $parent)) { continue }
    Get-ChildItem -Path $parent -Filter $leaf -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
      $rel = $_.FullName.Substring($proj.Length).TrimStart("\", "/").Replace("\", "/")
      $lines.Add(("{0}|{1}|{2}" -f $rel, $_.Length, $_.LastWriteTimeUtc.ToString("o")))
    }
  }
  $sorted = $lines | Sort-Object
  $text = [string]::Join("`n", $sorted)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace "-", "").ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Read-Fingerprints {
  if (-not (Test-Path $fpPath)) { return @{} }
  try {
    $obj = Get-Content $fpPath -Raw -Encoding utf8 | ConvertFrom-Json
    $map = @{}
    foreach ($p in $obj.PSObject.Properties) { $map[$p.Name] = [string]$p.Value }
    return $map
  } catch {
    return @{}
  }
}

function Write-Fingerprints([hashtable]$map) {
  $ordered = [ordered]@{}
  foreach ($k in ($map.Keys | Sort-Object)) { $ordered[$k] = $map[$k] }
  ($ordered | ConvertTo-Json -Depth 4) | Set-Content $fpPath -Encoding utf8
}

function Get-FileSha256([string]$path) {
  return (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TonnageModelBuckets {
  ## ship_group → bucket key (RELEASE_AND_HOTUPDATE §2.1)
  $groupToBucket = @{
    frigate              = "frigate"
    destroyer            = "frigate"
    cruiser              = "cruiser"
    battlecruiser        = "cruiser"
    battleship           = "battleship"
    carrier              = "capital"
    dreadnought          = "capital"
    force_auxiliary      = "capital"
    titan                = "capital"
    freighter            = "capital"
    capital_industrial   = "capital"
    industrial_command   = "capital"
    mining_barge         = "capital"
    drone_heavy          = "capital"
  }
  $keyToBucket = @{}
  $shipsDir = Join-Path $projData "ships"
  Get-ChildItem -Path $shipsDir -Filter "*.json" -File | ForEach-Object {
    try {
      $j = Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
      $g = [string]$j.ship_group
      $k = [string]$j.model_key
      if ([string]::IsNullOrWhiteSpace($k)) { return }
      $b = $groupToBucket[$g]
      if (-not $b) { $b = "capital" }
      if (-not $keyToBucket.ContainsKey($k)) { $keyToBucket[$k] = $b }
    } catch {}
  }
  $shipsRoot = Join-Path $proj "assets\models\ships"
  if (Test-Path $shipsRoot) {
    Get-ChildItem -Path $shipsRoot -Directory | ForEach-Object {
      if (-not $keyToBucket.ContainsKey($_.Name)) {
        $keyToBucket[$_.Name] = "capital" ## orphan → capital
      }
    }
  }
  $buckets = @{
    frigate    = New-Object System.Collections.Generic.List[string]
    cruiser    = New-Object System.Collections.Generic.List[string]
    battleship = New-Object System.Collections.Generic.List[string]
    capital    = New-Object System.Collections.Generic.List[string]
  }
  foreach ($k in ($keyToBucket.Keys | Sort-Object)) {
    $b = $keyToBucket[$k]
    if (-not $buckets.ContainsKey($b)) { $b = "capital" }
    $buckets[$b].Add($k)
  }
  return $buckets
}

function Set-ExportPresetIncludeFilter {
  param([string]$PresetName, [string]$IncludeFilter)
  if (-not (Test-Path $exportPresets)) { throw "Missing $exportPresets" }
  $lines = Get-Content $exportPresets -Encoding UTF8
  $out = New-Object System.Collections.Generic.List[string]
  $inPreset = $false
  $nameMatched = $false
  $patched = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -match '^\[preset\.\d+\]\s*$') {
      $inPreset = $true
      $nameMatched = $false
      $out.Add($line)
      continue
    }
    if ($line -match '^\[preset\.\d+\.options\]') {
      $inPreset = $false
      $out.Add($line)
      continue
    }
    if ($inPreset -and $line -match '^name="([^"]+)"') {
      $nameMatched = ($Matches[1] -eq $PresetName)
      $out.Add($line)
      continue
    }
    if ($inPreset -and $nameMatched -and $line -match '^include_filter=') {
      $out.Add(('include_filter="{0}"' -f $IncludeFilter.Replace('"', '')))
      $patched = $true
      continue
    }
    $out.Add($line)
  }
  if (-not $patched) { throw "Failed to patch include_filter for preset '$PresetName'" }
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllLines($exportPresets, $out.ToArray(), $utf8)
}

function Build-ShipIncludeFilter([string[]]$ModelKeys) {
  ## Whole ships tree; non-bucket dirs are moved aside before export.
  return "assets/models/ships/*"
}

function Move-NonBucketShipDirs {
  param([string[]]$KeepKeys, [string]$SkipRoot)
  $shipsRoot = Join-Path $proj "assets\models\ships"
  if (-not (Test-Path $shipsRoot)) { throw "Missing $shipsRoot" }
  if (Test-Path $SkipRoot) { Remove-Item $SkipRoot -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $SkipRoot | Out-Null
  $keep = @{}
  foreach ($k in $KeepKeys) { $keep[$k] = $true }
  $moved = New-Object System.Collections.Generic.List[string]
  Get-ChildItem -Path $shipsRoot -Force | ForEach-Object {
    $name = $_.Name
    if ($_.PSIsContainer) {
      if ($keep.ContainsKey($name)) { return }
      $dest = Join-Path $SkipRoot $name
      Move-Item -LiteralPath $_.FullName -Destination $dest -Force
      $moved.Add($name)
    } else {
      ## Loose files under ships/ (legacy .glb etc.) — park for non-capital? Always park unless capital keep-all orphans.
      $dest = Join-Path $SkipRoot ("__file_" + $name)
      Move-Item -LiteralPath $_.FullName -Destination $dest -Force
      $moved.Add("__file_:" + $name)
    }
  }
  return , $moved.ToArray()
}

function Restore-NonBucketShipDirs {
  param([string]$SkipRoot)
  $shipsRoot = Join-Path $proj "assets\models\ships"
  if (-not (Test-Path $SkipRoot)) { return }
  Get-ChildItem -Path $SkipRoot -Force | ForEach-Object {
    $name = $_.Name
    if ($name.StartsWith("__file_")) {
      $orig = $name.Substring("__file_".Length)
      Move-Item -LiteralPath $_.FullName -Destination (Join-Path $shipsRoot $orig) -Force
    } else {
      Move-Item -LiteralPath $_.FullName -Destination (Join-Path $shipsRoot $name) -Force
    }
  }
  Remove-Item $SkipRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$tonnageBuckets = Get-TonnageModelBuckets
Write-Host ("Tonnage models: frigate={0} cruiser={1} battleship={2} capital={3}" -f `
  $tonnageBuckets.frigate.Count, $tonnageBuckets.cruiser.Count, `
  $tonnageBuckets.battleship.Count, $tonnageBuckets.capital.Count)

$packDefs = @(
  @{
    Key = "data"; Preset = "Pack Data"; Rel = "packs/data.pck"; MountOrder = 5; Kind = "data"
    SourceGlobs = @("data\ships\*", "data\equipment\*")
  },
  @{
    Key = "logic"; Preset = "Pack Logic"; Rel = "packs/logic.pck"; MountOrder = 10; Kind = "pack"
    SourceGlobs = @(
      "scripts\*", "scenes\*", "shaders\*",
      "data\balance\*", "data\fetters\*", "data\unmanned_units\*", "data\admin\*", "data\locale\*",
      "data\regions\*", "data\*.json", "data\*.md"
    )
  },
  @{
    Key = "ui"; Preset = "Pack UI"; Rel = "packs/ui.pck"; MountOrder = 20; Kind = "pack"
    SourceGlobs = @("assets\ui\*", "assets\fonts\*")
  },
  @{
    Key = "models_env"; Preset = "Pack Models Env"; Rel = "packs/models_env.pck"; MountOrder = 30; Kind = "pack"
    SourceGlobs = @("assets\models\env\*", "assets\models\structures\*", "assets\models\preview\*")
  },
  @{
    Key = "models_frigate"; Preset = "Pack Models Frigate"; Rel = "packs/models_frigate.pck"; MountOrder = 31; Kind = "pack"
    Tonnage = "frigate"
    SourceGlobs = @() ## filled below
  },
  @{
    Key = "models_cruiser"; Preset = "Pack Models Cruiser"; Rel = "packs/models_cruiser.pck"; MountOrder = 32; Kind = "pack"
    Tonnage = "cruiser"
    SourceGlobs = @()
  },
  @{
    Key = "models_battleship"; Preset = "Pack Models Battleship"; Rel = "packs/models_battleship.pck"; MountOrder = 33; Kind = "pack"
    Tonnage = "battleship"
    SourceGlobs = @()
  },
  @{
    Key = "models_capital"; Preset = "Pack Models Capital"; Rel = "packs/models_capital.pck"; MountOrder = 34; Kind = "pack"
    Tonnage = "capital"
    SourceGlobs = @()
  },
  @{
    Key = "audio"; Preset = "Pack Audio"; Rel = "packs/audio.pck"; MountOrder = 40; Kind = "pack"
    SourceGlobs = @("assets\audio\*", "assets\textures\*", "assets\skyboxes\*")
  }
)

foreach ($def in $packDefs) {
  if ($def.ContainsKey("Tonnage") -and $def.Tonnage) {
    $keys = @($tonnageBuckets[$def.Tonnage])
    $def.ModelKeys = $keys
    $def.SourceGlobs = @($keys | ForEach-Object { "assets\models\ships\$_\*" })
  }
}

$onlySet = $null
if ($Only.Trim() -ne "") {
  $onlySet = @{}
  foreach ($p in ($Only -split "[,\s]+")) {
    $k = $p.Trim().ToLowerInvariant()
    if ($k -ne "") { $onlySet[$k] = $true }
  }
}

$requiredRelPaths = Get-RequiredRelPaths
if ($requiredRelPaths.Count -lt 2) {
  throw "requiredRelPaths too small ($($requiredRelPaths.Count)) — expected ships+equipment JSON"
}

$prevFp = Read-Fingerprints
$nextFp = @{}
foreach ($k in $prevFp.Keys) { $nextFp[$k] = $prevFp[$k] }
## Drop stale single-models fingerprint
if ($nextFp.ContainsKey("models")) { $nextFp.Remove("models") }

$manifestFiles = @()
foreach ($def in $packDefs) {
  $outPck = Join-Path $hfRoot ($def.Rel -replace "/", "\")
  New-Item -ItemType Directory -Force -Path (Split-Path $outPck) | Out-Null
  $wantRebuild = $true
  if ($null -ne $onlySet -and -not $onlySet.ContainsKey($def.Key)) {
    $wantRebuild = $false
  }

  if ($def.ContainsKey("ModelKeys") -and $def.ModelKeys) {
    $inc = Build-ShipIncludeFilter -ModelKeys $def.ModelKeys
    Set-ExportPresetIncludeFilter -PresetName $def.Preset -IncludeFilter $inc
  }

  $fp = Get-SourceFingerprint -RelGlobs $def.SourceGlobs
  $nextFp[$def.Key] = $fp
  $existingOk = (Test-Path $outPck) -and ((Get-Item $outPck).Length -ge 1024)
  if (-not $wantRebuild) {
    if (-not $existingOk) {
      throw "Pack $($def.Key) not selected (-Only) but missing/invalid: $outPck"
    }
    Write-Host "SKIP export $($def.Preset) (-Only) keep existing"
  } elseif ($existingOk -and $prevFp.ContainsKey($def.Key) -and $prevFp[$def.Key] -eq $fp) {
    Write-Host "KEEP $($def.Preset) (source fingerprint unchanged)"
    $wantRebuild = $false
  }

  if ($wantRebuild) {
    $tmpPck = Join-Path (Split-Path $outPck) ("_export_{0}.pck" -f $def.Key)
    if (Test-Path $tmpPck) { Remove-Item $tmpPck -Force }
    $skipRoot = $null
    if ($def.ContainsKey("ModelKeys") -and $def.ModelKeys) {
      $skipRoot = Join-Path $packsDir ("_ship_skip_" + $def.Key)
      Write-Host "  Staging ships aside (keep $($def.ModelKeys.Count) keys)..."
      [void](Move-NonBucketShipDirs -KeepKeys $def.ModelKeys -SkipRoot $skipRoot)
    }
    Write-Host "Exporting $($def.Preset) -> $($def.Rel) ..."
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
      cmd /c "`"$Godot`" --headless --path `"$proj`" --export-pack `"$($def.Preset)`" `"$tmpPck`""
      $packExit = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $prevEap
      if ($null -ne $skipRoot) {
        Restore-NonBucketShipDirs -SkipRoot $skipRoot
        Write-Host "  Restored ship dirs"
      }
    }
    if ($packExit -ne 0) { throw "export-pack failed ($($def.Preset)): $packExit" }
    if (-not (Test-Path $tmpPck)) { throw "PCK not created: $tmpPck" }
    $newSha = Get-FileSha256 $tmpPck
    $newSize = (Get-Item $tmpPck).Length
    if ($newSize -lt 1024) {
      Remove-Item $tmpPck -Force -ErrorAction SilentlyContinue
      throw "PCK too small ($newSize) for $($def.Preset)"
    }
    if ($existingOk) {
      $oldSha = Get-FileSha256 $outPck
      if ($oldSha -eq $newSha) {
        Remove-Item $tmpPck -Force
        Write-Host "  KEEP (export sha identical) size=$newSize sha=$newSha"
      } else {
        Move-Item $tmpPck $outPck -Force
        Write-Host "  REPLACE size=$newSize sha=$newSha"
      }
    } else {
      Move-Item $tmpPck $outPck -Force
      Write-Host "  OK size=$newSize sha=$newSha"
    }
  }

  if (-not (Test-Path $outPck)) { throw "PCK missing after pack step: $outPck" }
  $sha = Get-FileSha256 $outPck
  $size = (Get-Item $outPck).Length
  $entry = [ordered]@{
    path       = $def.Rel
    sha256     = $sha
    size       = $size
    kind       = [string]$def.Kind
    mountOrder = [int]$def.MountOrder
  }
  if ($def.Kind -eq "data") {
    $entry.requiredRelPaths = @($requiredRelPaths)
  }
  $manifestFiles += $entry
}

Write-Fingerprints $nextFp

$ver = "202609.1.1"
$publishedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")

$versionObj = [ordered]@{
  protocol             = 1
  version              = $ver
  publishedAt          = $publishedAt
  baseUrl              = "https://huggingface.co/buckets/liketocode789/eveautochess/resolve/"
  entry                = "res://scenes/main_menu.tscn"
  shellCompatibilityId = "eveac-shell-v1"
  notes                = "202609.1.1: consecutive-round AI deploy fix; first Prepare limited random buy 1 ship; prepare flush after force_finish"
}
$manifestObj = [ordered]@{
  version = $ver
  files   = $manifestFiles
}

($versionObj | ConvertTo-Json -Depth 5) | Set-Content "$hfRoot\version.json" -Encoding utf8
($manifestObj | ConvertTo-Json -Depth 8) | Set-Content "$hfRoot\manifest.json" -Encoding utf8
Copy-Item "$hfRoot\version.json" "H:\game_dev\eveautochess-hf\version.json" -Force
Copy-Item "$hfRoot\manifest.json" "H:\game_dev\eveautochess-hf\manifest.json" -Force

$contentMirror = "$hfRoot\content\data"
if (Test-Path $contentMirror) { Remove-Item $contentMirror -Recurse -Force }
Copy-Item "$proj\data" $contentMirror -Recurse -Force

Write-Host "OK version=$ver packs=$($manifestFiles.Count) requiredRelPaths=$($requiredRelPaths.Count)"
foreach ($f in $manifestFiles) {
  Write-Host ("  {0} kind={1} order={2} size={3} sha={4}" -f $f.path, $f.kind, $f.mountOrder, $f.size, $f.sha256.Substring(0, 12))
}
Write-Host "Staging: $hfRoot"
Write-Host "Push HF only after user confirms."
