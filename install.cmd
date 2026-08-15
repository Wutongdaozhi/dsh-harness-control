@echo off
rem Double-click to install: create the "DSH Harness" desktop shortcut
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
echo Done. Press any key to exit...
pause >nul
