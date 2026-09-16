# B批 final measurement batch: the density configurations the report quotes, plus the two
# render runs that produce the visual evidence and the fog luminance numbers.
#
# Sequential on purpose: concurrent Godot processes would distort the frame-time readings and
# the luminance profiles.
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot | Split-Path -Parent
$godot = 'D:\temp\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godot)) { $godot = 'D:\xia zai\AI project\8.30 Backup game\archive\workspace-support\_tools\godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe' }
$out = Join-Path $env:TEMP 'dontstop-bmeasure2'
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
    Write-Output ("{0,-30} pass={1,-5} fail={2,-4} script_errors={3}" -f $name, $pass, $fail, $err)
    Select-String -LiteralPath $log -Pattern '^FAIL |^SCRIPT ERROR' | Select-Object -First 8 | ForEach-Object { "     " + $_.Line }
}

Run-Case 'density-typical-probe' 'M10Density' @('typical', 'probe', 'stages=7,13,17,22,26,29') 40000
Run-Case 'density-typical-drive' 'M10Density' @('typical', 'stages=7,13,17,22,26,29') 40000
Run-Case 'density-strong' 'M10Density' @('stages=22,26,29,31,35,39') 40000
Run-Case 'density-strong-probe' 'M10Density' @('probe', 'stages=22,26,29,31,35,39') 40000
Run-Case 'fog-render' 'B4Fog' @() 30000 -render
Run-Case 'visual-tour' 'BVisual' @() 50000 -render
Write-Output 'BATCH2 DONE'
