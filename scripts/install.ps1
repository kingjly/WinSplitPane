$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$binDir = Join-Path $projectRoot '.bin'
$exePath = Join-Path $binDir 'tmux.exe'
$portableConfigPath = Join-Path $projectRoot '.tools\wezterm\portable.wezterm.lua'

function Resolve-WezTermCliPath {
    param(
        [string]$ProjectRoot
    )

    if ($env:WEZTERM_CLI -and (Test-Path $env:WEZTERM_CLI)) {
        return (Resolve-Path $env:WEZTERM_CLI).Path
    }

    $portableRoot = Join-Path $ProjectRoot '.tools\wezterm'
    if (Test-Path $portableRoot) {
        $portableExe = Get-ChildItem -Path $portableRoot -Recurse -File -Filter 'wezterm.exe' |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($portableExe) {
            return $portableExe.FullName
        }
    }

    $weztermCommand = Get-Command 'wezterm' -ErrorAction SilentlyContinue
    if ($weztermCommand) {
        return $weztermCommand.Source
    }

    return 'wezterm'
}

New-Item -ItemType Directory -Force -Path $binDir | Out-Null

Push-Location $projectRoot
try {
    go build -o $exePath .\cmd\tmux
} finally {
    Pop-Location
}

Write-Host "Built $exePath"
Write-Host "Add $binDir to PATH before launching Claude Code."
Write-Host 'Fastest launch options:'
Write-Host '  .\start-claude.cmd'
Write-Host '  powershell -ExecutionPolicy Bypass -File .\scripts\start-claude.ps1'
Write-Host 'Optional desktop shortcut installer:'
Write-Host '  .\install-shortcut.cmd'
Write-Host '  powershell -ExecutionPolicy Bypass -File .\scripts\install-shortcut.ps1'
Write-Host "Recommended environment variables:"
Write-Host '  $env:TMUX = "winsplitpane"'
$resolvedWezTermCli = Resolve-WezTermCliPath -ProjectRoot $projectRoot
Write-Host ('  $env:WEZTERM_CLI = "{0}"' -f $resolvedWezTermCli)
if (Test-Path $portableConfigPath) {
    Write-Host ('  $env:WEZTERM_CONFIG_FILE = "{0}"' -f $portableConfigPath)
    Write-Host '  powershell -ExecutionPolicy Bypass -File .\scripts\start-wezterm.ps1'
}
