Import-Module OperationsManager
$currpth = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$smtp = "yoursmtpserver.domain.com"
$sender = "sender@domain.com"
$recipient = "recipient@domain.com"
$pmgmt = Get-SCOMPendingManagement
$output = "C:\Temp\output.log"
$approved = "approved.log"
$notapproved = "not_approved.log"
$body = @()

if($pmgmt)
{
    Get-Date -Format ("dd/MM/yyyy hh:mm:ss") | Add-Content $currpth\$approved, $currpth\$notapproved
    $pmgmt.AgentName | Out-File $output
    $body += "$(Get-Date -Format ("dd/MM/yyyy hh:mm:ss"))`nall pending machines:`n"
    $agents = Get-Content $output
    $body += $agents | % {Write-Output $_`n}
    foreach($mgmt in $pmgmt)
    {
        $conn = (Test-Connection $mgmt.AgentName -ErrorAction SilentlyContinue)
        if($conn)
        {
            "approving $($mgmt.AgentName)" | Add-Content $currpth\$approved
            Approve-SCOMPendingManagement -PendingAction $mgmt
        }
        Else
        {
            "pending NOT approved $($mgmt.AgentName)" | Add-Content $currpth\$notapproved
        }
    }
    #send email with pending management status
    Send-MailMessage -From $sender -To $recipient -SmtpServer $smtp -Subject "Pending Management" -Body "$body" -Attachments $currpth\$approved,$currpth\$notapproved
}
