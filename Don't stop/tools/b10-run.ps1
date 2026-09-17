# B10 scene runner.
#
# A thin wrapper over tools/b8-run.ps1 so a case's arguments can be passed as one comma-separated
# string from a command line. `pwsh -File` cannot bind an ARRAY parameter (a first attempt at
# `-CaseArgs @('a','b')` failed with "找不到接受自变量 'b' 的位置参数"), and b8-run.ps1 must keep
# taking a real array so its own callers are unchanged.
#
# Usage:
#   tools/b10-run.ps1 -Scene B10Threat -Args 'only=E10+E14,trials=3,tag=baseline'
#   tools/b10-run.ps1 -Scene B10Playtest
#
# `+` inside a value becomes `,` so a case can carry its own comma-separated list even though the
# wrapper itself splits arguments on commas.
param(
    [Parameter(Mandatory = $true)][string]$Scene,
    [string]$Args = '',
    [int]$Frames = 40000,
    [string]$LogName = ''
)
$ErrorActionPreference = 'Continue'
$runner = Join-Path $PSScriptRoot 'b8-run.ps1'
$caseArgs = @()
if ($Args -ne '') {
    foreach ($piece in $Args.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $caseArgs += $piece.Trim().Replace('+', ',')
    }
}
if ([string]::IsNullOrEmpty($LogName)) { $LogName = $Scene }
& $runner -Scene $Scene -CaseArgs $caseArgs -Frames $Frames -LogName $LogName
exit $LASTEXITCODE
