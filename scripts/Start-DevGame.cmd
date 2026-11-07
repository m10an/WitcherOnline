@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-DevGame.ps1" %*
exit /b %ERRORLEVEL%
