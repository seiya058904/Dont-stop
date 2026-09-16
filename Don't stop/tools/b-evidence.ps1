# Assemble the B批 evidence files from the measurement run logs.
#
# The audit scenes print one JSON object per measured row, and every gate scene prints its
# PASS/FAIL lines. Rather than re-running anything, this collects those printed rows into the
# committed evidence files, so what the report quotes is exactly what the runs printed.
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot | Split-Path -Parent
$src = Join-Path $env:TEMP 'dontstop-bfinal'
$dest = Join-Path $root 'docs/iteration/evidence/b'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

function Row-Lines([string]$file, [string]$prefix) {
    if (-not (Test-Path -LiteralPath $file)) { return @() }
    $out = @()
    foreach ($line in Get-Content -LiteralPath $file) {
        if ($line.StartsWith($prefix)) { $out += $line.Substring($prefix.Length) }
    }
    return $out
}

# --- density: one array per configuration, keyed by the run label
$density = @()
foreach ($name in @('density-typical-probe', 'density-typical-drive', 'density-strong', 'density-strong-probe')) {
    foreach ($row in (Row-Lines (Join-Path $src "$name.log") 'M10 DENSITY ')) {
        $obj = $row | ConvertFrom-Json
        $obj | Add-Member -NotePropertyName run -NotePropertyValue $name -Force
        $density += $obj
    }
}
$density | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dest 'density.json')

# --- bosses: authored difficulty rows from the gate scene
$bosses = @()
foreach ($name in @('bosses-authored-high', 'bosses-authored-full')) {
    foreach ($row in (Row-Lines (Join-Path $src "$name.log") 'M10 BOSS ')) {
        $obj = $row | ConvertFrom-Json
        $obj | Add-Member -NotePropertyName run -NotePropertyValue $name -Force
        $bosses += $obj
    }
}
$bosses | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dest 'bosses-authored.json')

# --- per-scene gate summaries, so the report can cite exact check counts
$summary = @()
foreach ($file in (Get-ChildItem -LiteralPath $src -Filter '*.log' -ErrorAction SilentlyContinue)) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $summary += [pscustomobject]@{
        run = $file.BaseName
        pass = ([regex]::Matches($text, '(?m)^PASS ')).Count
        fail = ([regex]::Matches($text, '(?m)^FAIL ')).Count
        script_errors = ([regex]::Matches($text, '(?m)^SCRIPT ERROR')).Count
        failed_checks = (Select-String -LiteralPath $file.FullName -Pattern '^FAIL ' | ForEach-Object { $_.Line })
    }
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dest 'gate-summary.json')

# --- raw measurement lines that are not JSON rows
$raw = Join-Path $dest 'raw-measurements.txt'
Set-Content -LiteralPath $raw -Value "# B批 raw measurement lines, verbatim from the run logs"
foreach ($file in (Get-ChildItem -LiteralPath $src -Filter '*.log' -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $lines = Select-String -LiteralPath $file.FullName -Pattern '^(B4 |BVISUAL |R3_SPAWN_AUDIT|M10_DENSITY_CHECKS|B5 BOSSES|B6 |M10 BOSSES)'
    if ($lines) {
        Add-Content -LiteralPath $raw -Value ""
        Add-Content -LiteralPath $raw -Value "## $($file.BaseName)"
        foreach ($line in $lines) { Add-Content -LiteralPath $raw -Value $line.Line }
    }
}
Write-Output "assembled: $dest"
Get-ChildItem -LiteralPath $dest | Select-Object Name, Length
