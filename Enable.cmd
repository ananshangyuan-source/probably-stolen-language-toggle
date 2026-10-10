@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Set-Enabled.ps1" -Enabled true
set "RESULT=%ERRORLEVEL%"
pause
exit /b %RESULT%
