# B9 freeze drift audit.
#
# Compares the manifest written BEFORE the measurement batches against the manifest written
# AFTER them, and names every frozen file whose bytes moved. This is the evidence for the claim
# "no measurement definition changed while the batch was running".
param(
    [string]$Pre = "$env:TEMP\b9-freeze-prebatch.sha256",
    [string]$Post = "docs\iteration\evidence\b9\freeze.sha256"
)
$root = $PSScriptRoot | Split-Path -Parent
$prePath = if ([System.IO.Path]::IsPathRooted($Pre)) { $Pre } else { Join-Path $root $Pre }
$postPath = if ([System.IO.Path]::IsPathRooted($Post)) { $Post } else { Join-Path $root $Post }

$preMap = @{}
foreach ($line in Get-Content -LiteralPath $prePath) {
    if ($line.StartsWith('#') -or [string]::IsNullOrWhiteSpace($line)) { continue }
    $split = $line -split '\s+', 2
    $preMap[$split[1].Trim()] = $split[0]
}
$postMap = @{}
foreach ($line in Get-Content -LiteralPath $postPath) {
    if ($line.StartsWith('#') -or [string]::IsNullOrWhiteSpace($line)) { continue }
    $split = $line -split '\s+', 2
    $postMap[$split[1].Trim()] = $split[0]
}

Write-Output ("pre-batch entries {0}, post-batch entries {1}" -f $preMap.Count, $postMap.Count)
$same = 0
$changed = @()
foreach ($key in ($preMap.Keys | Sort-Object)) {
    if (-not $postMap.ContainsKey($key)) { $changed += "REMOVED  $key"; continue }
    if ($preMap[$key] -ne $postMap[$key]) { $changed += "CHANGED  $key" } else { $same++ }
}
Write-Output ("byte-identical across the whole measurement campaign: {0} of {1}" -f $same, $preMap.Count)
if ($changed.Count -eq 0) {
    Write-Output 'no frozen file moved'
} else {
    Write-Output 'files that moved after the manifests were first written:'
    $changed | ForEach-Object { Write-Output ("  " + $_) }
}
