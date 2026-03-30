param(
    [string]$WorkingDirectory,
    [string[]]$ClaudeArgs = @()
)

$ErrorActionPreference = 'Stop'

$startWezTermScript = Join-Path $PSScriptRoot 'start-wezterm.ps1'
if (-not (Test-Path $startWezTermScript)) {
    throw 'start-wezterm.ps1 not found.'
}

$program = @('claude')
if ($ClaudeArgs) {
    $program += $ClaudeArgs
}

& $startWezTermScript -WorkingDirectory $WorkingDirectory -Program $program
exit $LASTEXITCODE