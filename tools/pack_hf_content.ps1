# Build split content PCKs + HF staging (does NOT push HF).
# Five packs: data / logic / ui / models / audio — data uses presence skip; others sha256.
$ErrorActionPreference = "Stop"
$godot = "H:\game_dev\eveautochess-dev\tools\godot\Godot_v4.7.1-stable_win64.exe"
$proj = "H:\game_dev\eveautochess-dev\godot_project"
$hfRoot = "H:\game_dev\eveautochess-hf\_hf_publish_root"
$packsDir = Join-Path $hfRoot "packs"
$projData = Join-Path $proj "data"
New-Item -ItemType Directory -Force -Path $packsDir | Out-Null

# GDScript gate (DIAGNOSTICS §7): fail before any export-pack.
$checkScript = Join-Path $PSScriptRoot "check_gdscript.ps1"
Write-Host "Running GDScript check gate..."
& $checkScript -Godot $godot -Project $proj
if ($LASTEXITCODE -ne 0) {
  throw "check_gdscript.ps1 failed (exit=$LASTEXITCODE) — fix per-file blocks above before packing"
}

# Remove legacy monolithic pack from staging so it is not re-uploaded as current.
$legacy = Join-Path $packsDir "game.pck"
if (Test-Path $legacy) {
  Remove-Item $legacy -Force
  Write-Host "Removed legacy packs/game.pck from staging"
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
  return ,$rels.ToArray()
}

$packDefs = @(
  @{ Preset = "Pack Data";   Rel = "packs/data.pck";   MountOrder = 5;  Kind = "data" },
  @{ Preset = "Pack Logic";  Rel = "packs/logic.pck";  MountOrder = 10; Kind = "pack" },
  @{ Preset = "Pack UI";     Rel = "packs/ui.pck";     MountOrder = 20; Kind = "pack" },
  @{ Preset = "Pack Models"; Rel = "packs/models.pck"; MountOrder = 30; Kind = "pack" },
  @{ Preset = "Pack Audio";  Rel = "packs/audio.pck";  MountOrder = 40; Kind = "pack" }
)

$requiredRelPaths = Get-RequiredRelPaths
if ($requiredRelPaths.Count -lt 2) {
  throw "requiredRelPaths too small ($($requiredRelPaths.Count)) — expected ships+equipment JSON"
}

$manifestFiles = @()
foreach ($def in $packDefs) {
  $outPck = Join-Path $hfRoot ($def.Rel -replace "/", "\")
  New-Item -ItemType Directory -Force -Path (Split-Path $outPck) | Out-Null
  if (Test-Path $outPck) { Remove-Item $outPck -Force }
  Write-Host "Exporting $($def.Preset) -> $($def.Rel) ..."
  ## Godot prints non-fatal "ERROR: Attempt to open script ..." on stderr for
  ## orphaned scene refs; with $ErrorActionPreference=Stop that becomes a throw.
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  cmd /c "`"$godot`" --headless --path `"$proj`" --export-pack `"$($def.Preset)`" `"$outPck`""
  $packExit = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  if ($packExit -ne 0) { throw "export-pack failed ($($def.Preset)): $packExit" }
  if (-not (Test-Path $outPck)) { throw "PCK not created: $outPck" }
  $sha = (Get-FileHash -Path $outPck -Algorithm SHA256).Hash.ToLowerInvariant()
  $size = (Get-Item $outPck).Length
  Write-Host "  OK size=$size sha=$sha"
  if ($size -lt 1024) {
    throw "PCK too small ($size) for $($def.Preset) — check include_filter"
  }
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

$ver = "202608.6.2"
$publishedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")

$versionObj = [ordered]@{
  protocol              = 1
  version               = $ver
  publishedAt           = $publishedAt
  baseUrl               = "https://huggingface.co/buckets/liketocode789/eveautochess/resolve/"
  entry                 = "res://scenes/main_menu.tscn"
  shellCompatibilityId  = "eveac-shell-v1"
  notes                 = "Five packs: data.pck (ships+equipment, presence skip) + logic/ui/models/audio"
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
  Write-Host ("  {0} kind={1} order={2} size={3}" -f $f.path, $f.kind, $f.mountOrder, $f.size)
}
Write-Host "Staging: $hfRoot"
Write-Host "Push HF only after user confirms."
