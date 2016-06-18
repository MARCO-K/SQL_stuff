
param(
[string]$ServerInstance=$(Throw "Instanzname fehlt!"),
[string]$CurrentPath = (Split-Path ((Get-Variable MyInvocation -Scope 0).Value).MyCommand.Path))

$DebugPreference="Continue"
Set PS-Debug-Strict 

function main
{

#Initialize Script-Variables
	checksqlserver
	$ACFGroup = "DOM1\CSS_CC11SQLFull_DS"
	$Installpath = (Get-Location).Path
	$SMOVer = [reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
	$SMOServer = New-Object('Microsoft.SQLServer.Management.SMO.Server')("$ServerInstance")
	If (!($SMOServer)){Write-Host "Instanz existiert nicht!";break}
	$InstanzID = ($Serverinstance).split("\") | Select-Object -Last 1

    $serviceaccount = $SMOServer.ServiceAccount
    	if (!$serviceaccount)
		{$serviceaccount = Get-WmiObject -Namespace Root\CimV2 -Class Win32_Group -Filter "LocalAccount='true' and name like '%mssql%$InstanzID'" |
		ForEach-Object {$_.name}}

	$agentgroup = $SMOServer.JobServer.AgentDomainGroup
	if (!$agentgroup)
		{$agentgroup = Get-WmiObject -Namespace Root\CimV2 -Class Win32_Group -Filter "LocalAccount='true' and name like '%agent%$InstanzID'" |
		ForEach-Object {$_.name}}
	checkagent
	$dataroot=$smoServer.InstallDataDirectory
	If (($InstanzID))
		{
		$root=($smoServer.InstallDataDirectory).remove(($smoServer.InstallDataDirectory).indexOf("Microsoft SQL Server")+20) + "\" + "$InstanzID";
		$rootParent=($smoServer.InstallDataDirectory).remove(($smoServer.InstallDataDirectory).indexOf("Microsoft SQL Server")+20)
		}
			else
		{
		$root=($smoServer.InstallDataDirectory).remove(($smoServer.InstallDataDirectory).indexOf("Microsoft SQL Server")+20);
		$rootParent=($smoServer.InstallDataDirectory).remove(($smoServer.InstallDataDirectory).indexOf("Microsoft SQL Server")+20)
		}
	$PermReadAgent=New-Object System.Security.AccessControl.FileSystemAccessRule($agentgroup,"ReadData","ObjectInherit,ContainerInherit","None","Allow")
	$PermModAgent=New-Object System.Security.AccessControl.FileSystemAccessRule($agentgroup,"Modify","ObjectInherit,ContainerInherit","None","Allow")
	$PermControlACF=New-Object System.Security.AccessControl.FileSystemAccessRule($ACFGroup,"FullControl","ObjectInherit,ContainerInherit","None","Allow")
    $PermModMSSQL=New-Object System.Security.AccessControl.FileSystemAccessRule($serviceaccount,"Modify","ObjectInherit,ContainerInherit","None","Allow")

    createFolder
    Write-Host -ForegroundColor Yellow "1. Folders created"
    copyfiles
    Write-Host -ForegroundColor Yellow "2. Files created"
    createAudit
    Write-Host -ForegroundColor Yellow "3a. Audit created"
    createArchivingJob
    Write-Host -ForegroundColor Yellow "3b. Job created"
    Write-Host -ForegroundColor Green "___________________"
	Write-Host -ForegroundColor Green "Auditing installed!"
}

function checkSQLServer
# checks availability of SQL-Service
{
$Error.Clear()
trap{write-host -ForegroundColor Red "Please check instancename and availability of the SQL-Service!";Continue}
	
	& {
	$sqlCon = New-Object Data.SqlClient.SqlConnection
	$sqlCon.ConnectionString = "Data Source=$ServerInstance;Integrated Security=True"
	$sqlCon.open()
	}
if ($Error.Count -ne 0){break}
}

function checkAgent
# verifies if varibale $agentgroup has a value
{
$Error.Clear()
trap{Write-Host -ForegroundColor Red "SQL-Agent could not be found - is the service running?";Continue}
	& {
	If (!($agentgroup)){throw}
	}
if ($Error.Count -ne 0){break}
}

function createFolder
{
	Write-Debug $Installpath
    Write-Debug "$rootparent\Tools"
	Write-Debug "$dataroot\Audit_Scripts"
    Write-Debug "$dataroot\Audit_Logs"
    Write-Debug "$dataroot\Maintenance_Audit_Logs_Archive"

    if (!(Test-Path "$dataroot\Audit_Scripts"))
	{
		$md = md "$dataroot\Audit_Scripts"
		# $acl=Get-Acl $md
		$acl = (Get-Item $md).GetAccessControl("Access")
		$acl.setAccessrule($PermReadAgent)
		If ($SMOServer.ActiveDirectory.IsEnabled){$acl.setAccessrule($PermControlACF)}
		Set-Acl -Path $md -AclObject $acl
	}
	if (!(Test-Path "$rootparent\Tools"))
	{
		$md = md "$rootparent\Tools"
		$acl = (Get-Item $md).GetAccessControl("Access")
		#$acl=Get-Acl $md
		$acl.setAccessrule($PermReadAgent)
		If ($SMOServer.ActiveDirectory.IsEnabled){$acl.setAccessrule($PermControlACF)}
		Set-Acl -Path $md -AclObject $acl
	}
	if (!(Test-path "$dataroot\Audit_Logs"))
	{
		$md = md "$dataroot\Audit_Logs"
		$acl = (Get-Item $md).GetAccessControl("Access")
		#$acl=Get-Acl $md
		$acl.setAccessrule($PermModAgent)
		If ($SMOServer.ActiveDirectory.IsEnabled){$acl.setAccessrule($PermControlACF)}
		Set-Acl -Path $md -AclObject $acl

        $acl.setAccessrule($PermModMSSQL)
        if ($SMOServer.ActiveDirectory.IsEnabled){$acl.setAccessrule($PermControlACF)}
		Set-Acl -Path $md -AclObject $acl
    }
	if (!(Test-path "$dataroot\Maintenance_Audit_Logs_Archive"))
	{
		$md = md "$dataroot\Maintenance_Audit_Logs_Archive"
		$acl = (Get-Item $md).GetAccessControl("Access")
		# $acl=Get-Acl $md
		$acl.setAccessrule($PermModAgent)
		If ($SMOServer.ActiveDirectory.IsEnabled){$acl.setAccessrule($PermControlACF)}
		Set-Acl -Path $md -AclObject $acl
	}
	# Set permissions for data-directory
	$datapath = "$dataroot\data"
	$acl = (Get-Item $datapath).GetAccessControl("Access")
	# $acl = Get-Acl $datapath
	$acl.setaccessrule($PermModAgent)
	Set-Acl -Path $datapath -AclObject $acl
}

function copyfiles
{
	Write-Debug $Installpath
	Write-Debug "$dataroot\Audit_Scripts"
    Write-Debug "$rootparent\Tools"

	If ((Test-Path "$dataroot\Audit_Scripts"))
    	{Copy-Item "$Installpath\Auditing-Maintenance\*.*" -destination "$dataroot\Audit_Scripts" -recurse | out-Null}
	If (!(Test-path "$rootparent\Tools"))
		{Copy-Item "$Installpath\Tools\" "$rootparent\tools\" -recurse | out-Null}

	$acl = (Get-Item "$rootparent\Tools").GetAccessControl("Access")
	# $acl=Get-Acl "$rootparent\tools"
	$acl.setAccessrule($PermReadAgent)
	If ($SMOServer.ActiveDirectory.IsEnabled){$acl.setAccessrule($PermControlACF)}
	Set-Acl -Path "$rootparent\Tools" -AclObject $acl
}

function createAudit
{
#execute ps1 script 
$instanceArray = $ServerInstance.Split("\")
if ($instanceArray.length -eq 2){
	$instanceName = $instanceArray[1]
}
else {
	$instanceName = $ServerInstance
}
.\createAuditings.ps1 -fullInst $ServerInstance -instance $instanceName -path "$dataroot\Audit_Scripts\" -dataroot $dataroot
}

function createArchivingJob
{
#execute Auditing script
$instanceArray = $ServerInstance.Split("\")
if ($instanceArray.length -eq 2){
	$instanceName = $instanceArray[1]
}
else {
	$instanceName = $ServerInstance
}
.$CurrentPath\createArchivingJob.ps1 -fullInst $ServerInstance -instance $instanceName -path "$dataroot\Audit_Scripts" -dataroot $dataroot
}

main
