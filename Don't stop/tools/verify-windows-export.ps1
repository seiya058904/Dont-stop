# Clean-copy verification of the Windows export path used by the release workflow.
#
# Runs the same path logic as .github/workflows/build-windows.yml, but from a
# fresh clone with no old build output and no .godot cache, so a passing check
# cannot be an artefact of stale files on a developer machine.
#
# Ownership: it creates exactly one run-scoped directory under the system temp
# directory, marks it, and removes only that directory - success or failure.
param(
    [string]$Repo = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$Branch = 'feat/dont-stop-revision',
    [string]$Godot = '',
    [string]$ProjectPath = "Don't stop"
)

$ErrorActionPreference = 'Stop'

if (-not $Godot) {
    $Godot = Join-Path $Repo 'archive\workspace-support\_tools\godot\4.7.2\Godot_v4.7.2-stable_win64.exe'
}
if (-not (Test-Path -LiteralPath $Godot)) { throw "Godot binary not found: $Godot" }

$stamp = [guid]::NewGuid().ToString('N').Substring(0, 8)
$work = Join-Path $env:TEMP "dontstop-winexport-clean-$stamp"
$marker = Join-Path $work '.dontstop-clean-verify'
$failures = 0

function Step([string]$name, [bool]$ok, [string]$extra = '') {
    if ($ok) { Write-Host "ok   $name $extra" } else { Write-Host "FAIL $name $extra"; $script:failures++ }
}

try {
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Set-Content -LiteralPath $marker -Value "dontstop clean export verification $stamp"
    $clone = Join-Path $work 'repo'
    Write-Host "=== clean copy: $clone (branch $Branch)"
    git clone --quiet --depth 1 --branch $Branch $Repo $clone
    if ($LASTEXITCODE -ne 0) { throw 'git clone failed' }
    Step 'clean-copy-has-no-build-output' (-not (Test-Path -LiteralPath (Join-Path $clone "$ProjectPath/build")))
    Step 'clean-copy-has-no-import-cache' (-not (Test-Path -LiteralPath (Join-Path $clone "$ProjectPath/.godot")))

    # ---- the workflow's logic, verbatim in shape
    $env:GITHUB_WORKSPACE = $clone
    $project = Join-Path $env:GITHUB_WORKSPACE $ProjectPath
    Step 'project-dir-resolves' (Test-Path -LiteralPath (Join-Path $project 'project.godot')) $project

    $importLog = Join-Path $work 'import.log'
    # Start-Process -Wait on purpose: the non-console Godot binary detaches from
    # the shell, so `& $Godot ... --import` returns before the import is done and
    # the export would run against a half-written cache.
    # Every argument that can contain a space (the project directory does) is
    # quoted explicitly: Start-Process joins the array with spaces and would
    # otherwise split the path in half.
    $quotedProject = '"' + $project + '"'
    $imp = Start-Process -FilePath $Godot -PassThru -Wait -RedirectStandardOutput (Join-Path $work 'import.out') -RedirectStandardError (Join-Path $work 'import.err') `
        -ArgumentList @('--headless', '--path', $quotedProject, '--editor', '--import', '--quit', '--log-file', ('"' + $importLog + '"'))
    Step 'import-command-succeeded' ($imp.ExitCode -eq 0) "exit=$($imp.ExitCode)"
    if ($imp.ExitCode -ne 0) {
        Write-Host '--- import stderr (tail) ---'
        Get-Content -LiteralPath (Join-Path $work 'import.err') -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" }
        Write-Host '--- import log (tail) ---'
        Get-Content -LiteralPath $importLog -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" }
    }
    $count = (Get-ChildItem -LiteralPath (Join-Path $project '.godot/imported') -ErrorAction SilentlyContinue | Measure-Object).Count
    Step 'import-produced-assets' ($count -ge 50) "imported=$count"

    $winDir = Join-Path $project 'build/windows'
    New-Item -ItemType Directory -Force -Path $winDir | Out-Null
    $exe = Join-Path $winDir "Don't stop.exe"
    $pck = Join-Path $winDir "Don't stop.pck"
    Remove-Item -LiteralPath $exe, $pck -Force -ErrorAction SilentlyContinue

    $exportLog = Join-Path $work 'export.log'
    $p = Start-Process -FilePath $Godot -PassThru -Wait -RedirectStandardOutput (Join-Path $work 'export.out') -RedirectStandardError (Join-Path $work 'export.err') `
        -ArgumentList @('--headless', '--path', $quotedProject, ('--export-release "Windows x64 Release"'), ('"' + $exe + '"'), '--log-file', ('"' + $exportLog + '"'))
    Step 'export-command-succeeded' ($p.ExitCode -eq 0) "exit=$($p.ExitCode)"

    Step 'exe-at-absolute-path' (Test-Path -LiteralPath $exe) $exe
    Step 'pck-at-absolute-path' (Test-Path -LiteralPath $pck) $pck
    if (Test-Path -LiteralPath $exe) {
        Step 'exe-not-empty' ((Get-Item -LiteralPath $exe).Length -gt 1MB) "$([math]::Round((Get-Item -LiteralPath $exe).Length/1MB,1)) MiB"
    }
    if (Test-Path -LiteralPath $pck) {
        Step 'pck-not-empty' ((Get-Item -LiteralPath $pck).Length -gt 1MB) "$([math]::Round((Get-Item -LiteralPath $pck).Length/1MB,1)) MiB"
    }
    $nested = Join-Path $project $ProjectPath
    Step 'no-nested-project-dir' (-not (Test-Path -LiteralPath $nested)) $nested
    Step 'project-dir-has-no-extra-level' (-not (Test-Path -LiteralPath (Join-Path $project "$ProjectPath/build")))

    # Package + hash from the same two files the check used.
    $stage = Join-Path $work 'stage'
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Copy-Item -LiteralPath $exe $stage
    Copy-Item -LiteralPath $pck $stage
    $zip = Join-Path $work "Don't stop-Windows-x64.zip"
    Compress-Archive -Path "$stage\*" -DestinationPath $zip -Force
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipHandle = [System.IO.Compression.ZipFile]::OpenRead($zip)
    $entries = $zipHandle.Entries.FullName
    $zipHandle.Dispose()
    Step 'zip-contains-exe-and-pck' (($entries -contains "Don't stop.exe") -and ($entries -contains "Don't stop.pck")) ($entries -join ', ')
    $sha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
    $shaOfExe = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLower()
    Step 'hashes-computed' ($sha.Length -eq 64 -and $shaOfExe.Length -eq 64)
    Write-Host "     exe sha256=$shaOfExe"
    Write-Host "     zip sha256=$sha"

    $log = Get-Content -LiteralPath $exportLog -Raw -ErrorAction SilentlyContinue
    Step 'export-log-has-no-errors' ($null -eq ($log | Select-String -Pattern '^ERROR' -Quiet) -or -not ($log -match '(?m)^ERROR:')) ''
} finally {
    if (Test-Path -LiteralPath $marker) {
        Remove-Item -LiteralPath $work -Recurse -Force
        Write-Host "=== removed own run directory $work"
    } else {
        Write-Host "=== left $work in place (ownership marker missing)"
    }
}

if ($failures) { Write-Host "RESULT=FAIL ($failures checks)"; exit 1 }
Write-Host 'RESULT=PASS'
