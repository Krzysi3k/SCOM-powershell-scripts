cls
Import-Module OperationsManager

function run-main
{
    $lastdays = Read-Host "type number of last days to check"
    try
    {
        $lastdays = [convert]::ToInt32($lastdays)
    }
    catch
    {
        Write-Warning "you need to type integer`n"
        run-main
    }
    if(($lastdays.GetType()).Name -eq 'Int32')
    {
        machines-installed -days $lastdays
    }
}


function machines-installed
{
    Param([int]$days)
    $agents = Get-SCOMAgent | Where-Object {$_.InstallTime -ge ((Get-Date).AddDays(-$days))}
    $agents | select HealthState,DisplayName,InstallTime,Version | Sort-Object HealthState -Descending | Format-Table -AutoSize

    $job = @()
    foreach($a in $agents)
    {
        $agent = $a.DisplayName
        $conn = Test-Connection $agent -Count 1 -AsJob
        $job += $conn
    }
    
    Do
    {
        Start-Sleep -Seconds 2
    }
    While($job.State -eq 'Running')

    $table = Receive-Job -Job $job | select Address,StatusCode
    foreach($t in $table)
    {
        switch($t.StatusCode)
        {
            11010 {$t | Add-Member -MemberType NoteProperty -Name 'status' -Value 'Ping Timed Out'}
            0 {$t | Add-Member -MemberType NoteProperty -Name 'status' -Value 'Online'}
            11002 {$t | Add-Member -MemberType NoteProperty -Name 'status' -Value 'Destination Net Unreachable'}
            11003 {$t | Add-Member -MemberType NoteProperty -Name 'status' -Value 'Destination Host Unreachable'}
            11013 {$t | Add-Member -MemberType NoteProperty -Name 'status' -Value 'TimeToLive Expired Transit'}
            11050 {$t | Add-Member -MemberType NoteProperty -Name 'status' -Value 'General Failure'}
            default {$t | Add-Member -MemberType NoteProperty -Name 'status' -Value 'Unknown'}

        }
    }

    $table | Select-Object Address,status | Sort-Object StatusCode -Descending | Format-Table -AutoSize
    Write-Host "`nsummary:`n"
    Write-Host "machines installed: $($table.count)"
    Write-Host "machines online: $(($table | Where-Object StatusCode -EQ 0).count)"
    Write-Host "machines offline: $(($table | Where-Object StatusCode -NE 0).count)"
}
