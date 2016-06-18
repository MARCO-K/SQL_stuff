#Script to create the archiving jobs for the audits
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

function main
{

# create a server connection

$server=New-Object Microsoft.SqlServer.Management.Smo.Server($fullInst)
 
# create job
$jobName =  "DBA Job `'Cycle_Auditlogs`'"

$Server = New-Object('Microsoft.SQLServer.Management.SMO.Server')("$ServerInstance")
$jobs = $Server.JobServer.Jobs
foreach ($job in $jobs)
        {if ($job.Name -like $jobname){ $check_job = 1;  Write-Host -ForegroundColor Yellow "Job $jobname already exists"}}

if ($check_job -ne 1)
{
$job = New-Object Microsoft.SqlServer.Management.SMO.Agent.Job($server.JobServer, $jobName) 
$job.Description = "Create a new auditlog daily at 0 p.m."
$job.OwnerLoginName = "sa"
$job.Create()
$job.ApplyToTargetServer($fullInst)
	$jobStep = New-Object('Microsoft.SqlServer.Management.SMO.Agent.JobStep')($job, "Disable Audits")
	$jobStep.Subsystem = [Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem]::TransactSql
	$jobstep.Command = "ALTER SERVER AUDIT Config_Audit WITH (STATE = OFF); ALTER SERVER AUDIT Login_Audit WITH (STATE = OFF);
GO"
	$jobstep.OnSuccessAction = [Microsoft.SqlServer.Management.SMO.Agent.StepCompletionAction]::GoToNextStep;
	$jobstep.OnFailAction =[Microsoft.SqlServer.Management.SMO.Agent.StepCompletionAction]::GoToNextStep; 
	$jobstep.Create()
	
	$jobstep = New-Object('Microsoft.SqlServer.Management.SMO.Agent.JobStep')($job, "Archive_Audit_Files")
	$jobStep.Subsystem = [Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem]::PowerShell
	$jobstep.Command = "cd `"$path`"`n .\runArchivingJob.ps1 -path `"$dataroot`" -fullInst `"$fullInst`" -instance `"$instance`""
	$jobstep.OnSuccessAction = [Microsoft.SqlServer.Management.SMO.Agent.StepCompletionAction]::GoToNextStep;
	$jobstep.OnFailAction =[Microsoft.SqlServer.Management.SMO.Agent.StepCompletionAction]::GoToNextStep; 
	$jobstep.Create()
	
	$jobstep = New-Object('Microsoft.SqlServer.Management.SMO.Agent.JobStep')($job, "Reenable_Audits")
	$jobStep.Subsystem = [Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem]::TransactSql
	$jobstep.Command = "ALTER SERVER AUDIT Config_Audit WITH (STATE = ON); ALTER SERVER AUDIT Login_Audit WITH (STATE = ON);
GO"
	$jobstep.OnSuccessAction = [Microsoft.SqlServer.Management.SMO.Agent.StepCompletionAction]::QuitWithSuccess;
	$jobstep.OnFailAction =[Microsoft.SqlServer.Management.SMO.Agent.StepCompletionAction]::QuitWithFailure; 
	$jobstep.Create()
	
	$jobschd =  New-Object -TypeName Microsoft.SqlServer.Management.SMO.Agent.JobSchedule -argumentlist $job, "Daily 0 a.m." 
	$jobschd.FrequencyTypes =  [Microsoft.SqlServer.Management.SMO.Agent.FrequencyTypes]::Daily
	$ts1 =  New-Object -TypeName TimeSpan -argumentlist 0, 0, 0
	$jobschd.ActiveStartTimeOfDay = $ts1
	$jobschd.FrequencyInterval = 1
	$culture = New-Object System.Globalization.CultureInfo("en-US")
	$jobschd.ActiveStartDate = (Get-Date).tostring("d",$culture)
	$jobschd.create()
Write-Host -ForegroundColor Green "Job $jobname created"
}
}

main
