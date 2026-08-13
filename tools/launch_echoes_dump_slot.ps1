# ASCII-stable entry for Desktop shortcuts (avoid relying on .lnk encoding of 手游 path).
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('A', 'B')]
  [string]$Slot
)
$ErrorActionPreference = "Stop"
$launch = "H:\eve手游\history\skpw_hardcrack\avd_env\scripts\launch_echoes_dump.ps1"
if (-not (Test-Path -LiteralPath $launch)) {
  throw "Launch script missing: $launch"
}
& $launch -Slot $Slot
