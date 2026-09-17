# B9 minimal affected regression set.
#
# B9 changed the movement driver and nothing else. It did NOT touch the damage pipeline, the
# hazard implementation, fog, boss behaviour, saves, progression or spawn geometry - the product
# diff against the baseline commit is empty apart from test files. So the affected surface is:
#   * the DRIVER, which every driving suite uses: M10Density drives stage 22 and 31 in the native
#     CI pressure job and asserts row.clear and movement > 1000, so it is the strongest external
#     check that the new core did not break driving;
#   * the instrument itself: B9Driver (the new contracts) and B8Contracts (the probe contracts,
#     since B8Probe gained the dodge-telemetry merge);
#   * the spawn geometry the driver walks through: R3SpawnAudit.
#
# The damage-pipeline suites (M8Contracts / M6Contracts / M4Talents / M10Growth) and the hazard
# suite (B3Hazards) are re-run as well, because they are cheap and they are the suites that
# M8Runtime inherits from - a broken base class would show up there first.
#
# B4Fog / B5Bosses / B6Progression / M10Bosses are deliberately NOT re-run here (fog, boss
# implementation and progression are untouched and B5Bosses/M10Bosses run in the native CI
# `pressure` job on every push). Boss behaviour is covered instead by the targeted B03/B04 A/B
# in tools/b9-boss.ps1.
$ErrorActionPreference = 'Continue'
$runner = Join-Path $PSScriptRoot 'b8-run.ps1'

Write-Output '=== 1. the new driver contracts ==='
& $runner -Scene B9Driver -Frames 8000 -LogName b9-reg-driver

Write-Output '=== 2. the damage-probe contracts ==='
& $runner -Scene B8Contracts -Frames 3000 -LogName b9-reg-b8contracts

Write-Output '=== 3. the base-class suites the driver inherits from ==='
& $runner -Scene M8Contracts -Frames 20000 -LogName b9-reg-m8contracts
& $runner -Scene M6Contracts -Frames 20000 -LogName b9-reg-m6contracts
& $runner -Scene M4Talents -Frames 20000 -LogName b9-reg-m4talents
& $runner -Scene M10Growth -Frames 20000 -LogName b9-reg-m10growth

Write-Output '=== 4. hazard damage path ==='
& $runner -Scene B3Hazards -Frames 60000 -LogName b9-reg-b3hazards

Write-Output '=== 5. the exact gate the native CI pressure job runs on a driven stage ==='
& $runner -Scene M10Density -CaseArgs @('stages=22,31') -Frames 40000 -LogName b9-reg-density-driving
& $runner -Scene M10Density -CaseArgs @('probe', 'stages=22,31') -Frames 40000 -LogName b9-reg-density-probe

Write-Output '=== 6. spawn legality along the route the driver walks ==='
& $runner -Scene R3SpawnAudit -Frames 240000 -LogName b9-reg-spawn-audit

Write-Output 'B9 REGRESSION DONE'
