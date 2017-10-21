
# write output with current date time:
function log-output
{
    Param([string]$text)
    Write-Output "$(Get-Date -Format ("yyyy-MM-dd HH:mm:ss")): $text"
}

function send-notification
{
    Param([string]$attachement)
    $smtp = 'yoursmtpserver.domain.com'
    $from = 'sender@domain.com'
    $to = 'recipient@domain.com'
    $body = @()
    $body += "machines removed:`n"
    $body += Get-Content $attachement | Where-Object {$_ -match (Get-Date -Format "yyyy-MM-dd")}
    $body = $body | Out-String
    Send-MailMessage -SmtpServer $smtp -From $from -To $to -Subject 'removed obsolete machines that were offline more than 20 days' -Body $body -Attachments $attachement
}

function Delete-SCOMagent($agentFQDN)
{
	# function to remove obsolete machines
	# example: Delete-SCOMagent -agentFQDN agent_name.domain.com
	
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.EnterpriseManagement.OperationsManager.Common") 
	[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.EnterpriseManagement.OperationsManager")

	$MGConnSetting = New-Object Microsoft.EnterpriseManagement.ManagementGroupConnectionSettings("management_server_name") 
	$MG = New-Object Microsoft.EnterpriseManagement.ManagementGroup($MGConnSetting) 
	$Admin = $MG.Administration

   	$agentManagedComputerType = [Microsoft.EnterpriseManagement.Administration.AgentManagedComputer]; 
	$genericListType = [System.Collections.Generic.List``1] 
	$genericList = $genericListType.MakeGenericType($agentManagedComputerType) 
	$agentList = new-object $genericList.FullName

    $agent = Get-SCOMAgent -DNSHostName $agentFQDN -ComputerName management_server_name
    $agentList.Add($agent);
    $Admin.DeleteAgentManagedComputers($agentList)
}

Function run-main
{
    Param([switch]$verbose)
    if($verbose)
    {
        $VerbosePreference = "Continue"
    }
	
	$notify = $false
    $logpth = "D:\scripts\delete_old_machines_from_SCOM\do_not_remove"
    $hb_failure = Get-SCOMClass -name Microsoft.SystemCenter.Agent | Get-SCOMMonitoringObject | Where-Object {$_.InMaintenanceMode -eq $false -and $_.IsAvailable -eq $false}

    # remove online machines from catalog:
	$list = ls -Path $logpth -Filter "*.log"
	$list = ($list.Name).trim(".log")
	foreach($l in $list)
	{
		if(Test-Connection -ComputerName $l -Count 1 -ErrorAction SilentlyContinue)
		{
			Write-Verbose "pc: $l is online - removing log file"
			ls -Path "$logpth\$l*" | Remove-Item -Force
		}
	}
	
	# verify machines that failed to heartbeat:
    foreach($i in $hb_failure)
    {
        if(Test-Connection $i.DisplayName -Count 1 -ErrorAction SilentlyContinue)
        {
            Write-Verbose "connection ok $i trying to remove log file..."
		    ls -Path "$logpth\$($i.DisplayName)*" | Remove-Item -Force
        }
        else
        {
            Write-Verbose "connection failed $i now check file log..."
            $filecheck = ls -Path "$logpth\$($i.DisplayName)*" -ErrorAction SilentlyContinue
            if($filecheck)
            {
                if((Get-Date).AddDays(-20) -gt $filecheck.CreationTime)
                {
                    Write-Verbose "filecheck log older than 30 days $($filecheck.Name) `nremovinglog + agent"
                    # remove machine from SCOM + remove log file + add info to log file
				    $filecheck | Remove-Item -Force
				    $del_log = "D:\scripts\delete_old_machines_from_SCOM\del_log.log"
				    log-output "removing pc: $($i.DisplayName)" | Out-File $del_log -Append
                    $agentFQDN = $i.DisplayName
                    Delete-SCOMagent -agentFQDN $agentFQDN
                    Write-Verbose "agent $agentFQDN has been removed..."
					$notify = $true
                }
            }
            else
            {
                # create file
                Write-Verbose "filecheck log does not exist - creating new file"
                New-Item -Path "$logpth\$($i.DisplayName).log" -Type file -Force
            }
        }
    }
	
	if($notify -eq $true)
	{
		send-notification -attachement $del_log
	}
}
