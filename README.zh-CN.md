<div align="center">

# WinSplitPane

### 让 Claude Code Agent Teams 在 Windows 上用上 Split Panes 🪟

*A lightweight tmux shim that bridges Claude Code's split pane system to WezTerm on Windows.*

[![Go Version](https://img.shields.io/badge/Go-1.22+-00ADD8?style=flat&logo=go)](https://go.dev/)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078D4?style=flat&logo=windows)](https://github.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

</div>

---

## 🤔 为什么需要这个？

Claude Code 的 Agent Team 模式支持通过 **Split Panes** 同时运行多个 AI agent，每个 agent 占据一个独立的面板。但这个功能依赖 `tmux` 或 `iTerm2`，**Windows 上都不支持**。

**WinSplitPane** 是一个轻量级的 `tmux` 替代品（shim），它：
- 拦截 Claude Code 对 `tmux` 的所有调用
- 翻译成 [WezTerm](https://wezfurlong.org/wezterm/) CLI 操作
- 让 Split Panes 在 Windows 上完美工作 ✨

```
Claude Code                  WinSplitPane               WezTerm
    │                            │                          │
    │── tmux split-window ──────►│── wezterm cli split ────►│  ┌──────┬──────┐
    │── tmux send-keys ─────────►│── wezterm cli send ────►│  │agent1│agent2│
    │── tmux list-panes ────────►│── wezterm cli list ────►│  │      │      │
    │── tmux kill-pane ─────────►│── wezterm cli kill ────►│  └──────┴──────┘
```

---

## ✅ 效果展示

Claude Code 创建 Agent Team 时，WezTerm 窗口会自动分屏：
- 🔵 主 agent 面板（左侧）
- 🟢 🟡 🔴 子 agent 面板（右侧，可多个）
- 每个 agent 独立运行，实时可见

---

## 📋 前提条件

| 依赖 | 说明 |
|------|------|
| **Windows 10/11** | 操作系统 |
| **WezTerm** | 终端模拟器（[官网下载](https://wezfurlong.org/wezterm/) 或使用内置 portable 版本） |
| **Claude Code CLI** | `claude` 命令行工具 ([安装指南](https://docs.anthropic.com/en/docs/claude-code)) |
| **Go 1.22+**（可选）| 仅从源码构建时需要，否则使用预编译的 `tmux.exe` |

---

## 🚀 快速开始

### 方式一：直接下载 Release（推荐）

1. 从 [Releases](../../releases) 下载最新 ZIP
2. 解压到任意目录
3. 确保已安装 [WezTerm](https://wezfurlong.org/wezterm/)
4. 双击 `setup.cmd`

### 方式二：从源码构建

```powershell
git clone https://github.com/yourname/WinSplitPane.git
cd WinSplitPane

# 一键安装（构建 + 创建桌面快捷方式）
.\setup.cmd
```

### 方式三：手动安装

```powershell
# 1. 构建 tmux shim
go build -o .\.bin\tmux.exe .\cmd\tmux

# 2. 安装桌面快捷方式（可选）
.\install-shortcut.cmd

# 3. 启动 Claude
.\start-claude.cmd
```

---

## 🎮 使用方法

### 启动 Claude

双击桌面上的 **"Claude (WinSplitPane)"** 快捷方式，或运行：

```powershell
.\start-claude.cmd
```

### 创建 Agent Team

在 Claude Code 中，正常使用 Agent Team 功能即可：

```
> 创建一个 agent team 来分析项目代码
```

Claude 会自动：
1. 检测到 tmux 环境（我们的 shim）
2. 用 `split-window` 创建新面板
3. 每个 agent 在独立面板中运行
4. 任务完成后 `kill-pane` 清理

---

## 🏗️ 项目结构

```
WinSplitPane/
├── cmd/tmux/main.go          # 入口，解析 argv 分发命令
├── internal/
│   ├── app/app.go            # 核心命令处理（split, send-keys, list-panes 等）
│   ├── backend/wezterm/      # WezTerm CLI 适配层
│   ├── state/store.go        # Pane 状态持久化
│   └── logging/logger.go     # 日志（用于调试）
├── scripts/
│   ├── start-claude.ps1      # 启动 Claude
│   ├── start-wezterm.ps1     # 启动 WezTerm（设置环境变量）
│   ├── install.ps1           # 构建 + 配置
│   ├── install-shortcut.ps1  # 创建桌面快捷方式
│   └── (install / start scripts)
├── .tools/wezterm/           # WezTerm portable（可选）
│   └── portable.wezterm.lua  # 便携配置
├── setup.cmd                 # 一键安装
├── start-claude.cmd          # 双击启动 Claude
├── install-shortcut.cmd      # 双击安装快捷方式
└── docs/setup-windows.md     # 详细文档
```

---

## 🔧 技术实现

### 支持的 tmux 命令

| 命令 | 实现方式 | 说明 |
|------|----------|------|
| `split-window` | `wezterm cli split-pane` | 支持水平/垂直、百分比大小 |
| `send-keys` | `wezterm cli send-text` | 向指定面板发送文本 |
| `list-panes` | `wezterm cli list` | 列出面板（支持 session:window 过滤） |
| `kill-pane` | `wezterm cli kill-pane` | 关闭面板 |
| `display-message` | 格式化输出 | 支持 `#{pane_id}`, `#{session_name}` 等变量 |
| `capture-pane` | `wezterm cli get-text` | 读取面板内容 |
| `select-pane` | `wezterm cli activate-pane` | 激活面板 |
| `has-session` | `wezterm cli` | 检查连通性 |
| `set-option` | no-op | 兼容但不报错 |
| `select-layout` | no-op | 兼容但不报错 |
| `resize-pane` | no-op | 兼容但不报错 |

### Windows 兼容性处理

- **Bash 命令转译**：Claude Code 发送的是 bash 语法（`env VAR=val cmd`），子面板自动使用 Git Bash
- **百分比大小支持**：`-l 70%` 正确解析为 WezTerm 的 `--percent`
- **Target 格式兼容**：支持 tmux 的 `session:window`（如 `default:0`）和 `%N` 格式
- **环境变量注入**：`TMUX`、`WEZTERM_CLI`、`PATH` 自动配置

---

## 🐛 故障排除

### 检查系统状态

```powershell
# 查看诊断信息
.\.bin\tmux.exe doctor
```

### 查看日志

```powershell
Get-Content "$env:APPDATA\WinSplitPane\logs\tmux-shim.log"
```

### 常见问题

**Q: Claude 说 "Could not determine current tmux pane/window"**
→ 确保通过 `start-claude.cmd` 启动，它负责设置环境变量。

**Q: Split pane 打开了但 agent 没有执行**
→ 确保系统安装了 [Git Bash](https://git-scm.com/)（通常装 Git 时自带）。

**Q: WezTerm 没有找到**
→ 下载 [WezTerm](https://wezfurlong.org/wezterm/) 到 `.tools\wezterm\` 目录下，或安装到系统 PATH 中。

---

## 🤝 贡献

欢迎提交 Issue 和 PR！

---

## 📄 License

[MIT](LICENSE)
