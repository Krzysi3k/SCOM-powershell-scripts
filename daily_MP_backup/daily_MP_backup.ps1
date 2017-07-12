Import-Module OperationsManager
$zipfilename = "D:\MP_daily_backup\"+(get-date -Format("HHmmddMMyyyy"))+".zip"
$sourcedir = "D:\MP_daily_backup\mp"


#remove old files and export current MP's
Remove-Item $sourcedir\*.xml -Force
Get-SCOMManagementPack | Export-SCOMManagementPack -Path $sourcedir

function ZipFiles( $zipfilename, $sourcedir )
{
   Add-Type -Assembly System.IO.Compression.FileSystem
   $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
   [System.IO.Compression.ZipFile]::CreateFromDirectory($sourcedir,
        $zipfilename, $compressionLevel, $false)
}

ZipFiles $zipfilename $sourcedir

#remove zip files older than 20 days
$limit = (Get-Date).AddDays(-20)
gci -Path D:\MP_daily_backup\ -Filter *.zip | Where-Object {$_.CreationTime -lt $limit} | Remove-Item -Force
