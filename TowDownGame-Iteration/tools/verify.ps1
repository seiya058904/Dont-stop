$ErrorActionPreference = 'Stop'
$iterationRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $iterationRoot
$godotPath = Join-Path $workspaceRoot 'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godotPath)) { throw 'Expected workspace portable Godot not found.' }
$cases = @(
    @('--editor', '--import', '--quit'),
    @('tests/BaselineRegression.tscn'),
    @('tests/ContractRunner.tscn'),
    @('tests/SaveRunner.tscn', '--', 'write'),
    @('tests/SaveRunner.tscn', '--', 'read')
)
$failed = $false
for ($index = 0; $index -lt $cases.Count; $index++) {
    $log = Join-Path $iterationRoot "verify-$index.log"
    $caseArgs = $cases[$index]
    & $godotPath --headless --path $iterationRoot --quit-after 6000 @caseArgs *> $log
    $code = $LASTEXITCODE
    $errors = Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|ERROR:|FAIL |leaked at exit'
    if ($code -ne 0 -or $errors) {
        $failed = $true
        Write-Output "FAIL case $index (exit $code): $log"
        $errors | ForEach-Object { Write-Output $_.Line }
    } else { Write-Output "PASS case $index`: $log" }
}
if ($failed) { exit 1 }
