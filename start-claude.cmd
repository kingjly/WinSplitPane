@echo off
setlocal
powershell -ExecutionPolicy Bypass -File "%~dp0scripts\start-claude.ps1" %*
exit /b %ERRORLEVEL%