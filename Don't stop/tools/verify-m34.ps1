$ErrorActionPreference = 'Continue'
$iterationRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $iterationRoot
$godotPath = Join-Path $workspaceRoot 'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godotPath)) { throw 'Workspace Godot 4.7.2 not found.' }
$evidenceRoot = Join-Path $iterationRoot 'docs/iteration/evidence/m3-m4'
$cases = @(
    @{ name = 'thermal-clock'; scene = 'M4ThermalClock'; args = @() },
    @{ name = 'weapons'; scene = 'M3Weapons'; args = @() },
    @{ name = 'energy'; scene = 'M3Energy'; args = @() },
    @{ name = 'special'; scene = 'M3Special'; args = @() },
    @{ name = 'mechanics'; scene = 'M4Mechanics'; args = @() },
    @{ name = 'ui'; scene = 'M4UI'; args = @() },
    @{ name = 'attachments'; scene = 'M4Attachments'; args = @() },
    @{ name = 'talents'; scene = 'M4Talents'; args = @() },
    @{ name = 'persistence-write'; scene = 'M4Persistence'; args = @() },
    @{ name = 'persistence-read'; scene = 'M4Persistence'; args = @('--','read') },
    @{ name = 'combinations'; scene = 'M4Combinations'; args = @() }
)
$results = @()
$failed = $false
foreach ($case in $cases) {
    $log = Join-Path $evidenceRoot ('final-' + $case.name + '.txt')
    $stderr = Join-Path $iterationRoot ('m34-' + $case.name + '-stderr.log')
    $caseArgs = $case.args
    & $godotPath --headless --max-fps 160 --path $iterationRoot --quit-after 16000 ('res://tests/' + $case.scene + '.tscn') @caseArgs 1> $log 2> $stderr
    $code = $LASTEXITCODE
    $out = Get-Content -LiteralPath $log -Raw -Encoding UTF8
    $err = Get-Content -LiteralPath $stderr -Raw -Encoding UTF8
    if ($err) { Add-Content -LiteralPath $log -Value $err -Encoding UTF8 }
    $summary = [regex]::Match($out, 'SUMMARY checks=(\d+) failures=(\d+)')
    $assertionsPassed = $summary.Success -and $summary.Groups[2].Value -eq '0' -and $code -eq 0
    $runtimeError = ($out + $err) -match 'SCRIPT ERROR|Parse Error|FAIL '
    $knownExitDiagnostic = $err -match '2 ObjectDB instances were leaked at exit' -and $err -match '1 resources still in use at exit'
    $otherErrors = (($out + $err) -split "`r?`n" | Where-Object { $_ -match 'ERROR:' -and $_ -notmatch '^ERROR: 1 resources still in use at exit \(run with --verbose for details\)\.$' })
    $unclassifiedError = @($otherErrors).Count -gt 0 -or ($err -match 'ERROR:' -and -not $knownExitDiagnostic)
    $cleanExit = -not ($err -match 'ERROR:|leaked at exit')
    $result = [ordered]@{ case = $case.name; checks = $summary.Groups[1].Value; assertions_passed = $assertionsPassed; clean_exit = $cleanExit; known_exit_diagnostic = $knownExitDiagnostic; code = $code; log = ('final-' + $case.name + '.txt') }
    $results += $result
    if (-not $assertionsPassed -or $runtimeError -or $unclassifiedError) { $failed = $true }
    Write-Output ($result | ConvertTo-Json -Compress)
}
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidenceRoot 'final-index.json') -Encoding UTF8
if ($failed) { exit 1 }
# A known exit diagnostic is recorded separately; zero here means content assertions passed.
