# dsh-harness-control

> DeepSeek Harness **后台 GUI** 的一键启动与管理工具（Windows）
>
> 启动 · 停止 · 重启 · 端口设置 · 系统托盘可视化控制
>
> *One-click launch & management for the DeepSeek Harness web GUI on Windows.*

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## 这是什么

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 是 DeepSeek 开源的 AI 代理工作台。它以**浏览器后台界面（Web GUI）**的形式跑在你本机：在网页里和 DeepSeek 模型对话，让它操作文件、执行命令、调用工具、调度子代理，完成一个完整的任务闭环。

```
你 ──浏览器──> http://127.0.0.1:8081（后台 GUI）──> DeepSeek 模型 + 工具 + 插件
```

但 `dsh web` 本身是个**前台进程**：没有守护模式，官方也没有停止命令——关终端就没了，开一个又一个黑窗口。本仓库把这套 GUI 变成"像普通软件一样"管理的东西：**说启动就启动、说关就关、说换端口就换端口**。

## 界面预览

> 这里放两张截图：
> 1. **后台 GUI 主界面**（会话列表 + 聊天区 + 侧边栏插件）
> 2. **系统托盘菜单**（右键 启动/停止/重启/端口设置）

## 快速开始（30 秒跑起后台 GUI）

```powershell
git clone https://github.com/Wutongdaozhi/dsh-harness-control.git
cd dsh-harness-control
npm install                       # 安装 @deepseek-ai/dsh
.\dsh-web.ps1 start               # 后台启动 GUI
```

启动后浏览器打开 **http://127.0.0.1:8081** 即可进入后台 GUI。
（也可以不 clone，直接把你已有的 dsh 部署目录当成工作目录，见 [已有部署](#已有部署方式b)）

## 后台 GUI 里能做什么

- **代理对话**：与 DeepSeek 模型对话，代理自动规划并调用工具（文件读写、命令执行、网页搜索、子代理、工作流……）
- **会话持久化**：会话数据存本机 `$env:DSH_HOME\sessions`，重启 GUI 后刷新页面，历史会话与进行中的任务都能恢复
- **插件体系**：侧边栏可安装插件，如 SSH 远程运维、任务看板（定时任务）、右侧文件/预览/变更面板等
- **设置**：模型选择、界面主题、权限策略等

## 管理后台 GUI（本仓库的核心）

### 命令行

```powershell
.\dsh-web.ps1 status                    # 看状态（默认端口 8081）
.\dsh-web.ps1 start                     # 后台启动（隐藏窗口，日志写文件）
.\dsh-web.ps1 start -Port 9000          # 换端口启动
.\dsh-web.ps1 start -Console            # 前台窗口模式，Ctrl+C 即停
.\dsh-web.ps1 restart -Port 9000        # 停止并换端口重启
.\dsh-web.ps1 stop                      # 停止（会关闭 GUI，会话数据在磁盘上）
```

或 npm 快捷方式：`npm start` / `npm stop` / `npm status` / `npm restart`（端口固定为脚本默认值 8081）。

### 系统托盘（可视化）

```powershell
.\dsh-tray.ps1          # 或双击 dsh-tray.cmd / 桌面快捷方式（install.ps1 一键创建）
```

右键菜单：**启动 · 停止 · 重启 · 端口设置… · 打开界面 · 退出托盘**
（"退出托盘"只关托盘，不停 GUI；悬停看实时状态，双击直接打开网页；端口设置存 `$env:DSH_HOME\dsh-web\tray-config.json`，改完点重启生效）

### 端口设置（三种方式）

| 方式 | 说明 |
|---|---|
| 命令行 `-Port` / `--port` | 一次性：`.\dsh-web.ps1 start -Port 9000` 或 `dsh web --port 9000` |
| 托盘「端口设置…」 | 可视化，记住到配置文件 |
| 修改 profile 配置 | 永久默认：编辑 `$env:DSH_HOME\profiles\web\cordis.patch.yml`，加 `port: 9000`，之后裸 `dsh web` 即用该端口 |

> 注意：`dsh web --host 0.0.0.0` 被 dsh 故意禁止（防止远程代码执行暴露到网络），GUI 只能本机回环访问；需要局域网访问请自行评估风险后再开代理转发。

### 已有部署（方式 B）

如果你已经有一个 `npm install @deepseek-ai/dsh` 的目录（比如 `F:\xxx`），把本仓库的 `dsh-web.ps1`、`dsh-tray.ps1`、`dsh-tray.cmd`、`dsh-tray.ico` 拷进该目录即可；脚本会自动在 `node_modules\@deepseek-ai\dsh\lib\bin.js` 找到 dsh（也可用 `-DshBin` 显式指定）。

## 工作原理

- `dsh web` 就是个 Node 前台进程；`dsh-web.ps1` 用 `Start-Process` 以隐藏窗口拉起，PID 写入 `$env:DSH_HOME\dsh-web\dsh-web.pid`，日志在 `dsh-web.log` / `dsh-web.err.log`
- `stop` 通过 PID 文件（找不到则按端口找监听进程）停止
- 会话数据在 `$env:DSH_HOME\sessions`，GUI 重启后刷新页面即可恢复

## 常见问题

- **双击 `.ps1` 打开的是记事本** — 用 `dsh-tray.cmd` 或桌面快捷方式（内部已带 `-ExecutionPolicy Bypass`）
- **`stop` 把网页关掉了** — 这是"停止 GUI"的本意；重新 `start` 后刷新页面即恢复会话
- **端口被占用** — 换 `-Port` 或用托盘改端口；`--port 0` 可让系统随机分配
- **托盘图标不刷新** — 右键「退出托盘」重新启动一次（Windows 图标缓存）
- **找不到 dsh** — 确认已在脚本同目录 `npm install @deepseek-ai/dsh`，或用 `-DshBin` 指定 `bin.js` 路径

## 目录结构

```
dsh-harness-control/
├── dsh-web.ps1          # CLI 控制器（start/stop/status/restart）
├── dsh-tray.ps1         # 系统托盘控制器
├── dsh-tray.cmd         # 双击启动器
├── dsh-tray.ico         # DeepSeek 鲸鱼图标（可删，用 make-tray-icon.cjs 重新生成）
├── make-tray-icon.cjs   # 图标生成器（node make-tray-icon.cjs [输出] [颜色]）
├── install.ps1          # 桌面快捷方式安装脚本
├── package.json         # npm scripts + @deepseek-ai/dsh 依赖
└── README.md
```

## 许可

MIT。托盘图标素材取自 MIT 许可的 [`@deepseek-ai/dsh-web-frontend`](https://www.npmjs.com/package/@deepseek-ai/dsh-web-frontend) 包中的 `favicon.svg`；DeepSeek 标识归其权利人所有，商用前请自行确认品牌使用规范。不喜欢可删除 `dsh-tray.ico`，托盘自动回退默认图标。
