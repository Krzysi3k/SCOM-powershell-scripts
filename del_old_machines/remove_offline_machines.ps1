# delete obsolete SCOM agents
# for SCOM 2012 R2                    

# write output with current date time:
function log-output
{
    Param([string]$text)
    Write-Output "$(Get-Date -Format ("yyyy-MM-dd HH:mm:ss")): $text"
}

function send-notification
{
    Param([string]$attachement)
    $smtp = 'smtp.domain.com'
    $from = 'from@domain.com'
    $to = 'to@domain.com'
    $body = @()
    $body += "machines removed:`n"
    $body += Get-Content $attachement | Where-Object {$_ -match (Get-Date -Format "yyyy-MM-dd")}
    $body = $body | Out-String
    Send-MailMessage -SmtpServer $smtp -From $from -To $to -Subject 'removed obsolete machines that were offline more than 30 days' -Body $body -Attachments $attachement
}

function Delete-SCOMagent($agents)
{
	# function to remove obsolete machines
	# example: Delete-SCOMagent -agents $ListofAgents
	
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.EnterpriseManagement.OperationsManager.Common") 
	[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.EnterpriseManagement.OperationsManager")

	$MGConnSetting = New-Object Microsoft.EnterpriseManagement.ManagementGroupConnectionSettings("SFRFIDCSCOM012P") 
	$MG = New-Object Microsoft.EnterpriseManagement.ManagementGroup($MGConnSetting) 
	$Admin = $MG.Administration

   	$agentManagedComputerType = [Microsoft.EnterpriseManagement.Administration.AgentManagedComputer]; 
	$genericListType = [System.Collections.Generic.List``1] 
	$genericList = $genericListType.MakeGenericType($agentManagedComputerType) 
	$agentList = new-object $genericList.FullName

    foreach($i in $agents)
    {
        $agent = Get-SCOMAgent -DNSHostName $i -ComputerName SFRFIDCSCOM012P
        $agentList.Add($agent);
    }

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
        log-output -text $comp | Out-File D:\scripts\delete_old_machines_from_SCOM\removed_from_json.log -Append
    }
    
    $last_month = (Get-Date).AddDays(-20)
    $curr_date = Get-Date
    [System.Collections.ArrayList]$agents = @()
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
                    $agents.Add($pc_name + ".statoilfuelretail.com")
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
    # delete agents:
    if($agents.Count -gt 0)
    {
        Delete-SCOMagent -agents $agents
    }
    # save json file:
    $json_obj = $json_obj | ConvertTo-Json
    $json_obj | Out-File "D:\scripts\delete_old_machines_from_SCOM\machines.json" -Force
	
	if($notify -eq $true)
	{
		send-notification -attachement $del_log
	}
}