# Godot official CLI gate: import + per-file --check-only (skip addons) + optional scene smoke.
# Incremental: first run / -Full / warning-policy change → all scripts; else only mtime/size-changed.
# Output is ALWAYS per-file blocks so failures stay attributable (DIAGNOSTICS §7).
# Usage:
#   .\check_gdscript.ps1
#   .\check_gdscript.ps1 -Full
#   .\check_gdscript.ps1 -Project "H:\...\godot_project" -SkipSmoke
param(
  [string]$Godot = "H:\game_dev\eveautochess-dev\tools\godot\Godot_v4.7.1-stable_win64.exe",
  [string]$Project = "H:\game_dev\eveautochess-dev\godot_project",
  [switch]$SkipSmoke,
  [switch]$Full,
  [string]$SmokeScene = "res://scenes/main_menu.tscn"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Godot)) { throw "Godot not found: $Godot" }
if (-not (Test-Path (Join-Path $Project "project.godot"))) { throw "Not a Godot project: $Project" }

$cacheDir = Join-Path $Project ".godot"
$cachePath = Join-Path $cacheDir "eveac_gdscript_check_cache.json"
$projectGodot = Join-Path $Project "project.godot"

function Get-WarnPolicyFingerprint {
  if (-not (Test-Path $projectGodot)) { return "missing" }
  $lines = Get-Content -LiteralPath $projectGodot
  $buf = New-Object System.Collections.Generic.List[string]
  $inDebug = $false
  foreach ($line in $lines) {
    if ($line -match '^\[debug\]') { $inDebug = $true; continue }
    if ($line -match '^\[') { $inDebug = $false; continue }
    if ($inDebug -and $line -match 'gdscript/warnings/') { $buf.Add($line.Trim()) }
  }
  $text = ($buf -join "`n")
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
  }
  finally { $sha.Dispose() }
}

function Invoke-GodotCapture {
  param([string[]]$GodotArgs)
  $tmpOut = [System.IO.Path]::GetTempFileName()
  $tmpErr = [System.IO.Path]::GetTempFileName()
  try {
    $p = Start-Process -FilePath $Godot -ArgumentList $GodotArgs `
      -NoNewWindow -Wait -PassThru `
      -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
    $stdout = Get-Content -LiteralPath $tmpOut -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content -LiteralPath $tmpErr -Raw -ErrorAction SilentlyContinue
    if ($null -eq $stdout) { $stdout = "" }
    if ($null -eq $stderr) { $stderr = "" }
    return @{
      ExitCode = [int]$p.ExitCode
      StdOut   = $stdout
      StdErr   = $stderr
      Combined = ($stdout + "`n" + $stderr)
    }
  }
  finally {
    Remove-Item -LiteralPath $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue
  }
}

function Test-RelevantErrorLine([string]$line) {
  if ([string]::IsNullOrWhiteSpace($line)) { return $false }
  if ($line -match 'Godot Engine v') { return $false }
  if ($line -match '^\s*$') { return $false }
  if ($line -match 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|Warning treated as error|ERROR:') {
    return $true
  }
  if ($line -match '^\s*at:\s') { return $true }
  return $false
}

function Get-FileStamp([System.IO.FileInfo]$fi) {
  return @{
    mtimeUtc = $fi.LastWriteTimeUtc.Ticks
    length   = $fi.Length
  }
}

$warnFp = Get-WarnPolicyFingerprint
$cache = $null
if ((Test-Path $cachePath) -and -not $Full) {
  try {
    $cache = Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
  }
  catch {
    Write-Host "=== cache unreadable; forcing full check ==="
    $cache = $null
  }
}

$doFull = [bool]$Full
$fullReason = ""
if ($Full) { $fullReason = "-Full" }
elseif ($null -eq $cache) { $doFull = $true; $fullReason = "no cache (first run)" }
elseif ([string]$cache.warnPolicyFp -ne $warnFp) { $doFull = $true; $fullReason = "warning policy changed" }

$okMap = @{}
if ($cache -and $cache.files) {
  foreach ($prop in $cache.files.PSObject.Properties) {
    $okMap[$prop.Name] = $prop.Value
  }
}

Write-Host "=== check_gdscript: import ($Project) ==="
$import = Invoke-GodotCapture @(
  "--headless", "--path", $Project, "--import", "--quit"
)
$importFindings = @()
foreach ($line in ($import.Combined -split "`r?`n")) {
  if (Test-RelevantErrorLine $line) {
    # Autoload/script compile failures reappear in the per-file pass — skip here to avoid interlaced noise.
    if ($line -match 'SCRIPT ERROR|Parse Error|Failed to load script|GDScript|autoload|is not compiling') {
      continue
    }
    $importFindings += $line
  }
}
if ($importFindings.Count -gt 0) {
  Write-Host "=== IMPORT FINDINGS ==="
  $importFindings | ForEach-Object { Write-Host $_ }
}

$scriptsRoot = Join-Path $Project "scripts"
if (-not (Test-Path $scriptsRoot)) { throw "No scripts/ under $Project" }

$gdFiles = @(Get-ChildItem -Path $scriptsRoot -Filter "*.gd" -File -Recurse |
  Where-Object { $_.FullName -notmatch '[\\/]addons[\\/]' } |
  Sort-Object FullName)

$toCheck = New-Object System.Collections.Generic.List[object]
$skipped = 0
foreach ($f in $gdFiles) {
  $rel = ($f.FullName.Substring($Project.Length).TrimStart("\", "/") -replace "\\", "/")
  $resPath = "res://$rel"
  $stamp = Get-FileStamp $f
  $prev = $okMap[$rel]
  $need = $doFull
  if (-not $need) {
    if ($null -eq $prev) {
      $need = $true
    }
    elseif ([int64]$prev.mtimeUtc -ne [int64]$stamp.mtimeUtc -or [int64]$prev.length -ne [int64]$stamp.length) {
      $need = $true
    }
  }
  if ($need) {
    $toCheck.Add([pscustomobject]@{ File = $f; Rel = $rel; ResPath = $resPath; Stamp = $stamp })
  }
  else {
    $skipped++
  }
}

# Drop cache entries for deleted scripts.
$currentRels = @{}
foreach ($f in $gdFiles) {
  $rel = ($f.FullName.Substring($Project.Length).TrimStart("\", "/") -replace "\\", "/")
  $currentRels[$rel] = $true
}
$pruned = 0
foreach ($key in @($okMap.Keys)) {
  if (-not $currentRels.ContainsKey($key)) {
    $okMap.Remove($key)
    $pruned++
  }
}

if ($doFull) {
  Write-Host ("=== check_gdscript: FULL ({0}) — {1} scripts ===" -f $fullReason, $toCheck.Count)
}
else {
  Write-Host ("=== check_gdscript: INCREMENTAL — check={0} skip_ok={1} pruned={2} ===" -f $toCheck.Count, $skipped, $pruned)
}

$failed = New-Object System.Collections.Generic.List[object]
$checked = 0
$newlyOk = @{}

if ($toCheck.Count -gt 0) {
  # One Godot process with Autoloads live — --check-only alone mis-resolves DataStore/AdminBus as script classes.
  $list = ($toCheck | ForEach-Object { $_.ResPath }) -join ";"
  $env:EVEAC_CHECK_SCRIPTS = $list
  Write-Host "=== check_gdscript: SceneTree runner (autoload-aware) ==="
  $r = Invoke-GodotCapture @(
    "--headless", "--path", $Project, "--script", "res://tools/check_scripts_runner.gd"
  )
  Remove-Item Env:EVEAC_CHECK_SCRIPTS -ErrorAction SilentlyContinue
  # Do not dump full Combined (Godot prints every warning-as-error with backtrace — interlaced noise).
  # Only surface runner markers + attributed FAIL blocks below.

  $runnerOk = ($r.Combined -match 'eveac_check_runner RESULT')
  if ($r.Combined -match 'eveac_check_runner: scripts=') {
    ($r.Combined -split "`r?`n" | Where-Object { $_ -match 'eveac_check_runner' }) | ForEach-Object { Write-Host $_ }
  }
  if (-not $runnerOk) {
    Write-Host "=== FAIL res://tools/check_scripts_runner.gd (runner did not start) ==="
    foreach ($line in ($r.Combined -split "`r?`n")) {
      if (Test-RelevantErrorLine $line) { Write-Host $line }
    }
    Write-Host "=== END res://tools/check_scripts_runner.gd ==="
    $failed.Add([pscustomobject]@{
      Path = "res://tools/check_scripts_runner.gd"
      ExitCode = $r.ExitCode
      Lines = @("runner did not print RESULT (exit=$($r.ExitCode))")
    })
    foreach ($item in $toCheck) {
      $checked++
      if ($okMap.ContainsKey($item.Rel)) { $okMap.Remove($item.Rel) }
    }
  }
  else {
    $failSet = @{}
    $curFail = $null
    foreach ($line in ($r.Combined -split "`r?`n")) {
      if ($line -match '^=== FAIL (res://\S+) ===') {
        $curFail = $Matches[1]
        if (-not $failSet.ContainsKey($curFail)) {
          $failSet[$curFail] = New-Object System.Collections.Generic.List[string]
        }
        continue
      }
      if ($line -match '^=== END (res://\S+) ===') {
        $curFail = $null
        continue
      }
      if ($null -ne $curFail) {
        $failSet[$curFail].Add($line)
      }
      if ($line -match 'at: GDScript::reload \((res://[^:]+):\d+\)') {
        $p = $Matches[1]
        if (-not $failSet.ContainsKey($p)) {
          $failSet[$p] = New-Object System.Collections.Generic.List[string]
        }
        $failSet[$p].Add($line)
      }
    }

    foreach ($item in $toCheck) {
      $checked++
      $resPath = $item.ResPath
      if ($failSet.ContainsKey($resPath)) {
        $lines = @($failSet[$resPath])
        $failed.Add([pscustomobject]@{ Path = $resPath; ExitCode = 1; Lines = $lines })
        if ($okMap.ContainsKey($item.Rel)) { $okMap.Remove($item.Rel) }
        Write-Host ""
        Write-Host "=== FAIL $resPath ==="
        $lines | Select-Object -First 30 | ForEach-Object { Write-Host $_ }
        Write-Host "=== END $resPath ==="
      }
      else {
        $newlyOk[$item.Rel] = [pscustomobject]@{
          mtimeUtc = [int64]$item.Stamp.mtimeUtc
          length   = [int64]$item.Stamp.length
        }
      }
    }
  }
}


$smokeFailed = $false
$runSmoke = -not $SkipSmoke
if ($runSmoke -and $checked -eq 0 -and -not $doFull) {
  Write-Host "=== SMOKE SKIP: nothing changed (incremental) ==="
  $runSmoke = $false
}
if ($runSmoke) {
  $smokeScript = Join-Path $Project "tools\smoke_load_scene.gd"
  if (-not (Test-Path $smokeScript)) {
    Write-Host "=== SMOKE SKIP: missing tools/smoke_load_scene.gd ==="
  }
  else {
    Write-Host "=== check_gdscript: smoke load $SmokeScene ==="
    $env:EVEAC_SMOKE_SCENE = $SmokeScene
    $smoke = Invoke-GodotCapture @(
      "--headless", "--path", $Project, "--script", "res://tools/smoke_load_scene.gd", "--quit"
    )
    Remove-Item Env:EVEAC_SMOKE_SCENE -ErrorAction SilentlyContinue
    $smokeLines = @()
    foreach ($line in ($smoke.Combined -split "`r?`n")) {
      if (Test-RelevantErrorLine $line) { $smokeLines += $line.TrimEnd() }
      if ($line -match '\[eveac_smoke\]') { $smokeLines += $line.TrimEnd() }
    }
    $smokeOkMarker = ($smoke.Combined -match '\[eveac_smoke\]\s*OK')
    if (($smoke.ExitCode -ne 0) -or (-not $smokeOkMarker)) {
      $smokeFailed = $true
      Write-Host "=== FAIL SMOKE $SmokeScene (exit=$($smoke.ExitCode)) ==="
      if ($smokeLines.Count -gt 0) {
        $smokeLines | ForEach-Object { Write-Host $_ }
      }
      else {
        ($smoke.Combined -split "`r?`n" | Select-Object -Last 40) | ForEach-Object { Write-Host $_ }
      }
      Write-Host "=== END SMOKE ==="
    }
    else {
      Write-Host "=== SMOKE OK $SmokeScene ==="
    }
  }
}

# Merge successful stamps into cache (failed files stay unchecked).
foreach ($k in $newlyOk.Keys) { $okMap[$k] = $newlyOk[$k] }

$filesObj = [ordered]@{}
foreach ($k in ($okMap.Keys | Sort-Object)) {
  $filesObj[$k] = $okMap[$k]
}
$cacheOut = [ordered]@{
  version      = 1
  warnPolicyFp = $warnFp
  updatedAt    = (Get-Date).ToString("o")
  files        = $filesObj
}
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
# Always write cache (including partial oks) so incremental progress is kept; failed paths omitted.
($cacheOut | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $cachePath -Encoding utf8

Write-Host ""
Write-Host ("RESULT: mode={0} checked={1} skipped_ok={2} failed_scripts={3} smoke_failed={4}" -f `
  $(if ($doFull) { "full" } else { "incremental" }), $checked, $skipped, $failed.Count, $smokeFailed)
if ($failed.Count -gt 0) {
  Write-Host "Failed scripts (paths only):"
  foreach ($item in $failed) { Write-Host ("  - {0}" -f $item.Path) }
}
if ($failed.Count -gt 0 -or $smokeFailed) {
  exit 1
}
exit 0
