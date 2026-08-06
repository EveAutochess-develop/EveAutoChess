<#
.SYNOPSIS
  Install EveAutochess.apk onto both EchoesDump Android emulators (or all adb devices).

.DESCRIPTION
  Reusable dual-emulator install helper for local acceptance.
  Defaults to H:\disv1\EveAutochess.apk and serials emulator-5554 / emulator-5556.
  Optionally starts EchoesDump A/B AVDs when offline, waits for boot, then install -r -g.

.EXAMPLE
  .\install_dual_emulators.ps1

.EXAMPLE
  .\install_dual_emulators.ps1 -Apk H:\disv1\EveAutochess.apk -Launch

.EXAMPLE
  .\install_dual_emulators.ps1 -NoStartEmulators
#>
param(
  [string]$Apk = "H:\disv1\EveAutochess.apk",
  [string[]]$Serials = @("emulator-5554", "emulator-5556"),
  ## Parallel AVD names for -StartEmulators (index-aligned with default Serials).
  [string[]]$Avds = @("EchoesDump_API34_x86_64", "EchoesDump_API34_x86_64_B"),
  [int[]]$Ports = @(5554, 5556),
  [string]$Package = "com.eveautochess.game",
  [string]$Activity = "com.eveautochess.game/com.godot.game.GodotApp",
  [string]$Adb = "",
  [string]$Emulator = "",
  [switch]$AllDevices,
  [switch]$Launch,
  [switch]$NoLaunch,
  ## Default: start offline EchoesDump A/B before install.
  [switch]$StartEmulators,
  [switch]$NoStartEmulators,
  [int]$BootTimeoutSec = 180
)

$ErrorActionPreference = "Stop"

## -StartEmulators is the default unless -NoStartEmulators.
$doStart = -not $NoStartEmulators
if ($PSBoundParameters.ContainsKey("StartEmulators") -and $StartEmulators) {
  $doStart = $true
}

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
if (-not $Emulator) {
  $ecands = @(
    "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe",
    "$env:ANDROID_HOME\emulator\emulator.exe",
    "$env:ANDROID_SDK_ROOT\emulator\emulator.exe"
  )
  $Emulator = $ecands | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
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
    $raw = & $Adb devices
    if ($raw -match [regex]::Escape($Serial)) {
      & $Adb -s $Serial wait-for-device 2>$null | Out-Null
    }
    Start-Sleep -Seconds 2
  } while ((Get-Date) -lt $deadline)
  return $false
}

function Wait-BootCompleted {
  param([string]$Serial, [int]$TimeoutSec = 180)
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  & $Adb -s $Serial wait-for-device | Out-Null
  do {
    $boot = (& $Adb -s $Serial shell getprop sys.boot_completed 2>$null | Out-String).Trim()
    if ($boot -eq "1") { return $true }
    Start-Sleep -Seconds 3
  } while ((Get-Date) -lt $deadline)
  return $false
}

function Start-AvdIfNeeded {
  param([string]$Serial, [string]$AvdName, [int]$Port)
  $online = Get-OnlineSerials
  if ($online -contains $Serial) {
    Write-Host "Already online: $Serial"
    return
  }
  if (-not $Emulator -or -not (Test-Path $Emulator)) {
    throw "emulator.exe not found; cannot start $AvdName. Pass -Emulator or -NoStartEmulators."
  }
  Write-Host "Starting AVD $AvdName on port $Port → $Serial ..."
  Start-Process -FilePath $Emulator -ArgumentList @("-avd", $AvdName, "-port", "$Port", "-no-snapshot-save") -WindowStyle Minimized | Out-Null
  if (-not (Wait-SerialOnline -Serial $Serial -TimeoutSec $BootTimeoutSec)) {
    throw "Timed out waiting for $Serial after starting $AvdName"
  }
  if (-not (Wait-BootCompleted -Serial $Serial -TimeoutSec $BootTimeoutSec)) {
    throw "Timed out waiting for boot_completed on $Serial"
  }
  Write-Host "Booted: $Serial"
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
## adb may write "daemon not running" to stderr — do not treat as terminating error.
$prevEapStart = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $Adb start-server 2>&1 | Out-Null
$ErrorActionPreference = $prevEapStart

if ($doStart -and -not $AllDevices) {
  $n = [Math]::Min($Serials.Count, [Math]::Min($Avds.Count, $Ports.Count))
  for ($i = 0; $i -lt $n; $i++) {
    Start-AvdIfNeeded -Serial $Serials[$i] -AvdName $Avds[$i] -Port $Ports[$i]
  }
}

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
    if (-not (Wait-BootCompleted -Serial $s -TimeoutSec 60)) {
      Write-Warning "boot_completed not ready: $s (continuing install anyway)"
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
    ## GodotApp may be non-exported; monkey LAUNCHER is reliable on API 34.
    ## adb writes progress to stderr — do not treat as terminating error.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $launchOut = & $Adb -s $s shell monkey -p $Package -c android.intent.category.LAUNCHER 1 2>&1 | Out-String
    $ErrorActionPreference = $prevEap
    if ($launchOut -match "Events injected:\s*1") {
      Write-Host "  launched via monkey LAUNCHER"
    } else {
      Write-Warning ("launch may have failed on {0}: {1}" -f $s, $launchOut.Trim())
    }
  }
}

Write-Host ""
Write-Host "Done. Installed on $($results.Count) device(s):"
$results | Format-Table -AutoSize
exit 0
