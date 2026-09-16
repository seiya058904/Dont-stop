# Core native regression gate, run in place (no snapshot copy) for fast local iteration.
# The scenario list mirrors tools/verify-m11.py's `core` cases, which is the accepted gate.
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot | Split-Path -Parent
$godot = 'D:\temp\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godot)) { $godot = 'D:\xia zai\AI project\8.30 Backup game\archive\workspace-support\_tools\godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe' }
$tag = if ($env:DONTSTOP_CORE_TAG) { $env:DONTSTOP_CORE_TAG } else { 'branch' }
$outDir = Join-Path $env:TEMP "dontstop-core-$tag"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$cases = @(
    @('BaselineRegression', @()),
    @('M3Weapons', @()), @('M3Energy', @()), @('M3Special', @()),
    @('M4ThermalClock', @()), @('M4Talents', @()),
    @('M6Cross', @()), @('M6BossStops', @()), @('M6Contracts', @()),
    @('R1RecoveryUI', @()), @('R1LegacyRestore', @()),
    @('M8Mechanics', @()), @('M8Contracts', @('--r1')), @('M8UI', @()), @('M8Supply', @()),
    @('M8R1Telegraphs', @()),
    @('M7ExitWallet', @('camp')), @('M7ExitWallet', @('menu')), @('M7ExitWallet', @('combat')),
    @('M7ExitWallet', @('restore')), @('M7ExitWallet', @('window')),
    @('M7MainExit', @()),
    @('M10Growth', @()), @('M10RewardAudit', @()), @('M10RewardMatrix', @()),
    @('M10Interaction', @()), @('M10Ultimate', @()), @('M10Barrage', @()),
    @('M10Bosses', @('high')), @('M10Bosses', @('full')),
    @('B3Hazards', @()), @('B4Fog', @()), @('B6Progression', @()),
    @('B6Progression', @('--hell-unlock')),
    @('M10Density', @('stages=22,31')), @('M10Density', @('stages=22,31','probe'))
)

$rows = @()
foreach ($case in $cases) {
    $scene = $case[0]
    $args = $case[1]
    $tag = if ($args.Count -gt 0) { "$scene-$($args -join '-')" } else { $scene }
    $log = Join-Path $outDir "$tag.log"
    $cmdArgs = @('--headless', '--path', $root, '--quit-after', '40000', "res://tests/$scene.tscn")
    if ($args.Count -gt 0) { $cmdArgs += '--'; $cmdArgs += $args }
    & $godot @cmdArgs *> $log
    $text = Get-Content -LiteralPath $log -Raw
    $pass = ([regex]::Matches($text, '(?m)^PASS ')).Count
    $fail = ([regex]::Matches($text, '(?m)^FAIL ')).Count
    $scriptErrors = ([regex]::Matches($text, '(?m)^SCRIPT ERROR')).Count
    $rows += [pscustomobject]@{ scene = $tag; pass = $pass; fail = $fail; script_errors = $scriptErrors }
    Write-Output ("{0,-28} pass={1,-4} fail={2,-3} script_errors={3}" -f $tag, $pass, $fail, $scriptErrors)
}
$rows | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outDir 'summary.json')
$totalFail = ($rows | Measure-Object -Property fail -Sum).Sum
$totalErr = ($rows | Measure-Object -Property script_errors -Sum).Sum
$zeroCheck = ($rows | Where-Object { $_.pass -eq 0 }).Count
Write-Output "CORE TOTAL fail=$totalFail script_errors=$totalErr scenes_with_no_checks=$zeroCheck"
