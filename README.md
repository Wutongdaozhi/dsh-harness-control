# dsh-harness-control

> DeepSeek Harness **后台 GUI** 的一键启动与管理工具（Windows）
>
> 启动 · 停止 · 重启 · 端口设置 · 系统托盘可视化控制
>
> *One-click launch & management for the DeepSeek Harness web GUI on Windows.*

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE) · [English](README.en.md)

## 这是什么

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 是 DeepSeek 开源的 AI 代理工作台。它以**浏览器后台界面（Web GUI）**的形式跑在你本机：在网页里和 DeepSeek 模型对话，让它操作文件、执行命令、调用工具、调度子代理，完成一个完整的任务闭环。

```
你 ──浏览器──> http://127.0.0.1:8081（后台 GUI）──> DeepSeek 模型 + 工具 + 插件
```

但 `dsh web` 本身是个**前台进程**：没有守护模式，官方也没有停止命令——关终端就没了，开一个又一个黑窗口。本仓库把这套 GUI 变成"像普通软件一样"管理的东西：**说启动就启动、说关就关、说换端口就换端口**。

## 界面预览

![系统托盘右键菜单（启动/停止/重启/端口设置）](docs/tray-menu.png)

## 快速开始（装好以后，怎么用）

### 第一步：安装

```powershell
git clone https://github.com/Wutongdaozhi/dsh-harness-control.git
cd dsh-harness-control
npm install                       # 安装 @deepseek-ai/dsh
```
然后**双击 `install.cmd`** 即可在桌面创建快捷方式（无需命令行；`install.ps1` 等价）。
（已有 dsh 部署的用户可跳过 clone/npm install，直接拷贝脚本，见 [已有部署](#已有部署方式b)）

### 第二步：桌面快捷方式（唯一入口）

安装后桌面生成**一个图标「DSH Harness」**，双击一下全搞定：

```
双击「DSH Harness」
  ├─ 后台 GUI 未运行 → 自动启动
  ├─ 浏览器自动打开 → http://127.0.0.1:8081
  └─ 系统托盘同时就位（右下角鲸鱼图标）
```

之后**全用托盘右键菜单管理**：停止 / 重启 / 端口设置 / 打开界面，不用再碰桌面图标。

### 第三步：日常使用流程

```
开机 → 双击「DSH Harness」→ 浏览器进入后台 GUI，托盘就位
     → 用完后托盘右键「停止」
```

## 后台 GUI 里能做什么

- **代理对话**：与 DeepSeek 模型对话，代理自动规划并调用工具（文件读写、命令执行、网页搜索、子代理、工作流……）
- **会话持久化**：会话数据存本机 `$env:DSH_HOME\sessions`，重启 GUI 后刷新页面，历史会话与进行中的任务都能恢复
- **插件体系**：侧边栏可安装插件，如 SSH 远程运维、任务看板（定时任务）、右侧文件/预览/变更面板等
- **设置**：模型选择、界面主题、权限策略等

## 管理后台 GUI

### 桌面快捷方式（唯一入口）

双击「DSH Harness」= 启动（未运行则自动拉起）+ 自动打开浏览器 + 托盘就位，一步到位。
托盘只会有一个实例（重复双击不会重复开启）。

### 系统托盘（后台管理）

右键菜单：**启动 · 停止 · 重启 · 端口设置… · 打开界面 · 查看日志… · 开机自启 · 检查更新… · 退出托盘**
（"退出托盘"只关托盘，不停 GUI；悬停看实时状态，双击直接打开网页；端口设置存 `$env:DSH_HOME\dsh-web\tray-config.json`，改完点重启生效）

托盘图标会随状态变色：**运行中 = 蓝色鲸鱼，停止 = 灰色鲸鱼**，一眼可知 GUI 是否在线。
「开机自启」菜单项带 ✓ 显示当前状态，开启前会询问确认（与 `install.ps1 -AutoStart` 一致）。
「检查更新…」打开 GitHub Releases 页，方便跟进新版本。

### 命令行（高级）

```powershell
.\dsh-web.ps1 status                    # 看状态（默认端口 8081）
.\dsh-web.ps1 start                     # 后台启动（隐藏窗口，日志写文件）
.\dsh-web.ps1 start -Port 9000          # 换端口启动
.\dsh-web.ps1 start -OpenBrowser        # 启动后自动打开浏览器
.\dsh-web.ps1 start -Console            # 前台窗口模式，Ctrl+C 即停
.\dsh-web.ps1 restart -Port 9000        # 停止并换端口重启
.\dsh-web.ps1 stop                      # 停止（会关闭 GUI，会话数据在磁盘上）
.\dsh-web.ps1 logs                      # 查看最近日志
.\dsh-web.ps1 logs -Tail 200 -Follow    # 跟踪日志输出（Ctrl+C 停止）
```

或 npm 快捷方式：`npm start` / `npm stop` / `npm status` / `npm restart` / `npm run logs`（端口固定为脚本默认值 8081）。

### 端口设置（三种方式）

| 方式 | 说明 |
|---|---|
| 命令行 `-Port` / `--port` | 一次性：`.\dsh-web.ps1 start -Port 9000` 或 `dsh web --port 9000` |
| 托盘「端口设置…」 | 可视化，记住到配置文件 |
| 修改 profile 配置 | 永久默认：编辑 `$env:DSH_HOME\profiles\web\cordis.patch.yml`，加 `port: 9000`，之后裸 `dsh web` 即用该端口 |

> 注意：`dsh web --host 0.0.0.0` 被 dsh 故意禁止（防止远程代码执行暴露到网络），GUI 只能本机回环访问；需要局域网访问请自行评估风险后再开代理转发。

### 已有部署（方式 B）

如果你已经有一个 `npm install @deepseek-ai/dsh` 的目录（比如 `F:\xxx`），把本仓库的 `dsh-web.ps1`、`dsh-tray.ps1`、`dsh-tray.cmd`、`dsh-tray.ico`、`install.ps1` 拷进该目录，然后运行 `.\install.ps1` 创建桌面快捷方式即可；脚本会自动在 `node_modules\@deepseek-ai\dsh\lib\bin.js` 找到 dsh（也可用 `-DshBin` 显式指定）。

### 开机自启（可选）

- **托盘菜单「开机自启」**：带 ✓ 显示当前状态，开启前询问确认
- 或命令行：

```powershell
.\install.ps1 -AutoStart        # 登录时自动启动托盘（会先询问确认）
.\install.ps1 -AutoStart -Yes   # 跳过确认直接启用（脚本化场景）
.\install.ps1 -RemoveAutoStart  # 取消开机自启
```

> 开机自启会改变系统行为（每次登录自动运行托盘并拉起 GUI），**启用前必须经过你确认同意**；取消随时可执行 `-RemoveAutoStart` 或托盘菜单取消勾选。

### 卸载

```powershell
.\uninstall.ps1        # 移除桌面快捷方式、开机自启项；删除状态目录前会询问确认
```
或直接**双击 `uninstall.cmd`**（效果相同）。

## 工作原理

- `dsh web` 就是个 Node 前台进程；`dsh-web.ps1` 用 `Start-Process` 以隐藏窗口拉起，PID 写入 `$env:DSH_HOME\dsh-web\dsh-web.pid`，日志在 `dsh-web.log` / `dsh-web.err.log`
- `stop` 通过 PID 文件（找不到则按端口找监听进程）停止
- 会话数据在 `$env:DSH_HOME\sessions`，GUI 重启后刷新页面即可恢复

## 常见问题

- **双击 `.ps1` 打开的是记事本** — `.ps1` 默认不执行；需要双击的场景都已配好 `.cmd` 版本（`dsh-tray.cmd` / `install.cmd` / `uninstall.cmd`）或桌面快捷方式（内部已带 `-ExecutionPolicy Bypass`）
- **`stop` 把网页关掉了** — 这是"停止 GUI"的本意；重新 `start` 后刷新页面即恢复会话
- **端口被占用** — 换 `-Port` 或用托盘改端口；`--port 0` 可让系统随机分配（`status` 会显示实际端口）
- **想开机自启** — `.\install.ps1 -AutoStart`（启动文件夹方案）；取消用 `-RemoveAutoStart`
- **托盘图标不刷新** — 右键「退出托盘」重新启动一次（Windows 图标缓存）
- **找不到 dsh** — 确认已在脚本同目录 `npm install @deepseek-ai/dsh`，或用 `-DshBin` 指定 `bin.js` 路径

## 目录结构

```
dsh-harness-control/
├── dsh-web.ps1          # CLI 控制器（start/stop/status/restart/logs）
├── dsh-tray.ps1         # 系统托盘控制器（含一键启动+自动开浏览器）
├── dsh-tray.cmd         # 双击启动器（启动托盘）
├── install.cmd          # 双击安装（创建桌面快捷方式）
├── uninstall.cmd        # 双击卸载（快捷方式/自启项/状态目录）
├── dsh-tray.ico         # 运行态蓝色鲸鱼图标（可删，用 make-tray-icon.cjs 重新生成）
├── dsh-tray-off.ico     # 停止态灰色鲸鱼图标
├── make-tray-icon.cjs   # 图标生成器（node make-tray-icon.cjs [输出] [颜色]）
├── install.ps1          # 桌面快捷方式 + 开机自启安装脚本
├── uninstall.ps1        # 卸载脚本（快捷方式/自启项/状态目录）
├── package.json         # npm scripts + @deepseek-ai/dsh 依赖
├── docs/tray-menu.png   # 托盘菜单截图
├── .github/workflows/   # CI：BOM/语法/PSScriptAnalyzer 检查
├── README.md / README.en.md
└── LICENSE / .gitignore / .gitattributes
```

## 许可

MIT。托盘图标素材取自 MIT 许可的 [`@deepseek-ai/dsh-web-frontend`](https://www.npmjs.com/package/@deepseek-ai/dsh-web-frontend) 包中的 `favicon.svg`；DeepSeek 标识归其权利人所有，商用前请自行确认品牌使用规范。不喜欢可删除 `dsh-tray.ico`，托盘自动回退默认图标。
