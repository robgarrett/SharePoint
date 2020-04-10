#######################################
# Analyze SharePoint.

[CmdletBinding()]
param ([bool]$localExec = $true)

$0 = $myInvocation.MyCommand.Definition
$env:dp0 = [System.IO.Path]::GetDirectoryName($0)

# Source External Functions
. "$env:dp0\Settings\Settings-$env:COMPUTERNAME.ps1"
. "$env:dp0\..\Install\spCommonFunctions.ps1"
. "$env:dp0\spAnalyzeFunctions.ps1"
 
try {
    AnalyzeLoadCSOM;
    AnalyzeSiteCollections;
}
catch {
    Write-Host -ForegroundColor Red "Critial Error: " $_.Exception.Message;
}

Read-Host "Done, press enter";
