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
function Get-HarnessStatusText {
  param([int]$Port)
  $conn = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($conn) { return "运行中 · http://127.0.0.1:$Port (PID $($conn.OwningProcess))" }
  return "已停止 (端口 $Port)"
}

function Test-Listener {
  param([int]$Port)
  return [bool](Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1)
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

# --- 托盘主体 ------------------------------------------------------------------
function Show-Tray {
  # 单实例：托盘已在运行则直接退出（重复双击不会开两个托盘）
  $script:mutex = New-Object System.Threading.Mutex($false, 'dsh-harness-tray')
  if (-not $script:mutex.WaitOne(0)) { return }

  $script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
  $script:IconFile = Join-Path $script:ScriptDir 'dsh-tray.ico'
  if (Test-Path $script:IconFile) {
    $script:notifyIcon.Icon = New-Object System.Drawing.Icon($script:IconFile)
  } else {
    $script:notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
  }
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
  $sep2        = New-Object System.Windows.Forms.ToolStripSeparator
  $miExit      = New-Object System.Windows.Forms.ToolStripMenuItem('退出托盘')

  $miStatus.Add_Click({
    $p = Get-ConfiguredPort
    [System.Windows.Forms.MessageBox]::Show((Get-HarnessStatusText -Port $p), 'DSH Harness 状态',
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
    [System.Windows.Forms.MessageBox]::Show("端口已设为 $num`n点击菜单「重启」即可生效。", 'DSH Harness',
      [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
  })
  $miOpen.Add_Click({ Open-Gui })
  $miExit.Add_Click({
    $script:timer.Stop()
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Icon.Dispose()
    $script:notifyIcon.Dispose()
    try { $script:mutex.ReleaseMutex() } catch { }
    [System.Windows.Forms.Application]::Exit()
  })

  $menu.Items.AddRange(@($miStatus, $miStart, $miStop, $miRestart, $sep1, $miPort, $miOpen, $sep2, $miExit))
  $script:notifyIcon.ContextMenuStrip = $menu

  # 双击托盘 = 打开界面
  $script:notifyIcon.add_DoubleClick({ Open-Gui })

  # 定时刷新悬停提示
  $script:timer = New-Object System.Windows.Forms.Timer
  $script:timer.Interval = 2000
  $script:timer.add_Tick({
    $p = Get-ConfiguredPort
    # 一键启动：GUI 就绪后自动打开浏览器（只开一次）
    if (-not $script:autoBootOpened -and (Test-Listener -Port $p)) {
      Open-Gui
      $script:autoBootOpened = $true
    }
    $text = Get-HarnessStatusText -Port $p
    if ($text.Length -gt 63) { $text = $text.Substring(0, 63) }
    $script:notifyIcon.Text = "DSH · $text"
  })
  $script:timer.Start()

  # 一键入口：GUI 未运行则自动拉起，运行中则直接打开浏览器
  $script:autoBootOpened = $false
  if (Test-Listener -Port (Get-ConfiguredPort)) {
    Open-Gui
    $script:autoBootOpened = $true
  }
  else {
    Invoke-DshCtlAction 'start'
  }

  [System.Windows.Forms.Application]::Run()
}

if ($MyInvocation.InvocationName -ne '.') { Show-Tray }
