# B9 Normal batch: the same five seeds, the same pinned builds, the same fixture - but through
# tests/B9Normal.tscn, i.e. on the driver whose safe-movement core is shared with the Boss path.
#
# It delegates to tools/b8-batch.ps1 with -Scene B9Normal so the batch mechanics (one Godot
# process per stage, five sequential seeds inside it, argv-array launches) are literally the
# same code that produced the B8 numbers. Nothing about how a sample is taken changes here.
#
# Usage:
#   tools/b9-batch.ps1 -Tag newdriver
#   tools/b9-batch.ps1 -Tag smoke -Levels '22:7' -Seeds '9101'
param(
    [string]$Tag = 'newdriver',
    [string]$Levels = '22:7,26:7,29:8',
    [string]$Seeds = '9101,9102,9103,9104,9105'
)
$ErrorActionPreference = 'Continue'
& (Join-Path $PSScriptRoot 'b8-batch.ps1') -Tag $Tag -Levels $Levels -Seeds $Seeds -Scene 'B9Normal'
exit $LASTEXITCODE
