# 为 dsh-harness-control 创建桌面快捷方式（双击启动系统托盘）
# 用法:  powershell -ExecutionPolicy Bypass -File install.ps1
param(
  [string]$RepoRoot = $PSScriptRoot,
  [string]$ShortcutName = 'DSH Harness 托盘'
)

$ErrorActionPreference = 'Stop'

$ps1 = Join-Path $RepoRoot 'dsh-tray.ps1'
if (-not (Test-Path $ps1)) { throw "dsh-tray.ps1 not found in $RepoRoot" }

$icon  = Join-Path $RepoRoot 'dsh-tray.ico'
$desktop = [Environment]::GetFolderPath('Desktop')
$lnk     = Join-Path $desktop "$ShortcutName.lnk"

$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut($lnk)
$sc.TargetPath       = 'powershell.exe'
$sc.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1`""
$sc.WorkingDirectory = $RepoRoot
$sc.Description      = 'DeepSeek Harness 系统托盘控制器：启动/停止/重启/端口设置'
if (Test-Path $icon) { $sc.IconLocation = "$icon,0" } else { $sc.IconLocation = 'shell32.dll,134' }
$sc.Save()

Write-Host "shortcut created: $lnk"
