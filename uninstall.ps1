# 卸载 dsh-harness-control：移除桌面快捷方式、开机自启项
# 状态目录（端口配置/日志/PID）涉及删除数据，删除前必须征得同意
# 用法:  powershell -ExecutionPolicy Bypass -File uninstall.ps1
param(
  [switch]$Yes   # 跳过确认（脚本化场景）
)

$ErrorActionPreference = 'Stop'

$desktop = [Environment]::GetFolderPath('Desktop')
$startup = [Environment]::GetFolderPath('Startup')

$removed = @()

# 桌面快捷方式
$lnk = Join-Path $desktop 'DSH Harness.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force; $removed += $lnk }

# 开机自启项
$cmd = Join-Path $startup 'DSH Harness.cmd'
if (Test-Path $cmd) { Remove-Item $cmd -Force; $removed += $cmd }

if ($removed.Count -gt 0) {
  foreach ($r in $removed) { Write-Host "removed: $r" }
} else {
  Write-Host "未找到快捷方式或自启项（可能已卸载过）。"
}

# 状态目录：包含托盘端口配置、PID、日志 —— 删除需征得同意
if ($env:DSH_HOME) {
  $state = Join-Path $env:DSH_HOME 'dsh-web'
  if (Test-Path $state) {
    $ok = $Yes
    if (-not $ok) {
      $ans = Read-Host "是否删除状态目录（含托盘端口配置、PID、日志）？`n  $state`n (y/N)"
      $ok = ($ans -eq 'y' -or $ans -eq 'Y')
    }
    if ($ok) { Remove-Item $state -Recurse -Force; Write-Host "removed: $state" }
    else { Write-Host "保留状态目录：$state" }
  }
}

Write-Host "卸载完成。正在运行的后台 GUI 未受影响；会话数据保留在 $env:DSH_HOME\sessions（如需一并删除请手动处理）。"
