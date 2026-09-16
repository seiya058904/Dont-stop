# B批 confirmation run: re-measures everything that changed after the R8 seal fix, with the
# final audit bounds. Kept separate from tools/b-final.ps1 so a re-run cannot overwrite the
# already-committed evidence for the scenes that did not change.
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot | Split-Path -Parent
$godot = 'D:\temp\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godot)) { $godot = 'D:\xia zai\AI project\8.30 Backup game\archive\workspace-support\_tools\godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe' }
$out = Join-Path $env:TEMP 'dontstop-bconfirm'
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Run-Case {
    param([string]$name, [string]$scene, [string[]]$caseArgs, [int]$frames, [switch]$render)
    $log = Join-Path $out "$name.log"
    $cmd = @()
    if ($render) { $cmd += @('--rendering-method', 'gl_compatibility', '--position', '-10000,-10000', '--resolution', '1366x768', '--minimized') }
    else { $cmd += '--headless' }
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

Run-Case 'spawn-audit' 'R3SpawnAudit' @() 200000
Run-Case 'density-typical-probe' 'M10Density' @('typical', 'probe', 'stages=7,13,17,22,26,29') 40000
Run-Case 'density-typical-drive' 'M10Density' @('typical', 'stages=22,26,29') 40000
Run-Case 'density-strong' 'M10Density' @('stages=22,26,29,31,35,39') 40000
Run-Case 'density-strong-probe' 'M10Density' @('probe', 'stages=22,26,29,31,35,39') 40000
Run-Case 'bosses-authored-high' 'M10Bosses' @('high') 60000
Run-Case 'bosses-authored-full' 'M10Bosses' @('full') 60000
Run-Case 'bosses-phase-contract' 'B5Bosses' @() 120000
Write-Output 'BCONFIRM DONE'
