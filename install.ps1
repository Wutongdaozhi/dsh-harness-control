# 为 dsh-harness-control 创建桌面快捷方式（唯一入口）
#   「DSH Harness」—— 双击 = 启动后台 GUI（未运行则自动拉起）+ 自动打开浏览器 + 系统托盘就位
#   之后全用托盘菜单管理：停止 / 重启 / 端口设置 / 打开界面
# 用法:  powershell -ExecutionPolicy Bypass -File install.ps1
param(
  [string]$RepoRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$trayPs1 = Join-Path $RepoRoot 'dsh-tray.ps1'
if (-not (Test-Path $trayPs1)) { throw "dsh-tray.ps1 not found in $RepoRoot" }

$icon  = Join-Path $RepoRoot 'dsh-tray.ico'
$desktop = [Environment]::GetFolderPath('Desktop')
$ws = New-Object -ComObject WScript.Shell

# 删除旧的独立托盘快捷方式（已合并为统一入口）
$old = Join-Path $desktop 'DSH Harness 托盘.lnk'
if (Test-Path $old) { Remove-Item $old -Force; Write-Host "removed old shortcut: $old" }

# 唯一入口
$lnk = Join-Path $desktop 'DSH Harness.lnk'
$sc = $ws.CreateShortcut($lnk)
$sc.TargetPath       = 'powershell.exe'
$sc.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$trayPs1`""
$sc.WorkingDirectory = $RepoRoot
$sc.Description      = '一键启动 DeepSeek Harness 后台 GUI（自动打开浏览器），托盘常驻管理：停止/重启/端口设置'
$sc.IconLocation     = if (Test-Path $icon) { "$icon,0" } else { 'shell32.dll,134' }
$sc.Save()
Write-Host "shortcut created: $lnk"
