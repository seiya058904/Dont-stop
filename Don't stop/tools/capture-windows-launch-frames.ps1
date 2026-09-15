# Capture a frame sequence of the game window from BEFORE the engine can draw,
# so a flash of a giant image during start-up cannot hide from the evidence.
#
# Why not reuse capture-windows-launch.ps1: that script reads the PNGs Boot.gd
# writes through --boot-capture, which only start after Boot._ready(). Anything
# the engine paints earlier - a boot splash, the Godot default splash - is already
# gone by then, so it cannot prove those frames were clean.
#
# This script instead:
#   * starts the game and polls for its window handle from the first millisecond;
#   * copies ONLY the game window's own client rectangle, never the desktop around
#     it, so unrelated screen content cannot end up in evidence;
#   * stamps every frame with milliseconds since process start, so "before the
#     script ran" is a measured interval and not a claim;
#   * scores each frame by how much of it is NOT the configured boot background
#     colour. A full-window splash image scores high; the flat background and the
#     loading UI score low.
#
# Modes:
#   -Mode source : run the maintained project from source with the workspace Godot
#                  binary (the local "double-click PLAY_GAME.bat" path).
#   -Mode exe    : run the exported Windows candidate.
#   -SplashProbe : temporary control. Enables the boot splash image for this run
#                  only, to prove the scorer really does catch a splash. The
#                  project file is restored afterwards and its hash is checked.
param(
    [ValidateSet('source', 'exe')][string]$Mode = 'source',
    [string]$Exe = "Don't stop.exe",
    [string]$OutDir = "evidence\r3\windows-launch",
    [int]$RunSeconds = 14,
    [int]$Fps = 25,
    [switch]$SplashProbe
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DshWin32 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref System.Drawing.Point p);
}
"@ -ReferencedAssemblies System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root $OutDir
if ($SplashProbe) { $out = Join-Path $out 'splash-probe' }
New-Item -ItemType Directory -Force -Path $out | Out-Null
Get-ChildItem -LiteralPath $out -Filter 'frame-*.png' -ErrorAction SilentlyContinue | Remove-Item -Force

$projectFile = Join-Path $root 'project.godot'
$projectHashBefore = (Get-FileHash -LiteralPath $projectFile -Algorithm SHA256).Hash
$splashWasEnabled = $null

if ($SplashProbe) {
    # Control run: put the splash image back, in the project file only, so the
    # scorer is shown a start-up that DOES paint a full-window image.
    $text = Get-Content -LiteralPath $projectFile -Raw
    $splashWasEnabled = $text -match 'boot_splash/show_image=true'
    $text = $text -replace 'boot_splash/show_image=false', 'boot_splash/show_image=true'
    if ($text -notmatch 'boot_splash/image=') {
        $text = $text -replace '(boot_splash/bg_color=[^\r\n]*)', "`$1`nboot_splash/image=`"res://game-icon.png`""
    }
    Set-Content -LiteralPath $projectFile -Value $text -NoNewline
    Write-Host "splash-probe: boot splash image enabled for this run only"
}

$launchExe = $null
$launchArgs = @()
if ($Mode -eq 'exe') {
    $launchExe = Join-Path $root "build\windows\$Exe"
    if (-not (Test-Path -LiteralPath $launchExe)) { throw "missing $launchExe" }
} else {
    $launchExe = Join-Path $root '..\archive\workspace-support\_tools\godot\4.7.2\Godot_v4.7.2-stable_win64.exe'
    if (-not (Test-Path -LiteralPath $launchExe)) { throw "missing workspace Godot runtime" }
    $launchArgs = @('--path', ('"' + $root + '"'))
}

# Isolated profile: the shipped build writes %APPDATA%\TowDownGame and the source
# run %APPDATA%\TowDownGame-Iteration, both resolved from this variable, so the
# real save is never touched.
$profileRoot = Join-Path $env:TEMP ("dontstop-launch-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $profileRoot | Out-Null
$realAppData = $env:APPDATA
$env:APPDATA = $profileRoot

$bg = @(13, 12, 23)   # project.godot boot_splash/bg_color 0.0509804,0.0470588,0.0901961
$frames = New-Object System.Collections.Generic.List[object]
$title = ''
$sw = [System.Diagnostics.Stopwatch]::StartNew()

try {
    $p = Start-Process -FilePath $launchExe -ArgumentList $launchArgs -PassThru
    $handle = [IntPtr]::Zero
    $interval = [math]::Max(10, [int](1000 / $Fps))
    $deadline = $sw.Elapsed.TotalSeconds + $RunSeconds
    while ($sw.Elapsed.TotalSeconds -lt $deadline) {
        $tick = $sw.Elapsed.TotalMilliseconds
        if ($handle -eq [IntPtr]::Zero -and -not $p.HasExited) {
            $p.Refresh()
            if ($p.MainWindowHandle -ne [IntPtr]::Zero) {
                $handle = $p.MainWindowHandle
                try { $title = $p.MainWindowTitle } catch { $title = '' }
                [DshWin32]::SetForegroundWindow($handle) | Out-Null
                Write-Host ("window appeared at {0:N0}ms title=`"{1}`"" -f $tick, $title)
            }
        }
        if ($handle -ne [IntPtr]::Zero) {
            $r = New-Object DshWin32+RECT
            if ([DshWin32]::GetClientRect($handle, [ref]$r)) {
                $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
                if ($w -gt 40 -and $h -gt 40) {
                    $origin = New-Object System.Drawing.Point 0, 0
                    [DshWin32]::ClientToScreen($handle, [ref]$origin) | Out-Null
                    $shot = New-Object System.Drawing.Bitmap $w, $h
                    $g = [System.Drawing.Graphics]::FromImage($shot)
                    $g.CopyFromScreen($origin.X, $origin.Y, 0, 0, (New-Object System.Drawing.Size $w, $h))
                    $g.Dispose()
                    $file = Join-Path $out ("frame-{0:D5}ms.png" -f [int]$tick)
                    $shot.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
                    # Score: share of sampled pixels that differ from the boot colour.
                    $off = 0; $total = 0; $stepY = [math]::Max(1, [int]($h / 90)); $stepX = [math]::Max(1, [int]($w / 160))
                    for ($y = 0; $y -lt $h; $y += $stepY) {
                        for ($x = 0; $x -lt $w; $x += $stepX) {
                            $c = $shot.GetPixel($x, $y); $total++
                            if ([math]::Abs($c.R - $bg[0]) + [math]::Abs($c.G - $bg[1]) + [math]::Abs($c.B - $bg[2]) -gt 24) { $off++ }
                        }
                    }
                    $shot.Dispose()
                    $frames.Add([pscustomobject]@{ ms = [int]$tick; file = (Split-Path -Leaf $file); w = $w; h = $h; off_pct = [math]::Round(100.0 * $off / [math]::Max(1, $total), 2) })
                }
            }
        }
        Start-Sleep -Milliseconds $interval
    }
    if (-not $p.HasExited) {
        $p.CloseMainWindow() | Out-Null
        if (-not $p.WaitForExit(10000)) { $p.Kill() }
    }
} finally {
    $env:APPDATA = $realAppData
    if ($SplashProbe) {
        # Restore only the single flag the probe changed.
        $text = Get-Content -LiteralPath $projectFile -Raw
        $text = $text -replace 'boot_splash/show_image=true', 'boot_splash/show_image=false'
        Set-Content -LiteralPath $projectFile -Value $text -NoNewline
        if ($splashWasEnabled -eq $false -or $null -eq $splashWasEnabled) { }
    }
}

$frames | ForEach-Object { "{0,7}ms  {1}" -f $_.ms, ($_.file + "  " + $_.w + "x" + $_.h + "  off-bg=" + $_.off_pct + "%") } | Write-Host
$first = $frames | Select-Object -First 1
$maxOff = ($frames | Measure-Object -Property off_pct -Maximum).Maximum
"mode=$Mode frames=$($frames.Count) first_frame_ms=$($first.ms) window_title=`"$title`""
"max_off_background_pct=$maxOff"
"profile_isolated=$profileRoot"
$projectHashAfter = (Get-FileHash -LiteralPath $projectFile -Algorithm SHA256).Hash
"project_godot_unchanged=$($projectHashBefore -eq $projectHashAfter)"
$frames | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $out 'frames.json')
if (-not $SplashProbe) { "RESULT=EVIDENCE_WRITTEN" } else { "RESULT=SPLASH_PROBE_DONE" }
