@echo off
rem 双击启动 DSH Harness 系统托盘（隐藏窗口、不残留控制台）
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0dsh-tray.ps1"
