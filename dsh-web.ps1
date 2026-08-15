<#
.SYNOPSIS
  Convenience controller for the DeepSeek Harness Web GUI
  (start / stop / status / restart, with port control).

.DESCRIPTION
  Launches `dsh web` as a background process (hidden window, logs written
  under $env:DSH_HOME\dsh-web\ unless DSH_HOME is unset, then beside this
  script), remembers its PID, and lets you stop / query it later.

.EXAMPLE
  .\dsh-web.ps1 start                 # start on default port 8081
  .\dsh-web.ps1 start -Port 9000      # start on another port
  .\dsh-web.ps1 start -Console        # start in a visible window instead
  .\dsh-web.ps1 start -DshBin D:\node_modules\@deepseek-ai\dsh\lib\bin.js
                                      # point at a dsh install elsewhere
  .\dsh-web.ps1 status                # show whether it is running
  .\dsh-web.ps1 restart -Port 9000    # stop, then start on 9000
  .\dsh-web.ps1 stop                  # stop the instance on the default port
  .\dsh-web.ps1 logs                  # show recent log output
  .\dsh-web.ps1 logs -Tail 200 -Follow # tail the log and keep following

.NOTES
  - Stopping the harness kills the Web GUI, including any live session.
  - --host 0.0.0.0 is intentionally rejected by dsh itself for safety;
    the GUI is loopback-only by design.
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet('start', 'stop', 'status', 'restart', 'logs')]
  [string]$Action = 'status',

  [int]$Port = 8081,

  [ValidateSet('127.0.0.1', '0.0.0.0')]
  [string]$BindHost = '127.0.0.1',

  [string[]]$TrustedHost = @(),

  [string]$DshBin = '',

  [int]$Tail = 50,

  [switch]$Console,

  [switch]$OpenBrowser,

  [switch]$Follow
)

$ErrorActionPreference = 'Stop'

# --- resolve paths -----------------------------------------------------------
$DeployRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($env:DSH_HOME -and (Test-Path $env:DSH_HOME)) {
  $StateDir = Join-Path $env:DSH_HOME 'dsh-web'
}
else {
  $StateDir = $DeployRoot
}
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
$PidFile = Join-Path $StateDir 'dsh-web.pid'
$LogFile = Join-Path $StateDir 'dsh-web.log'
$ErrFile = Join-Path $StateDir 'dsh-web.err.log'

# --- locate the dsh CLI (portable: -DshBin > local node_modules > Node
#     resolution > PATH shims > global npm root) --------------------------------
# 修复: 从托盘/桌面启动时 PATH 里往往没有 dsh, 必须能靠项目本地依赖或 Node
# 模块解析找到 @deepseek-ai/dsh, 失败时把原因写进 err 日志而不是静默退出。
function Find-DshBin {
  param([string]$Explicit)
  if ($Explicit -and (Test-Path $Explicit)) { return $Explicit }

  # 1) 本目录 npm install 出来的依赖
  $local = Join-Path $DeployRoot 'node_modules\@deepseek-ai\dsh\lib\bin.js'
  if (Test-Path $local) { return $local }

  # 2) 交给 Node 的模块解析 (覆盖 npx 缓存安装 / 全局平铺安装两种布局)
  try {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCmd) {
      $resolved = & $nodeCmd.Source -e "console.log(require.resolve('@deepseek-ai/dsh/lib/bin.js', { paths: [process.argv[1]] }))" $DeployRoot 2>$null
      $cand = ($resolved | Select-Object -Last 1)
      if ($cand -and (Test-Path $cand.Trim())) { return $cand.Trim() }
    }
  } catch { }

  # 3) PATH 上有 dsh 可执行文件 (全局安装 / PATH 里的 npx 缓存)
  $dshCmd = Get-Command dsh -ErrorAction SilentlyContinue
  if ($dshCmd) {
    $shimDir = Split-Path -Parent $dshCmd.Source
    foreach ($rel in @('..\@deepseek-ai\dsh\lib\bin.js', 'node_modules\@deepseek-ai\dsh\lib\bin.js', '..\node_modules\@deepseek-ai\dsh\lib\bin.js')) {
      $candidate = [System.IO.Path]::GetFullPath((Join-Path $shimDir $rel))
      if (Test-Path $candidate) { return $candidate }
    }
  }

  # 4) 全局 npm 根目录
  try {
    $root = & npm root -g 2>$null
    $g = Join-Path (($root | Select-Object -Last 1).Trim()) '@deepseek-ai\dsh\lib\bin.js'
    if ($g -and (Test-Path $g)) { return $g }
  } catch { }

  # 5) npm npx 缓存里现成的 dsh 安装 (npx 跑过一次 @deepseek-ai/dsh 就有)
  try {
    $cache = & npm config get cache 2>$null
    if ($cache) {
      $npxRoot = Join-Path ($cache.Trim()) '_npx'
      foreach ($dir in (Get-ChildItem $npxRoot -Directory -ErrorAction SilentlyContinue)) {
        $p = Join-Path $dir.FullName 'node_modules\@deepseek-ai\dsh\lib\bin.js'
        if (Test-Path $p) { return $p }
      }
    }
  } catch { }

  return $null
}

$Bin = Find-DshBin -Explicit $DshBin

# --- helpers -----------------------------------------------------------------
function Get-NodePath {
  $cmd = Get-Command node -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw 'node was not found on PATH'
}

function Get-NodeMajorVersion {
  $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
  if (-not $nodeCmd) { return $null }
  try {
    $v = & $nodeCmd.Source --version 2>$null
    if ($v -match 'v?(\d+)\.') { return [int]$matches[1] }
  } catch { }
  return $null
}

# 环境检查: Node.js 必须存在且 >= 22 (DeepSeek Harness 硬性要求)。
# 直接跑脚本(没走 npm/npx 安装)的用户, 靠这里拿到明确提示而不是莫名失败。
function Test-NodeEnvironment {
  $major = Get-NodeMajorVersion
  if ($null -eq $major) {
    return $false, @'
未检测到 Node.js！
DeepSeek Harness 需要 Node.js >= 22。
安装: 到 https://nodejs.org 下载 LTS (推荐 nvm-windows 安装 22.x)，装完重开终端再试。
'@
  }
  if ($major -lt 22) {
    return $false, @"
Node.js 版本过低：当前 v$major.x，DeepSeek Harness 需要 >= 22。
升级: 到 https://nodejs.org 下载新版 (推荐 nvm-windows: nvm install 22 && nvm use 22)。
"@
  }
  return $true, ''
}

function Write-EnvError {
  param([string]$Message)
  if ($ErrFile) { try { $Message | Set-Content -Path $ErrFile -Encoding UTF8 } catch { } }
  Write-Host $Message
  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    [System.Windows.Forms.MessageBox]::Show($Message, 'DSH Harness - 环境检查未通过',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
  } catch { }
}

function Get-PidFromFile {
  if (Test-Path $PidFile) {
    $raw = (Get-Content $PidFile -Raw).Trim()
    if ($raw -match '^\d+$') { return [int]$raw }
  }
  return $null
}

function Get-ListenerPid {
  param([int]$CheckPort)
  $conn = Get-NetTCPConnection -State Listen -LocalPort $CheckPort -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($conn) { return [int]$conn.OwningProcess }
  return $null
}

function Test-ProcessAlive {
  param([int]$Id)
  return [bool](Get-Process -Id $Id -ErrorAction SilentlyContinue)
}

function Write-Status {
  $pidFromFile = Get-PidFromFile
  $listener = Get-ListenerPid -CheckPort $Port
  if ($listener) {
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$listener" -ErrorAction SilentlyContinue
    Write-Host "RUNNING  http://$BindHost`:$Port   (PID $listener)"
    if ($proc) {
      Write-Host ("         started {0}" -f $proc.CreationDate)
      Write-Host "         cmd: $($proc.CommandLine)"
    }
    if ($pidFromFile -and $pidFromFile -ne $listener) {
      Write-Host "WARN     pid file says $pidFromFile but the port listener is $listener"
    }
  }
  elseif ($pidFromFile) {
    Write-Host "STOPPED  (stale pid file: $pidFromFile)"
  }
  else {
    Write-Host "STOPPED  (no listener on port $Port)"
  }
}

function Rotate-Logs {
  # 启动前轮转日志：保留 .1（最近一次）、.2（更早一次），防止无限膨胀
  foreach ($f in @($LogFile, $ErrFile)) {
    if (-not (Test-Path $f)) { continue }
    if (Test-Path "$f.2") { Remove-Item "$f.2" -Force }
    if (Test-Path "$f.1") { Move-Item "$f.1" "$f.2" -Force }
    Move-Item $f "$f.1" -Force
  }
}

function Open-GuiBrowser {
  Start-Process "http://$BindHost`:$Port"
}

function Start-Harness {
  if (Get-ListenerPid -CheckPort $Port) {
    Write-Host "already running on port $Port (see: $PidFile)"
    if ($OpenBrowser) { Open-GuiBrowser }
    return
  }
  Rotate-Logs
  # 环境检查: Node >= 22 (直接跑脚本的用户也能得到明确提示)
  $envOk, $envMsg = Test-NodeEnvironment
  if (-not $envOk) {
    Write-EnvError -Message $envMsg
    throw $envMsg
  }
  if (-not $Bin -or -not (Test-Path $Bin)) {
    $msg = @"
dsh CLI not found: $Bin
Resolve it by any of:
  1) run  npm install  in this directory (installs @deepseek-ai/dsh), or
  2) install globally:  npm i -g @deepseek-ai/dsh, or
  3) copy this script into your dsh deployment directory
     (the one containing node_modules\@deepseek-ai\dsh), or
  4) pass -DshBin <path-to-dsh>\lib\bin.js explicitly.
"@
    Write-EnvError -Message $msg
    throw $msg
  }

  $node = Get-NodePath
  $nodeArgs = @($Bin, 'web', '--host', $BindHost, '--port', "$Port")
  foreach ($th in $TrustedHost) { $nodeArgs += @('--trusted-host', $th) }
  $nodeArgs = $nodeArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }

  if ($Console) {
    $p = Start-Process -FilePath $node -ArgumentList $nodeArgs -PassThru
  }
  else {
    $p = Start-Process -FilePath $node -ArgumentList $nodeArgs -WindowStyle Hidden `
      -RedirectStandardOutput $LogFile -RedirectStandardError $ErrFile -PassThru
  }
  Set-Content -Path $PidFile -Value $p.Id

  $deadline = (Get-Date).AddSeconds(45)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    if (Get-ListenerPid -CheckPort $Port) { break }
    if ($p.HasExited) {
      Write-Host "process exited early (code $($p.ExitCode)); tail of $ErrFile :"
      if (Test-Path $ErrFile) { Get-Content $ErrFile -Tail 10 }
      return
    }
  }
  Start-Sleep -Milliseconds 800
  if (Get-ListenerPid -CheckPort $Port) {
    Write-Host "STARTED  http://$BindHost`:$Port   (PID $($p.Id))"
    if ($OpenBrowser) { Open-GuiBrowser }
  }
  else {
    Write-Host "started PID $($p.Id) but no listener yet; check $ErrFile"
  }
}

function Stop-Harness {
  $listener = Get-ListenerPid -CheckPort $Port
  $pidFromFile = Get-PidFromFile
  $targets = @()
  if ($pidFromFile -and (Test-ProcessAlive -Id $pidFromFile)) { $targets += $pidFromFile }
  if ($listener -and ($listener -notin $targets)) { $targets += $listener }
  if ($targets.Count -eq 0) {
    Write-Host "nothing running on port $Port"
    if (Test-Path $PidFile) { Remove-Item $PidFile -Force }
    return
  }
  foreach ($t in ($targets | Select-Object -Unique)) {
    Write-Host "stopping PID $t ..."
    Stop-Process -Id $t -Force -ErrorAction SilentlyContinue
  }
  Start-Sleep -Milliseconds 600
  if (Test-Path $PidFile) { Remove-Item $PidFile -Force }
  if (Get-ListenerPid -CheckPort $Port) {
    Write-Host "WARN  port $Port still has a listener"
  }
  else {
    Write-Host "STOPPED"
  }
}

function Show-Logs {
  Write-Host "log: $LogFile"
  Write-Host "err: $ErrFile"
  Write-Host "--- $LogFile (tail $Tail) ---"
  if (Test-Path $LogFile) { Get-Content $LogFile -Tail $Tail } else { Write-Host '(not created yet)' }
  Write-Host "--- $ErrFile (tail $Tail) ---"
  if (Test-Path $ErrFile) { Get-Content $ErrFile -Tail $Tail } else { Write-Host '(not created yet)' }
  if ($Follow) {
    Write-Host "--- following $LogFile (Ctrl+C to stop) ---"
    Get-Content $LogFile -Tail $Tail -Wait
  }
}

# --- dispatch ----------------------------------------------------------------
switch ($Action) {
  'start'   { Start-Harness }
  'stop'    { Stop-Harness }
  'status'  { Write-Status | Out-Null }
  'restart' { Stop-Harness; Start-Sleep -Milliseconds 800; Start-Harness }
  'logs'    { Show-Logs }
}
