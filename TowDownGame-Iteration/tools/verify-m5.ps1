$ErrorActionPreference = 'Continue'
$iterationRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $iterationRoot
$godotPath = Join-Path $workspaceRoot 'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe'
$evidenceRoot = Join-Path $iterationRoot 'docs/iteration/evidence/m5'
$failed = $false
$results = @()
foreach ($case in @('M5Enemies','M5World','M5Mechanics')) {
    $log = Join-Path $evidenceRoot ($case + '.txt')
    & $godotPath --headless --max-fps 160 --path $iterationRoot --quit-after 30000 ("res://tests/$case.tscn") *> $log
    $code = $LASTEXITCODE
    $out = Get-Content -LiteralPath $log -Raw -Encoding UTF8
    $summary = [regex]::Match($out, 'SUMMARY checks=(\d+) failures=(\d+)')
    $known = $out -match '2 ObjectDB instances were leaked at exit' -and $out -match '1 resources still in use at exit'
    $otherErrors = @($out -split "`r?`n" | Where-Object { $_ -match 'ERROR:' -and $_ -notmatch '^ERROR: 1 resources still in use at exit \(run with --verbose for details\)\.$' })
    $passed = $code -eq 0 -and $summary.Success -and $summary.Groups[2].Value -eq '0' -and $out -notmatch 'SCRIPT ERROR|FAIL ' -and $otherErrors.Count -eq 0
    if ($out -match 'ERROR:|leaked at exit' -and -not $known) { $passed = $false }
    if (-not $passed) { $failed = $true }
    $item = [ordered]@{case=$case; checks=$summary.Groups[1].Value; passed=$passed; known_exit_diagnostic=$known; clean_exit=($out -notmatch 'ERROR:|leaked at exit'); code=$code}
    $results += $item
    Write-Output ($item | ConvertTo-Json -Compress)
}
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidenceRoot 'final-index.json') -Encoding UTF8
if ($failed) { exit 1 }
# Long run is separate: M5LongRun.tscn, >=1205 real seconds and >=24 camp returns.
