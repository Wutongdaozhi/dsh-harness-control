# 为 dsh-harness-control 创建桌面快捷方式
#   1. 「DSH Harness」      —— 一键启动后台 GUI 并自动打开浏览器（主入口）
#   2. 「DSH Harness 托盘」 —— 系统托盘后台管理（停止/重启/端口设置）
# 用法:  powershell -ExecutionPolicy Bypass -File install.ps1
param(
  [string]$RepoRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$webPs1 = Join-Path $RepoRoot 'dsh-web.ps1'
$trayPs1 = Join-Path $RepoRoot 'dsh-tray.ps1'
if (-not (Test-Path $webPs1))  { throw "dsh-web.ps1 not found in $RepoRoot" }
if (-not (Test-Path $trayPs1)) { throw "dsh-tray.ps1 not found in $RepoRoot" }

$icon  = Join-Path $RepoRoot 'dsh-tray.ico'
$desktop = [Environment]::GetFolderPath('Desktop')
$ws = New-Object -ComObject WScript.Shell

function New-Shortcut {
  param(
    [string]$Name,
    [string]$Arguments,
    [string]$Description,
    [string]$IconLocation = 'shell32.dll,134'
  )
  $lnk = Join-Path $desktop "$Name.lnk"
  $sc = $ws.CreateShortcut($lnk)
  $sc.TargetPath       = 'powershell.exe'
  $sc.Arguments        = $Arguments
  $sc.WorkingDirectory = $RepoRoot
  $sc.Description      = $Description
  $sc.IconLocation     = $IconLocation
  $sc.Save()
  Write-Host "shortcut created: $lnk"
}

$appIcon = if (Test-Path $icon) { "$icon,0" } else { 'shell32.dll,134' }

# 主入口：双击 → 启动后台 GUI + 自动打开浏览器
New-Shortcut -Name 'DSH Harness' `
  -Arguments "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$webPs1`" start -OpenBrowser" `
  -Description '启动 DeepSeek Harness 后台 GUI 并打开浏览器' `
  -IconLocation $appIcon

# 后台管理：双击 → 系统托盘（启动/停止/重启/端口设置）
New-Shortcut -Name 'DSH Harness 托盘' `
  -Arguments "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$trayPs1`"" `
  -Description 'DeepSeek Harness 系统托盘控制器：启动/停止/重启/端口设置' `
  -IconLocation $appIcon
