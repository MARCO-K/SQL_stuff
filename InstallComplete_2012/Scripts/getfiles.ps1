param(
[switch]$help,
[string]$ServerInstance=$(Throw "Paramter fehlt: -ServerInstance Server\Instanz; -help for all Parameters")
)

$SmoVer = [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
$WmiVer = [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")
$SmoServer = New-Object('Microsoft.SQLServer.Management.SMO.Server')("$ServerInstance")
$WmiServer = New-Object('Microsoft.SQLServer.Management.SMO.Wmi.ManagedComputer')

$DBs = $SmoServer.Databases
$Files=@()
Foreach ($DB in $DBs)
{
$Files += $DB.Filegroups | Select-Object -ExpandProperty Files | Select-Object -ExpandProperty Filename
}
$Files = $Files | Sort-Object -Unique

$drives = @()
$mountpoints = @()
$volumes = Get-WmiObject Win32_MountPoint | Select-Object Directory, Volume | % {if(($_.Directory).length -gt 27){$_} else {$drives += $_}}
if ($drives)
{
	foreach ($drive in $drives)
	{	
		$drive.directory = ($drive.directory).substring(22,2)
		$drive.Directory = ($drive.Directory).Replace("\\","\")
		$drive.Directory = ($Drive.Directory).Replace("`"","")
	}
}
$drives = $drives | Sort-Object Directory

if ($volumes)
{
	foreach ($dir in $volumes)
	{	
		$dir.Directory = ($Dir.Directory).Substring(21)
		$dir.Directory = ($Dir.Directory).Replace("\\","\")
		$dir.Directory = ($Dir.Directory).Replace("`"","")
	}

	foreach ($file in $Files)
	{
		foreach ($volume in $volumes)
		{
			if ($file.contains($volume.Directory))
				{$mountpoints += $volume}
			else
			{
				foreach ($drive in $Drives)
				{
					if ($file.StartsWith($drive.Directory))
						{$mountpoints += $drive}
				}
			}		
			
			
		}
	}
	$mountpoints = $mountpoints | sort-object directory -unique
}
else
{
	foreach ($file in $Files)
	{
		foreach ($drive in $drives)
		{
			if ($file.contains($drive.Directory))
				{$mountpoints += $drive}					
		}
	}
	$mountpoints = $mountpoints | sort-object directory -unique
}
$vol_wmi = Get-WmiObject Win32_Volume
$volume_information = @{}
foreach ($mountpoint in $mountpoints)
{
$volume_information[$mountpoint.Directory] = $vol_wmi | Where-Object {$_.__RELPATH -eq $mountpoint.volume}
}
$volume_information.Values |Select-Object name, blocksize