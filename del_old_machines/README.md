# Delete old machines
-script removes machines that were offline more than 20 days

-script should be scheduled at least once a day




how to run:
```winbatch
powershell.exe -command "import-module .\remove_offline_machines.ps1;run-main"
```