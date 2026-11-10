@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-ReplicaPeer.ps1" %*
exit /b %ERRORLEVEL%
