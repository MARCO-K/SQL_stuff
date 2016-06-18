
function main
{
[xml]$Config = get-content $mypath\configuration_Dom1.xml
foreach ($script in $Config.Configuration.Addins.psscript) 
	{
	$attrib = $script.param | ForEach-Object {"-"+$_.name,$_.Value}
	$command= "$Mypath\" + $script.scriptname.ToString()
	Invoke-Expression "&`"$command`" $attrib"
	}
}

$mypath = Split-Path -Parent $MyInvocation.MyCommand.Definition
. Main