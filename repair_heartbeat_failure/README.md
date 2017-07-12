-scripts repairs remote machines with heartbeat failure (clean healthstate by removing content of "Health Service Store" folder)

-script requires PsService.exe application, read more about PsTools here:
https://technet.microsoft.com/en-us/sysinternals/pstools.aspx

how to run:

powershell.exe -command "import-module .\repair_hb_failure.ps1;ping-machines"
