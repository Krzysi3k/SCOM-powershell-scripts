# create events in ITSM
# script is executed by SCOM command subscription
# parameters passed to the script are defined in SCOM command channel

Param (
	[String]$src, 
	[string]$raisedtime, 
	[string]$alertname, 
	[string]$desc
)

$description = ($desc -replace '\\n ','').ToString()
$countries = @("W8-PL", "W8-LT", "W8-LV", "W8-EE", "W8-SE", "W8-DK", "W8-NO", "W8-RU")
$2ndline = "IT Retail 2nd"
$1stline = "Retail Service Desk"
$team = "unknown"

if(($src.Split('\') | select -First 1) -match 'domain.com')
{
	$pcname = $src.Split('\') | Select -First 1
}
else
{
	$pcname = $src.Split('\') | Select -Last 1
}

$pcname = $pcname.Substring(0,$pcname.Length -22)

foreach($country in $countries)
{
	if($pcname -match $country)
	{
		if($pcname -match "LV" -or $pcname -match "LT" -or $pcname -match "EE" -or $pcname -match "RU")
		{
			$team = "$2ndline $($country.Trim("W8-"))"
		}
		else
		{
			$team = "$1stline $($country.Trim("W8-"))"
		}
	}
}


function create-body
{
    Param(
        [string]$team, 
        [string]$src, 
        [string]$alertname, 
        [string]$description, 
        [string]$pcname, 
        [string]$raisedtime
    )
    if($team -EQ "unknown")
    {
	    # dump log and exit script 
	    Write-Output "$(get-date -Format "yyyyMMdd HH:mm:ss") uknown source of the alert, source: $src, alertname: $alertname, team: $team"`
	    | Out-File D:\scripts\SCOM_2_ITSM_Integration\err.log -Append
	    exit
    }

    # create XML structure
    $body = 
    "<EVENT>
    <DESCRIPTION>$description</DESCRIPTION>
    <CINAME>$pcname</CINAME>
    <EventStartDateTime>$raisedtime</EventStartDateTime>
    <Source>SCOM Monitoring</Source>
    <OwnerTeam>$team</OwnerTeam>
    <Priority>4</Priority>
    </EVENT>"

    dump-to-log -src $src -desc $desc -description $description -body $body -alertname $alertname
}


function dump-to-log
{
    Param(
        [string]$src,
        [string]$desc,
        [string]$description,
        [string]$body,
        [string]$alertname
    )

    $tstamp = (get-date -Format "yyyyMMdd HH:mm:ss")
    "$tstamp $src" | Add-Content D:\scripts\SCOM_2_ITSM_Integration\src.log
    "$tstamp $desc" | Add-Content D:\scripts\SCOM_2_ITSM_Integration\desc.log
    "$tstamp $description" | Add-Content D:\scripts\SCOM_2_ITSM_Integration\description.log
    $body | Add-Content D:\scripts\SCOM_2_ITSM_Integration\body.log
    "$tstamp $alertname" | Add-Content D:\scripts\SCOM_2_ITSM_Integration\alertname.log

    send-to-ITSM -body $body
}


function send-to-ITSM
{
    Param([string]$body)
    $sender = "sender@domain.com"
    $recipient = "recipient@domain.com"
    $server = "smtpserver.domain.com"
    Send-MailMessage -From $sender -To $recipient -SmtpServer $server -Subject "Event" -Body $body
}


create-body -team $team -src $src -alertname $alertname -description $description -pcname $pcname -raisedtime $raisedtime
