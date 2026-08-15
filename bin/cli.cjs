#!/usr/bin/env node
// dsh-harness-control CLI — thin Node wrapper that forwards to the PowerShell scripts.
// Lets you use the tool via `npx dsh-harness-control <command>` or a global install.
const { spawn } = require('child_process');
const path = require('path');

const COMMANDS = {
  start:     { script: 'dsh-web.ps1' },
  stop:      { script: 'dsh-web.ps1' },
  status:    { script: 'dsh-web.ps1' },
  restart:   { script: 'dsh-web.ps1' },
  logs:      { script: 'dsh-web.ps1' },
  tray:      { script: 'dsh-tray.ps1', detached: true },
  install:   { script: 'install.ps1' },
  uninstall: { script: 'uninstall.ps1' },
};

function printHelp() {
  console.log(`dsh-harness-control — manage the DeepSeek Harness web GUI (Windows)

Usage: dsh-harness-control <command> [options...]

Commands:
  start      start the GUI (pass through: -Port 9000, -Console, -OpenBrowser, -DshBin)
  stop       stop the GUI
  restart    stop, then start
  status     show status
  logs       show recent logs (-Tail N, -Follow)
  tray       start the system tray (detached background)
  install    create the desktop shortcut
  uninstall  remove shortcut / autostart / state dir

Options are forwarded verbatim to the underlying PowerShell scripts.
`);
}

function main() {
  const args = process.argv.slice(2);
  const cmd = args[0];
  if (!cmd || cmd === '-h' || cmd === '--help' || cmd === 'help') {
    printHelp();
    process.exit(cmd && cmd !== '-h' && cmd !== '--help' && cmd !== 'help' ? 1 : 0);
  }
  const entry = COMMANDS[cmd];
  if (!entry) {
    console.error(`unknown command: ${cmd}  (run: dsh-harness-control --help)`);
    process.exit(1);
  }
  const script = path.join(__dirname, '..', entry.script);
  if (!require('fs').existsSync(script)) {
    console.error(`script not found: ${script}`);
    console.error('This looks like a broken install. Reinstall with:  npm i -g dsh-harness-control');
    process.exit(1);
  }
  const ps = spawn('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, ...args.slice(1)], {
    stdio: entry.detached ? 'ignore' : 'inherit',
    detached: !!entry.detached,
    windowsHide: true,
  });
  ps.on('error', (err) => {
    console.error(`failed to start PowerShell: ${err.message}`);
    console.error('Check that Windows PowerShell is installed and available on PATH.');
    process.exit(1);
  });
  if (entry.detached) {
    ps.unref();
    process.exit(0);
  }
  ps.on('exit', (code) => process.exit(code == null ? 1 : code));
}

main();
