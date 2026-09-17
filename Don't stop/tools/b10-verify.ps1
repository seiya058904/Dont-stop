# B10 final verification: the threat audit's "after" numbers plus the affected regression set.
#
# B10 changed the camp panel (a new entry and a new selector), the read-only probe channel, and
# the two enemy scripts that carry every special attack. So the affected surface is:
#   * the new contracts (B10Playtest) and the audit itself (B10Threat);
#   * the B9 driver contracts (B10Threat inherits M8Runtime, and the probe's rect reporting changed);
#   * the damage-probe contracts (B8Contracts), because the probe's read-only channel changed;
#   * the enemy behaviour contracts (M8Contracts) - DemoEnemy and TacticalEnemy are the whole
#     special-attack surface;
#   * the boss contracts (M10Bosses), because bosses reuse _begin()/zone(), so they inherit the
#     bounded tracking lock - this is the one that would catch a boss regression;
#   * the density gate the native CI pressure job runs (M10Density stages=22,31);
#   * spawn legality (R3SpawnAudit).
#
# B3Hazards / B4Fog are NOT re-run here: no hazard or fog code changed. They run in native CI.
$ErrorActionPreference = 'Continue'
$runner = Join-Path $PSScriptRoot 'b8-run.ps1'
$b10 = Join-Path $PSScriptRoot 'b10-run.ps1'

Write-Output '=== 1. the threat audit, AFTER (all specials, 3 trials each) ==='
& $b10 -Scene B10Threat -Args 'trials=3,tag=final,stage=24' -Frames 200000 -LogName b10-threat-final

Write-Output '=== 2. Hell playtest access contracts ==='
& $b10 -Scene B10Playtest -Frames 60000 -LogName b10-playtest

Write-Output '=== 3. B9 driver contracts (B10Threat inherits this base) ==='
& $runner -Scene B9Driver -Frames 8000 -LogName b10-b9driver

Write-Output '=== 4. damage-probe contracts (the read-only probe channel changed) ==='
& $runner -Scene B8Contracts -Frames 3000 -LogName b10-b8contracts

Write-Output '=== 5. enemy behaviour contracts (both enemy scripts changed) ==='
& $runner -Scene M8Contracts -Frames 20000 -LogName b10-m8contracts

Write-Output '=== 6. boss contracts: bosses reuse _begin()/zone(), so they inherit the new lock ==='
& $runner -Scene M10Bosses -CaseArgs @('full') -Frames 30000 -LogName b10-m10bosses

Write-Output '=== 7. the gate the native CI pressure job runs ==='
& $runner -Scene M10Density -CaseArgs @('stages=22,31') -Frames 40000 -LogName b10-density
& $runner -Scene M10Density -CaseArgs @('probe','stages=22,31') -Frames 40000 -LogName b10-density-probe

Write-Output '=== 8. spawn legality ==='
& $runner -Scene R3SpawnAudit -Frames 240000 -LogName b10-spawn

Write-Output 'B10 VERIFY DONE'
