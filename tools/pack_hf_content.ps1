# Build content PCK + HF staging (does NOT push HF).
$ErrorActionPreference = "Stop"
$godot = "H:\game_dev\eveautochess-dev\tools\godot\Godot_v4.7.1-stable_win64.exe"
$proj = "H:\game_dev\eveautochess-dev\godot_project"
$outPck = "H:\game_dev\eveautochess-hf\_hf_publish_root\packs\game.pck"
$hfRoot = "H:\game_dev\eveautochess-hf\_hf_publish_root"
New-Item -ItemType Directory -Force -Path (Split-Path $outPck) | Out-Null

Write-Host "Exporting content pack..."
cmd /c "`"$godot`" --headless --path `"$proj`" --export-pack `"Content Pack`" `"$outPck`""
if ($LASTEXITCODE -ne 0) { throw "export-pack failed: $LASTEXITCODE" }
if (-not (Test-Path $outPck)) { throw "PCK not created: $outPck" }

$sha = (Get-FileHash -Path $outPck -Algorithm SHA256).Hash.ToLowerInvariant()
$size = (Get-Item $outPck).Length
$ver = "202607.27.3"
$publishedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")

$versionObj = [ordered]@{
  protocol = 1
  version = $ver
  publishedAt = $publishedAt
  baseUrl = "https://huggingface.co/buckets/liketocode789/eveautochess/resolve/"
  entry = "res://scenes/main_menu.tscn"
  shellCompatibilityId = "eveac-shell-v1"
  notes = "weapon_fx/laser; hollow grid hide in battle; approach+separation; AI hover info; lights/mats; AI cap 2.5x; SSAA4"
}
$manifestObj = [ordered]@{
  version = $ver
  files = @(
    [ordered]@{
      path = "packs/game.pck"
      sha256 = $sha
      size = $size
      kind = "pack"
      mountOrder = 10
    }
  )
}

($versionObj | ConvertTo-Json -Depth 5) | Set-Content "$hfRoot\version.json" -Encoding utf8
($manifestObj | ConvertTo-Json -Depth 6) | Set-Content "$hfRoot\manifest.json" -Encoding utf8
Copy-Item "$hfRoot\version.json" "H:\game_dev\eveautochess-hf\version.json" -Force
Copy-Item "$hfRoot\manifest.json" "H:\game_dev\eveautochess-hf\manifest.json" -Force

$contentMirror = "$hfRoot\content\data"
if (Test-Path $contentMirror) { Remove-Item $contentMirror -Recurse -Force }
Copy-Item "$proj\data" $contentMirror -Recurse -Force

Write-Host "OK version=$ver sha=$sha size=$size"
Write-Host "Staging: $hfRoot"
Write-Host "Push HF only after user confirms."
