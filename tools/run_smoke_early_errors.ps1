# Headless early-error smoke for eveautochess content project.
$ErrorActionPreference = "Continue"
$godot = "H:\game_dev\eveautochess-dev\tools\godot\Godot_v4.7.1-stable_win64.exe"
$proj = "H:\game_dev\eveautochess-dev\godot_project"
if (-not (Test-Path $godot)) { throw "Godot not found: $godot" }
Write-Host "Running smoke_early_errors.gd ..."
$out = & $godot --headless --path $proj --quit-after 30 -s "res://tools/smoke_early_errors.gd" 2>&1 | ForEach-Object { "$_" }
$code = $LASTEXITCODE
$out | ForEach-Object { Write-Host $_ }
if ($null -eq $code) { $code = 0 }
$text = ($out -join "`n")
if ($text -match '\[smoke\] FAIL') {
  throw "smoke failed marker (exit=$code)"
}
if ($text -notmatch '\[smoke\] OK') {
  throw "smoke missing OK marker (exit=$code)"
}
Write-Host "smoke OK"
