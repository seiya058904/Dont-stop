# B8 minimal affected regression set.
#
# The brief forbids re-running the whole B批 long-test suite when this round did not touch fog,
# hazard implementation, boss implementation, save or spawn geometry. It did touch:
#   * Hero's damage entry point (an added observation signal and two optional parameters), and
#     the nine player-damage call sites that now state their mechanism - so the damage pipeline
#     suites and the hazard suite are in scope;
#   * the Normal 21-29 encounter dials - so the density audit and the spawn-legality audit are
#     in scope, the latter because ring_min is exactly the arrival ring it samples.
# It did NOT touch fog, boss behaviour, saves, progression, or the spawn-geometry code, so
# B4Fog / B5Bosses / B6Progression / M10Bosses are deliberately NOT re-run here. B5Bosses and
# M10Bosses are run by the native CI `pressure` job on every push anyway.
$ErrorActionPreference = 'Continue'
$runner = Join-Path $PSScriptRoot 'b8-run.ps1'

Write-Output '=== 1. the frozen instrument contract ==='
& $runner -Scene B8Contracts -Frames 3000 -LogName b8-reg-contracts

Write-Output '=== 2. damage pipeline after the Hero.onHit change ==='
& $runner -Scene M8Contracts -Frames 20000 -LogName b8-reg-m8contracts
& $runner -Scene M6Contracts -Frames 20000 -LogName b8-reg-m6contracts
& $runner -Scene M4Talents -Frames 20000 -LogName b8-reg-m4talents
& $runner -Scene M10Growth -Frames 20000 -LogName b8-reg-m10growth

Write-Output '=== 3. hazard damage path after the mechanism tag was threaded through it ==='
& $runner -Scene B3Hazards -Frames 60000 -LogName b8-reg-b3hazards

Write-Output '=== 4. the exact gate the native CI pressure job runs on the changed stage ==='
& $runner -Scene M10Density -CaseArgs @('stages=22,31') -Frames 40000 -LogName b8-reg-density-22-driving
& $runner -Scene M10Density -CaseArgs @('probe', 'stages=22,31') -Frames 40000 -LogName b8-reg-density-22-probe

Write-Output '=== 5. spawn legality at the new arrival ring ==='
& $runner -Scene R3SpawnAudit -Frames 240000 -LogName b8-reg-spawn-audit

Write-Output 'B8 REGRESSION DONE'
