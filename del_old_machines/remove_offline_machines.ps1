
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
    $hb_failure = Get-SCOMClass -name Microsoft.SystemCenter.Agent | Get-SCOMMonitoringObject | Where-Object {$_.InMaintenanceMode -eq $false -and $_.IsAvailable -eq $false}

    # ping all machines from json file (as Job)
    $json_file = Get-Content -Raw "D:\scripts\delete_old_machines_from_SCOM\machines.json"
    $json_obj = $json_file | ConvertFrom-Json
    $jobs = @()
    for ($i = 0; $i -le $json_obj.machines.PSobject.Properties.Name.Count -1; $i++)
    {
        $connection = Test-Connection -ComputerName $json_obj.machines.PSobject.Properties.Name[$i] -Count 1 -AsJob -ErrorAction SilentlyContinue
        $jobs += $connection
    }

    while ($jobs.State -eq "Running")
    {
        Start-Sleep -Milliseconds 500
    }

    $job_result = Receive-Job $jobs
    [System.Collections.ArrayList]$online_list = @()
    foreach ($j in $job_result)
    {
        switch ($j.StatusCode)
        {
            0 {Write-Verbose "machine is online: $(($j).Address)"; $null=$online_list.Add(($j).Address)}
            Default {Write-Verbose "machine is offline: $(($j).Address)"}
        }
    }
    # remove all online machines from json:
    foreach($comp in $online_list)
    {
        Write-Verbose "removing $comp from json..."
        $json_obj.machines.PSobject.Properties.Remove($comp)
    }
    
    $last_month = (Get-Date).AddDays(-30)
    $curr_date = Get-Date
	# verify machines that failed to heartbeat:
    foreach($hb in $hb_failure)
    {
        if(Test-Connection -ComputerName $hb.DisplayName -Count 1 -ErrorAction SilentlyContinue) 
        {
            Write-Verbose "hb failure but online: $($hb.DisplayName)"
        }
        else 
        {
            $pc_name = $hb.DisplayName
            $pc_name = $pc_name.Substring(0,$pc_name.Length -22)
            if($json_obj.machines.PSobject.Properties.Name -contains $pc_name -eq $true)
            {
                # check date and remove if older than 30 days
                if([datetime]::Parse($json_obj.machines.$pc_name) -lt $last_month)
                {
                    Write-Verbose "$pc_name is older than 30 days, removing..."
                    $json_obj.machines.PSobject.Properties.Remove($pc_name)
                    $del_log = "D:\scripts\delete_old_machines_from_SCOM\del_log.log"
                    log-output "removing pc: $pc_name" | Out-File $del_log -Append
                    $agentFQDN = $pc_name + ".statoilfuelretail.com"
                    Delete-SCOMagent -agentFQDN $agentFQDN
                    Write-Verbose "agent $pc_name has been removed..."
                    $notify = $true
                }
            }
            else
            {
                Write-Verbose "adding $pc_name to json file..."
                $json_obj.machines | Add-Member -MemberType NoteProperty -Name $pc_name -Value $curr_date.ToShortDateString()
            }
        }
    }

    # save json file:
    $json_obj = $json_obj | ConvertTo-Json
    $json_obj | Out-File "D:\scripts\delete_old_machines_from_SCOM\machines.json" -Force
	
	if($notify -eq $true)
	{
		send-notification -attachement $del_log
	}
}
