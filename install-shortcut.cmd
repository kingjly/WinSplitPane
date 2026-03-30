@echo off
setlocal
powershell -ExecutionPolicy Bypass -File "%~dp0scripts\install-shortcut.ps1" %*
exit /b %ERRORLEVEL%