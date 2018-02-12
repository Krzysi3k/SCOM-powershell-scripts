# SCOM to HEAT script - create events in HEAT
# script is executed by SCOM command subscription
# parameters passed to the script are defined in SCOM command channel

Param (
	[String]$src, 
	[string]$raisedtime, 
	[string]$alertname, 
	[string]$desc
)

$description = ($desc -replace '\\n ','').ToString()
$countries = @("W8-PL", "W8-LT", "W8-LV", "W8-ES", "W8-SE", "W8-DK", "W8-NO", "W8-RU")
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

# change Estonia from EE to ES:
if($pcname -match "W8-EE")
{
    $pcname = $pcname.Replace("W8-EE","W8-ES")
}

foreach($country in $countries)
{
	if($pcname -match $country)
	{
        $team = "$1stline $($country.Trim("W8-"))"
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
        # dump log and exit script:
		$textOutput = "$(get-date -Format "yyyyMMdd HH:mm:ss") uknown source of the alert, source: $src, alertname: $alertname, team: $team"
        output-Wtimeout -text $textOutput -pth "D:\scripts\SCOM_2_HEAT_Integration\err.log"
	    exit
    }

    # Revert Estonia from ES to EE:
    if($pcname -match "W8-ES")
    {
        $pcname = $pcname.Replace("W8-ES","W8-EE")
    }

    if($alertname -eq "Octane Export XML files found")
    {
        $description += "`nOrder document (with prefix in filename EHHT) has been stopped at BOS station in folder 'C:\OCT2000\export' and cannot be processed to EDI platform by service f2q.`
`n1. Reboot BOS computer`
`n2. Make sure that service 'filex F2Q Service' is running"
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
    output-Wtimeout -text "$tstamp $src" -pth "D:\scripts\SCOM_2_HEAT_Integration\src.log"

    output-Wtimeout -text "$tstamp $desc" -pth "D:\scripts\SCOM_2_HEAT_Integration\desc.log"
    output-Wtimeout -text "$tstamp $description" -pth "D:\scripts\SCOM_2_HEAT_Integration\description.log"
    output-Wtimeout -text $body -pth "D:\scripts\SCOM_2_HEAT_Integration\body.log"
    output-Wtimeout -text "$tstamp $alertname" -pth "D:\scripts\SCOM_2_HEAT_Integration\alertname.log"
        
    send-to-heat -body $body
}

function output-Wtimeout
{
    Param(
        [string]$text,
        [string]$pth
    )
    [int]$rnd = Get-Random -Minimum 1 -Maximum 5000
    Start-Sleep -Milliseconds $rnd
    $text | Add-Content $pth
}

function send-to-heat
{
    Param([string]$body)
    $sender = "sender@domain.com"
    $recipient = "recipient@domain.com"
    $server = "smtp.domain.com"
    Send-MailMessage -From $sender -To $recipient -SmtpServer $server -Subject "Event" -Body $body
}

create-body -team $team -src $src -alertname $alertname -description $description -pcname $pcname -raisedtime $raisedtime