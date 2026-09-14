param([switch]$GpuTimeline)
$ErrorActionPreference = 'Stop'
$iterationRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $iterationRoot
$godotPath = Join-Path $workspaceRoot 'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godotPath)) { throw 'Workspace portable Godot not found.' }
$cases = @(
    @('tests/R1Regression.tscn'),
    @('tests/R1Persistence.tscn'),
    @('tests/R1Flow.tscn'),
    @('tests/R1RecoveryUI.tscn'),
    @('tests/R1LegacyRestore.tscn'),
    @('tests/R1SaveMatrix.tscn', '--', 'write')
)
foreach ($cycle in 1..3) {
    foreach ($variation in 0..2) {
        foreach ($order in @('forward', 'reverse')) {
            $cases += ,@('tests/R1SaveMatrix.tscn', '--', 'read', "$variation", $order)
        }
    }
}
foreach ($variant in @('normal','trial')) {
    $cases += ,@('tests/R1DepartureSave.tscn', '--', 'write', $variant)
    $cases += ,@('tests/R1DepartureSave.tscn', '--', 'read', $variant)
}
$failed = $false
for ($index = 0; $index -lt $cases.Count; $index++) {
    $log = Join-Path $iterationRoot "r1-verify-$index.log"
    $caseArgs = $cases[$index]
    & $godotPath --headless --path $iterationRoot --quit-after 6000 @caseArgs *> $log
    $code = $LASTEXITCODE
    $errors = Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|ERROR:|FAIL |leaked at exit'
    $summary = Select-String -LiteralPath $log -Pattern 'failures=0'
    if ($code -ne 0 -or $errors -or -not $summary) {
        $failed = $true
        Write-Output "FAIL case $index (exit $code): $log"
        $errors | ForEach-Object { Write-Output $_.Line }
    } else { Write-Output "PASS case $index`: $log" }
}
if ($GpuTimeline) {
    # This case needs a real window: headless cannot capture the mouse.
    $log = Join-Path $iterationRoot 'r1-verify-timeline.log'
    & $godotPath --path $iterationRoot --resolution 1536x864 tests/R1Timeline.tscn *> $log
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|FAIL ') -or -not (Select-String -LiteralPath $log -Pattern 'R1 TIMELINE checks=30 failures=0')) { $failed = $true }
    # Renderer shutdown diagnostics are retained for separate review.
    Select-String -LiteralPath $log -Pattern 'ERROR:|leaked|R1 TIMELINE' | ForEach-Object { Write-Output $_.Line }
}
if ($failed) { exit 1 }
