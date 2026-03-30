<div align="center">

# WinSplitPane

### Split panes for Claude Code Agent Teams on Windows 🪟

*A lightweight tmux shim that bridges Claude Code's split pane workflow to WezTerm on Windows.*

[![Go Version](https://img.shields.io/badge/Go-1.22+-00ADD8?style=flat&logo=go)](https://go.dev/)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078D4?style=flat&logo=windows)](https://github.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

</div>

---

## Why this exists

Claude Code Agent Teams can run multiple agents side by side with **split panes**, but today that flow depends on `tmux` or `iTerm2`. Neither option is a native fit for Windows.

**WinSplitPane** is a small `tmux` shim that:
- intercepts Claude Code calls to `tmux`
- translates them to [WezTerm](https://wezfurlong.org/wezterm/) CLI operations
- makes split panes usable on Windows without patching Claude Code

```
Claude Code                  WinSplitPane               WezTerm
    │                            │                          │
    │── tmux split-window ──────►│── wezterm cli split ────►│  ┌──────┬──────┐
    │── tmux send-keys ─────────►│── wezterm cli send ────►│  │agent1│agent2│
    │── tmux list-panes ────────►│── wezterm cli list ────►│  │      │      │
    │── tmux kill-pane ─────────►│── wezterm cli kill ────►│  └──────┴──────┘
```

---

## What you get

When Claude Code creates an Agent Team, WezTerm opens and manages panes automatically:
- a primary pane for the main agent
- one or more secondary panes for worker agents
- real-time visibility into every running agent

---

## Requirements

| Dependency | Notes |
|------|------|
| **Windows 10/11** | Supported operating system |
| **WezTerm** | Installed system-wide or bundled as a portable build |
| **Claude Code CLI** | `claude` must already be installed and configured |
| **Go 1.22+** | Optional if you use the prebuilt release package |

---

## Quick start

### Option 1: Download a release

1. Download the latest ZIP from [Releases](../../releases)
2. Extract it anywhere
3. Make sure WezTerm is installed, or use the full package that bundles WezTerm portable
4. Double-click `setup.cmd`

### Option 2: Build from source

```powershell
git clone https://github.com/yourname/WinSplitPane.git
cd WinSplitPane
.\setup.cmd
```

### Option 3: Portable run

If the package already contains portable WezTerm, you can extract it and run:

```powershell
.\start-claude.cmd
```

If WezTerm is not bundled, install WezTerm normally or extract a portable build to `.tools\wezterm\<version>\` first.

---

## Usage

Launch Claude Code through the prepared entry point:

```powershell
.\start-claude.cmd
```

Inside Claude Code, use Agent Teams as usual. WinSplitPane will:
1. expose a tmux-compatible environment
2. create panes through WezTerm
3. route commands and input to the correct pane
4. clean up panes when tasks end

---

## Project layout

```
WinSplitPane/
├── cmd/tmux/main.go
├── internal/
│   ├── app/app.go
│   ├── backend/wezterm/
│   ├── logging/logger.go
│   └── state/store.go
├── scripts/
│   ├── start-claude.ps1
│   ├── start-wezterm.ps1
│   ├── install.ps1
│   ├── install-shortcut.ps1
│   ├── selfcheck-wezterm.ps1
│   └── make-release.ps1
├── .tools/wezterm/
│   └── portable.wezterm.lua
├── setup.cmd
├── start-claude.cmd
├── install-shortcut.cmd
└── docs/setup-windows.md
```

---

## Implementation notes

### tmux commands supported

| tmux command | Backend implementation | Notes |
|------|----------|------|
| `split-window` | `wezterm cli split-pane` | Supports horizontal, vertical, and percentage sizing |
| `send-keys` | `wezterm cli send-text` | Sends text to the target pane |
| `list-panes` | `wezterm cli list` | Lists panes and supports filtering |
| `kill-pane` | `wezterm cli kill-pane` | Closes a pane |
| `display-message` | formatted output | Supports variables such as `#{pane_id}` |
| `capture-pane` | `wezterm cli get-text` | Reads pane output |
| `select-pane` | `wezterm cli activate-pane` | Focuses a pane |
| `has-session` | `wezterm cli` | Connectivity check |
| `set-option` | no-op | Accepted for compatibility |
| `select-layout` | no-op | Accepted for compatibility |
| `resize-pane` | no-op | Accepted for compatibility |

### Windows-specific behavior

- bash-style command payloads are translated for Windows execution
- tmux percentage sizes such as `-l 70%` are mapped to WezTerm percentages
- tmux target formats such as `session:window` and `%N` are supported
- environment variables such as `TMUX`, `WEZTERM_CLI`, and `PATH` are prepared automatically

---

## Troubleshooting

### System checks

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\selfcheck-wezterm.ps1
.\.bin\tmux.exe doctor
```

### Logs

```powershell
Get-Content "$env:APPDATA\WinSplitPane\logs\tmux-shim.log"
```

### Common issues

**Could not determine current tmux pane/window**
Launch Claude through `start-claude.cmd` so the required environment is set correctly.

**Split panes open but agents do not start**
Make sure Git Bash is installed. Claude Code often sends bash-style commands to child panes.

**WezTerm cannot be found**
Install WezTerm, or place a portable build under `.tools\wezterm\`.

---

## Releases

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\make-release.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\make-release.ps1 -IncludeWezTerm
```

The standard package is intended for users who already have WezTerm installed.  
The full package bundles portable WezTerm for a more self-contained setup.

---

## Chinese README

For the Chinese version, see [README.zh-CN.md](README.zh-CN.md).

---

## License

[MIT](LICENSE)
