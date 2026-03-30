param(
    [string]$ShortcutName = 'Claude (WinSplitPane).lnk',
    [string]$DestinationDirectory
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$launcherPath = Join-Path $projectRoot 'start-claude.cmd'

if (-not (Test-Path $launcherPath)) {
    throw 'start-claude.cmd not found.'
}

if (-not $DestinationDirectory) {
    $DestinationDirectory = [Environment]::GetFolderPath('Desktop')
}

if (-not (Test-Path $DestinationDirectory)) {
    throw "Destination directory not found: $DestinationDirectory"
}

$shortcutPath = Join-Path $DestinationDirectory $ShortcutName
$powershellPath = (Get-Command 'powershell.exe' -ErrorAction Stop).Source
$weztermIcon = Get-ChildItem -Path (Join-Path $projectRoot '.tools\wezterm') -Recurse -File -Filter 'wezterm.exe' -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powershellPath
$shortcut.Arguments = ('-ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $projectRoot 'scripts\start-claude.ps1'))
$shortcut.WorkingDirectory = $projectRoot
$shortcut.Description = 'Launch Claude in WezTerm with WinSplitPane enabled.'
if ($weztermIcon) {
    $shortcut.IconLocation = $weztermIcon.FullName
}
$shortcut.Save()

Write-Host "Created shortcut: $shortcutPath"