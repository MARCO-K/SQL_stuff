#This script is used to archive old auditing logs and to delete all logs older than the specified amount of days


param(
[string]$path,
[string]$fullInst,
[string]$instance
)
$DebugPreference="Continue"
Set PS-Debug-Strict 

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") | out-null 
$Server = New-Object('Microsoft.SQLServer.Management.SMO.Server')("$fullInst")
$rootParent=($Server.InstallDataDirectory).remove(($Server.InstallDataDirectory).indexOf("Microsoft SQL Server")+20)

$file = "auditConfig.config" #change to new config Name if necessary
$date = (get-date).AddDays(-1).ToString("yyyyMMdd")
$filepath = "$path\Audit_Scripts"

[string]$auditName1 = Get-Content $filepath\$file | Select-String -Pattern "auditName1"
$auditName1 = $auditName1.TrimStart("auditName1:")
[string]$auditName2 = Get-Content $filepath\$file | Select-String -Pattern "auditName2"
$auditName2 = $auditName2.TrimStart("auditName2:")
[string]$myDrive = Get-Content $filepath\$file | Select-String -Pattern "drive"
$myDrive = $myDrive.TrimStart("drive:")
[string]$mainFolder = Get-Content $filepath\$file | Select-String -Pattern "mainFolder"
$mainFolder = $mainFolder.TrimStart("mainFolder:")
[string]$subFolder = Get-Content $filepath\$file | Select-String -Pattern "subFolder"
$subFolder = $subFolder.TrimStart("subFolder:")
[string]$logFolder1 = Get-Content $filepath\$file | Select-String -Pattern "logFolder1"
$logFolder1 = $logFolder1.TrimStart("logFolder1:")
[string]$logFolder2 = Get-Content $filepath\$file | Select-String -Pattern "logFolder2"
$logFolder2 = $logFolder2.TrimStart("logFolder2:")
[string]$auditDir1 = "$path\${subFolder}\${logFolder1}"
[string]$auditDir2 = "$path\${subFolder}\${logFolder2}"

[string]$archiveDuration = Get-Content $filepath\$file | Select-String -Pattern "archiveDuration"
$archiveDuration = $archiveDuration.TrimStart("archiveDuration:")

[string]$mainArchive = Get-Content $filepath\$file | Select-String -Pattern "mainArchive"
$mainArchive = $mainArchive.TrimStart("mainArchive:")
[string]$archiveFolder1 = Get-Content $filepath\$file | Select-String -Pattern "archiveFolder1"
$archiveFolder1 = $archiveFolder1.TrimStart("archiveFolder1:")
[string]$archiveFolder2 = Get-Content $filepath\$file | Select-String -Pattern "archiveFolder2"
$archiveFolder2 = $archiveFolder2.TrimStart("archiveFolder2:")
[string]$mainDirArch = "$path\${mainArchive}"
[string]$archiveDir1 = "$mainDirArch\${archiveFolder1}"
[string]$archiveDir2 = "$mainDirArch\${archiveFolder2}"
[string]$archivePath1 = "${archiveDir1}\${date}.zip"
[string]$archivePath2 = "${archiveDir2}\${date}.zip"

#zipping function
function create-7zip(
    [String] $aDirectory, 
    [String] $aZipfile)
    {
    [string]$pathToZipExe = "C:\Program Files\7-Zip\7z.exe";
    [Array]$arguments = "a", "-tzip", "$aZipfile", "$aDirectory", "-y";
    &$pathToZipExe $arguments;
}

if(!(Test-Path $mainDirArch)){New-Item -ItemType Directory -Path $mainDirArch}

create-7zip "$auditDir1" "$archivePath1"
create-7zip "$auditDir2" "$archivePath2"

#delete old files
Remove-Item $auditDir1\*ù -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item $auditDir2\*ù -Force -Recurse -ErrorAction SilentlyContinue


#delete all archives older than 90 days
$currDate = get-date
Get-ChildItem "$archiveDir1" -Filter *.zip | `
Foreach-Object{
    $fileDate = $_.LastWriteTime
	$fileName = $_.Name
	#compare whether the file is older than 90 days
	if (($currDate - $fileDate).Days -gt 90){
		Remove-Item $archiveDir1\$fileName
	}
}


Get-ChildItem "$archiveDir2" -Filter *.zip | `
Foreach-Object{
    $fileDate = $_.LastWriteTime
	$fileName = $_.Name
	#compare whether the file is older than 90 days
	if (($currDate - $fileDate).Days -gt 90){
		Remove-Item $archiveDir2/$fileName
	}
}