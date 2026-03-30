param(
    [string]$WorkingDirectory,
    [string[]]$Program = @('powershell.exe', '-NoLogo', '-NoExit')
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $WorkingDirectory) {
    $WorkingDirectory = $projectRoot
}

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

    throw 'Unable to find wezterm.exe. Put WezTerm in PATH or under .tools\wezterm.'
}

$weztermCli = Resolve-WezTermCliPath -ProjectRoot $projectRoot
$configPath = Join-Path $projectRoot '.tools\wezterm\portable.wezterm.lua'
$binDir = Join-Path $projectRoot '.bin'
$tmuxExe = Join-Path $binDir 'tmux.exe'
$launcherDir = Join-Path $projectRoot '.tmp\launchers'

if (-not (Test-Path $tmuxExe)) {
    throw 'tmux shim not built. Run scripts/install.ps1 first.'
}

if (-not (Test-Path $WorkingDirectory)) {
    throw "Working directory not found: $WorkingDirectory"
}

$env:TMUX = 'winsplitpane'
$env:WEZTERM_CLI = $weztermCli
if (Test-Path $configPath) {
    $env:WEZTERM_CONFIG_FILE = $configPath
}
if ($env:PATH -notlike "*$binDir*") {
    $env:PATH = "$binDir;$env:PATH"
}

function Convert-ToSingleQuotedLiteral {
    param(
        [string]$Value
    )

    return "'" + ($Value -replace "'", "''") + "'"
}

$isDefaultShell = ($Program.Count -ge 3 -and $Program[0] -eq 'powershell.exe' -and $Program -contains '-NoExit')

New-Item -ItemType Directory -Force -Path $launcherDir | Out-Null
$bootstrapScriptPath = Join-Path $launcherDir ("wezterm-bootstrap-{0}.ps1" -f ([guid]::NewGuid().ToString('N')))

$bootstrapLines = @(
    '$ErrorActionPreference = ''Stop''',
    ('$env:TMUX = {0}' -f (Convert-ToSingleQuotedLiteral -Value 'winsplitpane')),
    ('$env:WEZTERM_CLI = {0}' -f (Convert-ToSingleQuotedLiteral -Value $weztermCli)),
    ('$env:PATH = {0} + ";" + $env:PATH' -f (Convert-ToSingleQuotedLiteral -Value $binDir)),
    ('Set-Location -LiteralPath {0}' -f (Convert-ToSingleQuotedLiteral -Value $WorkingDirectory))
)

if ($env:WEZTERM_CONFIG_FILE) {
    $bootstrapLines += ('$env:WEZTERM_CONFIG_FILE = {0}' -f (Convert-ToSingleQuotedLiteral -Value $env:WEZTERM_CONFIG_FILE))
}

if ($isDefaultShell) {
    # Default mode: inject env then drop into interactive PowerShell
    $bootstrapLines += @(
        'Write-Host "WinSplitPane environment ready. TMUX=$($env:TMUX)  WEZTERM_PANE=$($env:WEZTERM_PANE)"',
        'Write-Host "Run: claude"'
    )
} else {
    # Custom program mode: run the program, then keep shell alive
    $programItems = @()
    foreach ($item in $Program) {
        $programItems += (Convert-ToSingleQuotedLiteral -Value $item)
    }
    $bootstrapLines += ('$program = @({0})' -f ($programItems -join ', '))
    $bootstrapLines += @(
        'try {',
        '  $programName = $program[0]',
        '  $programArgs = @()',
        '  if ($program.Count -gt 1) { $programArgs = $program[1..($program.Count - 1)] }',
        '  & $programName @programArgs',
        '} catch {',
        '  Write-Host "Program exited with error: $_"',
        '}',

        'Write-Host ""',
        'Write-Host "Program exited (code=$LASTEXITCODE). Shell kept alive."',
        'Write-Host "Press Ctrl+D or type exit to close."'
    )
}

Set-Content -Path $bootstrapScriptPath -Value ($bootstrapLines -join "`r`n") -Encoding UTF8

$argumentList = @()
if ($env:WEZTERM_CONFIG_FILE) {
    $argumentList += @('--config-file', $env:WEZTERM_CONFIG_FILE)
}

$paneProgram = @('powershell.exe', '-NoLogo', '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', $bootstrapScriptPath)
$argumentList += @('start', '--cwd', $WorkingDirectory)
$argumentList += $paneProgram

Write-Host "Launching WezTerm: $weztermCli"
if ($env:WEZTERM_CONFIG_FILE) {
    Write-Host "Using config: $($env:WEZTERM_CONFIG_FILE)"
}
Write-Host "Working directory: $WorkingDirectory"
Write-Host "TMUX=$($env:TMUX)"
Write-Host "WEZTERM_CLI=$($env:WEZTERM_CLI)"
Write-Host "Bootstrap script: $bootstrapScriptPath"
Write-Host 'Claude Code should be started from the opened WezTerm shell.'

Start-Process -FilePath $weztermCli -ArgumentList $argumentList | Out-Null
