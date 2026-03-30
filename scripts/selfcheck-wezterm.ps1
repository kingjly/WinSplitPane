$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$binDir = Join-Path $projectRoot '.bin'
$tmuxExe = Join-Path $binDir 'tmux.exe'
$tmpDir = Join-Path $projectRoot '.tmp'
$configPath = Join-Path $projectRoot '.tools\wezterm\portable.wezterm.lua'
$doctorOut = Join-Path $tmpDir 'doctor-from-pane.txt'
$doctorErr = Join-Path $tmpDir 'doctor-from-pane.err.txt'
$paneEnv = Join-Path $tmpDir 'pane-env-from-pane.txt'
$exitCodePath = Join-Path $tmpDir 'doctor-exitcode-from-pane.txt'
$paneScriptPath = Join-Path $tmpDir 'wezterm-pane-selfcheck.ps1'

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

if (-not (Test-Path $tmuxExe)) {
    throw 'tmux shim not built. Run scripts/install.ps1 first.'
}

$weztermCli = Resolve-WezTermCliPath -ProjectRoot $projectRoot
$env:TMUX = 'winsplitpane'
$env:WEZTERM_CLI = $weztermCli
if (Test-Path $configPath) {
    $env:WEZTERM_CONFIG_FILE = $configPath
}
if ($env:PATH -notlike "*$binDir*") {
    $env:PATH = "$binDir;$env:PATH"
}

New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue $doctorOut, $doctorErr, $paneEnv, $exitCodePath, $paneScriptPath

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
`$env:TMUX = 'winsplitpane'
`$env:WEZTERM_CLI = '$weztermCli'
"@

if ($env:WEZTERM_CONFIG_FILE) {
    $paneScript += "`r`n`$env:WEZTERM_CONFIG_FILE = '$($env:WEZTERM_CONFIG_FILE)'"
}

$paneScript += @"
`r`n'WEZTERM_PANE=' + `$env:WEZTERM_PANE | Set-Content -Path '$paneEnv'
'WEZTERM_CLI=' + `$env:WEZTERM_CLI | Add-Content -Path '$paneEnv'
'WEZTERM_CONFIG_FILE=' + `$env:WEZTERM_CONFIG_FILE | Add-Content -Path '$paneEnv'
& '$tmuxExe' doctor 1> '$doctorOut' 2> '$doctorErr'
'DOCTOR_EXIT=' + `$LASTEXITCODE | Set-Content -Path '$exitCodePath'
"@

Set-Content -Path $paneScriptPath -Value $paneScript -Encoding UTF8

$argumentList = @()
if ($env:WEZTERM_CONFIG_FILE) {
    $argumentList += @('--config-file', $env:WEZTERM_CONFIG_FILE)
}
$argumentList += @('start', '--cwd', $projectRoot, 'powershell.exe', '-NoLogo', '-ExecutionPolicy', 'Bypass', '-File', $paneScriptPath)

Write-Host "Launching WezTerm self-check via: $weztermCli"
Start-Process -FilePath $weztermCli -ArgumentList $argumentList | Out-Null

for ($i = 0; $i -lt 30; $i++) {
    if (Test-Path $exitCodePath) {
        break
    }
    Start-Sleep -Milliseconds 500
}

if (Test-Path $paneEnv) {
    Write-Host '== Pane environment =='
    Get-Content $paneEnv
}

if (Test-Path $doctorOut) {
    Write-Host '== doctor stdout =='
    Get-Content $doctorOut
} else {
    Write-Host 'doctor stdout file was not created.'
}

if (Test-Path $doctorErr) {
    $stderrContent = Get-Content $doctorErr
    if ($stderrContent) {
        Write-Host '== doctor stderr =='
        $stderrContent
    }
}

if (Test-Path $exitCodePath) {
    Write-Host '== doctor exit =='
    Get-Content $exitCodePath
    exit 0
}

throw 'Timed out waiting for pane self-check output.'
