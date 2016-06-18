# ====================================================================================================
# 
# NAME: create_ini.ps1
# 
# AUTHOR: Holger Voges
# DATE  : 07.04.2011 : Initial release
# 
# COMMENT: 	Script for creating a setup.ini-file from Input-parameters. Parameters should be 
#			provided by instGui.ini.
# CHANGES: -Added Support for MSSQL2008R2
#				- IACCEPTSQLSERVERLICENSETERMS
#				- corrected Path to Installation-log
#			13.03.2012
#			- added to function installps1: function restore_PendingFileRename
#			- added FMO-Switches
#			- added different Useraccount for SQL-Agent
#			12.11.2014
#			- 2012 ready (incl. new auditiung)
# =====================================================================================================

param(
[switch]$help,
[switch]$FMO,
[switch]$STD,
[bool]$SQLEngine,
[bool]$Tools,
[bool]$MSIS,
[bool]$MSAS,
[bool]$MSRS,
[bool]$PCU,
[bool]$CU,
[string]$InstanceName=$(Throw "Parameter missing: -InstanceName Instanz; -help for all Parameters"),
[int]$TcpPort,
[string]$SQLServiceDom,
[string]$AgentDom,												#FMO
[string]$ServiceUser,
[string]$AgentUser,												#FMO
[string]$ServiceUserPW,
[string]$AgentUserPW,											#FMO
[string]$MSSQLVersion,
[string]$MSSQLEdition,
[string]$Collation,
[char]$BinDrive="D",
[char]$sysDBDataDrive,
[char]$sysDBLogDrive,
[char]$TempDBDataDrive,
[char]$TempDBLogDrive,
[char]$UserDBDataDrive,
[char]$UserDBLogDrive,
[string]$SQLAdmins="DOM1\CSS_CC11SQLFull_DS"
)

function main()
{
	Set PS-Debug-Strict
	$DebugPreference="SilentlyContinue"
	$ReturnToGUI = @{} # contains return-values for the calling script
	
		write-host $instancename
		
	if ( $help ) {
	write-host "Usage: Please don´t start this script manually"
	exit 0
	}
	
	Switch ($MSSQLVersion)
	{
		"MSSQL 2005"	{$MSSQLVerNr = "9";$SQLString="SQLSERVER2005"}
		"MSSQL 2008"	{$MSSQLVerNr = "10";$SQLString="SQLSERVER2008"}
		"MSSQL 2008 R2" {$MSSQLVerNr = "10_50";$SQLString="SQLSERVER2008"}
		"MSSQL 2012" 	{$MSSQLVerNr = "11";$SQLString="OPTIONS"}
	}
	
	# Variables
	If (!$Agentuser)
	{
		$Agentuser=$ServiceUser
		$AgentUserPW=$ServiceUserPW
		$AgentDom=$SQLServiceDom
	}
	If ($FMO){$AuthModeWindows=$true}
	else {$AuthModeWindows=$false}
	If ($STD){$InstanceName="TD"}
	else {$InstanceName=$InstanceName}
	
	$ServerInstance=$((dir env:computername).value) + "\S" + $Instancename
	$UserDBDataDir="$($UserDBDataDrive):\Microsoft SQL Server\S$InstanceName\Instance\MSSQL$MSSQLVerNr.S$InstanceName\MSSQL\Data"
	$UserDBLogDir="$($UserDBLogDrive):\Microsoft SQL Server\S$InstanceName\Instance\MSSQL$MSSQLVerNr.S$InstanceName\MSSQL\Data"
	$TempDBDataDir="$($TempDBDataDrive):\Microsoft SQL Server\S$InstanceName\Instance\MSSQL$MSSQLVerNr.S$InstanceName\MSSQL\Data"
	$TempDBLogDir="$($TempDBLogDrive):\Microsoft SQL Server\S$InstanceName\Instance\MSSQL$MSSQLVerNr.S$InstanceName\MSSQL\Data"
	$BackupDir="$($UserDBDataDrive):\Microsoft SQL Server\S$InstanceName\Instance\MSSQL$MSSQLVerNr.S$InstanceName\MSSQL\Backup"
	$SQLBinDir="$($BinDrive):\Program Files\Microsoft SQL Server"
	$SQLBinDirWOW="$($BinDrive):\Program Files (x86)\Microsoft SQL Server"
	$SYSDBDir="$($sysDBDataDrive):\Microsoft SQL Server\S$InstanceName\Instance"
	If (Test-Path D:\)
		{$InstallDrive = "D:"} 
	else 
		{$InstallDrive = "C:"}
	$installFolder = "Install\UnattendedInstallation"
	$SetupFolder = ($MSSQLVersion).Replace(" ","_") + "_" + $MSSQLEdition + "_EN_S" + $InstanceName
	$SQLSourceFolder = ($MSSQLVersion).Replace(" ","_") + "_Full"
	$compDom = (Get-WmiObject -Namespace root\CIMV2 -Class Win32_ComputerSystem | % {$_.domain})
	$Dom = $compDom.Substring(0,$compDom.IndexOf("."))
	$configFile = "Configuration_$dom.xml"
		
	# If configuration.xml exist, read and evaluate the AdminAccount-Values.
	# ApplyConfig returns a Hash-Array with two members. AdminAccounts holds the valid account, 
	# NotExistingAccounts the 
	if (Test-Path "$mypath\$ConfigFile")
		{ $ReturnToGui += ApplyConfig( "$mypath\$ConfigFile" ) }
	else 
		{ Write-Debug "No config-file found. Default-settings will be applied" }
	If ( $ReturnToGui.AdminAccounts )
		{ $SQLAdmins = [System.String]::Join( "`" `"" , $ReturnToGui.AdminAccounts ) }
		
	$Features=@()  # will contain the used features
	if ($((Get-WmiObject -Namespace root\CIMV2 -Class Win32_ComputerSystem | % {$_.systemtype}).substring(1,2)) -eq "64")
		{$x64 = $true} 
	else 
		{$X64 = $false}
	$script:ini=@"
; MSSQL-Server-Configuration-File for Installation of $((dir env:computername).value)\S$InstanceName
; Creation-Date: $(get-date)
; Creator: $((dir env:Username).value)
; Version: $MSSQLVersion
[$SQLString]
Action="Install"
HELP="False"
INDICATEPROGRESS="False"
QUIET="False"
QUIETSIMPLE="True"
ERRORREPORTING="False"
INSTALLSHAREDDIR="$SQLBinDir"
INSTANCEDIR="$SQLBinDir"
SQMREPORTING=False
ENABLERANU="False"`r`n
"@
	If (!$STD) 	#named instance
		{$script:ini+=@"
INSTANCEID="S$InstanceName"
INSTANCENAME="S$InstanceName"`r`n
"@}
	else	#default instance
	{$script:ini+=@"
INSTANCEID="STD"
INSTANCENAME="MSSQLSERVER"`r`n
"@}
	#if ($PCU){$ini += "PCUSOURCE =`"$InstallDrive\$installFolder\$SQLSourceFolder\PCU`"`r`n"}
	if ($X64){$ini += "INSTALLSHAREDWOWDIR=`"$SQLBinDirWOW`"`r`n"}
	if ($MSSQLVersion -eq "MSSQL 2008"){add_2008}
	if ($MSSQLVersion -eq "MSSQL 2008 R2"){add_2008R2}
	if ($MSSQLVersion -eq "MSSQL 2012"){add_2012}
	if ($SQLEngine){add_SQLEngine
					$Features += "SQLENGINE"}
	if ($Tools){$Features += "BC"
				$Features += "Conn"
				$Features += "SSMS"
				$Features += "ADV_SSMS"}
	if ($MSIS){add_IS
			$Features += "IS"}
	if ($MSRS){add_RS
			$Features += "RS"}
	if ($MSAS){add_AS
			$Features += "AS"}
	$features=[system.string]::Join(",",$features)
	if ($MSSQLVersion -eq "MSSQL 2005"){$ini += "ADDLOCAL=" +$features}
	else {$ini += "FEATURES=" + $features}
	Create_InstallFolder
	$explorer = @(Get-Command explorer.exe -CommandType Application)
	& $explorer[0] $InstallDrive\$installFolder\$SetupFolder
	$ReturnToGui.Add("SetupScript","$InstallDrive\$installFolder\$setupFolder\install.ps1")
	Return $ReturnToGUI
}

function ApplyConfig([string]$configfile)
# Function reads the Configuration-File and returns a hashtable with two arrays, AdminAccount with the valid 
# accounts and NonExistingAccounts with the accounts not found in AD
{
	$ValidCheckBoxValues = "true", "false"
	$ReturnValues = @{}
	$AdminAccounts = @()
	$NotExisitingAccounts = @()
	[xml]$config = Get-Content $configfile
	if ($config.Configuration.Settings.AdminAccount -ne "")
		{
		foreach ($admin in $config.Configuration.Variables.AdminAccount)
			{
			$adminSplit = $admin.split( "\" )
			if (Find_User $adminSplit[1] (get_dom $adminSplit[0]).ldap)
				{ $AdminAccounts += $admin }
			else 
				{ $NotExistingAccounts += $admin }
			}
			$ReturnValues.Add( "NotExisitingAccounts", $NotExisitingAccounts )
			$ReturnValues.Add( "AdminAccounts", $AdminAccounts )
			Return $ReturnValues
		} 
	else 
		{
		 $ReturnValues.Add( "NotExistingAccounts", "Configurationfile has no Admin-Accounts set. Defaults will be used`r`n" )
		 return $ReturnValues
		}
}

Function Get_Dom([string]$Dom)
{
	$domstring=@{}
	$forest = [System.DirectoryServices.ActiveDirectory.Forest]::getCurrentForest()
	$Domain = $forest.domains | Where-Object {$_.name -like "$Dom*"}
	if ($domain)
	{
		$domstring["LDAP"] = "LDAP://" + ($domain.getDirectoryEntry()).distinguishedName # beide Werte mit Return zurückgeben
		$domstring["FQDN"] = $Domain.name
	}
	else
	{
	$Domain = $forest.GetAllTrustRelationships() | ForEach-Object {$_.TrustedDomainInformation} | Where-Object {$_.NetBiosName -eq "$Dom"}
	$domstring["FQDN"] = $Domain.DnsName
	$domLDAP = $domstring.FQDN.Split(".") | ForEach-Object {"DC="+$_}
	$domstring["LDAP"] = "LDAP://" + [System.String]::Join(",",$domLDAP)
	}
		return $domstring
}

Function Find_User($username,[string]$userDom)
# functions searchs for accounts (user, security-groups), parameter $userdom must be in LDAP-Format
# (grouptype:1.2.840.113556.1.4.803:=-2147483640) = Universal security groups
# (grouptype:1.2.840.113556.1.4.803:=-2147483646) = global security groups
# (samaccounttype=536870912) = local security groups
{
	Write-Debug "find dom $userdom"
	Write-Debug "find user $username"
	$Searcher=New-Object directoryServices.DirectorySearcher([ADSI]"$userdom")
	$Searcher.filter ="(&(|(objectClass=user)((objectcategory=group)`
	(|(grouptype:1.2.840.113556.1.4.803:=-2147483640)(grouptype:1.2.840.113556.1.4.803:=-2147483646)(samaccounttype=536870912))))(sAMAccountName=$username))"
	$Searcher.findall()
}

function add_SQLEngine()
{
	$script:ini+=@"
SQLSVCSTARTUPTYPE="Automatic"
SQLSVCACCOUNT="$SQLServiceDom\$ServiceUser"
SQLSVCPASSWORD="$ServiceUserPW"
AGTSVCSTARTUPTYPE="Automatic"
AGTSVCACCOUNT="$Agentdom\$AgentUser"
AGTSVCPASSWORD="$AgentUserPW"
SAPWD="sa`$S$InstanceName`$sdb"
FILESTREAMLEVEL="0"
SQLCOLLATION="$Collation"
SQLSYSADMINACCOUNTS="$SQLAdmins"
ADDCURRENTUSERASSQLADMIN="False"
TCPENABLED="1"
NPENABLED="0"
INSTALLSQLDATADIR="$SysDBDir"
SQLBACKUPDIR="$BackupDir"
SQLUSERDBDIR="$UserDBDataDir"
SQLUSERDBLOGDIR="$UserDBLogDir"
SQLTEMPDBDIR="$TempDBDataDir"
SQLTEMPDBLOGDIR="$TempDBLogDir"
BROWSERSVCSTARTUPTYPE="Automatic"
;FTSVCACCOUNT="LOCAL SERVICE"`r`n
"@
	If (!$AuthModeWindows) 	#Default is Windows Authentication
		{$script:ini += "SECURITYMODE=`"SQL`"`r`n"}
	
}

function add_2008
{
}

function add_2008R2
{
$script:ini += "IACCEPTSQLSERVERLICENSETERMS=`"True`"`r`n"
if ($PCU){$ini += "PCUSOURCE =`"$InstallDrive\$installFolder\$SQLSourceFolder\PCU`"`r`n"}
Switch ($MSSQLEdition)
	{
	"Standard" {$script:ini+= "PID=K8TCY-WY3TW-H2BCG-WTYV2-C96HM`r`n"}
	"Enterprise" {$script:ini+= "PID=GYF3T-H2V88-GRPPH-HWRJP-QRTYB`r`n"}
	"Developer" {$script:ini+= "MC46H-JQR3C-2JRHY-XYRKY-QWPVM`r`n"}
	}
}

function add_2012
{
Switch ($MSSQLEdition)
	{
	"Standard" {$script:ini+= "PID=YFC4R-BRRWB-TVP9Y-6WJQ9-MCJQ7`r`n"}
	"Enterprise" {$script:ini+= "PID=748RB-X4T6B-MRM7V-RTVFF-CHC8H`r`n"}
	"Developer" {$script:ini+= "PID=YQWTX-G8T4R-QW4XX-BVH62-GP68Y`r`n"}
	}
$script:ini+=@"
IACCEPTSQLSERVERLICENSETERMS=`"True`"
ENU="True"`r`n
"@

if ($PCU)
	{$script:ini+=@"
UpdateEnabled="TRUE"
UpdateSource=".\Updates"`r`n
"@
}	
}

function add_tools()
{
# not implemented
}

function add_IS()
{
$script:ini+=@"
ISSVCSTARTUPTYPE="Manual"
ISSVCACCOUNT=""
ISSVCPASSWORD=""`r`n
"@
}

function add_RS()
{
if (!$SQLEngine)
	{$script:ini+=@"
INSTANCEID="R$InstanceName"
INSTANCENAME="R$InstanceName""`r`n
"@
}
$script:ini+=@"
RSSVCACCOUNT="NETWORK SERVICE"
RSSVCSTARTUPTYPE="Automatic"
RSINSTALLMODE="FilesOnlyMode"
;FARMADMINPORT="0"
RSSVCPASSWORD=""`r`n 
"@
}

function add_AS()
{
if (!$SQLEngine){INSTANCENAME="$InstanceName"}
$script:ini+=@"
ASSVCACCOUNT=""
ASSVCSTARTUPTYPE="Automatic"
ASSVCPASSWORD=""
ASCOLLATION=""
ASDATADIR=""
ASLOGDIR=""
ASBACKUPDIR=""
ASTEMPDIR=""
ASCONFIGDIR=""
ASPROVIDERMSOLAP="1"
ASSYSADMINACCOUNTS=""`r`n
"@
}

function create_installps1
{
	Switch ($MSSQLVersion)
	{
		"MSSQL 2005"	{$logPath="C:\Program Files\Microsoft SQL Server\90\Setup Bootstrap\Log"}
		"MSSQL 2008"	{$logPath="C:\Program Files\Microsoft SQL Server\100\Setup Bootstrap\Log"}
		"MSSQL 2008 R2" {$logPath="C:\Program Files\Microsoft SQL Server\100\Setup Bootstrap\Log"}
		"MSSQL 2012" {$logPath="C:\Program Files\Microsoft SQL Server\110\Setup Bootstrap\Log"}
	}
	[string]$ConfigFeatures = ""
	If ($SQLEngine)
		{$ConfigFeatures = "configure_sql" }
	
	$setupscript=@"
# automatically created setup-script for $Serverinstance
param([switch]`$nosetup)

`$mypath = Split-Path -Parent `$MyInvocation.MyCommand.Definition
`$com_auditing=`"`$mypath\Scripts\Install_auditing.ps1 -ServerInstance $Serverinstance`"
`$com_settings=`"`$mypath\Scripts\change_settings.ps1 -ServerInstance $Serverinstance -port $TcpPort`"

function main
{if (`$nosetup)
	{
		configure_sql
	 	restore_PendingFileRename
	}
else 
	{setup}
}

function setup
{
	if (!(test-path `"$InstallDrive\$installFolder\$SQLSourceFolder\setup.exe`"))
	{Return "No Setupfiles found!"}

	If (test-path "$LogPath")
		{`$logBeforeSetup=Get-ChildItem "$logpath"}
	else
		{`$logBeforeSetup=""}
	`$setup=[Diagnostics.process]::start("$InstallDrive\$installFolder\$SQLSourceFolder\setup.exe","/Configurationfile=$InstallDrive\$installFolder\$SetupFolder\unattended.ini")
	`$setup.waitForExit()`r`n

	if (`$setup.exitcode -eq 3010)
	{
		clear_unattended
		If (!(test-path HKCU:Software\Microsoft\Windows\CurrentVersion\RunOnce)){New-Item -PATH HKCU:Software\Microsoft\Windows\CurrentVersion\RunOnce}
		New-ItemProperty HKCU:Software\Microsoft\Windows\CurrentVersion\RunOnce -name "StartConfig" -Value `"`$pshome\powershell.exe `$(`$MyInvocation.MyCommand.Definition) -ServerInstance $Serverinstance -port $TcpPort -notsetup`" -PropertyType string
		write-host -foregroundcolor Green `"Installation successful. Configuration will be resumed after reboot.`"
	}
	elseif (`$setup.exitcode -ne 0)
	{
		if (!(Test-Path `"$logpath`"))
			{write-host -foregroundcolor RED `"No Setup-log available. Installation failed with error `" `$setup.exitcode
			Return 
			}
		`$logAfterSetup=Get-ChildItem "$logpath"
		`$setupfiles = Compare-Object `$logAfterSetup `$LogBeforeSetup -Property Name, LastWriteTime -PassThru |
		Where-Object {`$_.sideIndicator -eq '<='}
		`$summary = `$setupfiles | where-object {`$_.name -eq "summary.txt"}
		if (`$summary)
			{notepad.exe `$summary.fullname}
		else 
			{`$summary = `$setupfiles | sort-object LastWritetime | select-object -first 1 | 
			foreach {get-childitem `$_.Fullname} | where-object {`$_.name -like "Summary*GlobalRules.txt"}
			notepad.exe `$summary.fullname
			}
		write-host -foregroundcolor RED `"Installation failed with error `" `$setup.exitcode
		Return
	}
	else
	{
		clear_unattended
		$ConfigFeatures
		restore_PendingFileRename
	}
}

function clear_unattended
{
	`$ini = Get-Content "$InstallDrive\$installFolder\$SetupFolder\unattended.ini"
	foreach (`$line in `$ini)
	{if ((`$line -like "*Password*") -or (`$line -like "SAPWD*"))
		{`$line = `$line.Split("=") | Select-Object -First 1
		`$line = `$line + "=***"
		}
	`$newini+=`@(`$line)
	}
	out-File $InstallDrive\$installFolder\$SetupFolder\unattended.ini -InputObject `$newini`r`n
}

function configure_sql
{
	Invoke-Expression `$com_settings -ErrorAction Continue
	Invoke-Expression `$com_auditing -ErrorAction Continue
}

function restore_PendingFileRename
{
	`$key = "HKLM:SYSTEM\CurrentControlSet\Control\Session Manager"
	`$OpenFiles = ((Get-ItemProperty `$key).PendingFileRenameOperations)
	`$Openfiles_PP = ((Get-ItemProperty `$key).PendingFileRenameOperations_PP)
	if (`$Opfenfiles_PP)
		{`$Openfiles += `$Openfiles_PP
		Set-ItemProperty -Path `$key -name PendingFileRenameOperations -value `$OpenFiles
		Remove-ItemProperty `$key PendingFileRenameOperations_PP
		}
}

Set PS-Debug-Strict
`$DebugPreference = `"SilentlyContinue"
. Main
"@
	$null = Out-File $InstallDrive\$installFolder\$setupFolder\install.ps1 -InputObject $setupscript 
}

function create_InstallFolder
{
	If (Test-Path $InstallDrive)
		{if ((Test-Path $InstallDrive\$installFolder\$SetupFolder))
			{create_installps1
			$null = Out-File $InstallDrive\$installFolder\$SetupFolder\unattended.ini -InputObject $ini}
		else 
			{$null = md $InstallDrive\$installFolder\$SetupFolder
			create_installps1
			$null = Out-File $InstallDrive\$installFolder\$SetupFolder\unattended.ini -InputObject $ini}
		If (!(Test-Path $InstallDrive\$installFolder\$SQLSourceFolder))
			{$null = md $InstallDrive\$installFolder\$SQLSourceFolder}
		}	
	Else
		{$installDrive = "c:"
		# Write-Host $InstallDrive\$installFolder\$SetupFolder
		if (!(Test-Path $InstallDrive\$installFolder\$SetupFolder))
 			{$null = md $InstallDrive\$installFolder\$SetupFolder}
 		$null = Out-File $InstallDrive\$installFolder\$SetupFolder\unattended.ini -InputObject $ini
		create_installps1}
	copy-Item -Path $mypath -Destination "$InstallDrive\$installFolder\$SetupFolder" -recurse -Exclude "create_ini.ps1"
	
}

$mypath = Split-Path -Parent $MyInvocation.MyCommand.Definition
. Main