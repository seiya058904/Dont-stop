# B批 measurement batch: one run of every audit the final report quotes a number from.
# Sequential on purpose - concurrent Godot processes would distort the frame-time readings.
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot | Split-Path -Parent
$godot = 'D:\temp\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godot)) { $godot = 'D:\xia zai\AI project\8.30 Backup game\archive\workspace-support\_tools\godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe' }
$out = Join-Path $env:TEMP 'dontstop-bmeasure'
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Run-Case([string]$name, [string]$scene, [string[]]$args, [int]$frames, [switch]$render) {
    $log = Join-Path $out "$name.log"
    $cmd = @()
    if ($render) {
        $cmd += @('--rendering-method', 'gl_compatibility', '--position', '-10000,-10000', '--resolution', '1366x768', '--minimized')
    } else {
        $cmd += '--headless'
    }
    $cmd += @('--path', $root, '--quit-after', "$frames", "res://tests/$scene.tscn")
    if ($args.Count -gt 0) { $cmd += '--'; $cmd += $args }
    & $godot @cmd *> $log
    $text = Get-Content -LiteralPath $log -Raw
    $pass = ([regex]::Matches($text, '(?m)^PASS ')).Count
    $fail = ([regex]::Matches($text, '(?m)^FAIL ')).Count
    $err = ([regex]::Matches($text, '(?m)^SCRIPT ERROR')).Count
    Write-Output ("{0,-34} pass={1,-5} fail={2,-4} script_errors={3}" -f $name, $pass, $fail, $err)
    if ($fail -gt 0 -or $err -gt 0) {
        Select-String -LiteralPath $log -Pattern '^FAIL |^SCRIPT ERROR' | Select-Object -First 8 | ForEach-Object { "     " + $_.Line }
    }
}

# Difficulty curve, apples to apples with the B0 baseline numbers (typical build, probe).
Run-Case 'density-typical-probe' 'M10Density' @('typical', 'probe', 'stages=7,13,17,22,26,29') 60000
# Same build, engaged: what a player actually faces.
Run-Case 'density-typical-drive' 'M10Density' @('typical', 'stages=7,13,17,22,26,29') 60000
# Strong build, late normal + Hell coverage required by the brief.
Run-Case 'density-strong' 'M10Density' @('stages=22,26,29,31,35,39') 60000
Run-Case 'density-strong-probe' 'M10Density' @('probe', 'stages=22,26,29,31,35,39') 60000
# Spawn legality across every region, boss and the Hell roster.
Run-Case 'spawn-audit' 'R3SpawnAudit' @() 200000
# Boss phases (reported) at authored difficulty.
Run-Case 'bosses-authored-high' 'M10Bosses' @('high') 60000
Run-Case 'bosses-authored-full' 'M10Bosses' @('full') 60000
# Visual evidence: the renderer Web uses, so the fog numbers are measured where they ship.
Run-Case 'fog-render' 'B4Fog' @() 40000 -render
Run-Case 'visual-tour' 'BVisual' @() 60000 -render

Write-Output "BATCH DONE"
