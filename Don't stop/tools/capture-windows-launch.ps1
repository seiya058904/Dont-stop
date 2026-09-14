# Launch the exported Windows build twice (cold and warm) and collect launch
# evidence.
#
# Two things this deliberately does NOT do:
#   * It never screenshots the desktop. The game saves its own framebuffer PNGs
#     from inside Boot.gd via `--boot-capture=<dir>`, so nothing outside the game
#     window can ever end up in evidence.
#   * It never touches the real save. The shipped build writes to
#     %APPDATA%\TowDownGame\, which Godot resolves from the APPDATA environment
#     variable, so the child process gets its own APPDATA. The script reports
#     afterwards whether the real save changed.
param(
    [string]$Exe = "Don't stop.exe",
    [string]$OutDir = "evidence\r2\windows",
    [int]$RunSeconds = 12
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$exePath = Join-Path $root "build\windows\$Exe"
if (-not (Test-Path -LiteralPath $exePath)) { throw "missing $exePath" }

$out = Join-Path $root $OutDir
New-Item -ItemType Directory -Force -Path $out | Out-Null

$realSave = Join-Path $env:APPDATA 'TowDownGame\camp-v1.json'
$realSaveBefore = if (Test-Path -LiteralPath $realSave) { (Get-Item -LiteralPath $realSave).LastWriteTimeUtc } else { $null }

function Invoke-Launch([string]$label, [string]$captureDir) {
    New-Item -ItemType Directory -Force -Path $captureDir | Out-Null
    $profileRoot = Join-Path $env:TEMP ("dontstop-boot-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $profileRoot | Out-Null
    $logFile = Join-Path $out "$label.log"

    $env:APPDATA = $profileRoot
    $args = @('--log-file', ('"' + $logFile + '"'), ('--boot-capture="' + $captureDir + '"'))
    $p = Start-Process -FilePath $exePath -ArgumentList $args -PassThru
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt $RunSeconds) { Start-Sleep -Milliseconds 200 }
    if (-not $p.HasExited) {
        $p.CloseMainWindow() | Out-Null
        if (-not $p.WaitForExit(15000)) { $p.Kill() }
    }
    $sw.Stop()
    Write-Host "=== ${label}: exited after $([math]::Round($sw.Elapsed.TotalSeconds,2))s, profile=$profileRoot"
    if (Test-Path -LiteralPath $logFile) {
        Select-String -Path $logFile -Pattern '\[boot\]|\[warmup\]|ERROR' | ForEach-Object { Write-Host ('    ' + $_.Line) }
    } else {
        Write-Host '    (no log file)'
    }
    Get-ChildItem -LiteralPath $captureDir -Filter *.png -ErrorAction SilentlyContinue |
        Sort-Object Name | ForEach-Object { Write-Host "    capture $($_.Name) $([math]::Round($_.Length/1024))KiB" }
    return $profileRoot
}

$coldDir = Join-Path $out 'cold'
$warmDir = Join-Path $out 'warm'
$coldProfile = Invoke-Launch 'cold-start' $coldDir
$warmProfile = Invoke-Launch 'warm-start' $warmDir

$realSaveAfter = if (Test-Path -LiteralPath $realSave) { (Get-Item -LiteralPath $realSave).LastWriteTimeUtc } else { $null }
"real_save_untouched=$($realSaveBefore -eq $realSaveAfter)"
"isolated_profiles_created=$((Test-Path -LiteralPath $coldProfile) -and (Test-Path -LiteralPath $warmProfile))"
