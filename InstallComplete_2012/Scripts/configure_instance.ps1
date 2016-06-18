<#
    Author: Marco Kleinert
    Version: 1.1
    Version 
    - 1.0 initial version
    - 1.1 bug fixing, added more parameter to functions

    .SYNOPSIS

    This is a post installation-script which modifies some SQL-Server settings.

    .DESCRIPTION
        This is a post installation-script which modifies some SQL-Server settings:
        - SQL-Logfiles are to Max 30
        - Admingroup (depending on the classification) and Backup-User is added
        - BUILIN\Admins are removed from Logins
        - Tempdb is changed to 1 File per core (max. 4) and 100 MB Filesize
        - master is change to 100 MB Filesize and Recovery-Model Full
        - msdb is change to 100 MB Filesize and Recovery-Model Full
        - Agent-CPU-Idlethreshold is set
        - Port is changed
        - System database are copyied to the default backup directory


    .PARAMETER ServerInstance

    This is the name of the source instance. It's a mandatory parameter beause it is needed to retrieve the data.

    .PARAMETER Port

    This is the port number for the instance. Only values between 1433 and 1450 are allowed.

    .PARAMETER classification

    This parameter adds the correct securioty group to the sysadmin role. Only values 'black','grey','white' are allowed.

    PARAMETER BackupUser

    This parameter adds the login for the backup service.

    .EXAMPLE

     .\change_settings.ps1 -port 1433 -ServerInstance DEFREON0830\S60039 -classification white –Verbose
#>
#requires -Version 3

param(
  [Parameter(Mandatory=$true,ValueFromPipeline=$true)][ValidateRange(1433,1450)][int]$port,
  [Parameter(Mandatory=$true,ValueFromPipeline=$true)][string]$ServerInstance=$(Throw 'Parameter missing: -ServerInstance Server\Instanz'),
  [Parameter(Mandatory=$true,ValueFromPipeline=$true)][ValidateSet('black','grey','white')][String]$classification,
  [string]$BackupUser='DOM1\P12795'
)

function main()
{
  Set PS-Debug-Strict 
  $DebugPreference='SilentlyContinue'

  #Load assemblies
  [void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO')

  #create initial SMO object
  $server = new-object ('Microsoft.SqlServer.Management.Smo.Server') $ServerInstance

    #set initial variales
  $backup_db='mast','model','msdb'

  if (Test-Path ($Server.InstallDataDirectory).remove(($Server.InstallDataDirectory).indexOf('Microsoft SQL Server')+20))
    {$tools=($Server.InstallDataDirectory).remove(($Server.InstallDataDirectory).indexOf('Microsoft SQL Server')+20)+'\tools'}
  else {Return 'Error: Directory cannot be found!'}
    if (Get-WmiObject -List -Namespace root\Microsoft\SqlServer\ComputerManagement11 -ea 0)
    {$WMInamespace = 'root\Microsoft\SqlServer\ComputerManagement11'}	
    elseif (Get-WmiObject -List -Namespace root\Microsoft\SqlServer\ComputerManagement10 -ea 0)
    {$WMInamespace = 'root\Microsoft\SqlServer\ComputerManagement10'}
  else 
    {$WMInamespace = 'root\Microsoft\SqlServer\ComputerManagement'}
    if ($Server.InstanceName -eq '') {$instance = 'MSSQLSERVER'} else {$instance=$Server.InstanceName}

  $robocopy=(Get-Command  Robocopy.exe -CommandType Application).Name
  if (!$robocopy -and $tools){$robocopy=Get-Command  $tools\Robocopy.exe -CommandType Application}

  switch ($classification)
    {
      'black'  { $shore = 'DOM1\CSS_CC11SQLFull_DS' }
      'grey'   { $shore = 'DOM1\CSS_CC11SQLAdmin_sub02_DS' }
      'white'  { $shore = 'DOM1\CSS_CC11SQLAdmin_sub01_DS' }
      Default  { $shore = 'DOM1\CSS_CC11SQLFull_DS' }
    }

  Test-SQLServer -ServerInstance $ServerInstance
  Set-logfiles -NumberOfLogFiles 30
  Add-Logins_G -logins $shore
  Add-Logins_U -logins $BackupUser
  Drop-Logins -logins 'BUILTIN\Administrators'
  Disable-Logins -logins 'sa','\everyone'
  #Add-Job_cycleErrorlog
  #Add-Jpb_dc19
  Add-Datafiles -dbname tempdb -size 102400 -growth 102400 -count 4
  Set-Database -dbname master -recovery Full
  Set-Database -dbname msdb -recovery Full
  Set-Agent -IdleCpuDuration 600 -IdleCpuPercentage 10 -IsCpuPollingEnabled $true
  Set-Port -port $port
  Set-ServiceStart -services 'SQL','agent','browser' -instance $server.InstanceName
  Copy-Databases -backup_db $backup_db
  Stop-SQLService -services 'SQL','agent','browser' -instance $server.InstanceName -verbose
  Start-SQLService -services 'SQL','agent','browser' -instance $server.InstanceName -verbose
}

function Test-SQLServer { param([string]$ServerInstance)
  TRY {
    $ServerInstance = 'DEFREON0830\S60039'
    $sqlCon = New-Object Data.SqlClient.SqlConnection
    $sqlCon.ConnectionString = "Data Source=$ServerInstance;Integrated Security=True"
    $sqlCon.open() 
    IF ($sqlCon.State -eq 'Open')
    {
      Write-Verbose "Connection to $ServerInstance is $($sqlCon.State)"
      $sqlCon.Close();
    }
    else {
      Write-Verbose 'SQLAgent is is not running --trying to start...'
      Start-SQLService -services 'agent' -instance $server.InstanceName
    }
  } 
  CATCH { Write-host -ForegroundColor Red "Not available Server: $ServerInstance" }
  try {
    $i = $server.JobServer.Properties['JobServerType'].value
    if($i) {Write-Verbose 'SQLAgent is running'}
    else {
      Write-Verbose 'SQLAgent is is not running --trying to start...'
      Start-SQLService -services 'agent' -instance $server.InstanceName
    }
  }
  catch{ Write-host -ForegroundColor Red "Not available SQLAgent: $ServerInstance"}
}

function Set-Logfiles { param( [int]$NumberOfLogFiles )
  try {
    if($server.NumberOfLogFiles -ne $NumberOfLogFiles) {
      $server.NumberOfLogFiles = $NumberOfLogFiles  
      $server.Alter() 
      Write-verbose $("Number of errorlog files changed to $NumberOfLogFiles" ) 
    }
    else { Write-verbose "Number of errorlog files already set to $NumberOfLogFiles" }
    }
  catch { Write-host -ForegroundColor Red 'Number of errorlog files not set' }
}

function Add-Logins_G { param( [string[]]$logins )
  TRY {
    $names = ($server.Logins | Where-Object {$_.IsSystemObject -eq $false -and $_.Name -notlike 'NT *'  -and $_.Name -notlike '##*##'}).Name.Trim()
    foreach ($loginname in $logins) { 
      if ($loginname -notin $names) { 
        $login = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Login -ArgumentList $Server, $loginname 
        $login.LoginType = 'WindowsGroup'
        $login.DefaultDatabase = 'master'
        $login.Create()
        $login.AddToRole('sysadmin')
        Write-Verbose "Login $loginname created"
      }
      else { Write-Verbose "Login $loginname already exists"}
    }
   }
  CATCH { Write-host -ForegroundColor Red "Failed to create logins: $logins" }
}

function Add-Logins_U { param( [string[]]$logins )
  TRY {
    $names = ($server.Logins | Where-Object {$_.IsSystemObject -eq $false -and $_.Name -notlike 'NT *'  -and $_.Name -notlike '##*##'}).Name.Trim()
    foreach ($loginname in $logins) { 
      if ($loginname -notin $names) { 
        $login = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Login -ArgumentList $Server, $loginname 
        $login.LoginType = 'WindowsUser'
        $login.DefaultDatabase = 'master'
        $login.Create()
        $login.AddToRole('sysadmin')
        Write-Verbose "Login $loginname created"
      }
      else { Write-Verbose "Login $loginname already exists"}
    }
   }
  CATCH { Write-host -ForegroundColor Red "Failed to create logins: $logins" }
}

function Drop-Logins { param( [string[]]$logins )
  try {
    $names = ($server.Logins | Where-Object {$_.IsSystemObject -eq $false -and $_.Name -notlike 'NT *'  -and $_.Name -notlike '##*##'}).Name.Trim()
    #drop database users
    foreach($database in $server.Databases) {
        foreach($login in $logins) {
            if($database.Users.Contains($login))
            { $database.Users[$login].Drop() }
        }
    }
    #drop server logins
    foreach($login in $logins) {
        if ($login -in $names) 
        { $server.Logins[$login].Drop() }
    }
    Write-verbose "Permissions for $logins revoked"
    }
  catch { Write-host -ForegroundColor Red "Permissions for $logins not revoked" }
}

function Disable-Logins  { param( [string[]]$logins )
  try {
    #drop server logins
    foreach($login in $logins)
    {
        if ($server.Logins.Contains($login)) 
        { $server.Logins[$login].Disable() }
    }
    Write-verbose "logins $logins disabled"
    }
  catch { Write-host -ForegroundColor Red "Login $logins not disabled" }
}

function Add-Datafiles { param( [string]$dbname, [int]$size, [int]$growth, [int]$count )
  try {   
    $db = $server.Databases[$dbname]
    $datapath=$tempdb.PrimaryFilePath
    $fg = $db.FileGroups['PRIMARY']
    if($fg.Files.Count -le $count) { 
      if ($count -gt 8) {$count=4}
      for ($i=1;$i -le $count-1;$i+=1)
      {
        $filename = $dbname+'_data'+$i
        $dbfile = new-object ('Microsoft.SqlServer.Management.Smo.DataFile') ($fg, $filename)
        $fg.Files.Add($dbfile)
        $dbfile.FileName = $datapath + '\' + $filename + '.ndf'
        $dbfile.Size = [double]$size
        $dbfile.Growth = [double]$growth
        $dbfile.GrowthType = 'kb'
        $fg.Alter()
        $db.Alter()
        Write-Verbose "Datafile $filename created"
      }
     }
     else {Write-Verbose "Datafile count for $dbname is alread $count"}
  }
  catch { Write-Host -ForegroundColor Red "Failed to add datafiles to $dbname"}
}

function Set-Database { param([string]$dbname, [string]$recovery = 'full')
  try {
    $db = $server.Databases[$dbname]
    $fg = $db.FileGroups['PRIMARY']
    foreach ($file in $fg.Files) {
        $file.Growth = '10240'
        $file.GrowthType = 'Percent'
        write-verbose "$($file.Name) customized"
        }
    $logs = $db.LogFiles
    foreach ($file in $logs) {
        $file.Growth = '10240'
        $file.GrowthType = 'Percent'
        write-verbose "$($file.Name) customized"
        }

    $db.RecoveryModel = $recovery
    $server.killallprocesses($dbname)
    $db.alter()
    write-verbose "Recovery for $dbname changed to $recovery"
    }
  catch { Write-host -ForegroundColor Red '$dbname configuration failed' }
}  

function Set-Agent { param([int]$IdleCpuDuration,[int]$IdleCpuPercentage,[bool]$IsCpuPollingEnabled)
  try {
    $server.JobServer.IdleCpuDuration = 600
    $server.JobServer.IdleCpuPercentage = 10
    $server.JobServer.IsCpuPollingEnabled = $true
    Write-verbose 'CPU-Idlethreshold customized'
    }
  catch {Write-Host -ForegroundColor red 'CPU-Idlethreshold not customized'}
}

function Set-Port { param( [int]$port)
  # Change SQL-Serverport via WMI
  try {
    $newport=Get-WmiObject -Namespace $WMInamespace -class ServerNetworkProtocolProperty -filter "PropertyName='TcpPort' and IPAddressName='IPAll' and Instancename='$Instance'" 
    $dynport=Get-WmiObject -Namespace $WMInamespace -class ServerNetworkProtocolProperty -filter "PropertyName='TcpDynamicPorts' and IPAddressName='IPAll' and Instancename='$Instance'" 
    $newPort.SetStringValue($port) | Out-Null
    $dynport.SetStringValue('') | Out-Null
    Write-verbose "Port changed to $Port - Service has to be restarted"
    }
  catch { Write-Host -ForegroundColor red 'Port not changed'}
}

function Copy-Databases { param( [string[]]$backup_db )
  try {
    If ($robocopy) {
        Stop-SQLService -service sql -instance $server.InstanceName
      If ($Server.MasterDBPath -eq $Server.MasterDBLogPath)
      {foreach ($db in $backup_db)
        {& $robocopy $Server.MasterDBPath $($Server.BackupDirectory +'\Offline_Backup_' + $(Get-Date -uFormat %d%m%Y)) "$db*.?df" /R:2 /njh /njs /ndl /nc /ns}
      }
      else
      {foreach ($db in $backup_db)
        {& $robocopy $Server.MasterDBPath $($Server.BackupDirectory +'\Offline_Backup_' + $(Get-Date -uFormat %d%m%Y)) "$db*.?df" /R:2 /njh /njs /ndl /nc /ns
        & $robocopy $Server.MasterDBLogPath $($Server.BackupDirectory +'\Offline_Backup_' + $(Get-Date -uFormat %d%m%Y)) "$db*.?df" /R:2 /njh /njs /ndl /nc /ns}
      }
        write-verbose 'System databases copied'
        Start-SQLService -service sql -instance $server.InstanceName
    }
    else {Write-Debug 'Robocopy was not found - System-databases were not copied'}
    }
  catch { Write-Host -ForegroundColor red 'Database backup failed'}
}

function Set-ServiceStart { param( [string[]]$services, [string]$instance )
  try {
    foreach ($service in $services) {
      switch ($service)
      {
        'agent' { if ($instance -eq  'SQLSERVERAGENT') { $searchstrg = $instance } else { $searchstrg = 'SQLAgent$' + $instance }}
        'sql'   { if ($instance -eq 'MSSQLSERVER') { $searchstrg = $instance } else { $searchstrg = 'MSSQL$' + $instance }}
        'browser'  { $searchstrg = 'SQLBrowser'}
      }
      $SqlService = (Get-Service | Where-Object {$_.name -like $searchstrg }).Name

      if((Get-WMIObject Win32_Service | Where-Object { $_.name -eq $SqlService} | Select-Object StartMode ).StartMode -ne 'Auto') { 
        Set-Service –Name $SqlService –StartupType 'automatic'
        Write-verbose "Service $SQLService set to startmode automatic"
      }
      else { Write-verbose "Service $SQLService is already set to startmode automatic" }
    }
    }
  catch { Write-verbose -ForegroundColor red "Failed to set startmode fro $service"}
}	

function Stop-SQLService { param( [string[]]$services, [string]$instance )
try {
  foreach ($service in $services) {   
    switch ($service)
    {
      'agent' { if ($instance -eq  'SQLSERVERAGENT') { $searchstrg = $instance } else { $searchstrg = 'SQLAgent$' + $instance }}
      'sql'   { if ($instance -eq 'MSSQLSERVER') { $searchstrg = $instance } else { $searchstrg = 'MSSQL$' + $instance }}
      'browser'  { $searchstrg = 'SQLBrowser'}
    }
    $SqlService = Get-Service | Where-Object {$_.name -like $searchstrg }	
    $ServiceName = $SqlService.Name
    if($SqlService.Status -eq 'Running') {
      write-verbose "Stopping service $ServiceName"
      $SqlService.DependentServices | foreach-object {Stop-Service -Inputobject $_}
      stop-service $sqlService
      write-verbose "Service $($SqlService.Name) is stopped"
    }
    else { write-verbose "Service $ServiceName is already stopped" }
  }
   }
catch { Write-Host -ForegroundColor red "Failed to stop service $ServiceName"}
}	
	
function Start-SQLService { param( [string[]]$services, [string]$instance )
try {
    foreach ($service in $services) {   
      switch ($service)
      {
        'agent' { if ($instance -eq  'SQLSERVERAGENT') { $searchstrg = $instance } else { $searchstrg = 'SQLAgent$' + $instance }}
        'sql'   { if ($instance -eq 'MSSQLSERVER') { $searchstrg = $instance } else { $searchstrg = 'MSSQL$' + $instance }}
        'browser'  { $searchstrg = 'SQLBrowser'}
      }
      $SqlService = Get-Service | Where-Object {$_.name -like $searchstrg }	
      $ServiceName = $SqlService.Name
      if($SqlService.Status -ne 'Running') {
        write-verbose "Starting service $ServiceName"
        Start-Service -InputObject $SqlService
        $SqlService.WaitForStatus('Running')
        $SqlService.DependentServices | foreach-object {start-Service -Inputobject $_}
        $SqlService.WaitForStatus('Running')
        write-verbose "Service $ServiceName is running"
      }
      else { write-verbose "Service $ServiceName is already running" }
    }
  }
catch { Write-Host -ForegroundColor red "Starting service $SqlServiceName failed"}
}

function Add-Job_cycleErrorlog {
  . .\add_spcycle_errorlog.ps1 -ServerInstance $ServerInstance
}

function Add-Job_dc19 {
  . .\add_DC19_job.ps1 -ServerInstance $ServerInstance
}

function execute_sql($script) {
  $sqlCon = New-Object Data.SqlClient.SqlConnection
  $sqlCon.ConnectionString = "Data Source=$ServerInstance;Initial Catalog=master;Integrated Security=True"
  $sqlCon.open()
  $sqlCmd = New-Object Data.SqlClient.SqlCommand
  $sqlCmd.Connection = $sqlCon
  $sqlCmd.CommandText = $script
  $sqlCmd.ExecuteNonQuery() | Out-Null
  $sqlCon.Close()
}

function Get-CPUs {
  param ($server)

      $processors = get-wmiobject -computername $server win32_processor
      [int]$cores = 0
      [int]$sockets = 0
      [string]$test = $null

      foreach ($proc in $processors)

      { if ($proc.numberofcores -eq $null)
            { If (-not $Test.contains($proc.SocketDesignation))
                  { $Test = $Test + $proc.SocketDesignation,  $sockets++ }
                  $cores++
            }
         else
            {$sockets++; $cores = $cores + $proc.numberofcores }

      }
      $cores, $sockets
}

$mypath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $mypath
. Main