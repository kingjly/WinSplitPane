# WinSplitPane v1

## Prerequisites

- Windows 11 or newer recommended
- Go 1.22+
- WezTerm available either from PATH or from `.tools/wezterm`
- Claude Code configured to use `tmux` teammate mode

## Build

Run:

```powershell
./scripts/install.ps1
```

This builds `.bin/tmux.exe`.

If `.tools/wezterm/portable.wezterm.lua` exists, the install script also prints the recommended `WEZTERM_CLI` and `WEZTERM_CONFIG_FILE` values.

## Quick start

The simplest way is:

```cmd
start-claude.cmd
```

That wrapper starts WezTerm with the correct environment and launches `claude` directly inside it.

If you prefer PowerShell:

```powershell
./scripts/start-claude.ps1
```

If you want a desktop icon, run once:

```cmd
install-shortcut.cmd
```

That creates `Claude (WinSplitPane).lnk` on your desktop.

## Shell setup

Add `.bin` to `PATH`, then launch Claude Code from a shell that contains:

```powershell
$env:TMUX = "winsplitpane"
$env:WEZTERM_CLI = "C:\path\to\wezterm.exe"
$env:WEZTERM_CONFIG_FILE = "C:\path\to\portable.wezterm.lua"
```

The recommended path on this project is to let the provided launch script do that for you:

```powershell
./scripts/start-wezterm.ps1
```

This opens a WezTerm window with `TMUX`, `WEZTERM_CLI`, `WEZTERM_CONFIG_FILE` and `.bin` already prepared for the child shell. Launch Claude Code from that WezTerm shell.

If you don't want the extra manual step, use `start-claude.cmd` or `./scripts/start-claude.ps1` instead.

## Validation

To run a non-interactive validation, use:

```powershell
./scripts/selfcheck-wezterm.ps1
```

That script launches a temporary WezTerm pane, runs `tmux.exe doctor` from inside the pane, and stores the captured output under `.tmp/`.

## Current command coverage

- `split-window`
- `send-keys`
- `capture-pane`
- `list-panes`
- `kill-pane`
- `display-message`
- `select-pane`
- `has-session`
- `doctor`
- `dump-state`

## Notes

- Pane ids are surfaced in tmux style such as `%12`, while WezTerm is called with raw numeric ids.
- `split-window` now uses `WEZTERM_PANE` as the default target when `-t` is omitted, matching normal WezTerm pane-local usage.
- v1 stores lightweight pane metadata and reconstructs live pane state from `wezterm cli list`.
- Commands such as `select-layout` are treated as no-op success for compatibility.
