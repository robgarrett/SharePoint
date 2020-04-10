#######################################################
# Configure Server to Server Trust for Provider Hosted Apps
# Rob Garrett

$0 = $myInvocation.MyCommand.Definition
$env:dp0 = [System.IO.Path]::GetDirectoryName($0)

# Source External Functions
. "$env:dp0\Settings\Settings-$env:COMPUTERNAME.ps1"
. "$env:dp0\spConstants.ps1"
. "$env:dp0\spCommonFunctions.ps1"
. "$env:dp0\spSQLFunctions.ps1"
. "$env:dp0\spFarmFunctions.ps1"
. "$env:dp0\spRemoteFunctions.ps1"
. "$env:dp0\spServiceFunctions.ps1"

function Configure-STS($opt) {
    $c = Get-SPSecurityTokenServiceConfig;
    $c.AllowMetadataOverHttp = $opt;
    $c.AllowOAuthOverHttp= $opt;
    $c.Update();
}

function Configure-S2S($web) {
    $issuerID = [System.Guid]::NewGuid().ToString();
    $certificate = Get-PfxCertificate $appsPFX;
    $realm = Get-SPAuthenticationRealm -ServiceContext $web.Site;
    $fullAppIdentifier = $issuerId + '@' + $realm;
    Write-Host -ForegroundColor White "Registering Trusted Security Token Issuer with ID $fullAppIdentifier";
    $tsti = Get-SPTrustedSecurityTokenIssuer | ? { $_.Name -eq $s2sIssuerName }
    if ($tsti -ne $null) { $tsti.Delete(); }
    New-SPTrustedSecurityTokenIssuer -Name $s2sIssuerName -Certificate $certificate `
        -RegisteredIssuerName $fullAppIdentifier -IsTrustBroker:$true;
    Write-Host -ForegroundColor White "Adding certificate to trusted store";
    $root = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($appsPFX);
    $rootAuth = Get-SPTrustedRootAuthority | ? { $_.Name -eq $s2sRootName };
    if ($rootAuth -eq $null) {
        New-SPTrustedRootAuthority -Name $s2sRootName -Certificate $root;
    }
    Write-Host -ForegroundColor White "Resetting IIS.";
    IISReset;
}

function Configure-AsHTTP() {
    Write-Host -ForegroundColor Yellow "Configuring S2S over HTTP, this is only recommended in development environments.";
    Configure-STS -opt $true;
    $web = Get-SPWeb $s2sSiteUrlHttp -ErrorAction SilentlyContinue;
    if ($web -eq $null) { throw "Cannot find site $s2sSiteUrlHttp"; }
    Configure-S2S -web $web;
}

function Configure-AsHTTPS() {
    Write-Host -ForegroundColor White "Configuring S2S over HTTPS.";
    Configure-STS -opt $false;
    $web = Get-SPWeb $s2sSiteUrlHttps -ErrorAction SilentlyContinue;
    if ($web -eq $null) { throw "Cannot find site $s2sSiteUrlHttps"; }
    Configure-S2S -web $web;
}

# Make sure we're running as elevated.
Use-RunAs;
try {
    SP-RegisterPS;

    $caption = "Choose Action.";
    $message = "Configure over HTTP or HTTPS?";
    $http = new-Object System.Management.Automation.Host.ChoiceDescription "&HTTP","HTTP";
    $https = new-Object System.Management.Automation.Host.ChoiceDescription "HTTP&S","HTTPS";
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]($http,$https);
    $answer = $host.ui.PromptForChoice($caption,$message,$choices,1)

     switch ($answer) {
         0 { Configure-AsHTTP; break; }
         1 { Configure-AsHTTPS; break; }
     }
}
catch {
    Write-Host -ForegroundColor Red "Critial Error: " $_.Exception.Message;
}

Pause;
