# B8 generic scene runner.
#
# Every launch goes through an explicit PowerShell argument ARRAY and the resolved argv is
# printed before the process starts. There is no string concatenation and no heredoc anywhere
# in this file, because the B批 batch lost ~21 minutes to an inline heredoc that split
# "--headless" into "- - h e a d l e s s" and left two Godot processes idling.
#
# Usage:
#   tools/b8-run.ps1 -Scene B8Contracts
#   tools/b8-run.ps1 -Scene B8Normal -CaseArgs @('stage=22','mode=batch','seeds=9101,9102','pin_level=3')
#   tools/b8-run.ps1 -Scene B4Fog -Render
param(
    [Parameter(Mandatory = $true)][string]$Scene,
    [string[]]$CaseArgs = @(),
    [int]$Frames = 4000,
    [switch]$Render,
    [string]$LogName = ''
)
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot | Split-Path -Parent
$godot = 'D:\temp\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godot)) {
    $godot = Join-Path (Split-Path -Parent $PSScriptRoot) 'archive\workspace-support\_tools\godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $godot)) { Write-Error "Godot not found"; exit 2 }

$out = Join-Path $env:TEMP 'dontstop-b8'
New-Item -ItemType Directory -Force -Path $out | Out-Null
if ([string]::IsNullOrEmpty($LogName)) { $LogName = $Scene }
$log = Join-Path $out "$LogName.log"

$argv = @()
if ($Render) {
    $argv += @('--rendering-method', 'gl_compatibility', '--position', '-10000,-10000', '--resolution', '1366x768', '--minimized')
} else {
    $argv += '--headless'
}
$argv += @('--path', $root, '--quit-after', "$Frames", "res://tests/$Scene.tscn")
if ($CaseArgs.Count -gt 0) { $argv += '--'; $argv += $CaseArgs }

Write-Output ("ARGV: {0} {1}" -f $godot, ($argv -join ' '))
$started = Get-Date
& $godot @argv *> $log
$elapsed = ((Get-Date) - $started).TotalSeconds

$text = Get-Content -LiteralPath $log -Raw
if ($null -eq $text) { $text = '' }
$pass = ([regex]::Matches($text, '(?m)^PASS ')).Count
$fail = ([regex]::Matches($text, '(?m)^FAIL ')).Count
$err = ([regex]::Matches($text, '(?m)^SCRIPT ERROR')).Count
$parse = ([regex]::Matches($text, '(?m)^ERROR|Parse Error')).Count
Write-Output ("RESULT {0} seconds={1:N1} pass={2} fail={3} script_errors={4} other_errors={5}" -f $Scene, $elapsed, $pass, $fail, $err, $parse)
Write-Output ("LOG    {0}" -f $log)
Select-String -LiteralPath $log -Pattern '^FAIL |^SCRIPT ERROR|Parse Error|^ERROR' | Select-Object -First 12 | ForEach-Object { '   ' + $_.Line }
if ($fail -gt 0 -or $err -gt 0) { exit 1 }
exit 0
