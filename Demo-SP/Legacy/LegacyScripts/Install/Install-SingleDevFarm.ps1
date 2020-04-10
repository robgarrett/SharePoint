#############################################################
# SharePoint Install Everything on a single server.
# Rob Garrett
# With the help from http://autospinstaller.codeplex.com/

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
. "$env:dp0\spSearchFunctions.ps1"
. "$env:dp0\spWFMFunctions.ps1"
 
# Make sure we're running as elevated.
Use-RunAs;
try {
    # Standard provisioning steps.
    SP-ExecCommonSPServerProvisioning
    # Configure Logging
    SP-ConfigureDiagnosticLogging;
    # Create CA web site
    SP-CreateCentralAdmin;
    # Go configure services (search is a separate server).
    SP-ConfigureClaimsToWindowsTokenService;
    SP-ConfigureDistributedCacheService;
    SP-CreateStateServiceApp;
    SP-CreateMetadataServiceApp;
    SP-CreateUserProfileServiceApplication;
    SP-CreateSecureStoreServiceApp;
    SP-CreateBusinessDataConnectivityServiceApp;
    SP-ConfigureTracing;
    SP-CreateSubscriptionSettingsServiceApp;
    SP-CreateAppManagementServiceApp;
    SP-CreateSPUsageApp;
    # Create default web apps.
    SP-CreateDefaultWebApps
    # Post Configuration
    SP-PostInstallation;
}
catch {
    Write-Host -ForegroundColor Red "Critial Error: " $_.Exception.Message;
}

Pause;


