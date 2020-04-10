#############################################################
# Install Workflow Manager.
# Rob Garrett

[CmdletBinding()]param()

$0 = $myInvocation.MyCommand.Definition
$env:dp0 = [System.IO.Path]::GetDirectoryName($0)

# Source External Functions
. "$env:dp0\Settings\Settings-$env:COMPUTERNAME.ps1"
. "$env:dp0\spConstants.ps1"
. "$env:dp0\spCommonFunctions.ps1"
. "$env:dp0\spSQLFunctions.ps1"
. "$env:dp0\spFarmFunctions.ps1"
. "$env:dp0\spServiceFunctions.ps1"
. "$env:dp0\spWFMFunctions.ps1"
 
# Make sure we're running as elevated.
Use-RunAs;
try {
    # Register SharePoint PowerShell Cmdlets
    SP-RegisterPS;
    # Download WFM
    WFM-DownloadAndInstall;
    # Now configure WFM.
    WFM-Configure;
    # Ask to configure a web app.
    #SP-ConfigureWFMPrompt;
    # Post Configuration
    SP-PostInstallation;
}
catch {
    Write-Host -ForegroundColor Red "Critial Error: " $_.Exception.Message;
}

Read-Host "Done, press enter";
