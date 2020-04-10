#############################################################
# SharePoint Farm Functions
# Rob Garrett
# With the help from http://autospinstaller.codeplex.com/

function SP-ExecCommonSPServerProvisioning {
    # Register SharePoint PowerShell Cmdlets
    SP-RegisterPS;
    # Disable loopback check.
    SP-DisableLoopback;
    # Create Farm
    if ($env:spdebug -eq $null -or $env:spdebug -ne "1") { SP-CreateOrJoinFarm;}
}

function SP-GetFarmCredential {
    # See if we have cached creds
    if ($global:cachedFarmCreds -ne $null) { return $global:cachedFarmCreds; }
    # Prompt for the farm account credentials.
    if ($global:spFarmAcctName -ne $null -and $global:spFarmAcctPwd -ne $null) {
        $secpasswd = ConvertTo-SecureString $global:spFarmAcctPwd -AsPlainText -Force
        $global:cachedFarmCreds = New-Object System.Management.Automation.PSCredential ($global:spFarmAcctName, $secpasswd);
        return $global:cachedFarmCreds;
    }
    Write-Host -BackgroundColor Gray -ForegroundColor DarkBlue "Prompting for Farm Account:"
    $global:cachedFarmCreds = $host.ui.PromptForCredential("Farm Setup", "Enter Farm Account Credentials:", "$:global:spFarmAcctName", "NetBiosUserName" )
    return $global:cachedFarmCreds;
}

function SP-DisableLoopback {
    # Disable loopback check.
    $item = Get-ItemProperty HKLM:\System\CurrentControlSet\Control\Lsa -Name "DisableLoopbackCheck" -ErrorAction SilentlyContinue;
    if (!$item) {
        New-ItemProperty HKLM:\System\CurrentControlSet\Control\Lsa -Name "DisableLoopbackCheck" -Value "1" -PropertyType dword | Out-Null;
        Write-Verbose "Loopback disabled";
    } else {
        Write-Verbose "Loopback already disabled";
    }
}

function SP-CreateOrJoinFarm {
    # Look for an existing farm and join the farm if not already joined, or create a new farm
    Write-Host -Foregroundcolor Green "Creating or Joining Server Farm";
    try {
        $configDB = $global:dbPrefix + "_Config_Farm";
        Write-Verbose "Checking farm membership for $env:COMPUTERNAME in `"$configDB`"..."
        $spFarm = Get-SPFarm | Where-Object {$_.Name -eq $configDB} -ErrorAction SilentlyContinue
    }
    catch {""}
    if ($spFarm -eq $null) {
        $farmCredential = SP-GetFarmCredential;
        if ($farmCredential -eq $null) { throw "Incorrect farm account"; }
        $centralAdminContentDB = $global:dbPrefix + "_Content_Farm";
        Write-Verbose "Attempting to join farm on `"$configDB`"..."
        $pp = ConvertTo-SecureString "$global:passphrase" -AsPlaintext -Force
        $spVer = (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell).Version.Major;
        if ($spVer -eq 16) {
            <# Invalid, WebFrontEnd, Application, SingleServer, SingleServerFarm, DistributedCache, Search, Custom #>
            $connectFarm = Connect-SPConfigurationDatabase -DatabaseName "$configDB" -Passphrase $pp -DatabaseServer "$global:dbServer" -LocalServerRole $global:serverRole -ErrorAction SilentlyContinue
        } else {
            $connectFarm = Connect-SPConfigurationDatabase -DatabaseName "$configDB" -Passphrase $pp -DatabaseServer "$global:dbServer" -ErrorAction SilentlyContinue
        }
        if (-not $?) {
            Write-Verbose "No existing farm found - Creating config database `"$configDB`"..."
            # Waiting a few seconds seems to help with the Connect-SPConfigurationDatabase barging in on the New-SPConfigurationDatabase command; not sure why...
            Start-Sleep 5
            if ($spVer -eq 16) {
                <# Invalid, WebFrontEnd, Application, SingleServer, SingleServerFarm, DistributedCache, Search, Custom #>
                New-SPConfigurationDatabase -DatabaseName "$configDB" -DatabaseServer "$global:dbServer" -AdministrationContentDatabaseName "`
                    $centralAdminContentDB" -Passphrase $pp -FarmCredentials $farmCredential -LocalServerRole $global:serverRole;
            } elseif ($spVer -eq 15) {
                New-SPConfigurationDatabase -DatabaseName "$configDB" -DatabaseServer "$global:dbServer" -AdministrationContentDatabaseName "`
                    $centralAdminContentDB" -Passphrase $pp -FarmCredentials $farmCredential;
            } else {
                throw "Not supported on versions of SharePoint prior to SP2013";
            }
            if (-not $?) {
                throw "Error creating new farm configuration database"}
            else {
                $farmMessage = "Done creating configuration database for farm."}
        }
        else {
            $farmMessage = "Done joining farm."
        }
    }
    else {
        $farmMessage = "$env:COMPUTERNAME is already joined to farm on `"$configDB`"."
    }
    # Configure new or existing farm
    SP-ConfigureFarm;
    Write-Verbose $farmMessage;
    Write-Host -Foregroundcolor Green "Done Creating or Joining Server Farm";
}

function SP-CheckIfUpgradeNeeded {
    # Check if we need to perform an upgrade.
    $spVer = (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell).Version.Major;
    $setupType = (Get-Item -Path "HKLM:\SOFTWARE\Microsoft\Shared Tools\Web Server Extensions\$spVer.0\WSS\").GetValue("SetupType")
    if ($setupType -ne "CLEAN_INSTALL") { # For example, if the value is "B2B_UPGRADE" 
        return $true
    }
    else {
        return $false
    }
}

function SP-ConfigureFarm {
    Write-Host -Foregroundcolor Green "Configuring the SharePoint farm/server..."
    # Check if farm has more than one server, other than DB server
    $configDB = $global:dbPrefix + "_Config_Farm";
    $spFarm = Get-SPFarm | Where-Object {$_.Name -eq $configDB}
    if ($spFarm -ne $null) {
        # Install Help Files
        Write-Verbose "Installing Help Collection..."
        Install-SPHelpCollection -All
        # Secure resources
        Write-Verbose "Securing Resources..."
        Initialize-SPResourceSecurity;
        # Install Services
        Write-Verbose "Installing Services";
        Install-SPService
        # Install (all) features
        Write-Verbose "Installing Features..."
        $features = Install-SPFeature -AllExistingFeatures;
        # Create application content.
        Write-Verbose "Installing Application Content..."
        Install-SPApplicationContent
        # Configure managed accounts
        SP-CreateManagedAccounts;
        # Check again if we need to run PSConfig, in case a CU was installed
        SP-ConfigFarmAfterUpgrade;
    } else {
        throw "Not connected to the farm";
    }
    Write-Host -Foregroundcolor Green "Done configuring the SharePoint farm/server."
}

function SP-ChangeCacheServiceAccount {
    # Change the Distributed Cache Service to us the service account
    # Not the farm account.
    Write-Host -Foregroundcolor Green "Changing cache service account to $global:spServiceAcctName."
    $spVer = (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell).Version.Major;
    if ($spVer -ge 15) {
        $configDB = $global:dbPrefix + "_Config_Farm";
        $spFarm = Get-SPFarm | Where-Object {$_.Name -eq $configDB}
        if ($spFarm -ne $null) {
            Write-Verbose "Changing the Distributed Cache Service account";
            $cacheService = $spFarm.Services | where {$_.Name -eq "AppFabricCachingService"}
            $accnt = Get-SPManagedAccount -Identity $global:spServiceAcctName;
            $cacheService.ProcessIdentity.CurrentIdentityType = "SpecificUser";
            $cacheService.ProcessIdentity.ManagedAccount = $accnt;
            $cacheService.ProcessIdentity.Update();
        }
    }
    Write-Host -Foregroundcolor Green "Done changing cache service account to $global:spServiceAcctName."
}

function SP-ConfigFarmAfterUpgrade {
    Write-Host -Foregroundcolor Green "Performing post farm config tasks"
    # Configure the farm after an upgrade.
    # Use PSConfig to ensure that we're upgraded.
    if (SP-CheckIfUpgradeNeeded -eq $true) {
        $retryNum = 1
        Run-PSConfig
        $PSConfigLastError = Check-PSConfig
        while (!([string]::IsNullOrEmpty($PSConfigLastError)) -and $retryNum -le 4) {
            Write-Warning $PSConfigLastError.Line
            Write-Verbose "An error occurred running PSConfig, trying again ($retryNum)..."
            Start-Sleep -Seconds 5
            $retryNum += 1
            Run-PSConfig
            $PSConfigLastError = Check-PSConfig
        }
        if ($retryNum -ge 5) {
            Write-Verbose "After $retryNum retries to run PSConfig, trying GUI-based..."
            Start-Process -FilePath $PSConfigUI -NoNewWindow -Wait
        }
        Clear-Variable -Name PSConfigLastError -ErrorAction SilentlyContinue
        Clear-Variable -Name PSConfigLog -ErrorAction SilentlyContinue
        Clear-Variable -Name retryNum -ErrorAction SilentlyContinue
    }
    $spVer = (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell).Version.Major;
    $spRegVersion = (Get-Item -Path "HKLM:\SOFTWARE\Microsoft\Shared Tools\Web Server Extensions\$spVer.0\").GetValue("Version")
    if (!($spRegVersion)) {
        Write-Verbose "Creating Version registry value (workaround for bug in PS-based install)"
        Write-Verbose "Getting version number... "
        $spBuild = "$($(Get-SPFarm).BuildVersion.Major).0.0.$($(Get-SPFarm).BuildVersion.Build)"
        Write-Verbose "$spBuild"
        New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Shared Tools\Web Server Extensions\$spVer.0\" `
            -Name Version -Value $spBuild -ErrorAction SilentlyContinue | Out-Null
    }
    # Set an environment variable for the hive (SharePoint root)
    [Environment]::SetEnvironmentVariable($spVer, "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\$spVer", "Machine")
    # Let's make sure the SharePoint Timer Service (SPTimerV4) is running
    # Per workaround in http://www.paulgrimley.com/2010/11/side-effects-of-attaching-additional.html
    if ((Get-Service SPTimerV4).Status -eq "Stopped") {
        Write-Verbose "Starting $((Get-Service SPTimerV4).DisplayName) Service..."
        Start-Service SPTimerV4
        if (!$?) {Throw "Could not start Timer service!"}
    } else {
        Write-Verbose "$((Get-Service SPTimerV4).DisplayName) Service already started.";
    }
    Write-Host -Foregroundcolor Green "Performing post farm config tasks"
}

function SP-CreateCentralAdmin {
    Write-Host -Foregroundcolor Green "Creating CA site."
    # Create CA if it doesn't already exist.
    # Get all Central Admin service instances in the farm
    $centralAdminServices = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq `
        "Microsoft.SharePoint.Administration.SPWebServiceInstance" -and $_.Name -eq "WSS_Administration"}
    # Get those Central Admin services that are Online
    $centralAdminServicesOnline = $centralAdminServices | ? {$_.Status -eq "Online"}
    # Get the local Central Admin service
    $localCentralAdminService = $centralAdminServices | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
    if (($localCentralAdminService.Status -ne "Online")) {
        try {
            # Check if there is already a Central Admin provisioned in the farm; if not, create one
            if (!(Get-SPWebApplication -IncludeCentralAdministration | `
                ? {$_.IsAdministrationWebApplication}) -or $centralAdminServicesOnline.Count -lt 1) {
                # Create Central Admin for farm
                Write-Verbose "Creating Central Admin site..."
                $newCentralAdmin = New-SPCentralAdministration -Port $global:CAportNumber -WindowsAuthProvider "NTLM" -ErrorVariable err
                if (-not $?) {Throw "Error creating central administration application"}
                Write-Host -ForegroundColor yellow "Waiting for Central Admin site..." -NoNewline
                while ($localCentralAdminService.Status -ne "Online") {
                    Write-Host -ForegroundColor yellow "." -NoNewline
                    Start-Sleep 1
                    $centralAdminServices = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq `
                        "Microsoft.SharePoint.Administration.SPWebServiceInstance" -and $_.Name -eq "WSS_Administration"}
                    $localCentralAdminService = $centralAdminServices | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
                }
                Write-Host -BackgroundColor yellow -ForegroundColor Black $($localCentralAdminService.Status)
            }
            # Otherwise create a Central Admin site locally, with an AAM to the existing Central Admin
            else {
                Write-Verbose "Creating local Central Admin site."
                $newCentralAdmin = New-SPCentralAdministration
            }
        }
        catch {
            If ($err -like "*update conflict*") {
                Write-Warning "A concurrency error occured, trying again."
                SP-CreateCentralAdmin
            }
            else {
                throw $_
            }
        }
    }
    Write-Host -Foregroundcolor Green "Done creating CA site."
}

function Run-PSConfig {
    # Run PS Config to complete an upgrade.
    $spVer = (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell).Version.Major;
    $PSConfig = "$env:CommonProgramFiles\microsoft shared\Web Server Extensions\$spVer\BIN\PSCONFIG.exe";
    Start-Process -FilePath $PSConfig -ArgumentList `
        "-cmd upgrade -inplace b2b -force -cmd applicationcontent -install -cmd installfeatures" -NoNewWindow -Wait
}

function Check-PSConfig {
    # Check error from last PSConfig run.
    $PSConfigLogLocation = $((Get-SPDiagnosticConfig).LogLocation) -replace "%CommonProgramFiles%","$env:CommonProgramFiles"
    $PSConfigLog = Get-ChildItem -Path $PSConfigLogLocation | ? {$_.Name -like "PSCDiagnostics*"} | `
        Sort-Object -Descending -Property "LastWriteTime" | Select-Object -first 1
    if ($PSConfigLog -eq $null) {
        Throw "Could not find PSConfig log file!"
    }
    else {
        # Get error(s) from log
        $PSConfigLastError = $PSConfigLog | select-string -SimpleMatch -CaseSensitive -Pattern "ERR" | Select-Object -Last 1
        return $PSConfigLastError
    }
}

function SP-ConfigureDiagnosticLogging {
    # Configure logging.
    Write-Host -Foregroundcolor Green "Configuring logging";
    $spVer = (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell).Version.Major;
    Write-Verbose "Configuring SharePoint diagnostic (ULS) logging..."
    Write-Verbose "Setting SharePoint diagnostic (ULS) logging options:"
    Write-Verbose "  - DaysToKeepLogs: $global:logDaysToKeepLogs"
    Write-Verbose "  - LogDiskSpaceUsageGB: $global:logSpaceUsage"
    Write-Verbose "  - LogLocation: $global:logLocation"
    Write-Verbose "  - LogCutInterval: $global:logCutInterval"
    if ($global:logDaysToKeepLogs -eq $null) {
        $global:logDaysToKeepLogs = 10;
    }
    if ($global:logSpaceUsage -eq $null) {
        $global:logSpaceUsage = 10;
    }
    if ($global:logLocation -eq $null) {
        $global:logLocation = "$env:CommonProgramFiles\microsoft shared\Web Server Extensions\$spVer\LOGS";
    }
    if ($global:logCutInterval -eq $null) {
        $global:logCutInterval = 30;
    }
    Set-SPDiagnosticConfig -DaysToKeepLogs $global:logDaysToKeepLogs -LogMaxDiskSpaceUsageEnabled:$true `
        -LogDiskSpaceUsageGB $global:logSpaceUsage -LogLocation $global:logLocation -LogCutInterval $global:logCutInterval
    # Finally, enable NTFS compression on the ULS log location to save disk space
    # Replace \ with \\ for WMI
    $wmiPath = $global:logLocation.Replace("\","\\")
    $wmiDirectory = Get-WmiObject -Class "Win32_Directory" -Namespace "root\cimv2" -ComputerName $env:COMPUTERNAME -Filter "Name='$wmiPath'"
    # Check if folder is already compressed
    if (!($wmiDirectory.Compressed)) {
        Write-Verbose "Compressing $global:logLocation and subfolders..."
        $compress = $wmiDirectory.CompressEx("","True")
    }
    else {
        Write-Verbose "$folder is already compressed."
    }
    ApplyLogFolderPermissions -path $global:logLocation;
    $where = ([String]"$env:CommonProgramFiles\microsoft shared\Web Server Extensions\$spVer\LOGS").ToLower();
    if (!$global:logLocation.ToLower().StartsWith($where)) {
        ApplyLogFolderPermissions -path $where;
    }
    Set-SPLogLevel -TraceSeverity High -EventSeverity Warning;
    Write-Host -Foregroundcolor Green "Done configuring logging";
}

function SP-ConfigureLanguagePacks {
    # Configure language packs.
    Write-Host -Foregroundcolor Green "Configuring language packs";
    $spVer = (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell).Version.Major;
    $installedOfficeServerLanguages = (Get-Item "HKLM:\Software\Microsoft\Office Server\$spVer.0\InstalledLanguages").GetValueNames() | ? {$_ -ne ""}
    $languagePackInstalled = (Get-Item -Path "HKLM:\SOFTWARE\Microsoft\Shared Tools\Web Server Extensions\$spVer.0\WSS\").GetValue("LanguagePackInstalled")
    # If there were language packs installed we need to run psconfig to configure them
    if (($languagePackInstalled -eq "1") -and ($installedOfficeServerLanguages.Count -gt 1)) {
        Write-Verbose "Configuring language packs..."
        # Let's sleep for a while to let the farm config catch up...
        Start-Sleep 20
        $retryNum += 1
        # Run PSConfig.exe per http://sharepoint.stackexchange.com/questions/9927/sp2010-psconfig-fails-trying-to-configure-farm-after-installing-language-packs
        # Note this was changed from v2v to b2b as suggested by CodePlex user jwthompson98
        Run-PSConfig
        $PSConfigLastError = Check-PSConfig
        while (!([string]::IsNullOrEmpty($PSConfigLastError)) -and $retryNum -le 4) {
            Write-Warning $PSConfigLastError.Line
            Write-Verbose "An error occurred running PSConfig, trying again ($retryNum)..."
            Start-Sleep -Seconds 5
            $retryNum += 1
            Run-PSConfig
            $PSConfigLastError = Check-PSConfig
        }
        if ($retryNum -ge 5) {
            Write-Verbose "After $retryNum retries to run PSConfig, trying GUI-based..."
            Start-Process -FilePath $PSConfigUI -NoNewWindow -Wait
        }
        Clear-Variable -Name PSConfigLastError -ErrorAction SilentlyContinue
        Clear-Variable -Name PSConfigLog -ErrorAction SilentlyContinue
        Clear-Variable -Name retryNum -ErrorAction SilentlyContinue
    }
    Write-Host -Foregroundcolor Green "Done configuring language packs";
}

function SP-RegisterManagedAccount {
    param($username, $password);
    $secPassword = ConvertTo-SecureString "$password" -AsPlaintext -Force
    $alreadyAdmin = $false
    # The following was suggested by Matthias Einig (http://www.codeplex.com/site/users/view/matein78)
    # And inspired by http://todd-carter.com/post/2010/05/03/Give-your-Application-Pool-Accounts-A-Profile.aspx & 
    # http://blog.brainlitter.com/archive/2010/06/08/how-to-revolve-event-id-1511-windows-cannot-find-the-local-profile-on-windows-server-2008.aspx
    try {
        $credAccount = New-Object System.Management.Automation.PsCredential $username,$secPassword
        $managedAccountDomain,$managedAccountUser = $username -Split "\\"
        Write-Verbose "Account `"$managedAccountDomain\$managedAccountUser`:"
        Write-Verbose "Creating local profile for $username...";
        # Add managed account to local admins (very) temporarily so it can log in and create its profile
        if (!($global:localAdmins -contains $managedAccountUser)) {
            $builtinAdminGroup = Get-AdministratorsGroup
            ([ADSI]"WinNT://$env:COMPUTERNAME/$builtinAdminGroup,group").Add("WinNT://$managedAccountDomain/$managedAccountUser")
        }
        else {
            $alreadyAdmin = $true
        }
        # Spawn a command window using the managed account's credentials, create the profile, and exit immediately
        Start-Process -WorkingDirectory "$env:SYSTEMROOT\System32\" -FilePath `
            "cmd.exe" -ArgumentList "/C" -LoadUserProfile -NoNewWindow -Credential $credAccount
        # Remove managed account from local admins unless it was already there
        $builtinAdminGroup = Get-AdministratorsGroup;
        if (-not $alreadyAdmin) {
            ([ADSI]"WinNT://$env:COMPUTERNAME/$builtinAdminGroup,group").Remove("WinNT://$managedAccountDomain/$managedAccountUser")
            if (!$?) {
                Write-Host -ForegroundColor Yellow "   - Could not remove `"$managedAccountDomain\$managedAccountUser`" from local Admins."
                Write-Host -ForegroundColor Yellow "   - Please remove it manually."
            }
        }
    }
    catch {
        $_
        Write-Warning "Could not create local user profile for $username"
        break;
    }
    $managedAccount = Get-SPManagedAccount | Where-Object {$_.UserName -eq $username}
    if ($managedAccount -eq $null) {
        Write-Verbose "Registering managed account $username..."
        if ($username -eq $null -or $password -eq $null) {
            Write-Host -BackgroundColor Gray -ForegroundColor DarkBlue "   - Prompting for Account: "
            $credAccount = $host.ui.PromptForCredential("Managed Account", "Enter Account Credentials:", "", "NetBiosUserName" )
        }
        else {
            $credAccount = New-Object System.Management.Automation.PsCredential $username,$secPassword
        }
        New-SPManagedAccount -Credential $credAccount | Out-Null
        if (-not $?) { Throw "Failed to create managed account" }
    }
    else {
        Write-Verbose "Managed account $username already exists."
    }
}

function SP-CreateManagedAccounts {
    # Create managed accounts.
    Write-Host -Foregroundcolor Green "Adding Managed Accounts."
    # Get the members of the local Administrators group
    $builtinAdminGroup = Get-AdministratorsGroup
    $adminGroup = ([ADSI]"WinNT://$env:COMPUTERNAME/$builtinAdminGroup,group")
    # This syntax comes from Ying Li (http://myitforum.com/cs2/blogs/yli628/archive/2007/08/30/powershell-script-to-add-remove-a-domain-user-to-the-local-administrators-group-on-a-remote-machine.aspx)
    $localAdmins = $adminGroup.psbase.invoke("Members") | ForEach-Object {$_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)}
    # Ensure Secondary Logon service is enabled and started
    if (!((Get-Service -Name seclogon).Status -eq "Running")) {
        Write-Verbose "Enabling Secondary Logon service..."
        Set-Service -Name seclogon -StartupType Manual
        Write-Verbose "Starting Secondary Logon service..."
        Start-Service -Name seclogon
    }
    SP-RegisterManagedAccount -username $global:spAppPoolAcctName -password $global:spAppPoolAcctPwd
    SP-RegisterManagedAccount -username $global:spServiceAcctName -password $global:spServiceAcctPwd
    Write-Host -Foregroundcolor Green "Done adding Managed Accounts."
}

function SP-CreateWebApp {
    param($appPool, $webAppName, $database, $url, $port, $hostheader = $null);
    # Check for an existing App Pool
    $existingWebApp = Get-SPWebApplication | Where-Object { ($_.ApplicationPool).Name -eq $appPool }
    $appPoolExists = ($existingWebApp -ne $null);
    $spVer = (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell).Version.Major;
    $installedOfficeServerLanguages = (Get-Item "HKLM:\Software\Microsoft\Office Server\$spVer.0\InstalledLanguages").GetValueNames() | ? {$_ -ne ""}
    # Strip out any protocol value
    [bool]$useSSL = $false;
    if ($url -like "https://*") {$useSSL = $true}
    # Get the auth provider.
    $authProvider = New-SPAuthenticationProvider -UseWindowsIntegratedAuthentication;
    $authProviderSwitch = @{AuthenticationProvider = $authProvider}
    # If we are running Win2008 (non-R2), we may need the claims hotfix
    if ((Gwmi Win32_OperatingSystem).Version -like "6.0*") { 
        [bool]$claimsHotfixRequired = $true
        Write-Host -ForegroundColor Yellow "Web Applications using Claims authentication require an update"
        Write-Host -ForegroundColor Yellow "Apply the http://go.microsoft.com/fwlink/?LinkID=184705 update after setup."
    }
    if ($appPoolExists) {
        $appPoolAccountSwitch = @{}
    }
    else {
        $appPoolAccountSwitch = @{ApplicationPoolAccount = $($spAppPoolAcctName)}
    }
    # See if the we have the app already
    Write-Verbose "Checking existence of web app $($url):$($port)";
    $getSPWebApplication = Get-SPWebApplication "$($url):$($port)" -ErrorAction SilentlyContinue;
    if ($getSPWebApplication -eq $null) {
        Write-Verbose "Creating Web App `"$webAppName`""
        $hostHeaderSwitch = @{}
        $pathSwitch = @{}
        if ($hostheader -ne $null) { $hostHeaderSwitch = @{HostHeader = $hostHeader}; }
        New-SPWebApplication -Name $webAppName -ApplicationPool $appPool -DatabaseServer $global:dbServer -DatabaseName $database `
            -Url $url -Port $port -SecureSocketsLayer:$useSSL @hostHeaderSwitch @appPoolAccountSwitch @authProviderSwitch @pathSwitch | Out-Null
        if (-not $?) { Throw "Failed to create web application" }
    }
    else {
        Write-Verbose "Web app `"$webAppName`" already provisioned."
    }
}

function SP-CreateSiteCollection($appPool, $database, $siteCollectionName, $siteURL, $template = $null) {
    Write-Host -foregroundcolor Green "Creating Web App for site collection $siteURL";
    # Get the web app
    $webApp = Get-SPWebApplication | Where-Object { ($_.ApplicationPool).Name -eq $appPool }
    if ($webApp -eq $null) { throw "Failed to get web application"; }
    # See if we have the site collection already.
    Write-Verbose "Checking for Site Collection `"$siteURL`"..."
    $getSPSiteCollection = Get-SPSite -Limit ALL | Where-Object {$_.Url -eq $siteURL}
    if (($getSPSiteCollection -eq $null)) {
        # Verify that the Language we're trying to create the site in is currently installed on the server
        $culture = [System.Globalization.CultureInfo]::GetCultureInfo(1033);
        $cultureDisplayName = $culture.DisplayName;
        $spVer = (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell).Version.Major;
        $installedOfficeServerLanguages = (Get-Item "HKLM:\Software\Microsoft\Office Server\$spVer.0\InstalledLanguages").GetValueNames() | ? {$_ -ne ""}
        if (!($installedOfficeServerLanguages | Where-Object {$_ -eq $culture.Name})) {
            Write-Warning "You must install the `"$culture ($cultureDisplayName)`" Language Pack before you can create a site using LCID $LCID"
        }
        else {
            $siteDatabaseExists = Get-SPContentDatabase -Identity $database -ErrorAction SilentlyContinue
            if (!$siteDatabaseExists) {
                Write-Verbose "Creating new content database `"$database`"..."
                New-SPContentDatabase -Name $database -WebApplication $webApp | Out-Null
            }
            Write-Verbose "Creating Site Collection `"$siteURL`"..."
            if ($template -eq $null) {
                $templateSwitch = @{}
            } else {
                $templateSwitch = @{Template = $template}
            }
            $hostHeaderWebAppSwitch = @{}
            $site = New-SPSite -Url $siteURL -OwnerAlias $spAdminAcctName -SecondaryOwner $env:USERDOMAIN\$env:USERNAME -ContentDatabase $database `
                -Name $siteCollectionName -Language 1033 @templateSwitch @hostHeaderWebAppSwitch -ErrorAction Stop

            # Add the Portal Site Connection to the web app, unless of course the current web app *is* the portal
            # Inspired by http://www.toddklindt.com/blog/Lists/Posts/Post.aspx?ID=264
            if ($site.URL -ne $siteURL) {
                Write-Verbose "Setting the Portal Site Connection for `"$siteCollectionName`"..."
                $site.PortalName = $siteCollectionName;
                $site.PortalUrl = $siteURL;
            }
            $site.RootWeb.Update()
        }
    }
    else {
        Write-Verbose "Skipping creation of site `"$siteCollectionName`"already provisioned."
    }
    Write-Host -foregroundcolor Green "Done creating Web App for site collection $siteURL";
}

function SP-CreateMySiteHost {
    # Create the MySite Host.
    SP-CreateWebApp -appPool "MySite Host App Pool" -webAppName "MySite Host" `
        -database ($global:dbPrefix + "_Content_MySiteHost") -url $global:mySiteHost;
    SP-CreateSiteCollection -appPool "MySite Host App Pool" -database ($global:dbPrefix + "_Content_MySiteHost") `
        -siteCollectionName "MySite Host" -siteURL $global:mySiteHost -template "SPSMSITEHOST#0"
}

function SP-CreateDefaultWebApps {
    # Create the main portal and my site host apps.
    SP-CreateWebApp -appPool "Portal App Pool" -webAppName "Portal" `
        -database ($global:dbPrefix + "_Content_Portal") -url "http://$env:COMPUTERNAME" -port 80
    SP-CreateSiteCollection -appPool "Portal App Pool" -database ($global:dbPrefix + "_Content_Portal") `
        -siteCollectionName "Portal" -siteURL "http://$env:COMPUTERNAME" -template "STS#0"
}

function SP-ConfigureEmail {
    Write-Host -Foregroundcolor Green "Configuring Outgoing Email."
    try {
        $loadasm = [System.Reflection.Assembly]::LoadWithPartialName(“Microsoft.SharePoint”)
        $SPGlobalAdmin = New-Object Microsoft.SharePoint.Administration.SPGlobalAdmin
        Write-Verbose "$global:smtpServer $global:fromEmailAddress";
        $SPGlobalAdmin.UpdateMailSettings($global:smtpServer, $global:fromEmailAddress, $global:fromEmailAddress, 65001);
    }
    catch {
        $_
        Write-Warning "Failed to configure email.";
    }
    Write-Host -Foregroundcolor Green "Done configuring Outgoing Email."
}

function SP-PostInstallation {
    # Do some post installation tasks.
    Write-Host -Foregroundcolor Green "Performing post config tasks.";
    # Add custom work here.
    Write-Host -Foregroundcolor Green "Done performing post config tasks.";
}

