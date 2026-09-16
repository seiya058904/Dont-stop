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
    [string]$Seeds = '9101,9102,9103,9104,9105'
)
$ErrorActionPreference = 'Continue'
$runner = Join-Path $PSScriptRoot 'b8-run.ps1'

foreach ($entry in $Levels.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries)) {
    $parts = $entry.Split(':')
    $stage = $parts[0].Trim()
    $pin = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '0' }
    $caseArgs = @("stage=$stage", 'mode=batch', "seeds=$Seeds", "pin_level=$pin", "tag=$Tag")
    Write-Output ("=== stage {0} pin {1} seeds {2} ===" -f $stage, $pin, $Seeds)
    & $runner -Scene B8Normal -CaseArgs $caseArgs -Frames 300000 -LogName "b8-$Tag-s$stage"
    Write-Output ("--- stage {0} exit {1} ---" -f $stage, $LASTEXITCODE)
}
Write-Output 'B8 BATCH DONE'
