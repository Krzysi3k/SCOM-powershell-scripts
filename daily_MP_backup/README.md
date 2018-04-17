# Management Packs daily backup

-creates backup of all MP (xml files), and creates one archive (zip)

-keeps up to 20 zip archives

how to run:
```bat
cd /d "%~dp0"
powershell.exe -file .\daily_MP_backup.ps1
```