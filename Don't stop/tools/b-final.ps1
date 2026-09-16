# B批 final verification and measurement batch.
#
# Sequential on purpose: concurrent Godot processes would distort the frame-time readings and
# the luminance profiles. Every case is a real production-path run; none of them injects
# damage, calls perform_attack(), or diffs screenshots to decide a pass.
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot | Split-Path -Parent
$godot = 'D:\temp\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godot)) { $godot = 'D:\xia zai\AI project\8.30 Backup game\archive\workspace-support\_tools\godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe' }
$out = Join-Path $env:TEMP 'dontstop-bfinal'
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Run-Case {
    param([string]$name, [string]$scene, [string[]]$caseArgs, [int]$frames, [switch]$render)
    $log = Join-Path $out "$name.log"
    $cmd = @()
    if ($render) {
        $cmd += @('--rendering-method', 'gl_compatibility', '--position', '-10000,-10000', '--resolution', '1366x768', '--minimized')
    } else {
        $cmd += '--headless'
    }
    $cmd += @('--path', $root, '--quit-after', "$frames", "res://tests/$scene.tscn")
    if ($caseArgs.Count -gt 0) { $cmd += '--'; $cmd += $caseArgs }
    & $godot @cmd *> $log
    $text = Get-Content -LiteralPath $log -Raw
    $pass = ([regex]::Matches($text, '(?m)^PASS ')).Count
    $fail = ([regex]::Matches($text, '(?m)^FAIL ')).Count
    $err = ([regex]::Matches($text, '(?m)^SCRIPT ERROR')).Count
    Write-Output ("{0,-32} pass={1,-5} fail={2,-4} script_errors={3}" -f $name, $pass, $fail, $err)
    Select-String -LiteralPath $log -Pattern '^FAIL |^SCRIPT ERROR' | Select-Object -First 10 | ForEach-Object { "     " + $_.Line }
}

# Spawn / collision legality, now including per-region reachability.
Run-Case 'spawn-audit' 'R3SpawnAudit' @() 200000
# Density, apples to apples with the B0 baseline numbers.
Run-Case 'density-typical-probe' 'M10Density' @('typical', 'probe', 'stages=7,13,17,22,26,29') 40000
Run-Case 'density-typical-drive' 'M10Density' @('typical', 'stages=7,13,17,22,26,29') 40000
Run-Case 'density-strong' 'M10Density' @('stages=22,26,29,31,35,39') 40000
Run-Case 'density-strong-probe' 'M10Density' @('probe', 'stages=22,26,29,31,35,39') 40000
# Bosses: authored difficulty TTK, then the three-phase contract for all four.
Run-Case 'bosses-authored-high' 'M10Bosses' @('high') 60000
Run-Case 'bosses-authored-full' 'M10Bosses' @('full') 60000
Run-Case 'bosses-phase-contract' 'B5Bosses' @() 90000
# Fog contract + the A/B render measurements and screenshots.
Run-Case 'fog-contract' 'B4Fog' @() 30000
Run-Case 'fog-render' 'B4Fog' @() 30000 -render
Run-Case 'visual-tour' 'BVisual' @() 50000 -render
# Hazards, progression, and the accepted core gate.
Run-Case 'hazards' 'B3Hazards' @() 30000
Run-Case 'progression' 'B6Progression' @() 30000
Run-Case 'progression-bypass' 'B6Progression' @('--hell-unlock') 30000
Run-Case 'core-baseline' 'BaselineRegression' @() 20000
Run-Case 'core-contracts' 'ContractRunner' @() 20000
Run-Case 'core-m6-contracts' 'M6Contracts' @() 20000
Run-Case 'core-m8-contracts' 'M8Contracts' @('--r1') 20000
Run-Case 'core-m8-telegraphs' 'M8R1Telegraphs' @() 20000
Run-Case 'core-m10-ultimate' 'M10Ultimate' @() 20000
Run-Case 'core-m10-barrage' 'M10Barrage' @() 20000
Write-Output 'BFINAL DONE'
