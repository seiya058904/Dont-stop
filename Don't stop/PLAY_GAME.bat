@echo off
setlocal EnableExtensions
for %%I in ("%~dp0.") do set "GAME_DIR=%%~fI"
set "GODOT=%~dp0..\archive\workspace-support\_tools\godot\4.7.2\Godot_v4.7.2-stable_win64.exe"
set "SOURCE_RUNTIME_DIR=%GAME_DIR%\build\source-runtime"
set "SOURCE_RUNTIME_EXE=%SOURCE_RUNTIME_DIR%\Don't stop.exe"
if not exist "%GODOT%" (
    echo The workspace portable Godot 4.7.2 runtime is missing.
    echo See README-PLAY.md in this project folder.
    pause
    exit /b 1
)
if not exist "%GAME_DIR%\.godot\global_script_class_cache.cfg" (
    echo Preparing game assets for the first launch...
    "%GODOT%" --headless --path "%GAME_DIR%" --editor --import --quit --log-file "%GAME_DIR%\first-launch.log"
    if errorlevel 1 (
        echo Asset preparation failed. See first-launch.log.
        pause
        exit /b 1
    )
    findstr /C:"ERROR:" "%GAME_DIR%\first-launch.log" >nul
    if not errorlevel 1 (
        echo Asset preparation reported errors. See first-launch.log.
        pause
        exit /b 1
    )
)
if not exist "%SOURCE_RUNTIME_DIR%" mkdir "%SOURCE_RUNTIME_DIR%"
echo Building the source Release runtime...
start "" /wait "%GODOT%" --headless --path "%GAME_DIR%" --export-release "Windows x64 Release" "%SOURCE_RUNTIME_EXE%" --log-file "%GAME_DIR%\source-export.log"
if errorlevel 1 (
    echo Source Release export failed. See source-export.log.
    pause
    exit /b 1
)
findstr /C:"ERROR:" "%GAME_DIR%\source-export.log" >nul
if not errorlevel 1 (
    echo Source Release export reported errors. See source-export.log.
    pause
    exit /b 1
)
if not exist "%SOURCE_RUNTIME_EXE%" (
    echo Source Release executable was not produced.
    pause
    exit /b 1
)
start "Don't Stop (source Release)" "%SOURCE_RUNTIME_EXE%"
exit /b 0
