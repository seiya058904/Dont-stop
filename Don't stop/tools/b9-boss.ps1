# B9 Boss A/B regression.
#
# The brief (§5, §16) is: do not balance the Boss, but PROVE the shared-core refactor did not
# degrade the existing Boss tests. So this re-runs the B8 fairness fixture, on the exact seeds
# B8 sampled (4201,4202,4203), at the authored 8 HP pool, with the NEW driver, and writes a
# separate tag. The comparison is old (boss-fair-final-s30/s40) vs new (boss-fair-b9new-*).
#
# It uses the B8 fixture UNCHANGED - the same scene, the same build, the same fight() - because
# that is the only way the two evidence sets are comparable.
#
# Sequential, and launched from a FILE rather than an inline heredoc: the B批 batch lost ~21
# minutes to an inline heredoc that split "--headless" into "- - h e a d l e s s".
param([string]$Tag = 'b9new')
$ErrorActionPreference = 'Continue'
$runner = Join-Path $PSScriptRoot 'b8-run.ps1'

foreach ($pair in @(@(30, 'B03'), @(40, 'B04'))) {
    $stage = $pair[0]; $name = $pair[1]
    Write-Output ("=== B9 boss regression: {0} (stage {1}) x3 real authored-8HP fights ===" -f $name, $stage)
    & $runner -Scene B8BossFair -CaseArgs @("stage=$stage", 'seeds=4201,4202,4203', "tag=$Tag") -Frames 300000 -LogName "b9-boss-$stage"
    Write-Output ("--- {0} exit {1} ---" -f $name, $LASTEXITCODE)
}
Write-Output 'B9 BOSS A/B DONE'
