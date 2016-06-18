# ====================================================================================================
# 
# NAME: Backup-Database.ps1
# 
# AUTHOR: Holger Voges
# DATE  : 17.12.2010
# 
# COMMENT: Installing the itmV6-user and creating the connection-string
# =====================================================================================================

param(
[String]$Instance=$(throw "please insert Servername\Instanz"),
[string]$pw=$(throw "please insert password"),
[string]$user=$(throw "please insert username"))
$DebugPreference="Continue"

function main
{
checkSQLServer
if (get-itm6User $Instance) {Write-Host "User $user exisitert bereits"} else {add-itm6User $Instance $Pw $User}
set-itmV6 $Instance $pw $User
notepad C:\temp\itmv6.txt
}

function checkSQLServer
# überprüft die Verfügbarkeit des Server
{
$Error.Clear()
trap{write-host -ForegroundColor Red "Bitte Instanznamen und Dienstverfügbarkeit prüfen!";Continue}
	
	& {
	$sqlCon = New-Object Data.SqlClient.SqlConnection
	$sqlCon.ConnectionString = "Data Source=$Instance;Integrated Security=True"
	$sqlCon.open()
	}
if ($Error.Count -ne 0){break}
Write-Debug "Konnektivitätsprüfung abgeschlossen"
}

# erzeugt den für itmV6 notwendigen Textstring
function set-itmV6($serverInstance,$Password,$TivUser)
{
	# Load SMO assemblies
	Write-Debug "Erzeuge Textstring"
	$SmoVer=[reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
	$smoServer = new-object ('Microsoft.SqlServer.Management.Smo.Server') ("$serverInstance")
	$String=$smoServer.NetName + ";" + $smoServer.InstanceName + ";" + $TivUser + ";" + $Password + ";`"" + $smoServer.RootDirectory + "`";`"" + $smoServer.ErrorLogPath +"\ERRORLOG`";0;0"
	$string
	if (!(Test-Path "C:\temp")){md "C:\temp"}
	$String | out-file "c:\temp\itmv6.txt" -Append
}

#erzeugt einen neuen Login mit sysadmin-Rechten
function add-itm6User($serverInstance,$Password,$TivUser)
{
	Write-Debug "Login erzeugen"
	$sqlCon = New-Object Data.SqlClient.SqlConnection
	$sqlCon.ConnectionString = "Data Source=$serverInstance;Integrated Security=True"
	$sqlCon.open()
	$sqlCmd = New-Object Data.SqlClient.SqlCommand
	$sqlCmd.Connection = $sqlCon
	$sqlCmd.CommandText = "CREATE LOGIN [$TivUser] WITH PASSWORD=N'$Password', DEFAULT_DATABASE=[master], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF;EXEC master..sp_addsrvrolemember @loginame = N'$TivUser', @rolename = N'sysadmin';"
	$sqlCmd.ExecuteNonQuery()
}	

#fragt ab, ob der itmV6-User schon existiert
function get-itm6User($serverInstance)
{
	Write-Debug "Abfragen, ob User exisitiert"
	$sqlCon = New-Object Data.SqlClient.SqlConnection
	$sqlCon.ConnectionString = "Data Source=$serverInstance;Integrated Security=True"
	$sqlCon.open()
	$sqlCmd = New-Object Data.SqlClient.SqlCommand
	$sqlCmd.Connection = $sqlCon
	$sqlCmd.CommandText ="select name from sys.server_principals where name = 'MSSQL_TIV_ITM6'"
	if ($sqlCmd.executeScalar()){$true} else {$false}
}

main
