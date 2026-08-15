#requires -Version 5.1
<#
.SYNOPSIS
  系统托盘控制器 —— DeepSeek Harness Web GUI 的可视化管理（启动/停止/重启/端口设置）。

.DESCRIPTION
  常驻右下角托盘图标，是后台 GUI 的**唯一桌面入口**：启动托盘时若 GUI 未运行
  会自动拉起（调用同目录的 dsh-web.ps1），就绪后自动打开浏览器，之后全用
  托盘菜单管理（启动/停止/重启/端口设置）。
  - 端口配置保存在 $env:DSH_HOME\dsh-web\tray-config.json
  - 悬停托盘图标可看到实时状态（2 秒刷新）
  - 双击托盘图标 = 打开浏览器界面
  - 菜单里的"退出"只关闭托盘，不停 harness

.EXAMPLE
  .\dsh-tray.ps1           # 启动托盘
  . .\dsh-tray.ps1         # 仅加载函数，不显示托盘（测试用）
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

$script:ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:DshCtl     = Join-Path $script:ScriptDir 'dsh-web.ps1'
$script:StateDir   = if ($env:DSH_HOME -and (Test-Path $env:DSH_HOME)) { Join-Path $env:DSH_HOME 'dsh-web' } else { $script:ScriptDir }
$script:ConfigFile = Join-Path $script:StateDir 'tray-config.json'

# --- 环境检查: 启动托盘前先确认 Node >= 22, 否则弹窗退出 ---------------------------
# 直接双击运行本脚本(没走 npm/npx 安装)的用户, 靠这里立刻知道缺什么。
function Test-TrayEnvironment {
  $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
  if (-not $nodeCmd) {
    [System.Windows.Forms.MessageBox]::Show(@'
未检测到 Node.js！
DeepSeek Harness 需要 Node.js >= 22。
安装: https://nodejs.org 下载 LTS (推荐 nvm-windows 安装 22.x)，装完再启动托盘。
'@, 'DSH Harness - 环境检查未通过',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    return $false
  }
  try {
    $v = & $nodeCmd.Source --version 2>$null
    if ($v -match 'v?(\d+)\.') {
      $major = [int]$matches[1]
      if ($major -lt 22) {
        [System.Windows.Forms.MessageBox]::Show(
          "Node.js 版本过低：当前 v$major.x，DeepSeek Harness 需要 >= 22。`n升级: https://nodejs.org (推荐 nvm-windows: nvm install 22 && nvm use 22)",
          'DSH Harness - 环境检查未通过',
          [System.Windows.Forms.MessageBoxButtons]::OK,
          [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return $false
      }
    }
  } catch { }
  return $true
}

# --- 配置读写 ----------------------------------------------------------------
function Get-ConfiguredPort {
  if (Test-Path $script:ConfigFile) {
    try {
      $cfg = Get-Content $script:ConfigFile -Raw | ConvertFrom-Json
      if ($cfg.port -is [int] -and $cfg.port -ge 1 -and $cfg.port -le 65535) { return [int]$cfg.port }
    } catch { }
  }
  return 8081
}

function Save-ConfiguredPort {
  param([int]$Port)
  New-Item -ItemType Directory -Force -Path $script:StateDir | Out-Null
  @{ port = $Port } | ConvertTo-Json | Set-Content -Path $script:ConfigFile -Encoding UTF8
}

# --- 状态查询（进程内快速实现，不另起进程） ------------------------------------
# 注意: 悬停提示是定时轮询的, 必须用轻量 .NET API (GetActiveTcpListeners, ~2ms)。
# 之前用 Get-NetTCPConnection (~500ms/次) 会阻塞 UI 线程, 鼠标悬停菜单时正好撞上就卡顿。
function Test-Listener {
  param([int]$Port)
  try {
    $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    foreach ($ep in $listeners) { if ($ep.Port -eq $Port) { return $true } }
  } catch { }
  return $false
}

function Get-HarnessStatusText {
  param([int]$Port)
  if (Test-Listener -Port $Port) { return "运行中 · http://127.0.0.1:$Port" }
  return "已停止 (端口 $Port)"
}

# 点菜单时才用的详细版(带 PID); 一次性调用, 用慢一点的 Get-NetTCPConnection 无妨
function Get-HarnessStatusDetail {
  param([int]$Port)
  $conn = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($conn) { return "运行中 · http://127.0.0.1:$Port (PID $($conn.OwningProcess))" }
  return "已停止 (端口 $Port)"
}

# --- 动作执行（后台调用 dsh-web.ps1，不卡托盘界面） ------------------------------
function Invoke-DshCtlAction {
  param([string]$Action)
  $port = Get-ConfiguredPort
  $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:DshCtl, $Action, '-Port', "$port")
  Start-Process powershell -ArgumentList $args -WindowStyle Hidden | Out-Null
}

function Open-Gui {
  $port = Get-ConfiguredPort
  Start-Process "http://127.0.0.1:$port"
}

# --- 开机自启（启动文件夹方案，用户级） ----------------------------------------
function Get-AutoStartEntry {
  $startup = [Environment]::GetFolderPath('Startup')
  return (Join-Path $startup 'DSH Harness.cmd')
}

function Test-AutoStart {
  return (Test-Path (Get-AutoStartEntry))
}

function Set-AutoStart {
  param([bool]$Enable)
  $entry = Get-AutoStartEntry
  if ($Enable) {
    $content = "@`n@echo off`nrem DSH Harness tray autostart (tray menu)`nstart `"`" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($script:ScriptDir)\dsh-tray.ps1`"`n`"@"
    [System.IO.File]::WriteAllText($entry, $content, (New-Object System.Text.UTF8Encoding($false)))
  }
  else {
    if (Test-Path $entry) { Remove-Item $entry -Force }
  }
}

# --- 托盘图标：运行蓝 / 停止灰 --------------------------------------------------
function Set-TrayIcon {
  param([bool]$Running)
  $target = if ($Running) { $script:IconOn } else { $script:IconOff }
  if ($script:currentIcon -eq $target) { return }
  $script:notifyIcon.Icon = $target
  $script:currentIcon = $target
}

# --- 托盘主体 ------------------------------------------------------------------
function Show-Tray {
  # 单实例：托盘已在运行则直接退出（重复双击不会开两个托盘）
  $script:mutex = New-Object System.Threading.Mutex($false, 'dsh-harness-tray')
  if (-not $script:mutex.WaitOne(0)) { return }

  # 环境检查: Node >= 22, 不满足直接弹窗退出(不创建托盘)
  if (-not (Test-TrayEnvironment)) { return }

  $script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
  $script:IconOnFile = Join-Path $script:ScriptDir 'dsh-tray.ico'
  $script:IconOffFile = Join-Path $script:ScriptDir 'dsh-tray-off.ico'
  $script:iconOnFromFile = $false; $script:iconOffFromFile = $false
  if (Test-Path $script:IconOnFile) { $script:IconOn = New-Object System.Drawing.Icon($script:IconOnFile); $script:iconOnFromFile = $true }
  else { $script:IconOn = [System.Drawing.SystemIcons]::Application }
  if (Test-Path $script:IconOffFile) { $script:IconOff = New-Object System.Drawing.Icon($script:IconOffFile); $script:iconOffFromFile = $true }
  else { $script:IconOff = $script:IconOn }
  $script:currentIcon = $null
  $script:notifyIcon.Text = 'DSH Harness'
  $script:notifyIcon.Visible = $true

  $menu = New-Object System.Windows.Forms.ContextMenuStrip

  $miStatus    = New-Object System.Windows.Forms.ToolStripMenuItem('状态…')
  $miStart     = New-Object System.Windows.Forms.ToolStripMenuItem('启动')
  $miStop      = New-Object System.Windows.Forms.ToolStripMenuItem('停止')
  $miRestart   = New-Object System.Windows.Forms.ToolStripMenuItem('重启')
  $sep1        = New-Object System.Windows.Forms.ToolStripSeparator
  $miPort      = New-Object System.Windows.Forms.ToolStripMenuItem('端口设置…')
  $miOpen      = New-Object System.Windows.Forms.ToolStripMenuItem('打开界面')
  $miLogs      = New-Object System.Windows.Forms.ToolStripMenuItem('查看日志…')
  $miAuto      = New-Object System.Windows.Forms.ToolStripMenuItem('开机自启')
  $miUpdate    = New-Object System.Windows.Forms.ToolStripMenuItem('检查更新…')
  $sep2        = New-Object System.Windows.Forms.ToolStripSeparator
  $miExit      = New-Object System.Windows.Forms.ToolStripMenuItem('退出托盘')
  $script:miAuto = $miAuto
  $miAuto.Checked = Test-AutoStart

  $miStatus.Add_Click({
    $p = Get-ConfiguredPort
    [System.Windows.Forms.MessageBox]::Show((Get-HarnessStatusDetail -Port $p), 'DSH Harness 状态',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
  })
  $miStart.Add_Click({ Invoke-DshCtlAction 'start' })
  $miStop.Add_Click({ Invoke-DshCtlAction 'stop' })
  $miRestart.Add_Click({ Invoke-DshCtlAction 'restart' })
  $miPort.Add_Click({
    $cur = Get-ConfiguredPort
    $ans = [Microsoft.VisualBasic.Interaction]::InputBox("输入监听端口（1-65535）：", 'DSH Harness 端口设置', "$cur")
    if ($ans -eq '') { return }
    $num = 0
    if (-not [int]::TryParse($ans, [ref]$num) -or $num -lt 1 -or $num -gt 65535) {
      [System.Windows.Forms.MessageBox]::Show("无效端口：$ans", 'DSH Harness',
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
      return
    }
    Save-ConfiguredPort -Port $num
    $script:cfgPort = $num
    [System.Windows.Forms.MessageBox]::Show("端口已设为 $num`n点击菜单「重启」即可生效。", 'DSH Harness',
      [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
  })
  $miOpen.Add_Click({ Open-Gui })
  $miAuto.Add_Click({
    $wantOn = -not (Test-AutoStart)
    if ($wantOn) {
      $r = [System.Windows.Forms.MessageBox]::Show(
        "启用开机自启？`n登录后自动启动托盘，托盘会自动拉起后台 GUI 并打开浏览器。",
        'DSH Harness 开机自启',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
      if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }
    Set-AutoStart -Enable $wantOn
    $script:miAuto.Checked = Test-AutoStart
  })
  $miUpdate.Add_Click({ Start-Process 'https://github.com/Wutongdaozhi/dsh-harness-control/releases' })
  $miLogs.Add_Click({
    $log = Join-Path $script:StateDir 'dsh-web.log'
    $err = Join-Path $script:StateDir 'dsh-web.err.log'
    if (Test-Path $log) { Start-Process $log }
    elseif (Test-Path $err) { Start-Process $err }
    else {
      [System.Windows.Forms.MessageBox]::Show('还没有日志文件，先启动一次 harness。', 'DSH Harness',
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
  })
  $miExit.Add_Click({
    $script:timer.Stop()
    $script:notifyIcon.Visible = $false
    try { if ($script:iconOnFromFile) { $script:IconOn.Dispose() } } catch { }
    try { if ($script:iconOffFromFile -and $script:IconOff -ne $script:IconOn) { $script:IconOff.Dispose() } } catch { }
    $script:notifyIcon.Dispose()
    try { $script:mutex.ReleaseMutex() } catch { }
    [System.Windows.Forms.Application]::Exit()
  })

  $menu.Items.AddRange(@($miStatus, $miStart, $miStop, $miRestart, $sep1, $miPort, $miOpen, $miLogs, $miAuto, $miUpdate, $sep2, $miExit))
  $script:notifyIcon.ContextMenuStrip = $menu

  # 双击托盘 = 打开界面
  $script:notifyIcon.add_DoubleClick({ Open-Gui })

  # 定时刷新悬停提示: 4 秒一次, 轻量检测 + 气泡只在内容变化时更新(避免重建托盘提示窗口)
  $script:cfgPort = Get-ConfiguredPort
  $script:timer = New-Object System.Windows.Forms.Timer
  $script:timer.Interval = 4000
  $script:timer.add_Tick({
    $p = $script:cfgPort
    $running = Test-Listener -Port $p
    # 图标状态：运行蓝 / 停止灰
    Set-TrayIcon -Running $running
    # 一键启动：GUI 就绪后自动打开浏览器（只开一次）
    if (-not $script:autoBootOpened -and $running) {
      Open-Gui
      $script:autoBootOpened = $true
    }
    $text = Get-HarnessStatusText -Port $p
    $newTip = "DSH · $text"
    if ($newTip.Length -gt 63) { $newTip = $newTip.Substring(0, 63) }
    # 只在内容变化时更新, 避免频繁重建气泡窗口导致悬停卡顿
    if ($script:notifyIcon.Text -ne $newTip) { $script:notifyIcon.Text = $newTip }
  })
  $script:timer.Start()

  # 一键入口：GUI 未运行则自动拉起，运行中则直接打开浏览器
  $script:autoBootOpened = $false
  if (Test-Listener -Port $script:cfgPort) {
    Set-TrayIcon -Running $true
    Open-Gui
    $script:autoBootOpened = $true
  }
  else {
    Set-TrayIcon -Running $false
    Invoke-DshCtlAction 'start'
  }

  [System.Windows.Forms.Application]::Run()
}

if ($MyInvocation.InvocationName -ne '.') { Show-Tray }
