# B10 local Web export.
#
# The same two commands .github/workflows/deploy-pages.yml runs in its `build` job, so the
# browser evidence is taken against a build produced the same way the shipped one is. Every
# launch goes through an explicit argument ARRAY and the resolved argv is printed first: the
# B批 batch lost ~21 minutes to an inline heredoc that split "--headless" into
# "- - h e a d l e s s".
param(
    [string]$Godot = 'D:\temp\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe',
    [string]$Preset = 'Web Release',
    [switch]$Fresh
)
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot | Split-Path -Parent
if (-not (Test-Path -LiteralPath $Godot)) {
    $alt = Join-Path (Split-Path -Parent $PSScriptRoot) 'archive\workspace-support\_tools\godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe'
    if (Test-Path -LiteralPath $alt) { $Godot = $alt }
}
if (-not (Test-Path -LiteralPath $Godot)) { Write-Error "Godot not found"; exit 2 }

$out = Join-Path $root 'build\web'
if ($Fresh) { Remove-Item -Recurse -Force -LiteralPath $out -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $out | Out-Null

$importArgv = @('--headless', '--path', $root, '--import', '--quit')
Write-Output ("ARGV: {0} {1}" -f $Godot, ($importArgv -join ' '))
& $Godot @importArgv 2>&1 | Select-String -Pattern 'ERROR|Parse' | Select-Object -First 10
Write-Output ("import exit {0}" -f $LASTEXITCODE)

$exportArgv = @('--headless', '--path', $root, '--export-release', $Preset, 'build/web/index.html')
Write-Output ("ARGV: {0} {1}" -f $Godot, ($exportArgv -join ' '))
& $Godot @exportArgv 2>&1 | Select-String -Pattern 'ERROR|error|Save|export' | Select-Object -First 15
Write-Output ("export exit {0}" -f $LASTEXITCODE)

foreach ($required in @('index.html', 'index.pck', 'index.wasm', 'index.js')) {
    $path = Join-Path $out $required
    if (-not (Test-Path -LiteralPath $path)) { Write-Error "missing $required"; exit 3 }
}
$pck = Get-Item -LiteralPath (Join-Path $out 'index.pck')
Write-Output ("B10 WEB EXPORT pck_bytes={0} at {1}" -f $pck.Length, $pck.LastWriteTime.ToString('s'))
exit 0
