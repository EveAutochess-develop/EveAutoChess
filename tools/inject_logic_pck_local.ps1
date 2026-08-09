# Replace local EveAutochess logic.pck with staged HF pack (same content version).
# Does NOT push HF. Close EveAutochess before running.
param(
  [string]$Src = "H:\game_dev\eveautochess-hf\_hf_publish_root\packs\logic.pck"
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Src)) { throw "missing $Src — run pack_hf_content.ps1 -Only logic first" }
$shaSrc = (Get-FileHash $Src -Algorithm SHA256).Hash.ToLowerInvariant()
$roots = @(
  "$env:APPDATA\userdata",
  "$env:APPDATA\Godot\app_userdata\userdata",
  "$env:LOCALAPPDATA\Programs\EveAutochess\userdata"
)
$found = @()
foreach ($r in $roots) {
  if (Test-Path $r) {
    Get-ChildItem $r -Recurse -Filter logic.pck -EA SilentlyContinue | ForEach-Object { $found += $_ }
  }
}
if ($found.Count -eq 0) {
  Get-ChildItem "$env:APPDATA\Godot\app_userdata" -Recurse -Filter logic.pck -EA SilentlyContinue |
    ForEach-Object { $found += $_ }
}
if ($found.Count -eq 0) { throw "No logic.pck found — launch game once to seed packs, then rerun" }
foreach ($f in $found) {
  $bak = "$($f.FullName).bak_pre_zt"
  if (-not (Test-Path $bak)) { Copy-Item $f.FullName $bak -Force }
  Copy-Item $Src $f.FullName -Force
  Write-Host "Replaced $($f.FullName)"
  $dir = $f.Directory.FullName
  foreach ($mc in @(
    (Join-Path $dir "..\manifest.json"),
    (Join-Path $dir "..\..\manifest.json"),
    (Join-Path $dir "manifest.json")
  )) {
    $m = [IO.Path]::GetFullPath($mc)
    if (-not (Test-Path $m)) { continue }
    $obj = Get-Content $m -Raw | ConvertFrom-Json
    $chg = $false
    foreach ($file in $obj.files) {
      if ([string]$file.path -match 'logic\.pck$') {
        $file.sha256 = $shaSrc
        $file.size = (Get-Item $Src).Length
        $chg = $true
      }
    }
    if ($chg) {
      ($obj | ConvertTo-Json -Depth 10) | Set-Content $m -Encoding utf8
      Write-Host "Updated manifest $m"
    }
  }
}
Write-Host "OK sha=$shaSrc version stays 202608.8.74"
Write-Host "Restart EveAutochess -> host room -> copy room code (embeds ZeroTier IP)"
