# ====================================================================================================
# 
# NAME: change_settings.ps1
# 
# AUTHOR: Holger Voges
# DATE  : 20.04.2010
# Version: 1.0.3
#
# COMMENT: 	This is a post installation-script which modifies some SQL-Server settings:
#			- SQL-Logfiles are to Max 30
#			- Admingroup, UC4 and Backup-User is added
#			- Local Admin are removed from Logins
#			- Tempdb is changed to 1 File / core and 100 MB Filesize
#			- msdb is change to 100 MB Filesize and Recovery-Model Full
#			- Agent-CPU-Idlethreshold is set
#			- Port is changed
#
# Changes: 	16.02.2012
#			- disabling of sa added
#			28.03.2012
#			- changed tempdb-datafiles to max of 8 Files
#			11.07.2012
#			
# =====================================================================================================

param(
[int]$port=$(Throw "Parameter missing: -port Port"),
[string]$ServerInstance=$(Throw "Parameter missing: -ServerInstance Server\Instanz"),
#[string]$UC4Group="DOM1\CSS_CC11UC4_DS",
[string]$BackupUser="DOM1\P12795",
[string]$ACFGroup="DOM1\CSS_CC11SQLFull_DS"
)


function main()
{
	Set PS-Debug-Strict 
	$DebugPreference="SilentlyContinue"
	$backup_db="mast","model","msdb"
	$SMOVer = [reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
	$Server = New-Object('Microsoft.SQLServer.Management.SMO.Server')("$ServerInstance")
	if (Test-Path ($Server.InstallDataDirectory).remove(($Server.InstallDataDirectory).indexOf("Microsoft SQL Server")+20))
		{$tools=($Server.InstallDataDirectory).remove(($Server.InstallDataDirectory).indexOf("Microsoft SQL Server")+20)+"\tools"}
	else {Return "Error: Directory cannot be found!"}
    if (Get-WmiObject -List -Namespace root\Microsoft\SqlServer\ComputerManagement11 -ea 0)
		{$WMInamespace = 'root\Microsoft\SqlServer\ComputerManagement11'}	
    elseif (Get-WmiObject -List -Namespace root\Microsoft\SqlServer\ComputerManagement10 -ea 0)
		{$WMInamespace = 'root\Microsoft\SqlServer\ComputerManagement10'}
	else 
		{$WMInamespace = 'root\Microsoft\SqlServer\ComputerManagement'}
    if ($Server.InstanceName -eq '') {$instance = 'MSSQLSERVER'} else {$instance=$Server.InstanceName}

	$robocopy=Get-Command  Robocopy.exe -CommandType Application
	if (!$robocopy -and $tools){$robocopy=Get-Command  $tools\Robocopy.exe -CommandType Application}
	Check_SQLServer
	set_logfiles
 	Add_logins
	drop_localAdmins
	disable_sa
	create_Job_cycleErrorlog
	create_DC19_job
	change_tempdb
	change_msdb
	change_master
	change_model
	change_agent
	change_port
	restart_service
}

function check_SQLServer
# Checks availability of the Server
{
$Error.Clear()
trap{write-host -ForegroundColor Red "Please check Instancename and availabilty of service!";Continue}
	
	& {
	$sqlCon = New-Object Data.SqlClient.SqlConnection
	$sqlCon.ConnectionString = "Data Source=$ServerInstance;Integrated Security=True"
	$sqlCon.open()
	}
if ($Error.Count -ne 0){break}
}

function set_Logfiles
{
	$sql_change_logfiles = "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE',N'Software\Microsoft\MSSQLServer\MSSQLServer',N'NumErrorLogs',REG_DWORD,30"
	execute_sql($sql_change_logfiles)
Write-Host -ForegroundColor Green "Number of errorLogs set to 30"
}

function Add_Logins
{
	$sql_Add_Login = @"
IF NOT EXISTS (select * from sys.server_principals where [name] ='$BackupUser')
Begin
CREATE LOGIN [$BackupUser] FROM WINDOWS WITH DEFAULT_DATABASE=[master];
EXEC master..sp_addsrvrolemember @loginame = N'$BackupUser', @rolename = N'sysadmin';
END
IF NOT EXISTS (select * from sys.server_principals where [name] ='$ACFGroup')
BEGIN
CREATE LOGIN [$ACFGroup] FROM WINDOWS WITH DEFAULT_DATABASE=[master];
EXEC master..sp_addsrvrolemember @loginame = N'$ACFGroup', @rolename = N'sysadmin';
END
"@
	execute_sql($sql_Add_login)
	Write-Host -ForegroundColor Green "Created Logins and Roles"
}

function drop_LocalAdmins
{
	$sql_Drop_admins=@"
IF EXISTS (select * from sys.server_principals where [name] ='BUILTIN\Administrators')
BEGIN
EXEC master..sp_dropsrvrolemember @loginame = N'BUILTIN\Administrators', @rolename = N'sysadmin'
DROP LOGIN [BUILTIN\Administrators]
END
"@
	execute_sql($sql_Drop_admins)
	Write-Host -ForegroundColor Green "Permissions for local Admins revoked"
}

function disable_sa
{
	$sql_disable_sa=@"
IF (select is_disabled from sys.server_principals where name = 'sa') = 0
BEGIN
ALTER LOGIN [sa] DISABLE
END
"@
	execute_sql($sql_disable_sa)
	Write-Host -ForegroundColor Green "SA disabled"
}


function change_tempdb
{
	$tempdb=$server.databases | where-object {$_.name -eq "tempdb"}
	$templog=$($tempdb.logfiles).filename
	$tempdatapath=$tempdb.PrimaryFilePath
	$CPUs=Get-WmiObject Win32_processor
if (!($CPUs.count -eq $tempdb.filegroups.files.count))
{
	foreach ($i in $CPUs){$cores=$cores + $i.NumberOfCores}
	if ($cores -gt 8){$cores=8}
	for ($i=1;$i -le $cores-1;$i+=1)
	{
	$tempfile=$tempdatapath+"\"+"tempdev"+$i+".ndf"
	$sql_new_tempfile=@"
ALTER DATABASE [tempdb] ADD FILE 
( NAME = N'tempdev$i', FILENAME = N'$tempfile' , 
SIZE = 102400KB , FILEGROWTH = 102400KB )
"@
	execute_sql($sql_new_tempfile)
	}
	$tempfile=$tempdatapath+"\"+"tempdev.mdf"
	$templogfile=$templog
	$sql_change_tempfile=@"
ALTER DATABASE [tempdb] MODIFY FILE ( NAME = N'tempdev', 
FILENAME = '$tempfile', 
SIZE = 102400KB, FILEGROWTH = 102400KB );
ALTER DATABASE [tempdb] MODIFY FILE ( NAME = N'templog', 
FILENAME = '$templogfile', 
SIZE = 102400KB, FILEGROWTH = 102400KB )
"@
	execute_sql($sql_change_tempfile)
	Write-Host -ForegroundColor Green "TempDB customized"
}
else {Write-Host -ForegroundColor Yellow "TempDB already customized"}
}

function Change_msdb
{
	$sql_change_msdb=@"
ALTER DATABASE [msdb] SET RECOVERY FULL WITH NO_WAIT
ALTER DATABASE [msdb] MODIFY FILE ( NAME = N'MSDBData', FILEGROWTH = 10240KB )
ALTER DATABASE [msdb] MODIFY FILE ( NAME = N'MSDBLog', FILEGROWTH = 10240KB )
"@
	execute_sql($sql_change_msdb)
	Write-Host -ForegroundColor Green "MSDB customized"
}

function Change_master
{	
	$sql_change_master=@"
ALTER DATABASE [master] MODIFY FILE ( NAME = N'master', FILEGROWTH = 10240KB )
ALTER DATABASE [master] MODIFY FILE ( NAME = N'mastlog', FILEGROWTH = 10240KB )
"@
	execute_sql($sql_change_master)
	Write-Host -ForegroundColor Green "Master customized"
}

function change_model
{
	$sql_change_model=@"
ALTER DATABASE [model] MODIFY FILE ( NAME = N'modeldev', FILEGROWTH = 10240KB )
ALTER DATABASE [model] MODIFY FILE ( NAME = N'modellog', FILEGROWTH = 10240KB )
"@
	execute_sql($sql_change_model)
	Write-Host -ForegroundColor Green "Model customized"
}

function change_agent
{
	$sql_change_idlethreshold=@"
EXEC msdb.dbo.sp_set_sqlagent_properties @cpu_poller_enabled=1, @idle_cpu_percent=10, @idle_cpu_duration=600
"@
	execute_sql($sql_change_idlethreshold)
	Write-Host -ForegroundColor Green "CPU-Idlethreshold customized"
}

function change_Port
# Change SQL-Serverport via WMI
{
	$newport=Get-WmiObject -Namespace $WMInamespace -class ServerNetworkProtocolProperty -filter "PropertyName='TcpPort' and IPAddressName='IPAll' and Instancename='$Instance'" 
	$dynport=Get-WmiObject -Namespace $WMInamespace -class ServerNetworkProtocolProperty -filter "PropertyName='TcpDynamicPorts' and IPAddressName='IPAll' and Instancename='$Instance'" 
	$newPort.SetStringValue($port) | Out-Null
	$dynport.SetStringValue('') | Out-Null
	Write-Host -ForegroundColor Green "Port changed to $Port - Service has to be restarted"
}

function restart_service
{
if ($instance -eq 'MSSQLSERVER') { $searchstrg = $instance } else { $searchstrg = 'MSSQL$' + $instance }
	
$SqlService = Get-Service | Where-Object {$_.name -like $searchstrg }
	Stop-Service -InputObject $SqlService -Force
	
	If ($robocopy)
		{If ($Server.MasterDBPath -eq $Server.MasterDBLogPath)
			{foreach ($db in $backup_db)
				{& $robocopy $Server.MasterDBPath $($Server.BackupDirectory +"\Offline_Backup_" + $(Get-Date -uFormat %d%m%Y)) "$db*.?df" /R:2}
			}
		else
			{foreach ($db in $backup_db)
				{& $robocopy $Server.MasterDBPath $($Server.BackupDirectory +"\Offline_Backup_" + $(Get-Date -uFormat %d%m%Y)) "$db*.?df" /R:2
			 	& $robocopy $Server.MasterDBLogPath $($Server.BackupDirectory +"\Offline_Backup_" + $(Get-Date -uFormat %d%m%Y)) "$db*.?df" /R:2}
			}
		}
	else {Write-Debug "Robocopy was not found - System-databases were not copied"}
	
	Start-Service -InputObject $SqlService
	$SqlService.WaitForStatus("Running")
	$SqlService.DependentServices | foreach-object {start-Service -Inputobject $_}
}

function create_Job_cycleErrorlog
{
. .\add_spcycle_errorlog.ps1 -ServerInstance $ServerInstance
}

function create_DC19_job
{
. .\add_DC19_job.ps1 -ServerInstance $ServerInstance
}
function execute_sql($script)
{
	$sqlCon = New-Object Data.SqlClient.SqlConnection
	$sqlCon.ConnectionString = "Data Source=$ServerInstance;Initial Catalog=master;Integrated Security=True"
	$sqlCon.open()
	$sqlCmd = New-Object Data.SqlClient.SqlCommand
	$sqlCmd.Connection = $sqlCon
	$sqlCmd.CommandText = $script
	$sqlCmd.ExecuteNonQuery() | Out-Null
	$sqlCon.Close()
}

$mypath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $mypath
. Main