<#
.SYNOPSIS
  Install EveAutochess.apk onto both EchoesDump Android emulators (or all adb devices).

.DESCRIPTION
  Reusable dual-emulator install helper for local acceptance.
  Defaults to H:\disv1\EveAutochess.apk and serials emulator-5554 / emulator-5556.
  Waits for devices, installs with -r -g, prints versionName/versionCode, optionally launches.

.EXAMPLE
  .\install_dual_emulators.ps1

.EXAMPLE
  .\install_dual_emulators.ps1 -Apk H:\disv1\EveAutochess.apk -Launch

.EXAMPLE
  .\install_dual_emulators.ps1 -Serials @('emulator-5554','emulator-5556') -AllDevices
#>
param(
  [string]$Apk = "H:\disv1\EveAutochess.apk",
  [string[]]$Serials = @("emulator-5554", "emulator-5556"),
  [string]$Package = "com.eveautochess.game",
  [string]$Activity = "com.eveautochess.game/com.godot.game.GodotApp",
  [string]$Adb = "",
  # If set, install to every `adb devices` entry that is "device" (ignores -Serials filter when empty list falls back).
  [switch]$AllDevices,
  [switch]$Launch,
  [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"

if (-not $Adb) {
  $cands = @(
    "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    "$env:ANDROID_HOME\platform-tools\adb.exe",
    "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe"
  )
  $Adb = $cands | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $Adb -or -not (Test-Path $Adb)) {
  throw "adb.exe not found. Pass -Adb or install Android SDK platform-tools."
}
if (-not (Test-Path $Apk)) {
  throw "APK missing: $Apk"
}

function Get-OnlineSerials {
  $lines = & $Adb devices | Where-Object { $_ -match "^\S+\s+device$" }
  $out = @()
  foreach ($line in $lines) {
    $parts = ($line -split "\s+")
    if ($parts.Count -ge 1) { $out += $parts[0] }
  }
  return $out
}

function Wait-SerialOnline {
  param([string]$Serial, [int]$TimeoutSec = 90)
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  do {
    $online = Get-OnlineSerials
    if ($online -contains $Serial) { return $true }
    ## Soft reconnect once if listed offline.
    $raw = & $Adb devices
    if ($raw -match [regex]::Escape($Serial)) {
      & $Adb -s $Serial wait-for-device 2>$null | Out-Null
    }
    Start-Sleep -Seconds 2
  } while ((Get-Date) -lt $deadline)
  return $false
}

function Get-PackageVersion {
  param([string]$Serial)
  $dump = & $Adb -s $Serial shell dumpsys package $Package 2>$null
  $code = ($dump | Select-String -Pattern "versionCode=(\d+)" | Select-Object -First 1)
  $name = ($dump | Select-String -Pattern 'versionName=([^\s]+)' | Select-Object -First 1)
  return [pscustomobject]@{
    Serial = $Serial
    VersionCode = if ($code) { $code.Matches[0].Groups[1].Value } else { "?" }
    VersionName = if ($name) { $name.Matches[0].Groups[1].Value } else { "?" }
  }
}

Write-Host "APK: $Apk ($((Get-Item $Apk).Length) bytes)"
Write-Host "adb: $Adb"
& $Adb start-server | Out-Null

$targets = @()
if ($AllDevices) {
  $targets = @(Get-OnlineSerials)
  if ($targets.Count -eq 0) {
    throw "No online adb devices. Start EchoesDump A/B first."
  }
} else {
  foreach ($s in $Serials) {
    Write-Host "Wait for $s ..."
    if (-not (Wait-SerialOnline -Serial $s)) {
      Write-Warning "Skip offline: $s"
      continue
    }
    $targets += $s
  }
}
if ($targets.Count -eq 0) {
  throw "No target emulators online."
}

$results = @()
foreach ($s in $targets) {
  Write-Host "=== Install $s ==="
  & $Adb -s $s wait-for-device | Out-Null
  $out = & $Adb -s $s install -r -g $Apk 2>&1 | Out-String
  Write-Host $out.Trim()
  if ($out -notmatch "Success") {
    Write-Warning "Install may have failed on $s"
  }
  $ver = Get-PackageVersion -Serial $s
  $results += $ver
  Write-Host ("  {0} versionName={1} versionCode={2}" -f $ver.Serial, $ver.VersionName, $ver.VersionCode)
  if (-not $NoLaunch) {
    & $Adb -s $s shell am start -n $Activity 2>&1 | Out-Null
    Write-Host "  launched $Activity"
  }
}

Write-Host ""
Write-Host "Done. Installed on $($results.Count) device(s):"
$results | Format-Table -AutoSize
exit 0
