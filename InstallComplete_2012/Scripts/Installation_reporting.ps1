# ====================================================================================================
# 
# NAME: installation_reporting.ps1
# 
# AUTHOR: Holger Voges
# DATE  : 12.01.2011
# 
# COMMENT: 	This is a post installation-script which checks and Reports SQL-Instance-Settings
# =====================================================================================================

param(
[switch]$help,
[string]$ServerInstance=$(Throw "Parameter missing: -ServerInstance Server\Instanz; -help for all Parameters"),
[string]$outpath="C:\TEMP\",
[string]$UC4Group="DOM1\P12795",
[string]$BackupUser="DOM1\P12795",
[string]$ACFGroup="DOM1\CSS_CC11SQLFull_DS",
[string]$tdptest = $true
)

Set PS-Debug-Strict 

function main()
{
	$DebugPreference="SilentlyContinue"
	if ( $help ) {
	"Usage: Installation_reporting.ps1 -ServerInstance <string[]> -out [<string[]>] -$UC4Group [<string[]>] -BackupUser [<string[]>] `
	-$ACFGroup [<string[]>]"
	exit 0
	}
	$ServerDaten = @{}	# contains Server-data
	$LabelDescEN = @{}	# contains description of all the server-data from $Serverdaten, used for output
	# $output defines the order in which $Serverdaten will be sorted in the output-file
	$output = "Servername","Instancename","Edition","ServicePack","Version","Productlevel","Language", `
	"AuthenticationMode","Collation","AuditLevel","Errorlogs","netlib","Port","itmRunning","UC4","LocalAdminActive",
	"SQLAdmins","Cluster","DBMirroring_active","tempdb_datafiles","tempdb_logfiles", `
	"Master_Data_path","Master_log_path","InstallSharedDir","installDataDir","InstallLogDir","ErrorLogPath","ServiceInstanceID", `
	"ServiceStartmode","AgentStartMode","SQLServiceaccount","AgentServiceAccount","tdpInstalled","tdpversion","backuptest","audits","auditJob","NotInFullRecover","nonshared"
	$LocalAdmin = "Builtin\Administrators"
	$SmoVer = [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
	$WmiVer = [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")
	$SmoServer = New-Object('Microsoft.SQLServer.Management.SMO.Server')("$ServerInstance")
	$WmiServer = New-Object('Microsoft.SQLServer.Management.SMO.Wmi.ManagedComputer')
	$serverName = $SmoServer.NetName
    if ($SmoServer.InstanceName -eq "")
		{$InstanceName ="MSSQLSERVER"
		 $tdpInstanceName = "STD"}
	else 
		{$InstanceName = $itmInstance = $SmoServer.InstanceName
		 $tdpInstanceName = $SmoServer.InstanceName}
	Check_SQLServer
	$LabelDesc = Fill_LabelDesc
	$def = fill_defaults
	get_maindata
	Generate_Report
	
	
	
}


function check_SQLServer()
# Checks the availabilty of the server
{
$Error.Clear()
trap{write-host -ForegroundColor Red "Please check Instancename and availability of SQL-Service";Continue}
	
	& {
	$sqlCon = New-Object Data.SqlClient.SqlConnection
	$sqlCon.ConnectionString = "Data Source=$ServerInstance;Integrated Security=True"
	$sqlCon.open()
	}
if ($Error.Count -ne 0){break}
}

function fill_defaults()
{
	$defaults=@{}
	$defaults.Add("AgentServiceAccount",'($Serverdaten.AgentServiceAccount -eq $Serverdaten.SQLServiceAccount) -and `
	$Serverdaten.AgentServiceAccount -notlike "NT*"') 
	$defaults.Add("AuditLevel",'$Serverdaten.Auditlevel -eq "Failure"')
	$defaults.Add("AuthenticationMode",'$Serverdaten.Authenticationmode -eq "Mixed"')
	$defaults.Add("backuptest",'$Serverdaten.backuptest -like "*working"')
	$defaults.Add("tdpversion",'$Serverdaten.tdpversion -like "7.1.*"')
	$defaults.Add("tdpInstalled",'$Serverdaten.tdpInstalled -notlike "*not*"')
	$defaults.Add("Cluster",'')
	$defaults.Add("Collation",'')
	$defaults.Add("DBMirroring_active",'')
	$defaults.Add("Edition",'')
	$defaults.Add("ErrorLogPath",'')
	$defaults.Add("Errorlogs",'$Serverdaten.ErrorLogs -eq "30"')
	$defaults.Add("InstallDataDir",'') #Instance.../data
	$defaults.Add("InstallLogDir",'')  # .../data
	$defaults.Add("InstallSharedDir",'$ServerDaten.InstallSharedDir.startswith("D:\")')
	$defaults.Add("InstanceName",'')
	$defaults.Add("itmRunning",'$Serverdaten.itmRunning -like "*OKAY*"')
	$defaults.Add("audits",'$Serverdaten.audits -notlike  "*Audits not inistalled*"')
    $defaults.Add("auditJob",'$Serverdaten.auditJob -notlike  "*No audit job inistalled*"')
	$defaults.Add("Language",'$Serverdaten.Language -eq "English (United States)"')
	$defaults.Add("LocalAdminActive",'$Serverdaten.LocalAdminActive -eq ""')
	$defaults.Add("Master_data_path",'-not $ServerDaten.master_data_path.startswith("C:\")') #<> C:
	$defaults.Add("Master_log_path",'-not $ServerDaten.master_log_path.startswith("C:\")') #<> C:
	$defaults.Add("Netlib",'$Serverdaten.Netlib -match "tcp"')
	$defaults.Add("NonShared",'')
	$defaults.Add("notInFullRecover",'')
	$defaults.Add("Port",'$Serverdaten.Port -ge 1433 -and $Serverdaten.Port -le 1450') # between 1434 and 1450
	$defaults.Add("ProductLevel",'')
	$defaults.Add("Servername",'')
	$defaults.Add("ServiceInstanceID",'')
	$defaults.Add("ServicePack",'')
	$defaults.Add("ServiceStartMode",'$Serverdaten.ServiceStartMode -eq "Auto"')
	$defaults.Add("AgentStartMode",'$Serverdaten.AgentStartMode -eq "Auto"')
	$defaults.Add("SQLAdmins",'$Serverdaten.SQLAdmins -eq "true"')
	$defaults.Add("SQLServiceAccount",'$Serverdaten.SQLServiceAccount -notlike "NT*"') #dom-x
	$defaults.Add("tempdb_datafiles",'') #<= cpu/2 <=cpu
	$defaults.Add("tempdb_logfiles",'')
	$defaults.Add("UC4",'$Serverdaten.UC4 -eq "true"')
	$defaults.Add("Version",'')
	$defaults.Add("SA_disabled",'')
	$defaults
}

function Fill_LabelDesc
{
	$LabelDescEN["Servername"]="Server"
	$LabelDescEN["Instancename"]="Instance"
	$LabelDescEN["Edition"]="Edition"
	$LabelDescEN["Version"]="Version"
	$LabelDescEN["ServicePack"]="ServicePack level"
	$LabelDescEN["Language"]="Language"
	$LabelDescEN["Cluster"]="Is Server clustered"
	$LabelDescEN["AuthenticationMode"]="AuthenticationMode"
	$LabelDescEN["Collation"]="Collation"
	$LabelDescEN["AuditLevel"]="Audit-Level"
	$LabelDescEN["ErrorLogs"]="Number of errorlog files"
	$LabelDescEN["ServiceInstanceID"]="ServiceInstanceID"
	$LabelDescEN["ServiceStartMode"]="MSSQL Service StartMode"
	$LabelDescEN["AgentStartMode"]="MSSQL Agent StartMode"
	$LabelDescEN["SQLServiceAccount"]="MSSQL ServiceAccount"
	$LabelDescEN["AgentServiceAccount"]="MSSQL Agent ServiceAccount"
	$LabelDescEN["InstallSharedDir"] ="Shared directory"
	$LabelDescEN["InstallDataDir"] ="Default data directory"
	$LabelDescEN["InstallLogDir"] ="Default log directory"
	$LabelDescEN["ErrorLogPath"] ="Errorlog directory"
	$LabelDescEN["Master_data_path"] ="MasterDB data directory"
	$LabelDescEN["Master_log_Path"] ="MasterDB log Path"
	$LabelDescEN["netlib"] ="Installed Network Libraries"
	$LabelDescEN["Port"] ="TCP Port"
	$LabelDescEN["NonShared"] ="Installed non-shared services"
	$LabelDescEN["LocalAdminActive"] ="LocalAdmin group member of Sysadmin"
	$LabelDescEN["SQLAdmins"] ="$ACFGroup member of Sysadmin"
	$LabelDescEN["UC4"] ="$UC4Group member of Sysadmin-Role"
	$LabelDescEN["tempdb_datafiles"] ="TempDB datafiles"
	$LabelDescEN["tempdb_logfiles"] ="TempDB logfiles"
	$LabelDescEN["DBMirroring_active"] ="Mirrored databases"
	$LabelDescEN["itmRunning"] ="Status of DBSPI"
    $LabelDescEN["audits"] ="Status of audits"
    $LabelDescEN["auditJob"] ="Status of audit job"
	$LabelDescEN["notInFullRecovery"] ="Databases not in FullRecovery mode"
	$LabelDescEN["tdpInstalled"]="TDP installed"
	$LabelDescEN["tdpversion"]="TDP version"
	$LabelDescEN["backuptest"]="TDP backup test"
	$LabelDescEN["SA_disabled"]="sa disabled"
}

function get_maindata()

{
	$ServerDaten["Servername"]=$SmoServer.NetName
	if ($SmoServer.InstanceName -eq "")
		{
		$ServerDaten["InstanceName"] = "MSSQLSERVER"
		$itmInstance = $SmoServer.NetName
		}
	else 
		{$ServerDaten["Instancename"]=$SmoServer.InstanceName}
		$ServerDaten["Edition"]=$SmoServer.Edition
		$ServerDaten["Version"]=$SmoServer.Version
		$ServerDaten["ServicePack"]=$SmoServer.ProductLevel
		$ServerDaten["Language"]=$SmoServer.Language
		$ServerDaten["Cluster"]=$SmoServer.IsClustered
		$ServerDaten["AuthenticationMode"]=$SmoServer.LoginMode
		$ServerDaten["Collation"]=$SmoServer.Collation
		$ServerDaten["AuditLevel"]=$SmoServer.AuditLevel
		$ServerDaten["ErrorLogs"]=$SmoServer.NumberOfLogFiles
		$ServerDaten["ServiceInstanceID"]=$SmoServer.ServiceInstanceID
		$ServerDaten["ServiceStartMode"]=$SmoServer.ServiceStartMode
		$ServerDaten["AgentStartMode"]=$SmoServer.JobServer.ServiceStartMode
		$Serverdaten["SQLServiceAccount"]=$SmoServer.ServiceAccount
		$Serverdaten["AgentServiceAccount"]=$SmoServer.JobServer.ServiceAccount
		$Serverdaten["InstallSharedDir"] = ($smoserver.InstallSharedDirectory).ToUpper()
		$Serverdaten["InstallDataDir"] = $SmoServer.InstallDataDirectory.ToUpper()
		$Serverdaten["InstallLogDir"] = $SmoServer.DefaultLog.ToUpper()
		$Serverdaten["ErrorLogPath"] = $smoServer.ErrorLogPath.ToUpper()
		$Serverdaten["Master_data_path"] = ($SmoServer.MasterDBPath).ToUpper()
		$Serverdaten["Master_log_Path"] = ($SmoServer.MasterDBLogPath).ToUpper()
		$Serverdaten["netlib"] = get_netlib
		$Serverdaten["Port"] = get_port
		$ServerDaten["NonShared"] = get_nonshared
		$Serverdaten["LocalAdminActive"] = get_groups $LocalAdmin
		$Serverdaten["SQLAdmins"] = get_groups $ACFGroup
		$Serverdaten["UC4"] = get_groups $UC4Group
		$Serverdaten["tempdb_datafiles"] = check_tempdb data
		$Serverdaten["tempdb_logfiles"] = check_tempdb log
		$Serverdaten["DBMirroring_active"] = get_mirroredDBs
		$Serverdaten["itmRunning"] = get_dbspi
        $Serverdaten["audits"] = check_audits
        $Serverdaten["auditJob"] = check_auditJob
		$ServerDaten["notInFullRecovery"] = get_DBNotFullRec
		$ServerDaten["tdpInstalled"] = test_tdp
		if ($Serverdaten["tdpInstalled"] -notlike "*not*")
		{$ServerDaten["tdpversion"] = (Get-ItemProperty "HKLM:\SOFTWARE\IBM\ADSM\CurrentVersion\TDPSQL\" PTFLevel).PTFLevel}
		if ($ServerDaten["tdpversion"] -and $tdptest -eq $true)
			{$ServerDaten["backuptest"] = test_backup}
		$ServerDaten["SA_disabled"] = check_sa
	
}

function get_netlib()

{
	$Ret=""
	$server= $wmiServer.ServerInstances["$instancename"]
	foreach ($prot in $server.ServerProtocols){if ($prot.IsEnabled -eq $true){$Ret += $prot.name +", "}}
	Return $Ret
}

function get_nonshared()

{
	$Ret=""
	foreach ($service in $wmiServer.Services)
		{If (($Service.Type -notlike "SqlServer") -and ($Service.Type -notlike "SqlAgent")){$service.Displayname + "`<br`>" + $service.ServiceAccount + "`<br`>" + $Service.ServiceState `
		+ "`<br`>" + $service.StartMode +"`<br`>"}}	
	Return $Ret
	
}

function get_port()
{
	$server =$wmiServer.ServerInstances["$instancename"]
	$tcp = $server.ServerProtocols["Tcp"]
	$IPAll=($tcp.IPAddresses["IPAll"]).IpAddressProperties
	foreach($Port in $IPAll)
	 {if (($Port.name -eq "TcpDynamicPorts") -and ($Port.value -eq 0))
	  {Return "dynamisch"}
	 elseif (($Port.name -eq "TcpPort") -and ($Port.value -ne ""))
	  {$Port.Value}}
}

function get_Groups([string]$group)
{
	$Sysadmin = $SmoServer.Roles["sysadmin"]
	foreach ($Rolemember in $Sysadmin.EnumServerRoleMembers()){if ($group -eq $Rolemember){return $true}}
	return $false
}

function check_tempDB([string]$type)
{
	If ($type -eq "data")
		{foreach ($file in $($smoserver.databases["TempDB"]).Filegroups["Primary"].files){$file.FileName}}
	elseif ($type -eq "log")
		{foreach ($file in $($smoserver.databases["TempDB"]).Logfiles){$file.FileName}}
}

function get_mirroredDBs
{
	$Ret=""
 	foreach ($db in $SmoServer.Databases){if ($db.IsMirroringEnabled){$Ret += $db.Name + "`n"}}
	Return $Ret
}

function get_DBNotFullRec()
{
	$Ret=""
	foreach ($db in $SmoServer.Databases){if ($db.Recoverymodel -ne "FULL"){$Ret += $db.Name + "`n" }}
	Return $ret
}

function get_itmv6
{
IF ((get-itemProperty -ErrorAction SilentlyContinue `
		"HKLM:Software\Candle\KOQ\610\$itmInstance\Configuration" Services).Services)
	{$service = (get-itemProperty -ErrorVariable Err -ErrorAction SilentlyContinue `
		"HKLM:Software\Candle\KOQ\610\$itmInstance\Configuration" Services).Services
	(get-service | where-object {$_.name -eq $service.substring(0,$service.indexOf(" "))}).status}
elseif ((get-itemProperty -ErrorAction SilentlyContinue `
		"HKLM:Software\Wow6432Node\Candle\KOQ\610\$itmInstance\Configuration" Services).Services)
	{$service = (get-itemProperty -ErrorVariable Err -ErrorAction SilentlyContinue `
		"HKLM:Software\Wow6432Node\Candle\KOQ\610\$itmInstance\Configuration" Services).Services
	(get-service | where-object {$_.name -eq $service.substring(0,$service.indexOf(" "))}).status}
else {Return "ItmV6 not installed"}
}

function get_dbspi
{
if (test-path "c:\program files\hp openview\data\bin\instrumentation\dbspicam.bat")
#	{Return "DBSPI installed"}
	{ cd "c:\program files\hp openview\data\bin\instrumentation\"
    $output = .\dbspicam.bat -dpv
	if ($InstanceName -eq "MSSQLSERVER") {$item = "*$ServerName*"} else {$item = "*$InstanceName*"}
	$idx = 0..($output.Count - 1) | Where { $output[$_] -like $item }
	$output[$idx] + "->" + $output[$idx+1]
	}
	else {Return "DBSPI not installed"}
}		

function test_tdp
{
#if (Get-ChildItem HKLM:Software\Microsoft\Windows\CurrentVersion\uninstall | Where-Object {$_.name -like "*TSM-for-Databases*"})
if (Test-Path HKLM:SOFTWARE\IBM\FlashCopyManager)
	{Return "TDP FlashCopyManager installed"}
	else {Return "TDP FlashCopyManager not installed"}
}

function test_backup
{
$nodename=$tdpInstancename + "_" + $SmoServer.NetName
# $node verifys if a tdp-node exists
If (Get-childitem -Path "HKLM:\SOFTWARE\IBM\ADSM\CurrentVersion\Nodes" | % {$_.PsChildname} | Where-Object {$_ -eq "$nodename"})
	{$tdppath=(Get-ItemProperty "HKLM:\SOFTWARE\IBM\ADSM\CurrentVersion\TDPSQL\" Path).Path
	$tsmpath=(Get-ItemProperty "HKLM:\SOFTWARE\IBM\ADSM\CurrentVersion" TSMSqlPath).TSMSqlPath
	$tsmconfig = $tsmpath + $tdpInstanceName + "\conf\tdpsql.cfg"
	$tsmopt = $tsmpath + $tdpInstanceName + "\conf\dsm.opt"
	$tdp = Get-Command $tdppath\tdpsqlc.exe
	$backup_out = & $tdp backup master full /configfile=$tsmconfig /TSMOPTFILE=$tsmopt
	if ($backup_out | Select-String "successfully")
		{Return "Backup master working"}
	else
		{Return "Backup master failed"}
	}
else
	{return "tdp not configured for this instance"}
}

function check_audits
{
	If ($Smoserver.Audits.Count -eq 2)
		{foreach ($audit in ($Smoserver.Audits)){ $audit.Name+": " + $audit.Enabled}}
	else 
		{return "Audits not inistalled"}
}

function check_auditJob
{
if ($SmoServer.JobServer.Jobs | Where-Object {$_.Name -eq "DBA Job 'Cycle_Auditlogs'"})
    {$job = ($SmoServer.JobServer.Jobs | Where-Object {$_.Name -eq "DBA Job 'Cycle_Auditlogs'"})
    $job.LastRunOutcome.ToString() + " -> " + $job.LastRunDate.ToString('d')
    }
else
    {return "No audit job inistalled"}
}



function check_sa
{
"not implemented"
}

function Prepare_html
{
$script:html = @'
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
		"http://www.w3.org/TR/html4/loose.dtd">
<html>
<head>
<title>Serverreport</title>

<style type="text/css">
.table {
				font-family: Arial, Helvetica, Sans-Serif;
				border-width: 2px;
}
.td		 {
				font-family: Arial, Helvetica, Sans-Serif;
				border-width: 1px;
}
.td_bold {
				font-family: Arial, Helvetica, Sans-Serif;
				border-width: 1px;
				font-weight: bold;
}
.td_red {
				font-family: Arial, Helvetica, Sans-Serif;
				border-width: 1px;
				background-color: #FF5050;
}
.td_green {
				font-family: Arial, Helvetica, Sans-Serif;
				border-width: 1px;
				background-color: #99FF66;
}

</style>
</head>
<body>
'@
$script:html += @"

<h3>created $(get-date -format F)</h3><br>
"@
}


function check_defaults($compare)
{	
	if (!$def.$compare -eq "" )
		{
		$string="if ($($def.$compare)){'`<td class=`"td_green`"`>'} else {'`<td class=`"td_red`"`>'};"
		Invoke-Expression $string
		}
	else
		{
		'<td class="td">'
		}
}


function Generate_Report()
{
		#Prepare_html
$html = @'
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
		"http://www.w3.org/TR/html4/loose.dtd">
<html>
<head>
<title>Serverreport</title>

<style type="text/css">
.table {
				font-family: Arial, Helvetica, Sans-Serif;
				border-width: 2px;
}
.td		 {
				font-family: Arial, Helvetica, Sans-Serif;
				border-width: 1px;
}
.td_bold {
				font-family: Arial, Helvetica, Sans-Serif;
				border-width: 1px;
				font-weight: bold;
}
.td_red {
				font-family: Arial, Helvetica, Sans-Serif;
				border-width: 1px;
				background-color: #FF5050;
}
.td_green {
				font-family: Arial, Helvetica, Sans-Serif;
				border-width: 1px;
				background-color: #99FF66;
}
h2,h3    {     font-family: Arial, Helvetica, Sans-Serif;
}

</style>
</head>
<body>
'@
        $html += "<h2>Report for Server: $ServerInstance</h2>"
        $html += "<h3>Created: $(get-date -format F)</h3><br>"
        $html += "`<table class=`"table`"`>`n"
		foreach($prop in $output)
			{if ($ServerDaten.$prop -is [System.Array])
				{$html = $html + "`<tr`>`<td` valign=`"top`" class=`"td_bold`">$($LabelDescEN.$Prop)`</td`>`<td`>`n"; 
				 for ($i=0;$i -lt $ServerDaten.$prop.count;$i++)
				 		{$html = $html + $serverdaten.$prop[$i] + "`<br`>"}
				 $html = $html + "`</td`>`</tr`>"}
			else
				{
				# $html += "`<tr`>" + (check_defaults($prop)) + "`<td class=`"td`"`>$($LabelDesc.$Prop)`</td`>`<td`>$($serverdaten.$prop)`</td`>`n"
				$html += "`<tr`><td class=`"td_bold`"`>$($LabelDescEN.$Prop)`</td`>" + (check_defaults($prop)) + "$($serverdaten.$prop)`</td`>`</tr`>`n"
				# $html += "`<td`>" + (check_defaults($prop)) + "`</td`>`</tr`>`n"
				}				
			}
		$html += "`</table`>`</body`>`</html`>"
		$html | Out-File $outpath"ServerReport_$tdpInstanceName.html"
}


. Main