# B8 extension runs: the §14 sanity sweep over the untouched representative stages, and the §11
# Boss fairness sampling for B03 / B04 at the authored 8 HP pool.
#
# Sequential, and launched from a FILE rather than an inline heredoc: the B批 batch lost ~21
# minutes to an inline heredoc that split "--headless" into "- - h e a d l e s s" and left two
# Godot processes idling.
$ErrorActionPreference = 'Continue'
$runner = Join-Path $PSScriptRoot 'b8-run.ps1'
$batch = Join-Path $PSScriptRoot 'b8-batch.ps1'

Write-Output '=== §14 sanity sweep: 21 / 24 / 25 / 27 / 28, one seed each ==='
& $batch -Tag sanity -Levels '21:7,24:7,25:7,27:8,28:8' -Seeds '9101'
Write-Output ("--- sanity sweep exit {0} ---" -f $LASTEXITCODE)

Write-Output '=== §11 Boss fairness: B03 (stage 30) x3 real authored-8HP fights ==='
& $runner -Scene B8BossFair -CaseArgs @('stage=30', 'seeds=4201,4202,4203', 'tag=final') -Frames 300000 -LogName b8-boss-30
Write-Output ("--- B03 exit {0} ---" -f $LASTEXITCODE)

Write-Output '=== §11 Boss fairness: B04 (stage 40) x3 real authored-8HP fights ==='
& $runner -Scene B8BossFair -CaseArgs @('stage=40', 'seeds=4201,4202,4203', 'tag=final') -Frames 300000 -LogName b8-boss-40
Write-Output ("--- B04 exit {0} ---" -f $LASTEXITCODE)

Write-Output 'B8 EXTENSION RUNS DONE'
