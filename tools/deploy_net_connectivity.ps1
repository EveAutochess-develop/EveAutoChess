<#
.SYNOPSIS
  Deploy net_connectivity.cfg into Windows Godot userdata + Android emulators.

.EXAMPLE
  .\deploy_net_connectivity.ps1 -TurnUrls "192.168.3.4:27001" -Emulators
#>
param(
  [string]$TurnUrls = "",
  [string]$TurnUser = "",
  [string]$TurnPass = "",
  [string]$ConfigPath = "",
  ## Godot user:// folder name (config/name). Default: EVE + zi zou qi.
  [string]$AppDataName = "",
  [switch]$Emulators,
  [string[]]$Serials = @("emulator-5554", "emulator-5556"),
  [string]$Adb = ""
)

$ErrorActionPreference = "Stop"
if (-not $AppDataName) {
  $AppDataName = "EVE" + [char]0x81EA + [char]0x8D70 + [char]0x68CB
}

$Example = Join-Path $PSScriptRoot "net_connectivity.example.cfg"
if (-not $ConfigPath) {
  $ConfigPath = Join-Path $env:TEMP "eveac_net_connectivity.cfg"
  Copy-Item $Example $ConfigPath -Force
  $raw = Get-Content $ConfigPath -Raw -Encoding UTF8
  if ($TurnUrls -ne "") {
    $raw = $raw -replace 'turn_urls=""', ('turn_urls="{0}"' -f $TurnUrls)
  }
  if ($TurnUser -ne "") {
    $raw = $raw -replace 'turn_user=""', ('turn_user="{0}"' -f $TurnUser)
  }
  if ($TurnPass -ne "") {
    $raw = $raw -replace 'turn_pass=""', ('turn_pass="{0}"' -f $TurnPass)
  }
  [System.IO.File]::WriteAllText($ConfigPath, $raw, (New-Object System.Text.UTF8Encoding $false))
}

if (-not (Test-Path $ConfigPath)) {
  throw "Config missing: $ConfigPath"
}

$winDir = Join-Path $env:APPDATA ("Godot\app_userdata\" + $AppDataName)
New-Item -ItemType Directory -Force -Path $winDir | Out-Null
$winDst = Join-Path $winDir "net_connectivity.cfg"
Copy-Item $ConfigPath $winDst -Force
Write-Host "Windows: $winDst"

$legacy = Join-Path $env:APPDATA "Godot\app_userdata\EVE???"
if (Test-Path -LiteralPath $legacy) {
  Copy-Item $ConfigPath (Join-Path $legacy "net_connectivity.cfg") -Force
  Write-Host "Windows legacy EVE???: updated"
}

if ($Emulators) {
  if (-not $Adb) {
    $cands = @(
      "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
      "$env:ANDROID_HOME\platform-tools\adb.exe"
    )
    $Adb = $cands | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  }
  if (-not $Adb) {
    Write-Warning "adb not found; skip emulators"
  } else {
    ## Godot Android user:// == app files/ root (not Windows app_userdata/<name>/).
    $remoteRel = "files/net_connectivity.cfg"
    $sdcardTmp = "/sdcard/Download/eveac_net_connectivity.cfg"
    foreach ($s in $Serials) {
      $online = & $Adb devices | Where-Object { $_ -match ("^" + [regex]::Escape($s) + "\s+device") }
      if (-not $online) {
        Write-Warning "Skip offline $s"
        continue
      }
      & $Adb -s $s push $ConfigPath $sdcardTmp
      $prev = $ErrorActionPreference
      $ErrorActionPreference = "Continue"
      $copyOut = & $Adb -s $s shell "run-as com.eveautochess.game sh -c 'cp $sdcardTmp $remoteRel && chmod 600 $remoteRel && ls -l $remoteRel'" 2>&1 | Out-String
      $ErrorActionPreference = $prev
      if ($copyOut -match "net_connectivity\.cfg") {
        Write-Host "Android ${s}: $remoteRel OK"
      } else {
        Write-Warning ("Android {0}: run-as copy failed: {1}" -f $s, $copyOut.Trim())
      }
    }
  }
}

Write-Host "Done. Restart game clients to reload cfg."
exit 0
