@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1

echo ╔══════════════════════════════════════════════════════════╗
echo ║           WinSplitPane - One-Click Installer            ║
echo ║    Windows tmux shim for Claude Code Agent Teams        ║
echo ╚══════════════════════════════════════════════════════════╝
echo.

::  ---------- 1. Check / Download WezTerm ----------
set "WEZTERM_DIR=%~dp0.tools\wezterm"
set "WEZTERM_ZIP_DIR=%~dp0.tools\downloads"

:: Check if WezTerm portable already exists
set "WEZTERM_EXE="
if exist "%WEZTERM_DIR%" (
    for /f "delims=" %%f in ('dir /s /b "%WEZTERM_DIR%\wezterm.exe" 2^>nul') do (
        set "WEZTERM_EXE=%%f"
    )
)

if not defined WEZTERM_EXE (
    echo [1/3] WezTerm not found locally, checking PATH...
    where wezterm.exe >nul 2>&1
    if !errorlevel! equ 0 (
        for /f "delims=" %%p in ('where wezterm.exe') do set "WEZTERM_EXE=%%p"
        echo       Found: !WEZTERM_EXE!
    ) else (
        echo       WezTerm not on PATH either.
        echo       Please download WezTerm portable ZIP from:
        echo       https://wezfurlong.org/wezterm/
        echo.
        echo       Extract to: %WEZTERM_DIR%
        echo       So that wezterm.exe is at: %WEZTERM_DIR%\^<version^>\wezterm.exe
        echo.
        echo       Or install WezTerm normally and re-run this script.
        echo.
        pause
        exit /b 1
    )
) else (
    echo [1/3] WezTerm found: !WEZTERM_EXE!
)

::  ---------- 2. Build / Locate tmux.exe ----------
set "BIN_DIR=%~dp0.bin"
set "TMUX_EXE=%BIN_DIR%\tmux.exe"

if exist "%TMUX_EXE%" (
    echo [2/3] tmux shim already built: %TMUX_EXE%
) else (
    :: Try Go build first
    where go >nul 2>&1
    if !errorlevel! equ 0 (
        echo [2/3] Go found, building tmux shim...
        if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"
        pushd "%~dp0"
        go build -o "%TMUX_EXE%" .\cmd\tmux
        if !errorlevel! neq 0 (
            echo       BUILD FAILED. Make sure Go 1.22+ is installed.
            popd
            pause
            exit /b 1
        )
        popd
        echo       Build OK: %TMUX_EXE%
    ) else (
        echo [2/3] Go not found. Looking for pre-built tmux.exe...
        if exist "%~dp0tmux.exe" (
            if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"
            copy /y "%~dp0tmux.exe" "%TMUX_EXE%" >nul
            echo       Copied pre-built: %TMUX_EXE%
        ) else (
            echo       ERROR: No Go compiler and no pre-built tmux.exe found.
            echo       Either install Go 1.22+ or place a pre-built tmux.exe
            echo       in the project root directory.
            pause
            exit /b 1
        )
    )
)

::  ---------- 3. Create desktop shortcut ----------
echo [3/3] Creating desktop shortcut...
powershell -ExecutionPolicy Bypass -Command "& { Join-Path '%~dp0' 'scripts\install-shortcut.ps1' | ForEach-Object { & $_ } }"
if !errorlevel! neq 0 (
    echo       Shortcut creation failed ^(non-fatal^). You can still launch via:
    echo       %~dp0start-claude.cmd
)

echo.
echo ╔══════════════════════════════════════════════════════════╗
echo ║              Installation Complete!                     ║
echo ╠══════════════════════════════════════════════════════════╣
echo ║                                                          ║
echo ║  Launch Claude with split panes:                         ║
echo ║    1. Double-click desktop shortcut                      ║
echo ║       "Claude (WinSplitPane)"                            ║
echo ║    2. Or run: start-claude.cmd                           ║
echo ║                                                          ║
echo ║  In Claude, use Agent Teams as usual. Split panes       ║
echo ║  will appear in the WezTerm window!                      ║
echo ║                                                          ║
echo ╚══════════════════════════════════════════════════════════╝
echo.

::  ---------- Optional: Context Menu ----------
set /p "ADD_CONTEXT=Add right-click context menu entry? (y/N): "
if /i "!ADD_CONTEXT!"=="y" (
    echo.
    echo Installing context menu...
    powershell -ExecutionPolicy Bypass -File "%~dp0scripts\install-context-menu.ps1" -Action Install
    echo.
)

pause
