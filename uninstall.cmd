@echo off
rem Double-click to uninstall: remove shortcut + autostart (asks before deleting state dir)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
echo.
echo Done. Press any key to exit...
pause >nul
