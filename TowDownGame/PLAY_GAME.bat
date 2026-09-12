@echo off
setlocal EnableExtensions

set "GAME_DIR=%~dp0"
set "GODOT=%~dp0..\archive\workspace-support\_tools\godot\4.7.2\Godot_v4.7.2-stable_win64.exe"

if not exist "%GODOT%" (
    echo Godot 4.7.2 was not found:
    echo "%GODOT%"
    pause
    exit /b 1
)

start "" "%GODOT%" --path "%GAME_DIR%"
exit /b 0
