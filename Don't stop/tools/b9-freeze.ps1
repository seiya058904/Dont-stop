# B9 freeze manifest generator.
#
# The B9 instrument is frozen BEFORE any long battle runs, and verified unchanged AFTER, so a
# batch can never be quoted against a moving measurement definition.
#
# Usage:
#   tools/b9-freeze.ps1                 # write docs/iteration/evidence/b9/freeze.sha256
#   tools/b9-freeze.ps1 -Verify         # re-hash and report changed files (exit 1 if any)
param([switch]$Verify)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot | Split-Path -Parent
$manifest = Join-Path $root 'docs\iteration\evidence\b9\freeze.sha256'

# What is frozen, and why each entry is in the list:
#   the driver under test, the contracts that prove it, the measurement fixture (B9's own and the
#   B8 one it inherits), the damage probe, the launchers, every product damage entry point the
#   ledger can attribute, and the encounter configuration B8 edited - which B9 must prove is
#   byte-identical to main.
$files = @(
    'tests/M8Runtime.gd'
    'tests/B9Driver.gd'
    'tests/B9Driver.tscn'
    'tests/B9Normal.gd'
    'tests/B9Normal.tscn'
    'tests/B8Normal.gd'
    'tests/B8Normal.tscn'
    'tests/B8Probe.gd'
    'tests/B8BossFair.gd'
    'tests/B8BossFair.tscn'
    'tests/B8Contracts.gd'
    'tests/B8Contracts.tscn'
    'tools/b8-run.ps1'
    'tools/b8-batch.ps1'
    'tools/b9-batch.ps1'
    'tools/b9-boss.ps1'
    'tools/b9-regression.ps1'
    'tools/b9-summary.py'
    'tools/b9-freeze.ps1'
    'game/hero/Hero.gd'
    'game/monster/DemoEnemy.gd'
    'game/monster/TacticalEnemy.gd'
    'game/monster/EnemyShot.gd'
    'game/monster/HostileZone.gd'
    'game/monster/BossUltimate.gd'
    'game/monster/Monster 2/Monster2.gd'
    'game/map/StageHazard.gd'
    'game/map/ArenaHazardDirector.gd'
    'game/config/M5Content.gd'
    'game/config/DemoConfig.gd'
)

if ($Verify) {
    $changed = 0
    $checked = 0
    foreach ($line in Get-Content -LiteralPath $manifest) {
        if ($line.StartsWith('#') -or [string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split '\s+', 2
        $expected = $parts[0]
        $relative = $parts[1].Trim()
        $path = Join-Path $root $relative
        if (-not (Test-Path -LiteralPath $path)) { Write-Output "MISSING $relative"; $changed++; continue }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
        $checked++
        if ($actual -ne $expected) { Write-Output "CHANGED $relative"; $changed++ }
    }
    Write-Output ("B9 FREEZE frozen files verified: {0}, changed: {1}" -f $checked, $changed)
    if ($changed -gt 0) { exit 1 }
    exit 0
}

$head = (& git -C (Split-Path -Parent $root) rev-parse HEAD).Trim()
$lines = @()
$lines += '# B9 frozen measurement instrument'
$lines += '# FROZEN. The first B9 batch may change exactly ONE thing against the B8 numbers: the'
$lines += '# driver. Nothing here - not the fixture, not the probe, not a launcher, not one product'
$lines += '# damage entry point, not one encounter value - may change while the batch is running.'
$lines += '# A change invalidates the batch and requires a fresh one.'
$lines += '# Validated by tools/b8-run.ps1 -Scene B9Driver (38 checks) and -Scene B8Contracts.'
$lines += '# base_commit=' + $head
foreach ($relative in $files) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path)) { Write-Error "missing $relative"; exit 2 }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
    $lines += "$hash  $relative"
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $manifest) | Out-Null
Set-Content -LiteralPath $manifest -Value $lines -Encoding utf8
Write-Output ("B9 FREEZE wrote {0} entries to {1} (base_commit={2})" -f $files.Count, $manifest, $head)
