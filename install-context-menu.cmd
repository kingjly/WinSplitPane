@echo off
setlocal

if "%~1"=="" (
    powershell -ExecutionPolicy Bypass -File "%~dp0scripts\install-context-menu.ps1" -Action Install
) else (
    powershell -ExecutionPolicy Bypass -File "%~dp0scripts\install-context-menu.ps1" -Action %*
)
pause
exit /b %ERRORLEVEL%
