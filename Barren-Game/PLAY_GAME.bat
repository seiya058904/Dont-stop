@echo off
setlocal EnableExtensions

set "GAME_DIR=%~dp0"
set "GAME_EXE=%GAME_DIR%Export\Windows\Barren.exe"

if not exist "%GAME_EXE%" (
    echo Barren.exe was not found:
    echo "%GAME_EXE%"
    pause
    exit /b 1
)

pushd "%GAME_DIR%Export\Windows"
start "" "Barren.exe"
popd
exit /b 0
