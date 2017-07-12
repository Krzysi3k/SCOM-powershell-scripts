cd /d "%~dp0"
powershell.exe -command "import-module .\remove_offline_machines.ps1;run-main"
