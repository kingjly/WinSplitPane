param(
    [int]$TimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$binDir = Join-Path $projectRoot '.bin'
$tmuxExe = Join-Path $binDir 'tmux.exe'
$tmpRoot = Join-Path $projectRoot '.tmp\real-smoke'
$configPath = Join-Path $projectRoot '.tools\wezterm\portable.wezterm.lua'

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

function Initialize-SmokeEnvironment {
    param(
        [string]$ProjectRoot,
        [string]$BinDir,
        [string]$ConfigPath,
        [string]$TmuxExe
    )

    if (-not (Test-Path $TmuxExe)) {
        throw 'tmux shim not built. Run scripts/install.ps1 first.'
    }

    $resolvedWezTerm = Resolve-WezTermCliPath -ProjectRoot $ProjectRoot
    $env:TMUX = 'winsplitpane'
    $env:WEZTERM_CLI = $resolvedWezTerm
    if (Test-Path $ConfigPath) {
        $env:WEZTERM_CONFIG_FILE = $ConfigPath
    }
    if ($env:PATH -notlike "*$BinDir*") {
        $env:PATH = "$BinDir;$env:PATH"
    }

    return $resolvedWezTerm
}

function Invoke-SmokeCore {
    param(
        [string]$TmuxExe,
        [string]$OutputRoot
    )

    New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
    Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $OutputRoot '*')

    $paneEnvPath = Join-Path $OutputRoot 'pane-env.txt'
    $statusPath = Join-Path $OutputRoot 'status.txt'
    $donePath = Join-Path $OutputRoot 'done.txt'

    function Invoke-Step {
        param(
            [string]$Name,
            [string[]]$CommandArgs
        )

        $stdoutPath = Join-Path $OutputRoot ("$Name.stdout.txt")
        $stderrPath = Join-Path $OutputRoot ("$Name.stderr.txt")
        $exitPath = Join-Path $OutputRoot ("$Name.exitcode.txt")

        & $TmuxExe @CommandArgs 1> $stdoutPath 2> $stderrPath
        $exitCode = $LASTEXITCODE
        Set-Content -Path $exitPath -Value $exitCode
        return $exitCode
    }

    @(
        'WEZTERM_PANE=' + $env:WEZTERM_PANE,
        'TMUX=' + $env:TMUX,
        'WEZTERM_CLI=' + $env:WEZTERM_CLI,
        'WEZTERM_CONFIG_FILE=' + $env:WEZTERM_CONFIG_FILE
    ) | Set-Content -Path $paneEnvPath

    $listBeforeExit = Invoke-Step -Name '01-list-before' -CommandArgs @('list-panes')
    if ($listBeforeExit -ne 0) {
        Set-Content -Path $statusPath -Value 'FAIL: list-before'
        Set-Content -Path $donePath -Value '1'
        exit $listBeforeExit
    }

    $splitExit = Invoke-Step -Name '02-split' -CommandArgs @('split-window', '-P', '-F', '#{pane_id}')
    if ($splitExit -ne 0) {
        Set-Content -Path $statusPath -Value 'FAIL: split-window'
        Set-Content -Path $donePath -Value '1'
        exit $splitExit
    }

    Start-Sleep -Milliseconds 600

    $newPaneText = (Get-Content (Join-Path $OutputRoot '02-split.stdout.txt') -Raw).Trim()
    if (-not $newPaneText) {
        Set-Content -Path $statusPath -Value 'FAIL: split-window-empty-output'
        Set-Content -Path $donePath -Value '1'
        exit 1
    }

    Set-Content -Path (Join-Path $OutputRoot 'new-pane.txt') -Value $newPaneText

    $listAfterSplitExit = Invoke-Step -Name '03-list-after-split' -CommandArgs @('list-panes')
    if ($listAfterSplitExit -ne 0) {
        Set-Content -Path $statusPath -Value 'FAIL: list-after-split'
        Set-Content -Path $donePath -Value '1'
        exit $listAfterSplitExit
    }

    $killExit = Invoke-Step -Name '04-kill' -CommandArgs @('kill-pane', '-t', $newPaneText)
    if ($killExit -ne 0) {
        Set-Content -Path $statusPath -Value 'FAIL: kill-pane'
        Set-Content -Path $donePath -Value '1'
        exit $killExit
    }

    Start-Sleep -Milliseconds 400

    $listAfterKillExit = Invoke-Step -Name '05-list-after-kill' -CommandArgs @('list-panes')
    if ($listAfterKillExit -ne 0) {
        Set-Content -Path $statusPath -Value 'FAIL: list-after-kill'
        Set-Content -Path $donePath -Value '1'
        exit $listAfterKillExit
    }

    Set-Content -Path $statusPath -Value 'OK'
    Set-Content -Path $donePath -Value '1'
    exit 0
}

$entryScriptPath = Join-Path $PSScriptRoot 'e2e-smoke.ps1'

$weztermCli = Initialize-SmokeEnvironment -ProjectRoot $projectRoot -BinDir $binDir -ConfigPath $configPath -TmuxExe $tmuxExe

if ($env:WEZTERM_PANE) {
    Invoke-SmokeCore -TmuxExe $tmuxExe -OutputRoot $tmpRoot
    exit $LASTEXITCODE
}

New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $tmpRoot '*')

$paneScriptPath = Join-Path $tmpRoot 'wezterm-pane-real-smoke.ps1'
$statusPath = Join-Path $tmpRoot 'status.txt'
$donePath = Join-Path $tmpRoot 'done.txt'

Get-Process -Name 'wezterm-gui', 'wezterm-mux-server', 'wezterm' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

$socketRoot = Join-Path $env:USERPROFILE '.local\share\wezterm'
if (Test-Path $socketRoot) {
    Get-ChildItem -Path $socketRoot -File -Filter 'gui-sock-*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $sockPath = Join-Path $socketRoot 'sock'
    if (Test-Path $sockPath) {
        Remove-Item -Force -ErrorAction SilentlyContinue $sockPath
    }
}

$paneScript = @"
`$ErrorActionPreference = 'Stop'
`$env:TMUX = 'winsplitpane'
`$env:WEZTERM_CLI = '$weztermCli'
"@

if ($env:WEZTERM_CONFIG_FILE) {
    $paneScript += "`r`n`$env:WEZTERM_CONFIG_FILE = '$($env:WEZTERM_CONFIG_FILE)'"
}

$paneScript += @"
`r`nif (`$env:PATH -notlike '*$binDir*') { `$env:PATH = '$binDir;' + `$env:PATH }
& '$entryScriptPath' -TimeoutSeconds $TimeoutSeconds
exit `$LASTEXITCODE
"@

Set-Content -Path $paneScriptPath -Value $paneScript -Encoding UTF8

$argumentList = @()
if ($env:WEZTERM_CONFIG_FILE) {
    $argumentList += @('--config-file', $env:WEZTERM_CONFIG_FILE)
}
$argumentList += @('start', '--cwd', $projectRoot, 'powershell.exe', '-NoLogo', '-ExecutionPolicy', 'Bypass', '-File', $paneScriptPath)

Write-Host "Launching WezTerm real smoke via: $weztermCli"
Start-Process -FilePath $weztermCli -ArgumentList $argumentList | Out-Null

for ($i = 0; $i -lt ($TimeoutSeconds * 2); $i++) {
    if (Test-Path $donePath) {
        break
    }
    Start-Sleep -Milliseconds 500
}

if (-not (Test-Path $donePath)) {
    throw 'Timed out waiting for real smoke output.'
}

Write-Host '== real smoke status =='
Get-Content $statusPath

$interestingFiles = @(
    'pane-env.txt',
    '01-list-before.stdout.txt',
    '02-split.stdout.txt',
    '03-list-after-split.stdout.txt',
    '04-kill.stderr.txt',
    '05-list-after-kill.stdout.txt'
)

foreach ($fileName in $interestingFiles) {
    $filePath = Join-Path $tmpRoot $fileName
    if (Test-Path $filePath) {
        Write-Host "== $fileName =="
        Get-Content $filePath
    }
}

$finalStatus = (Get-Content $statusPath -Raw).Trim()
if ($finalStatus -ne 'OK') {
    exit 1
}

exit 0
