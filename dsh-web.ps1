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

.NOTES
  - Stopping the harness kills the Web GUI, including any live session.
  - --host 0.0.0.0 is intentionally rejected by dsh itself for safety;
    the GUI is loopback-only by design.
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet('start', 'stop', 'status', 'restart')]
  [string]$Action = 'status',

  [int]$Port = 8081,

  [ValidateSet('127.0.0.1', '0.0.0.0')]
  [string]$BindHost = '127.0.0.1',

  [string[]]$TrustedHost = @(),

  [string]$DshBin = '',

  [switch]$Console
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

# --- locate the dsh CLI (portable: -DshBin > repo node_modules > PATH) --------
if ($DshBin -and (Test-Path $DshBin)) {
  $Bin = $DshBin
}
else {
  $Bin = Join-Path $DeployRoot 'node_modules\@deepseek-ai\dsh\lib\bin.js'
  if (-not (Test-Path $Bin)) {
    $dshCmd = Get-Command dsh -ErrorAction SilentlyContinue
    if ($dshCmd) {
      $candidate = [System.IO.Path]::GetFullPath((Join-Path (Split-Path $dshCmd.Source) '..\@deepseek-ai\dsh\lib\bin.js'))
      if (Test-Path $candidate) { $Bin = $candidate }
    }
  }
}

# --- helpers -----------------------------------------------------------------
function Get-NodePath {
  $cmd = Get-Command node -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw 'node was not found on PATH'
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

function Start-Harness {
  if (Get-ListenerPid -CheckPort $Port) {
    Write-Host "already running on port $Port (see: $PidFile)"
    return
  }
  if (-not (Test-Path $Bin)) {
    throw @"
dsh CLI not found: $Bin
Resolve it by any of:
  1) run  npm install @deepseek-ai/dsh  in this directory, or
  2) copy this script into your dsh deployment directory
     (the one containing node_modules\@deepseek-ai\dsh), or
  3) pass -DshBin <path-to-dsh>\lib\bin.js explicitly.
"@
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

# --- dispatch ----------------------------------------------------------------
switch ($Action) {
  'start'   { Start-Harness }
  'stop'    { Stop-Harness }
  'status'  { Write-Status | Out-Null }
  'restart' { Stop-Harness; Start-Sleep -Milliseconds 800; Start-Harness }
}
