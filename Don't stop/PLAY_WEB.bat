@echo off
setlocal EnableExtensions
rem Serves the locally exported Web candidate from build\web and opens it in the
rem default browser. This is the *candidate* build from this working tree - it is
rem NOT the published GitHub Pages site, which still serves the previous
rem (pre-revision) baseline until the branch is merged and deployed.
for %%I in ("%~dp0.") do set "GAME_DIR=%%~fI"
set "WEB_DIR=%GAME_DIR%\build\web"

if not exist "%WEB_DIR%\index.html" (
    echo No local Web build found in "%WEB_DIR%".
    echo Export it first:
    echo   godot --headless --path "%GAME_DIR%" --export-release "Web Release" "build/web/index.html"
    pause
    exit /b 1
)

set "PORT=8799"
echo Serving "%WEB_DIR%" at http://127.0.0.1:%PORT%/index.html
start "" "http://127.0.0.1:%PORT%/index.html"
python -m http.server %PORT% --bind 127.0.0.1 --directory "%WEB_DIR%"
exit /b 0
