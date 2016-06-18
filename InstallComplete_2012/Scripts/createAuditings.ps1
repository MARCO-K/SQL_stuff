#Script to create audits
#as to be included in unattended installation
#Version 2.0 - July 2014
#Creator: Sarah Brock <sarah.brock@hp.com>

param(
[string]$fullInst,
[string]$instance,
[string]$path,
[string]$dataroot
)
$DebugPreference="Continue"
Set PS-Debug-Strict 

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") | out-null 

#create variable to check for errors
$currErrCount = $error.Count

#the first part creates the audit as such

#load all variables necessary for the audit from config file
$file = "auditConfig.config" #change to new config Name if necessary
$filterScript="setFilter.sql"

[string]$auditName1 = Get-Content $path\$file | Select-String -Pattern "auditName1"
$auditName1 = $auditName1.TrimStart("auditName1:")
[string]$auditName2 = Get-Content $path\$file | Select-String -Pattern "auditName2"
$auditName2 = $auditName2.TrimStart("auditName2:")

[string]$myDrive = Get-Content $path\$file | Select-String -Pattern "drive"
$myDrive = $myDrive.TrimStart("drive:")
[string]$mainFolder = Get-Content $path\$file | Select-String -Pattern "mainFolder"
$mainFolder = $mainFolder.TrimStart("mainFolder:")
[string]$subFolder = Get-Content $path\$file | Select-String -Pattern "subFolder"
$subFolder = $subFolder.TrimStart("subFolder:")
[string]$logFolder1 = Get-Content $path\$file | Select-String -Pattern "logFolder1"
$logFolder1 = $logFolder1.TrimStart("logFolder1:")
[string]$logFolder2 = Get-Content $path\$file | Select-String -Pattern "logFolder2"
$logFolder2 = $logFolder2.TrimStart("logFolder2:")
[string]$auditDir1 = "$dataroot\${subFolder}\${logFolder1}"
[string]$auditDir2 = "$dataroot\${subFolder}\${logFolder2}"

[string]$fileSize = Get-Content $path\$file | Select-String -Pattern "fileSize"
$fileSize = $fileSize.TrimStart("fileSize:")

[string]$nrFiles = Get-Content $path\$file | Select-String -Pattern "nrFiles"
$nrFiles = $nrFiles.TrimStart("nrFiles:")

[string]$delay = Get-Content $path\$file | Select-String -Pattern "delay"
$delay = $delay.TrimStart("delay:")

#create folders for saving the audit files if they do not exist yet
if(!(Test-Path $auditDir1)){New-Item -ItemType Directory -Path $auditDir1 | out-null}
if(!(Test-Path $auditDir2)){New-Item -ItemType Directory -Path $auditDir2 | out-null}

#read all variables that are additionally necessary for the specification
[string]$specName1 = Get-Content $path\$file | Select-String -Pattern "specName1"
$specName1 = $specName1.TrimStart("specName1:")
[string]$specName2 = Get-Content $path\$file | Select-String -Pattern "specName2"
$specName2 = $specName2.TrimStart("specName2:")

$srv = New-Object ('Microsoft.SqlServer.Management.Smo.Server') "$fullInst"

#check for exisiting audit
foreach ($a in $srv.Audits)
    {if ($a.Name -like $auditName1){ $check_audit = 1;  Write-Host -ForegroundColor Yellow "Audit $auditName1 already exists"}}

#create config audit first
if ($check_audit -ne 1)
{
$newAudit1 = New-Object Microsoft.SqlServer.Management.Smo.Audit($srv, "$auditName1")

$newAudit1.DestinationType = [Microsoft.SqlServer.Management.Smo.AuditDestinationType]::File
$newAudit1.FilePath = $auditDir1
$newAudit1.MaximumRolloverFiles = $nrFiles
$newAudit1.MaximumFileSize = $fileSize
$newAudit1.QueueDelay = $delay


 try{      
        $newAudit1.Create()
		$newAudit1.Enable()
    }catch{
        $error[0]|format-list -force        
        exit 1
    }

#set filter for config audit
import-module "sqlps" -DisableNameChecking
Invoke-Sqlcmd -ServerInstance $fullInst -inputFile "$path\$filterScript"
Set-Location $path

#first, create specification for config audit
## Set audit spec properties
$AuditSpec1 = new-object Microsoft.SqlServer.Management.Smo.ServerAuditSpecification($srv, $specName1)
$AuditSpec1.AuditName = "$auditName1"

## Set audit actions
$actionList1 = Get-Content $path\$file | Select-String -Pattern "action1"
ForEach($action1 in $actionList1){
	$action1 = $action1 | out-string
	$action1 = $action1 -replace "`t|`n|`r","" #remove all line breaks and spaces
	$action1 = $action1.TrimStart("action1:")
	$SpecDetail1 = new-object Microsoft.SqlServer.Management.Smo.AuditSpecificationDetail("$action1")
	$AuditSpec1.AddAuditSpecificationDetail($SpecDetail1)
}
## Create and enable audit spec
 try{      
    $AuditSpec1.Create()
	$AuditSpec1.Enable()
    }catch{
        $error[0]|format-list -force        
        exit 1
    }

Write-Host -ForegroundColor Green "Audit $auditName1 & $AuditSpec1 created"
}

#check for exisiting audit
foreach ($a in $srv.Audits)
    {if ($a.Name -like $auditName2){ $check_audit = 1;  Write-Host -ForegroundColor Yellow "Audit $auditName2 already exists"}}

#create config audit first
if ($check_audit -ne 1)
{
$newAudit2 = New-Object Microsoft.SqlServer.Management.Smo.Audit($srv, "$auditName2")

$newAudit2.DestinationType = [Microsoft.SqlServer.Management.Smo.AuditDestinationType]::File
$newAudit2.FilePath = $auditDir2
$newAudit2.MaximumRolloverFiles = $nrFiles
$newAudit2.MaximumFileSize = $fileSize
$newAudit2.QueueDelay = $delay


 try{      
        $newAudit2.Create()
		$newAudit2.Enable()
    }catch{
        $error[0]|format-list -force        
        exit 1
    }

#this part creates the pertaining audit specification
#now, create audit specification for login audit
$AuditSpec2 = new-object Microsoft.SqlServer.Management.Smo.ServerAuditSpecification($srv, $specName2)
$AuditSpec2.AuditName = "$auditName2"

## Set audit actions
$actionList2 = Get-Content $path\$file | Select-String -Pattern "action2"
ForEach($action2 in $actionList2){
	$action2 = $action2 | out-string
	$action2 = $action2 -replace "`t|`n|`r","" #remove all line breaks and spaces
	$action2 = $action2.TrimStart("action2:")
	$SpecDetail2 = new-object Microsoft.SqlServer.Management.Smo.AuditSpecificationDetail("$action2")
	$AuditSpec2.AddAuditSpecificationDetail($SpecDetail2)
}
## Create and enable audit spec
 try{      
    $AuditSpec2.Create()
	$AuditSpec2.Enable()
    }catch{
        $error[0]|format-list -force        
        exit 1
    }


Write-Host -ForegroundColor Green "Audit $auditName2 & $AuditSpec2 created"
}	
	
#display message if everything went successfully
if($error.Count -eq $currErrCount){
	Write-Host "Successfully created the audit $auditName and the pertaining specification $specName."
}
else{
	Write-Host "The script was not executed successfully. Please check the documentation for common causes for errors."
}