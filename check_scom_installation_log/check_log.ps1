$currpth = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$logfile = "c$\path_to_log\SCOMAgent2012_AMD64_Install.log"
$pc = Get-Content $currpth\list_of_agents.txt
$pc += Get-Content $currpth\another_list_of_agents.txt
$dumplog = "$currpth\dump.log"
$n = 1

function log-line($text)
{
	Write-Output "$(get-date -Format ("yyyyMMdd HH:mm:ss")) : $text" | Out-File $dumplog -Append
}


Write-Host "`n`n`n`n`n"
foreach($p in $pc)
{
    Write-Progress -Activity "analyzing log file: SCOMAgent2012_AMD64_Install.log"`
    -Status "checking $p - $n of $($pc.count), percent complete: $([math]::Round(($n / $pc.count) * 100))"`
    -PercentComplete (($n / $pc.count) * 100)
    
    if(ls -Path \\$p\$logfile -ErrorAction SilentlyContinue)
    {
        $cont = (Get-Content \\$p\$logfile | select -Last 20)
        if($cont -match "Installation operation completed successfully" -or $cont -match "Configuration completed successfully")
        {
            # Write-Host "installation ok"
            log-line "installation ok on machine:, $p"
        }
        Else
        {
            Write-Warning "installation failed"
            # dump log to file
            Write-Output $cont | Out-File $currpth\$p.log -Append
            log-line "installation failed on machine:, $p"
        }
    }
    Else
    {
        Write-Warning "log doesnt exist on: $p"
        log-line "log doesn't exist on:, $p"
    }
    $n++
}
