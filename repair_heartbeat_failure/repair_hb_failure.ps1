$currpth = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
function ping-machines
{
	Import-Module OperationsManager
	$pinglog = "$currpth\ping_big_log.log"
	$TTLex = "$currpth\TTLex.log"
	$alive = "$currpth\alive.log"
	$timedout = "$currpth\timedout.log"
	$notexist = "$currpth\notexist.log"
	$unreachable = "$currpth\unreachable.log"
	$list_unsorted = "$currpth\unsorted.log"
	$sorted = "$currpth\sorted.log"

	write-host "removing old logs file...`nGetting machines with heartbeat failure..."
	Move-Item -Path "$currpth\*.log" -Destination "$currpth\old_logs\" -Force

	#get list of machines with heartbeat failure
	$hb_failure = Get-SCOMClass -name Microsoft.SystemCenter.Agent | Get-SCOMMonitoringObject | Where-Object {$_.InMaintenanceMode -eq $false -and $_.IsAvailable -eq $false}
	$hb_failure | Select-Object DisplayName | Format-Table -HideTableHeaders | Out-File $list_unsorted
	$machines_unsorted = Get-Content $list_unsorted
	$machines_unsorted | % {$_.substring(0,12) | Out-File $sorted -Append}
	Remove-Item $list_unsorted -Force
	cls
	#ping machines and create logs
	$machines = Get-Content $sorted
	$n = 1
    $job = @()

	foreach ($line in $machines)
	{
		Write-Progress -Activity "pinging machines" -Status "$n of $($machines.count)" -PercentComplete (($n / $machines.count) * 100)
		$n++
		if($line -match "W8-")
		{
			$conn = Test-Connection $line -Count 1 -AsJob
			$job += $conn       
        }
    }
	
	Do
	{
		Start-Sleep -Milliseconds 500
	}
	While($job.State -EQ 'Running')
	
    $table = Receive-Job -Job $job
    foreach($t in $table)
    {
        Switch($t.StatusCode)
        {
            0 {$t | select -ExpandProperty Address | Out-File $currpth\alive.log -Append}              # Success
            11010 {$t | select -ExpandProperty Address | Out-File $currpth\timedout.log -Append}       # Request Timed Out
            11002 {$t | select -ExpandProperty Address | Out-File $currpth\unreachable.log -Append}    # Destination Net Unreachable
            11003 {$t | select -ExpandProperty Address | Out-File $currpth\unreachable.log -Append}    # Destination Host Unreachable
            11013 {$t | select -ExpandProperty Address | Out-File $currpth\TTLex.log -Append}          # TimeToLive Expired Transit
            11014 {$t | select -ExpandProperty Address | Out-File $currpth\TTLex.log -Append}          # TimeToLive Expired Reassembly
            11050 {$t | select -ExpandProperty Address | Out-File $currpth\GeneralFailure.log -Append} # General Failure
            default {$t | select -ExpandProperty Address | Out-File $currpth\uknown.log -Append}       # Unknown
        }
    }

	write-host "pinging done"
	#repair healthservice store on remote online computers

	$computers = Get-Content $alive

	foreach ($computer in $computers)
	{
		Start-Process powershell.exe -ArgumentList "Import-Module $currpth\repair_hb_failure_v2.0.ps1;repair-SCOM-agent $computer" -NoNewWindow
		Start-Sleep -Milliseconds 500
		While((Get-Process -Name powershell).count -ge 10)
		{
			Start-Sleep -Milliseconds 250
		}	
	}
}


function repair-SCOM-agent
{
	Param([string]$computer)
	$outlog = "$currpth\fix_.log"
	$partial_log = @()
	$pth1 = "C$\Program Files\System Center Operations Manager\Agent\Health Service State\Health Service Store"
	$pth2 = "C$\Program Files\Microsoft Monitoring Agent\Agent\Health Service State\Health Service Store"

	function healthservice-stop {
		for ($r=1; $r -le 2; $r++)
		{
			Invoke-Expression "$currpth\PsService.exe \\$computer stop Healthservice"
			Start-Sleep 3
		}
	}

	function healthservice-start {
		for ($r=1; $r -le 2; $r++)
		{
			Invoke-Expression "$currpth\PsService.exe \\$computer start Healthservice"
			Start-Sleep 3
		}
	}

	$partial_log += "checking $computer"
	if(Test-Connection $computer -Count 1 -ErrorAction SilentlyContinue)
	{
		$partial_log += "$computer is alive"
		$service = Get-Service -ComputerName $computer -Name Healthservice
		if($service)
		{
			$partial_log += "service exists"
			if($service | Where-Object {$_.Status -match "running"})
			{
				$partial_log += "service is running on $computer"
				$testpath1 = Test-Path \\$computer\$pth1 -ErrorAction SilentlyContinue
				$testpath2 = Test-Path \\$computer\$pth2 -ErrorAction SilentlyContinue
				if($testpath1 -eq $true -or $testpath2 -eq $true)
				{
					$partial_log += "Health Service store exist"
					$partial_log += "removing healthservice store on $computer"
					healthservice-stop
					if($testpath1 -eq $true)
					{
						Remove-Item \\$computer\$pth1\*.* -Force
					}
					Else
					{
						Remove-Item \\$computer\$pth2\*.* -Force
					}
					healthservice-start
				}
				Else
				{
					$partial_log += "Health Service store does not exist"
				}
			}
			Else
			{
				if($service.Status -like "*Pending*")
				{
					$partial_log += "service not running on $computer status: $($service.Status) kill process and force start service"
					Invoke-Expression "$currpth\pskill.exe \\$computer -t Healthservice.exe"
					Start-Sleep 3
					healthservice-stop
					healthservice-start
				}
				Else
				{
					$partial_log += "service not running on $computer status: $($service.Status) force start service"
					healthservice-start
				}
			}
		}
		Else
		{
			$partial_log += "service does not exists on $computer"
			Write-Output $computer | Out-File $currpth\check_scom_installation\machines.log -Append
		}          
	}
	Else
	{
		$partial_log += "$computer does not respond to ping"
	}
	$partial_log += "-------------- checking ended of $computer at: $(get-date) --------------------"
	$partial_log | Out-File $outlog -Append
}
