# dsh-harness-control

> 在 Windows 上方便地管理 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) Web GUI：
> 命令行启停 + 系统托盘可视化控制 + 端口设置。
>
> *Manage the DeepSeek Harness Web GUI on Windows — CLI start/stop/status/restart, a system-tray controller, and port control.*

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## 这是什么

DeepSeek Harness 的 `dsh web` 是一个**前台进程**（没有 daemon/守护模式），官方也没有提供 stop 命令。
本仓库提供一套轻量工具，把它变成"想开就开、想关就关"的服务：

- **`dsh-web.ps1`** — 命令行控制器：`start / stop / status / restart`，支持 `-Port` 换端口、`-Console` 前台窗口模式
- **`dsh-tray.ps1`** — 系统托盘可视化控制器：右键菜单 启动/停止/重启/端口设置/打开界面/退出，悬停看实时状态，双击打开网页
- **`dsh-tray.cmd`** — 可双击的托盘启动器（绕过 `.ps1` 双击被记事本打开、执行策略拦截的问题）
- **`install.ps1`** — 一键创建桌面快捷方式（双击即启动托盘）
- **`make-tray-icon.cjs`** — 从 dsh 自带前端资源生成 DeepSeek 鲸鱼图标（多尺寸 `.ico`）

## 环境要求

- Windows 10/11
- PowerShell 5.1+（Windows 自带）或 PowerShell 7
- Node.js 18+（运行 dsh 需要）

## 安装

### 方式 A：全新部署（推荐）

```powershell
git clone https://github.com/<you>/dsh-harness-control.git
cd dsh-harness-control
npm install                       # 安装 @deepseek-ai/dsh 本体
.\install.ps1                     # 可选：创建桌面快捷方式
.\dsh-web.ps1 start               # 启动！
```

### 方式 B：已有 dsh 部署

如果你已经在某个目录 `npm install @deepseek-ai/dsh` 了（比如 `F:\xxx\node_modules\@deepseek-ai\dsh`），
把 `dsh-web.ps1`、`dsh-tray.ps1`、`dsh-tray.cmd`、`dsh-tray.ico` 拷进那个目录即可；
脚本会自动在 `node_modules\@deepseek-ai\dsh\lib\bin.js` 找到 dsh（也可用 `-DshBin` 显式指定）。

## 快速开始

### 命令行

```powershell
.\dsh-web.ps1 status                    # 看状态（默认端口 8081）
.\dsh-web.ps1 start                     # 后台启动（隐藏窗口，日志写文件）
.\dsh-web.ps1 start -Port 9000          # 换端口启动
.\dsh-web.ps1 start -Console            # 前台窗口模式，Ctrl+C 即停
.\dsh-web.ps1 restart -Port 9000        # 停止并换端口重启
.\dsh-web.ps1 stop                      # 停止（会关闭 Web GUI，会话数据在磁盘上）
```

或 npm 快捷方式：`npm start` / `npm stop` / `npm status` / `npm restart`（端口固定为脚本默认值）。

### 系统托盘（可视化）

```powershell
.\dsh-tray.ps1          # 或双击 dsh-tray.cmd / 桌面快捷方式
```

右键菜单：**启动 · 停止 · 重启 · 端口设置… · 打开界面 · 退出托盘**
（"退出托盘"只关托盘，不停 harness；端口设置存 `$env:DSH_HOME\dsh-web\tray-config.json`，改完点重启生效）

### 端口设置（三种方式）

| 方式 | 说明 |
|---|---|
| 命令行 `-Port` / `--port` | 一次性：`dsh web --port 9000` 或 `.\dsh-web.ps1 start -Port 9000` |
| 托盘「端口设置…」 | 可视化，记住到配置文件 |
| 修改 profile 配置 | 永久默认：编辑 `$env:DSH_HOME\profiles\web\cordis.patch.yml`，加 `port: 9000`，之后裸 `dsh web` 即用该端口 |

> 注意：`dsh web --host 0.0.0.0` 被 dsh 故意禁止（防止远程代码执行暴露到网络），GUI 只能本机回环访问。

## 工作原理

- dsh 本身就是个 Node 前台进程；`dsh-web.ps1` 用 `Start-Process` 以隐藏窗口方式拉起，PID 写入 `$env:DSH_HOME\dsh-web\dsh-web.pid`，日志在 `dsh-web.log` / `dsh-web.err.log`
- `stop` 通过 PID 文件（找不到则按端口找监听进程）停止
- 会话数据存在 `$env:DSH_HOME\sessions`，harness 重启后网页刷新即可恢复之前的会话

## 常见问题

- **双击 `.ps1` 打开的是记事本** — 用 `dsh-tray.cmd` 或桌面快捷方式，内部已带 `-ExecutionPolicy Bypass`
- **托盘图标不刷新** — 右键「退出托盘」重新启动一次（Windows 图标缓存）
- **`stop` 把网页关掉了** — 这是"停止 harness"的本意；重新 `start` 后刷新页面即恢复会话
- **端口被占用** — 换 `-Port` 或用托盘改端口；`--port 0` 可让系统随机分配
- **找不到 dsh** — 确认已在脚本同目录 `npm install @deepseek-ai/dsh`，或用 `-DshBin` 指定 `bin.js` 路径

## 目录结构

```
dsh-harness-control/
├── dsh-web.ps1          # CLI 控制器
├── dsh-tray.ps1         # 系统托盘控制器
├── dsh-tray.cmd         # 双击启动器
├── dsh-tray.ico         # DeepSeek 鲸鱼图标（可删，用 make-tray-icon.cjs 重新生成）
├── make-tray-icon.cjs   # 图标生成器（node make-tray-icon.cjs [输出] [颜色]）
├── install.ps1          # 桌面快捷方式安装脚本
├── package.json         # npm scripts + @deepseek-ai/dsh 依赖
└── README.md
```

## 许可

MIT。托盘图标素材取自 MIT 许可的 [`@deepseek-ai/dsh-web-frontend`](https://www.npmjs.com/package/@deepseek-ai/dsh-web-frontend) 包中的 `favicon.svg`；
DeepSeek 标识归其权利人所有，商用前请自行确认品牌使用规范。不喜欢可删除 `dsh-tray.ico`，托盘自动回退默认图标。
