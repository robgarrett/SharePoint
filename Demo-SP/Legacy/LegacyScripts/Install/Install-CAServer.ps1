#############################################################
# SharePoint Install Central Admin on local server
# Rob Garrett
# With the help from http://autospinstaller.codeplex.com/

[CmdletBinding()]param()

$0 = $myInvocation.MyCommand.Definition
$env:dp0 = [System.IO.Path]::GetDirectoryName($0)

# Source External Functions
. "$env:dp0\spConstants.ps1"
. "$env:dp0\spCommonFunctions.ps1"
. "$env:dp0\spSQLFunctions.ps1"
. "$env:dp0\spFarmFunctions.ps1"
. "$env:dp0\spServiceFunctions.ps1"

# Include settings.
if (Test-Path "$env:dp0\Settings\Settings-$env:COMPUTERNAME.ps1") {
    . "$env:dp0\Settings\Settings-$env:COMPUTERNAME.ps1"
}
 
# Make sure we're running as elevated.
Use-RunAs;
try {
    # Check settings.
    Check-Settings;
    # Standard provisioning steps.
    SP-ExecCommonSPServerProvisioning
    # Create CA web site
    SP-CreateCentralAdmin;
    # Configure ULS
    SP-ConfigureDiagnosticLogging;
    # Install Language Packs
    SP-ConfigureLanguagePacks;
    # Configure email.
    #SP-ConfigureEmail;
    # Post Configuration
    SP-PostInstallation;
    #>
}
catch {
    Write-Host -ForegroundColor Red "Critial Error: " $_.Exception.Message;
}


