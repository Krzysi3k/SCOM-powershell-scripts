@echo off
echo off
cls
cd /d "%~dp0"
powershell.exe -NoLogo -command "import-module .\check_recent_agent_installed.ps1;run-main"
pause
