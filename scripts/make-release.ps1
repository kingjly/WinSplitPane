<#
.SYNOPSIS
    Creates a distributable ZIP of WinSplitPane.
.DESCRIPTION
    Builds the tmux.exe shim, then packages everything needed (except WezTerm
    portable binary which is ~200MB) into a ZIP file for sharing.
    
    Optionally includes WezTerm portable with -IncludeWezTerm switch.
#>

param(
    [switch]$IncludeWezTerm,
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$binDir = Join-Path $projectRoot '.bin'
$tmuxExe = Join-Path $binDir 'tmux.exe'

function Get-NormalizedPath {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootPath = [System.IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Length -gt $rootPath.Length) {
        return $fullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    }

    return $fullPath
}

function Test-IsUnderPath {
    param(
        [string]$Path,
        [string[]]$ExcludedRoots
    )

    $normalizedPath = Get-NormalizedPath $Path
    foreach ($root in $ExcludedRoots) {
        if ($normalizedPath.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }

        $prefix = $root + [System.IO.Path]::DirectorySeparatorChar
        if ($normalizedPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $projectRoot 'dist'
} elseif (-not [System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir = Join-Path $projectRoot $OutputDir
}

$OutputDir = Get-NormalizedPath $OutputDir
$scriptsSourceDir = Get-NormalizedPath (Join-Path $projectRoot 'scripts')
$sourceRoots = @(
    Get-NormalizedPath (Join-Path $projectRoot 'cmd'),
    Get-NormalizedPath (Join-Path $projectRoot 'internal'),
    $scriptsSourceDir
)

if (Test-IsUnderPath -Path $OutputDir -ExcludedRoots $sourceRoots) {
    throw "OutputDir cannot be inside cmd/internal/scripts. Use a path outside packaged source trees, for example '$projectRoot\dist'."
}

# Build
Write-Host '[1/3] Building tmux shim...' -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
Push-Location $projectRoot
try {
    go build -o $tmuxExe .\cmd\tmux
    if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
} finally {
    Pop-Location
}
Write-Host "      Built: $tmuxExe" -ForegroundColor Green

# Prepare staging directory
$stageDir = Join-Path ([System.IO.Path]::GetTempPath()) ("WinSplitPane-release-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
if (Test-Path $stageDir) { Remove-Item $stageDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

Write-Host '[2/3] Staging files...' -ForegroundColor Cyan

# Copy source code
try {
    $sourceDirs = @('cmd', 'internal')
    foreach ($dir in $sourceDirs) {
        $src = Join-Path $projectRoot $dir
        $dst = Join-Path $stageDir $dir
        Copy-Item -Path $src -Destination $dst -Recurse
    }

    # Copy root files
    $rootFiles = @('go.mod', 'go.sum', 'LICENSE', '.gitignore')
    foreach ($file in $rootFiles) {
        $src = Join-Path $projectRoot $file
        if (Test-Path $src) { Copy-Item -Path $src -Destination $stageDir }
    }

    # Copy pre-built binary (so users without Go can use it immediately)
    $stageBinDir = Join-Path $stageDir '.bin'
    New-Item -ItemType Directory -Force -Path $stageBinDir | Out-Null
    Copy-Item -Path $tmuxExe -Destination (Join-Path $stageBinDir 'tmux.exe')

    # Copy scripts
    $scriptsDir = Join-Path $stageDir 'scripts'
    New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null
    Get-ChildItem -LiteralPath $scriptsSourceDir -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $scriptsDir $_.Name) -Force
    }

    # Copy launcher
    Copy-Item -Path (Join-Path $projectRoot 'start-claude.cmd') -Destination $stageDir

    # Copy install.cmd
    Copy-Item -Path (Join-Path $projectRoot 'setup.cmd') -Destination $stageDir
    Copy-Item -Path (Join-Path $projectRoot 'install-shortcut.cmd') -Destination $stageDir

    # Copy config
    $weztermDir = Join-Path $stageDir '.tools\wezterm'
    New-Item -ItemType Directory -Force -Path $weztermDir | Out-Null
    Copy-Item -Path (Join-Path $projectRoot '.tools\wezterm\portable.wezterm.lua') -Destination $weztermDir

    # Optionally include WezTerm
    if ($IncludeWezTerm) {
        $weztermPortable = Join-Path $projectRoot '.tools\wezterm'
        Get-ChildItem -Path $weztermPortable -Directory | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $weztermDir -Recurse
            Write-Host "      Included WezTerm: $($_.Name)" -ForegroundColor Green
        }
    }

    # Create README
    $readmeContent = @'
# WinSplitPane - Quick Start

## Prerequisites
- **WezTerm** terminal (portable or installed)
- **Claude Code** CLI (`claude`) installed and configured

## Installation

### Option A: Pre-built binary (no Go required)
1. Double-click `setup.cmd`

### Option B: Build from source
1. Install [Go 1.22+](https://go.dev/dl/)
2. Double-click `setup.cmd` (it will auto-build)

### Option C: Portable run
- If this package already includes WezTerm portable, just run `start-claude.cmd`
- Otherwise install WezTerm or extract portable WezTerm to `.tools\wezterm\<version>\`, then run `start-claude.cmd`

## Usage
- **Desktop shortcut**: Double-click "Claude (WinSplitPane)" on desktop
- **Command line**: Run `start-claude.cmd`
- **In Claude**: Create an Agent Team task → split panes appear in WezTerm!

## Troubleshooting
- Run `powershell -ExecutionPolicy Bypass -File scripts\selfcheck-wezterm.ps1`
- Check logs at `%APPDATA%\WinSplitPane\logs\tmux-shim.log`
'@
    Set-Content -Path (Join-Path $stageDir 'QUICKSTART.md') -Value $readmeContent -Encoding UTF8

    # Create ZIP
    Write-Host '[3/3] Creating ZIP...' -ForegroundColor Cyan
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmm'
    $zipName = "WinSplitPane-$timestamp.zip"
    if ($IncludeWezTerm) { $zipName = "WinSplitPane-$timestamp-full.zip" }
    $zipPath = Join-Path $OutputDir $zipName

    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    # Use .NET for ZIP creation (faster than Compress-Archive for large files)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stageDir, $zipPath)

    $sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Host ''
    Write-Host "Done! Created: $zipPath ($sizeMB MB)" -ForegroundColor Green
    Write-Host ''
    Write-Host 'Share this ZIP file. Recipients extract and run setup.cmd' -ForegroundColor Yellow
} finally {
    if (Test-Path $stageDir) {
        Remove-Item $stageDir -Recurse -Force
    }
}
