# Build split content PCKs + HF staging (does NOT push HF).
# Four packs: logic / ui / models / audio — sha256 skip enables incremental hotupdate.
$ErrorActionPreference = "Stop"
$godot = "H:\game_dev\eveautochess-dev\tools\godot\Godot_v4.7.1-stable_win64.exe"
$proj = "H:\game_dev\eveautochess-dev\godot_project"
$hfRoot = "H:\game_dev\eveautochess-hf\_hf_publish_root"
$packsDir = Join-Path $hfRoot "packs"
New-Item -ItemType Directory -Force -Path $packsDir | Out-Null

# Remove legacy monolithic pack from staging so it is not re-uploaded as current.
$legacy = Join-Path $packsDir "game.pck"
if (Test-Path $legacy) {
  Remove-Item $legacy -Force
  Write-Host "Removed legacy packs/game.pck from staging"
}

$packDefs = @(
  @{ Preset = "Pack Logic";  Rel = "packs/logic.pck";  MountOrder = 10 },
  @{ Preset = "Pack UI";     Rel = "packs/ui.pck";     MountOrder = 20 },
  @{ Preset = "Pack Models"; Rel = "packs/models.pck"; MountOrder = 30 },
  @{ Preset = "Pack Audio";  Rel = "packs/audio.pck";  MountOrder = 40 }
)

$manifestFiles = @()
foreach ($def in $packDefs) {
  $outPck = Join-Path $hfRoot ($def.Rel -replace "/", "\")
  New-Item -ItemType Directory -Force -Path (Split-Path $outPck) | Out-Null
  if (Test-Path $outPck) { Remove-Item $outPck -Force }
  Write-Host "Exporting $($def.Preset) -> $($def.Rel) ..."
  cmd /c "`"$godot`" --headless --path `"$proj`" --export-pack `"$($def.Preset)`" `"$outPck`""
  if ($LASTEXITCODE -ne 0) { throw "export-pack failed ($($def.Preset)): $LASTEXITCODE" }
  if (-not (Test-Path $outPck)) { throw "PCK not created: $outPck" }
  $sha = (Get-FileHash -Path $outPck -Algorithm SHA256).Hash.ToLowerInvariant()
  $size = (Get-Item $outPck).Length
  Write-Host "  OK size=$size sha=$sha"
  if ($size -lt 1024) {
    throw "PCK too small ($size) for $($def.Preset) — check include_filter"
  }
  $manifestFiles += [ordered]@{
    path       = $def.Rel
    sha256     = $sha
    size       = $size
    kind       = "pack"
    mountOrder = [int]$def.MountOrder
  }
}

$ver = "202608.2.1"
$publishedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")

$versionObj = [ordered]@{
  protocol              = 1
  version               = $ver
  publishedAt           = $publishedAt
  baseUrl               = "https://huggingface.co/buckets/liketocode789/eveautochess/resolve/"
  entry                 = "res://scenes/main_menu.tscn"
  shellCompatibilityId  = "eveac-shell-v1"
  notes                 = "Battleship HP from TQ SDE; ship-data editor DPS/HP charts; sleepers+freighters in charts; mining gold x star; content/combat sync 202608.2.1"
}
$manifestObj = [ordered]@{
  version = $ver
  files   = $manifestFiles
}

($versionObj | ConvertTo-Json -Depth 5) | Set-Content "$hfRoot\version.json" -Encoding utf8
($manifestObj | ConvertTo-Json -Depth 6) | Set-Content "$hfRoot\manifest.json" -Encoding utf8
Copy-Item "$hfRoot\version.json" "H:\game_dev\eveautochess-hf\version.json" -Force
Copy-Item "$hfRoot\manifest.json" "H:\game_dev\eveautochess-hf\manifest.json" -Force

$contentMirror = "$hfRoot\content\data"
if (Test-Path $contentMirror) { Remove-Item $contentMirror -Recurse -Force }
Copy-Item "$proj\data" $contentMirror -Recurse -Force

Write-Host "OK version=$ver packs=$($manifestFiles.Count)"
foreach ($f in $manifestFiles) {
  Write-Host ("  {0} order={1} size={2}" -f $f.path, $f.mountOrder, $f.size)
}
Write-Host "Staging: $hfRoot"
Write-Host "Push HF only after user confirms."
