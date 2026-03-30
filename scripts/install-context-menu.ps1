param(
    [ValidateSet('Install', 'Uninstall')]
    [string]$Action = 'Install'
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$startClaudeScript = Join-Path $projectRoot 'scripts\start-claude.ps1'

if ($Action -eq 'Install' -and -not (Test-Path $startClaudeScript)) {
    throw "start-claude.ps1 not found at: $startClaudeScript"
}

$registryPath = 'Registry::HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\WinSplitPane'
$registryPathFolder = 'Registry::HKEY_CURRENT_USER\Software\Classes\Directory\shell\WinSplitPane'

function Install-ContextMenu {
    param(
        [string]$RegPath,
        [string]$Label
    )

    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    Set-ItemProperty -Path $regPath -Name '(Default)' -Value $Label
    Set-ItemProperty -Path $regPath -Name 'Icon' -Value 'powershell.exe'

    $commandPath = Join-Path $regPath 'command'
    if (-not (Test-Path $commandPath)) {
        New-Item -Path $commandPath -Force | Out-Null
    }

    $command = 'powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -Command "& ''{0}'' -WorkingDirectory ''%V''"' -f $startClaudeScript
    Set-ItemProperty -Path $commandPath -Name '(Default)' -Value $command

    Write-Host "  Registered: $RegPath"
}

function Uninstall-ContextMenu {
    param(
        [string]$RegPath
    )

    if (Test-Path $regPath) {
        Remove-Item -Path $regPath -Recurse -Force
        Write-Host "  Removed: $RegPath"
    } else {
        Write-Host "  Not found (already clean): $RegPath"
    }
}

switch ($Action) {
    'Install' {
        Write-Host 'Installing context menu entries...'
        Install-ContextMenu -RegPath $registryPath -Label 'Open Claude (WinSplitPane) here'
        Install-ContextMenu -RegPath $registryPathFolder -Label 'Open Claude (WinSplitPane) here'
        Write-Host ''
        Write-Host 'Done! Right-click in any folder (or on any folder) to see the option.'
    }

    'Uninstall' {
        Write-Host 'Removing context menu entries...'
        Uninstall-ContextMenu -RegPath $registryPath
        Uninstall-ContextMenu -RegPath $registryPathFolder
        Write-Host ''
        Write-Host 'Done! Context menu entries removed.'
    }
}
