# B8 Normal late-game batch.
#
# One Godot process PER STAGE, five seeds inside it, sequentially. A process per stage and not
# one process for all fifteen runs because the per-run configuration has to be identical: the
# build is installed once at boot (RewardServer.addReward increments a stackable count, so
# re-adding it per run would silently change the build between run 1 and run 5), and the level
# is pinned per run so the eight samples of a stage are the same build.
#
# Every launch goes through the same argv-array runner; see tools/b8-run.ps1 for why.
#
# Usage:
#   tools/b8-batch.ps1 -Tag pre  -Levels '22:3,26:5,29:6'
#   tools/b8-batch.ps1 -Tag post -Levels '22:3,26:5,29:6'
param(
    [string]$Tag = 'pre',
    [Parameter(Mandatory = $true)][string]$Levels,
    [string]$Seeds = '9101,9102,9103,9104,9105',
    # B9 runs the identical batch through the B9 measurement fixture, which is the same fixture
    # with a different driver. Default unchanged so every B8 invocation still reproduces B8.
    [string]$Scene = 'B8Normal'
)
$ErrorActionPreference = 'Continue'
$runner = Join-Path $PSScriptRoot 'b8-run.ps1'

foreach ($entry in $Levels.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries)) {
    $parts = $entry.Split(':')
    $stage = $parts[0].Trim()
    $pin = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '0' }
    $caseArgs = @("stage=$stage", 'mode=batch', "seeds=$Seeds", "pin_level=$pin", "tag=$Tag")
    Write-Output ("=== scene {0} stage {1} pin {2} seeds {3} ===" -f $Scene, $stage, $pin, $Seeds)
    & $runner -Scene $Scene -CaseArgs $caseArgs -Frames 300000 -LogName "b8-$Tag-s$stage"
    Write-Output ("--- stage {0} exit {1} ---" -f $stage, $LASTEXITCODE)
}
Write-Output 'B8 BATCH DONE'
