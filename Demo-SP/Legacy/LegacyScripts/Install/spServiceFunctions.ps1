#############################################################
# SharePoint Service Functions
# Rob Garrett
# With the help from http://autospinstaller.codeplex.com/

function UpdateProcessIdentity {
    param($serviceToUpdate, $svcName = $null);
    # Update service to use SP service account.
    # Managed Account
    if ($svcName -eq $null) { $svcName = $global:spServiceAcctName; }
    $managedAccountGen = Get-SPManagedAccount | Where-Object {$_.UserName -eq $($svcName)}
    if ($managedAccountGen -eq $null) { Throw "Managed Account $($svcName) not found" }
    if ($serviceToUpdate.Service) {$serviceToUpdate = $serviceToUpdate.Service}
    if ($serviceToUpdate.ProcessIdentity.Username -ne $managedAccountGen.UserName) {
        Write-Verbose "Updating $($serviceToUpdate.TypeName) to run as $($managedAccountGen.UserName)..."
        # Set the Process Identity to our servic account; otherwise it's set by default to the Farm Account and gives warnings in the Health Analyzer
        $serviceToUpdate.ProcessIdentity.CurrentIdentityType = "SpecificUser"
        $serviceToUpdate.ProcessIdentity.ManagedAccount = $managedAccountGen
        $serviceToUpdate.ProcessIdentity.Update()
        $serviceToUpdate.ProcessIdentity.Deploy()
    }
    else {
        Write-Verbose "$($serviceToUpdate.TypeName) is already configured to run as $($managedAccountGen.UserName)."
    }
}

function Get-HostedServicesAppPool {
    # Managed Account
    $managedAccountGen = Get-SPManagedAccount | Where-Object {$_.UserName -eq $($global:spServiceAcctName)}
    if ($managedAccountGen -eq $null) { Throw "Managed Account $($spservice.username) not found" }
    # App Pool
    $applicationPool = Get-SPServiceApplicationPool "SharePoint Hosted Services" -ea SilentlyContinue
    if ($applicationPool -eq $null) {
        Write-Verbose "Creating SharePoint Hosted Services Application Pool..."
        $applicationPool = New-SPServiceApplicationPool -Name "SharePoint Hosted Services" -account $managedAccountGen
        if (-not $?) { Throw "Failed to create the application pool" }
    }
    return $applicationPool
}

function SP-ConfigureSandboxedCodeService {
    # Configure the sandbox code service.
    Write-Host -Foregroundcolor Green "Starting Sandboxed Code Service"
    $spVer = (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell).Version.Major;
    $currentServer = Get-SPServer $env:COMPUTERNAME;
    if ($spVer -ge 16 -and $currentServer.Role -ine "Custom") {
        # TODO: I should check this, seems to be the case when I deploy to "Application or WebFrontEnd"
        Write-Warning "Sandboxed Code Service supports legacy sandbox applications."
        Write-Warning "Deploying this service to non-Custom server roles wil break MinRole compliance.";
        return;
    }
    $sandboxedCodeServices = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Administration.SPUserCodeServiceInstance"}
    $sandboxedCodeService = $sandboxedCodeServices | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
    if ($sandboxedCodeService.Status -ne "Online") {
        try {
            Write-Verbose "Starting Microsoft SharePoint Foundation Sandboxed Code Service..."
            UpdateProcessIdentity $sandboxedCodeService
            $sandboxedCodeService.Update()
            $sandboxedCodeService.Provision()
            if (-not $?) {Throw "Failed to start Sandboxed Code Service"}
        }
        catch {
            throw "An error occurred starting the Microsoft SharePoint Foundation Sandboxed Code Service"
        }
        Write-Host -ForegroundColor Yellow "Waiting for Sandboxed Code service..." -NoNewline
        while ($sandboxedCodeService.Status -ne "Online") {
            Write-Host -ForegroundColor Yellow "." -NoNewline
            Start-Sleep 1
            $sandboxedCodeServices = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Administration.SPUserCodeServiceInstance"}
            $sandboxedCodeService = $sandboxedCodeServices | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
        }
        Write-Host -BackgroundColor Yellow -ForegroundColor Black $($sandboxedCodeService.Status)
    } else {
        Write-Verbose "Sandboxed Code Service already started."
    }
    Write-Host -Foregroundcolor Green "Done Starting Sandboxed Code Service"
}

function SP-CreateStateServiceApp {
    Write-Host -Foregroundcolor Green "Creating state service app";
    # Create the state service application.
    try {
        $stateServiceDB = $global:dbPrefix + "_Service_StateApp";
        $stateServiceProxyName = "$global:stateServiceName Proxy";
        $getSPStateServiceApplication = Get-SPStateServiceApplication
        if ($getSPStateServiceApplication -eq $null) {
            Write-Verbose "Provisioning State Service Application..."
            New-SPStateServiceDatabase -DatabaseServer $global:dbServer -Name $stateServiceDB | Out-Null
            New-SPStateServiceApplication -Name $global:stateServiceName -Database $stateServiceDB | Out-Null
            Get-SPStateServiceDatabase | Initialize-SPStateServiceDatabase | Out-Null
            Write-Verbose "Creating State Service Application Proxy..."
            Get-SPStateServiceApplication | New-SPStateServiceApplicationProxy -Name $stateServiceProxyName -DefaultProxyGroup | Out-Null
            Write-Verbose "Done creating State Service Application."
        }
        else {
            Write-Verbose "State Service Application already provisioned."
        }
    } catch {
        Write-Output $_
        throw "Error provisioning the state service application";
    }
    Write-Host -Foregroundcolor Green "Done creating state service app";
}

function SP-CreateMetadataServiceApp {
    Write-Host -Foregroundcolor Green "Creating Managed Metadata Service Application"
    # Create a managed metadata service app.
    try {
        $metaDataDB = $global:dbPrefix + "_Service_MMS";
        $metadataServiceProxyName = "$global:metadataServiceName Proxy";
        Write-Verbose "Provisioning Managed Metadata Service Application"
        $applicationPool = Get-HostedServicesAppPool
        Write-Verbose "Starting Managed Metadata Service:"
        # Get the service instance
        $metadataServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Taxonomy.MetadataWebServiceInstance"}
        $metadataServiceInstance = $metadataServiceInstances | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
        If (-not $?) { Throw "Failed to find Metadata service instance" }
        # Start Service instances
        if($metadataServiceInstance.Status -eq "Disabled") {
            Write-Verbose "Starting Metadata Service Instance..."
            $metadataServiceInstance.Provision()
            if (-not $?) { Throw "Failed to start Metadata service instance" }
            Write-Host -ForegroundColor Yellow "Waiting for Metadata service..." -NoNewline
            while ($metadataServiceInstance.Status -ne "Online") {
                Write-Host -ForegroundColor Yellow "." -NoNewline
                Start-Sleep 1
                $metadataServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Taxonomy.MetadataWebServiceInstance"}
                $metadataServiceInstance = $metadataServiceInstances | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
            }
            Write-Host -BackgroundColor Yellow -ForegroundColor Black ($metadataServiceInstance.Status)
        }
        else {
            Write-Verbose "Managed Metadata Service already started."
        }
        $metaDataServiceApp = Get-SPServiceApplication | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Taxonomy.MetadataWebServiceApplication"}
        # Create a Metadata Service Application if we don't already have one
        if ($metaDataServiceApp -eq $null) {
            # Create Service App
            Write-Verbose "Creating Metadata Service Application..."
            $metaDataServiceApp = New-SPMetadataServiceApplication -Name $global:metadataServiceName -ApplicationPool $applicationPool -DatabaseServer $global:dbServer -DatabaseName $metaDataDB
            if (-not $?) { Throw "Failed to create Metadata Service Application" }
        } else {
            Write-Verbose "Managed Metadata Service Application already provisioned."
        }
        $metaDataServiceAppProxy = Get-SPServiceApplicationProxy | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Taxonomy.MetadataWebServiceApplicationProxy"}
        if ($metaDataServiceAppProxy -eq $null) {
            # create proxy
            Write-Verbose "Creating Metadata Service Application Proxy..."
            $metaDataServiceAppProxy = New-SPMetadataServiceApplicationProxy -Name $metadataServiceProxyName -ServiceApplication `
                $metaDataServiceApp -DefaultProxyGroup -ContentTypePushdownEnabled -DefaultKeywordTaxonomy -DefaultSiteCollectionTaxonomy
            if (-not $?) { Throw "Failed to create Metadata Service Application Proxy" }
        } else {
            Write-Verbose "Managed Metadata Service Application Proxy already provisioned."
        }
        if ($metaDataServiceApp -or $metaDataServiceAppProxy) {
            # Added to enable Metadata Service Navigation for SP2013, per http://www.toddklindt.com/blog/Lists/Posts/Post.aspx?ID=354
            if ($metaDataServiceAppProxy.Properties.IsDefaultSiteCollectionTaxonomy -ne $true) {
                Write-Verbose "Configuring Metadata Service Application Proxy..."
                $metaDataServiceAppProxy.Properties.IsDefaultSiteCollectionTaxonomy = $true
                $metaDataServiceAppProxy.Update()
            }
            if ($global:spAdminAcctName -ne $null) {
                Write-Verbose "Granting rights to Metadata Service Application:"
                # Get ID of "Managed Metadata Service"
                $metadataServiceAppToSecure = Get-SPServiceApplication | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Taxonomy.MetadataWebServiceApplication"}
                $metadataServiceAppIDToSecure = $metadataServiceAppToSecure.Id
                # Create a variable that contains the list of administrators for the service application
                $metadataServiceAppSecurity = Get-SPServiceApplicationSecurity $metadataServiceAppIDToSecure
                # Create a variable that contains the claims principal for the admin account
                Write-Verbose "$($global:spAdminAcctName)..."
                $accountPrincipal = New-SPClaimsPrincipal -Identity $global:spAdminAcctName -IdentityType WindowsSamAccountName
                # Give permissions to the claims principal you just created
                Grant-SPObjectSecurity $metadataServiceAppSecurity -Principal $accountPrincipal -Rights "Full Access to Term Store"
                # Apply the changes to the Metadata Service application
                Set-SPServiceApplicationSecurity $metadataServiceAppIDToSecure -objectSecurity $metadataServiceAppSecurity
                Write-Verbose "Done granting rights."
            }
            Write-Verbose "Done creating Managed Metadata Service Application."
        }
    } catch {
        Write-Output $_
        Throw "Error provisioning the Managed Metadata Service Application"
    }
    Write-Host -Foregroundcolor Green "Done Creating Managed Metadata Service Application"
}

function SP-ConfigureClaimsToWindowsTokenService {
    Write-Host -Foregroundcolor Green "Configuring C2WTS.";
    # C2WTS is required by Excel Services, Visio Services and PerformancePoint Services; 
    # if any of these are being provisioned we should start it.
    # Configure Claims to Windows STS
    # Ensure Claims to Windows Token Service is started
    $claimsServices = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Administration.Claims.SPWindowsTokenServiceInstance"}
    $claimsService = $claimsServices | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
    if ($claimsService.Status -ne "Online") {
        try {
            UpdateProcessIdentity -serviceToUpdate $claimsService;
            Write-Verbose "Starting $($claimsService.DisplayName)..."
            $claimsService.Provision();
            if (-not $?) {throw " Failed to start $($claimsService.DisplayName)"}
        }
        catch {
            Write-Output $_;
            throw "An error occurred starting $($claimsService.DisplayName)"
        }
        Write-Host -ForegroundColor Yellow "Waiting for $($claimsService.DisplayName)..." -NoNewline
        while ($claimsService.Status -ne "Online") {
            Write-Host -ForegroundColor Yellow "." -NoNewline
            sleep 1
            $claimsServices = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Administration.Claims.SPWindowsTokenServiceInstance"}
            $claimsService = $claimsServices | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
        }
        Write-Host -BackgroundColor Yellow -ForegroundColor Black $($claimsService.Status)
    }
    else {
        Write-Verbose "$($claimsService.DisplayName) already started."
        UpdateProcessIdentity -serviceToUpdate $claimsService;
    }
    Write-Verbose "Setting C2WTS to depend on Cryptographic Services..."
    Start-Process -FilePath "$env:windir\System32\sc.exe" -ArgumentList "config c2wts depend= CryptSvc" -Wait -NoNewWindow -ErrorAction SilentlyContinue
    Write-Host -Foregroundcolor Green "Done configuring C2WTS.";
}

function SetC2WTSToLocalAccount {
    $claimsServices = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.Administration.Claims.SPWindowsTokenServiceInstance"}
    $claimsService = $claimsServices | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
    if ($claimsService.Status -ne "Online") { throw "C2WTS not online"; }
    $pi = $claimsService.Service.ProcessIdentity 
    $pi.CurrentIdentityType = 0;
    $pi.Update();
    $pi.Deploy();
}

function SP-CreateUserProfileServiceApplication {
    Write-Host -Foregroundcolor Green "Creating User Profile Service.";
    # Create user profile service application and set up sync
    try {
        $userProfileServiceProxyName = "$global:userProfileServiceName Proxy";
        # Get the service instance
        $profileServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Administration.UserProfileServiceInstance"}
        $profileServiceInstance = $profileServiceInstances | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
         # Start Service instance
        Write-Verbose "Starting User Profile Service instance..."
        if (($profileServiceInstance.Status -eq "Disabled") -or ($profileServiceInstance.Status -ne "Online")) {
            $profileServiceInstance.Provision()
            if (-not $?) { Throw "Failed to start User Profile Service instance" }
            Write-Host -ForegroundColor Yellow "Waiting for User Profile Service..." -NoNewline
            while ($profileServiceInstance.Status -ne "Online") {
                Write-Host -ForegroundColor Yellow "." -NoNewline
                Start-Sleep 1
                $profileServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Administration.UserProfileServiceInstance"}
                $profileServiceInstance = $profileServiceInstances | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
            }
            Write-Host -BackgroundColor Yellow -ForegroundColor Black $($profileServiceInstance.Status)
        }

        # Create a Profile Service Application
        $profileServiceApp = (Get-SPServiceApplication | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Administration.UserProfileApplication"});
        if ($profileServiceApp -eq $null) {
            # Create MySite Host, if not already created
            SP-CreateMySiteHost;
            # Create Service App
            Write-Verbose "Creating $global:userProfileServiceName..."
            CreateUPSAsAdmin
            Write-Host -ForegroundColor Yellow "Waiting for $global:userProfileServiceName..." -NoNewline
            $profileServiceApp = Get-SPServiceApplication |?{$_.DisplayName -eq $global:userProfileServiceName}
            while ($profileServiceApp.Status -ne "Online") {
                [int]$UPSWaitTime = 0
                # Wait 2 minutes for either the UPS to be created, or the UAC prompt to time out
                while (($UPSWaitTime -lt 120) -and ($profileServiceApp.Status -ne "Online")) {
                    Write-Host -ForegroundColor Yellow "." -NoNewline
                    Start-Sleep 1
                    $profileServiceApp = Get-SPServiceApplication |?{$_.DisplayName -eq $global:userProfileServiceName}
                    [int]$UPSWaitTime += 1
                }
                # If it still isn't Online after 2 minutes, prompt to try again
                if (!($profileServiceApp)) {
                    Write-Host -ForegroundColor Yellow "."
                    Write-Warning "Timed out waiting for service creation (maybe a UAC prompt?)"
                    Write-Host "`a`a`a" # System beeps
                    Pause "try again"
                    CreateUPSAsAdmin
                    Write-Host -ForegroundColor Yellow "Waiting for $global:userProfileServiceName..." -NoNewline
                    $profileServiceApp = Get-SPServiceApplication |?{$_.DisplayName -eq $global:userProfileServiceName}
                } else {
                    break
                }
            }
            Write-Host -BackgroundColor Yellow -ForegroundColor Black $($profileServiceApp.Status)
            # Wait a few seconds for the CreateUPSAsAdmin function to complete
            Start-Sleep 30
            # Get our new Profile Service App
            $profileServiceApp = Get-SPServiceApplication |?{$_.DisplayName -eq $global:userProfileServiceName}
            if (!($profileServiceApp)) {Throw "Could not get $global:userProfileServiceName!";}
            # Create Proxy
            Write-Verbose  "Creating $global:userProfileServiceName Proxy..."
            $profileServiceAppProxy  = New-SPProfileServiceApplicationProxy -Name "$userProfileServiceProxyName" -ServiceApplication $profileServiceApp -DefaultProxyGroup
            if (-not $?) { Throw "Failed to create $global:userProfileServiceName Proxy" }
        }
        # Grant permissions.
        Write-Verbose "Granting rights to ($global:userProfileServiceName):"
        SP-GrantAdminAccessToServiceApplication -serviceApp $profileServiceApp;
        Write-Verbose "Done granting rights."
        # Add resource link to CA.
        SP-AddResourcesLink "User Profile Administration" ("_layouts/ManageUserProfileServiceApplication.aspx?ApplicationID=" +  $profileServiceApp.Id);

        # Configure User Profile Sync Service
        if ($global:disableUPSS -ne $null -and $global:disableUPSS -eq $false) { SP-ConfigureUPSS; }
    } catch {
        Write-Output $_
        Throw "Error provisioning the User Profile Service Application"
    }
    Write-Host -Foregroundcolor Green "Done Creating User Profile Service."
}

function SP-ConfigureUPSS {
    try {
        # Configure User Profile Sync Service
        Write-Host -Foregroundcolor Green "Configuring User Profile Sync Service";
        $spVer = (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell).Version.Major;
        if ($spVer -ge 16) {
            Write-Warning "User Profile Sync not applicable to Sharepoint 2016, use Microsoft Identity Manager instead.";
            Write-Warning "https://technet.microsoft.com/en-us/library/mt627723(v=office.16).aspx";
            return;
        }
        # Get User Profile Service
        $profileServiceApp = Get-SPServiceApplication |?{$_.DisplayName -eq $global:userProfileServiceName}
        if ($profileServiceApp -eq $null) { throw "User Profile Service App not provisioned"; }
        # Get User Profile Synchronization Service
        Write-Verbose "Checking User Profile Synchronization Service...";
        $profileSyncServices = @(Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.Office.Server.Administration.ProfileSynchronizationServiceInstance"})
        $profileSyncService = $profileSyncServices | ? {MatchComputerName $_.Parent.Address $env:COMPUTERNAME}
        if (!($profileSyncServices | ? {$_.Status -eq "Online"})) {
            # Add Farm account to admins group.
            AddAccountToAdmin -spAccountName $global:spFarmAcctName;
            # Check for an existing UPS credentials timer job (e.g. from a prior provisioning attempt), and delete it
            $UPSCredentialsJob = Get-SPTimerJob | ? {$_.Name -eq "windows-service-credentials-FIMSynchronizationService"}
            if ($UPSCredentialsJob.Status -eq "Online") {
                Write-Verbose "Deleting existing sync credentials timer job..."
                $UPSCredentialsJob.Delete()
            }
            UpdateProcessIdentity $profileSyncService -svcName $global:spFarmAcctName;
            $profileSyncService.Update()
            Write-Host -ForegroundColor Yellow "Waiting for User Profile Synchronization Service...";
            # Provision the User Profile Sync Service (using Timer Service Account)
            if ($global:cachedFarmCreds -eq $null) { $global:cachedFarmCreds = SP-GetFarmCredential; }
            $profileServiceApp.SetSynchronizationMachine($env:COMPUTERNAME, $profileSyncService.Id, $global:spFarmAcctName, $global:cachedFarmCreds.Password);
            if (($profileSyncService.Status -ne "Provisioning") -and ($profileSyncService.Status -ne "Online")) {
                Write-Host -ForegroundColor Yellow "Waiting for User Profile Synchronization Service to start..." -NoNewline
            }
            # Monitor User Profile Sync service status
            while ($profileSyncService.Status -ne "Online") {
                while ($profileSyncService.Status -ne "Provisioning") {
                    Write-Host -ForegroundColor Yellow "." -NoNewline
                    Start-Sleep 1
                    $profileSyncService = @(Get-SPServiceInstance | ? {$_.GetType().ToString() -eq `
                        "Microsoft.Office.Server.Administration.ProfileSynchronizationServiceInstance"}) | ? {MatchComputerName $_.Parent.Address $env:COMPUTERNAME}
                }
                if ($profileSyncService.Status -eq "Provisioning") {
                    Write-Host -BackgroundColor Yellow -ForegroundColor Black $($profileSyncService.Status)
                    Write-Host -ForegroundColor Yellow "Provisioning User Profile Sync Service, please wait..." -NoNewline
                }
                while($profileSyncService.Status -eq "Provisioning" -and $profileSyncService.Status -ne "Disabled") {
                    Write-Host -ForegroundColor Yellow "." -NoNewline
                    Start-Sleep 1
                    $profileSyncService = @(Get-SPServiceInstance | ? {$_.GetType().ToString() -eq `
                        "Microsoft.Office.Server.Administration.ProfileSynchronizationServiceInstance"}) | ? {MatchComputerName $_.Parent.Address $env:COMPUTERNAME}
                }
                if ($profileSyncService.Status -ne "Online") {
                    Write-Host -ForegroundColor Red ".`a`a"
                    Write-Host -BackgroundColor Red -ForegroundColor Black "User Profile Synchronization Service could not be started!"
                    break;
                }
                else {
                    Write-Host -BackgroundColor Yellow -ForegroundColor Black $($profileSyncService.Status)
                    # Need to recycle the Central Admin app pool before we can do anything with the User Profile Sync Service
                    Write-Verbose "Recycling Central Admin app pool..."
                    # From http://sharepoint.nauplius.net/2011/09/iisreset-not-required-after-starting.html
                    $appPool = gwmi -Namespace "root\MicrosoftIISv2" -class "IIsApplicationPool" | `
                        where {$_.Name -eq "W3SVC/APPPOOLS/SharePoint Central Administration v4"}
                    if ($appPool) { $appPool.Recycle() }
                    $newlyProvisionedSync = $true
                }
            }
        }
    }
    catch {
        Write-Output $_
        Throw "Error provisioning the User Profile Sync Service"
    }
    finally {
        # Remove the Farm account from admins group.
        RemoveAccountFromAdmin -spAccountName $global:spFarmAcctName;
    }
    Write-Host -Foregroundcolor Green "Done Configuring User Profile Sync Service";
}

function CreateUPSAsAdmin {
    # Create the UPS app.
    try {
        $mySiteHostLocation = $global:mySiteHost;
        $global:userProfileServiceName = "User Profile Service Application";
        # Set the ProfileDBServer, SyncDBServer and SocialDBServer to the same value ($global:dbServer). 
        $profileDBServer = $global:dbServer
        $syncDBServer = $global:dbServer
        $socialDBServer = $global:dbServer
        $profileDB = $global:dbPrefix + "_Service_UPS_Profile";
        $syncDB = $global:dbPrefix + "_Service_UPS_Sync";
        $socialDB = $global:dbPrefix + "_Service_UPS_Social";
        # Create the UPS app.
        $applicationPool = Get-HostedServicesAppPool
        $newProfileServiceApp = New-SPProfileServiceApplication -Name $global:userProfileServiceName -ApplicationPool $applicationPool.Name `
            -ProfileDBName $profileDB -SocialDBName $socialDB -ProfileSyncDBName $syncDB -MySiteHostLocation $mySiteHostLocation;
    } catch {
        Write-Output $_
        Throw "Error provisioning the User Profile Service Application";
    }
}

function SP-CreateSPUsageApp {
    Write-Host -ForegroundColor Green "Creating Usage Managed Service App";
    # Create the SharePoint Usage App.
    try {
        $spUsageDB = $global:dbPrefix + "_Service_UsageApp";
        $getSPUsageApplication = Get-SPUsageApplication
        if ($getSPUsageApplication -eq $null) {
            Write-Verbose "Provisioning SP Usage Application..."
            New-SPUsageApplication -Name $spUsageApplicationName -DatabaseServer $global:dbServer -DatabaseName $spUsageDB | Out-Null
            # Need this to resolve a known issue with the Usage Application Proxy not automatically starting/provisioning
            # Thanks and credit to Jesper Nygaard Schi?tt (jesper@schioett.dk) per http://autospinstaller.codeplex.com/Thread/View.aspx?ThreadId=237578 !
            Write-Verbose "Fixing Usage and Health Data Collection Proxy..."
            $spUsageApplicationProxy = Get-SPServiceApplicationProxy | where {$_.DisplayName -eq $spUsageApplicationName}
            $spUsageApplicationProxy.Provision()
            # End Usage Proxy Fix
            Write-Verbose "Enabling usage processing timer job..."
            $usageProcessingJob = Get-SPTimerJob | ? {$_.TypeName -eq "Microsoft.SharePoint.Administration.SPUsageProcessingJobDefinition"}
            $usageProcessingJob.IsDisabled = $false
            $usageProcessingJob.Update()
            Write-Verbose "Done provisioning SP Usage Application."
        }
        else {
            Write-Verbose "SP Usage Application already provisioned."
        }
    }
    catch {
        Write-Output $_
        Throw "Error provisioning the SP Usage Application"
    }
    Write-Host -ForegroundColor Green "Done Creating Usage Managed Service App";
}

function SP-CreateSecureStoreServiceApp {
    Write-Host -ForegroundColor Green "Creating Secure Store Service";
    # Create a secure store app.
    try {        
        $secureStoreServiceAppProxyName = "$secureStoreServiceAppName Proxy";
        $secureStoreDB = $global:dbPrefix + "_Service_SecureStore";
        Write-Verbose "Provisioning Secure Store Service Application..."
        $applicationPool = Get-HostedServicesAppPool;
        # Get the service instance
        $secureStoreServiceInstances = Get-SPServiceInstance | ? {$_.GetType().Equals([Microsoft.Office.SecureStoreService.Server.SecureStoreServiceInstance])}
        $secureStoreServiceInstance = $secureStoreServiceInstances | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
        if (-not $?) { Throw "Failed to find Secure Store service instance" }
        # Start Service instance
        if ($secureStoreServiceInstance.Status -eq "Disabled") {
            Write-Verbose "Starting Secure Store Service Instance..."
            $secureStoreServiceInstance.Provision()
            if (-not $?) { Throw "Failed to start Secure Store service instance" }
            Write-Host -ForegroundColor Yellow "Waiting for Secure Store service..." -NoNewline
            while ($secureStoreServiceInstance.Status -ne "Online") {
                Write-Host -ForegroundColor Yellow "." -NoNewline
                Start-Sleep 1
                $secureStoreServiceInstances = Get-SPServiceInstance | `
                    ? {$_.GetType().ToString() -eq "Microsoft.Office.SecureStoreService.Server.SecureStoreServiceInstance"}
                $secureStoreServiceInstance = $secureStoreServiceInstances | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
            }
            Write-Host -BackgroundColor Yellow -ForegroundColor Black $($secureStoreServiceInstance.Status)
        }
        # Create Service Application
        $getSPSecureStoreServiceApplication = Get-SPServiceApplication | `
            ? {$_.GetType().Equals([Microsoft.Office.SecureStoreService.Server.SecureStoreServiceApplication])}
        if ($getSPSecureStoreServiceApplication -eq $null) {
            Write-Verbose "Creating Secure Store Service Application..."
            New-SPSecureStoreServiceApplication -Name $secureStoreServiceAppName -PartitionMode:$false -Sharing:$false -DatabaseServer `
                $global:dbServer -DatabaseName $secureStoreDB -ApplicationPool $($applicationPool.Name) -AuditingEnabled:$true -AuditLogMaxSize 30 | Out-Null
            Write-Verbose "Creating Secure Store Service Application Proxy..."
            Get-SPServiceApplication | ? {$_.GetType().Equals([Microsoft.Office.SecureStoreService.Server.SecureStoreServiceApplication])} `
            | New-SPSecureStoreServiceApplicationProxy -Name $secureStoreServiceAppProxyName -DefaultProxyGroup | Out-Null
            Write-Verbose "Done creating Secure Store Service Application."
        }
        else {
            Write-Verbose "Secure Store Service Application already provisioned."
        }
        # Grant access to the store for the current user.
        $secureStoreApp = Get-SPServiceApplication | ? {$_.GetType().Equals([Microsoft.Office.SecureStoreService.Server.SecureStoreServiceApplication])};
        SP-GrantAdminAccessToServiceApplication -serviceApp $secureStoreApp;
        # Create keys
        $secureStore = Get-SPServiceApplicationProxy | Where {$_.GetType().Equals([Microsoft.Office.SecureStoreService.Server.SecureStoreServiceApplicationProxy])}
        Start-Sleep 5
        Write-Verbose "Creating the Master Key..."
        Update-SPSecureStoreMasterKey -ServiceApplicationProxy $secureStore.Id -Passphrase $global:passphrase
        Start-Sleep 5
        Write-Verbose "Creating the Application Key..."
        Update-SPSecureStoreApplicationServerKey -ServiceApplicationProxy $secureStore.Id -Passphrase $global:passphrase -ErrorAction SilentlyContinue
        Start-Sleep 5
        if (!$?) {
            # Try again...
            Write-Verbose "Creating the Application Key (2nd attempt)..."
            Update-SPSecureStoreApplicationServerKey -ServiceApplicationProxy $secureStore.Id -Passphrase $global:passphrase
        }
    } catch {
        Write-Output $_
        Throw "Error provisioning secure store application"
    }
    Write-Verbose "Done creating/configuring Secure Store Service Application.";
    Write-Host -ForegroundColor Green "Done Creating Secure Store Service";
}

function SP-GrantAdminAccessToServiceApplication {
    Param($serviceApp);
    Write-Host -ForegroundColor Green "Granting Adminstrator Access to Service Application";
    try {
        $username = "$env:USERDOMAIN\$env:USERNAME";
        $claim = New-SPClaimsPrincipal -Identity $username -IdentityType WindowsSAMAccountName;
        $serviceAppIDToSecure = Get-SPServiceApplication $($serviceApp.Id);
        $serviceAppSecurity = Get-SPServiceApplicationSecurity $serviceAppIDToSecure -Admin;
        $serviceAppPermissions = Get-SPServiceApplicationSecurity $serviceAppIDToSecure;
        # Get account principals
        $currentUserAcctPrincipal = New-SPClaimsPrincipal -Identity $username -IdentityType WindowsSamAccountName
        $spServiceAcctPrincipal = New-SPClaimsPrincipal -Identity $($global:spServiceAcctName) -IdentityType WindowsSamAccountName
        $spAdminAcctPrincipal = New-SPClaimsPrincipal -Identity $($global:spAdminAcctName) -IdentityType WindowsSamAccountName
        Grant-SPObjectSecurity $serviceAppSecurity -Principal $currentUserAcctPrincipal -Rights "Full Control"
        Grant-SPObjectSecurity $serviceAppPermissions -Principal $currentUserAcctPrincipal -Rights "Full Control"
        Grant-SPObjectSecurity $serviceAppPermissions -Principal $spServiceAcctPrincipal -Rights "Full Control"
        Grant-SPObjectSecurity $serviceAppPermissions -Principal $spAdminAcctPrincipal -Rights "Full Control"
        Set-SPServiceApplicationSecurity $serviceAppIDToSecure -objectSecurity $serviceAppSecurity -Admin
        Set-SPServiceApplicationSecurity $serviceAppIDToSecure -objectSecurity $serviceAppPermissions
    } catch {
        Write-Output $_
        Throw "Error Granting Adminstrator Access to Service Application";
    }
    Write-Host -ForegroundColor Green "Done Granting Adminstrator Access to Service Application";
}

function SP-ConfigureTracing {
    Write-Host -ForegroundColor Green "Configuring Tracing";
    # Configure tracing.
    # Make sure a credential deployment job doesn't already exist
    if (!(Get-SPTimerJob -Identity "windows-service-credentials-SPTraceV4")) {
        $spTraceV4 = (Get-SPFarm).Services | where {$_.Name -eq "SPTraceV4"}
        $appPoolAcctDomain, $appPoolAcctUser = $global:spServiceAcctName -Split "\\"
        Write-Verbose "Applying service account $($global:spServiceAcctName) to service SPTraceV4..."
        # Add to Performance Monitor Users group
        Write-Verbose "Adding $($global:spServiceAcctName) to local Performance Monitor Users group..."
        try {
            ([ADSI]"WinNT://$env:COMPUTERNAME/Performance Monitor Users,group").Add("WinNT://$appPoolAcctDomain/$appPoolAcctUser")
            if (-not $?) {Throw}
        }
        catch {
            Write-Verbose "$($global:spServiceAcctName) is already a member of Performance Monitor Users."
        }
        # Add to Performance Log Users group
        Write-Verbose "Adding $($global:spServiceAcctName) to local Performance Log Users group..."
        try {
            ([ADSI]"WinNT://$env:COMPUTERNAME/Performance Log Users,group").Add("WinNT://$appPoolAcctDomain/$appPoolAcctUser")
            if (-not $?) {Throw}
        }
        catch {
            Write-Verbose "$($global:spServiceAcctName) is already a member of Performance Log Users."
        }
        try {
            UpdateProcessIdentity $spTraceV4
        }
        catch {
            Write-Output $_
            Throw "An error occurred updating the service account for service SPTraceV4."
        }
        # Restart SPTraceV4 service so changes to group memberships above can take effect
        Write-Verbose "Restarting service SPTraceV4..."
        Restart-Service -Name "SPTraceV4" -Force
    }
    else {
        Write-Warning "Timer job `"windows-service-credentials-SPTraceV4`" already exists."
        Write-Host -ForegroundColor Yellow "Check that $($global:spServiceAcctName) is a member of the Performance Log Users and Performance Monitor Users local groups once install completes."
    }
    Write-Host -ForegroundColor Green "Done Configuring Tracing";
}

function SP-CreateBusinessDataConnectivityServiceApp {
    Write-Host -ForegroundColor Green "Creating BCS Service App.";
    # Create BCS service app
    try {
        $bdcDataDB = $global:dbPrefix + "_Service_BCS";
        $bdcAppProxyName = "$global:bdcAppName Proxy";
        Write-Verbose "Provisioning $global:bdcAppName"
        $applicationPool = Get-HostedServicesAppPool;
        Write-Verbose "Checking local service instance..."
        # Get the service instance
        $bdcServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.BusinessData.SharedService.BdcServiceInstance"}
        $bdcServiceInstance = $bdcServiceInstances | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
        If (-not $?) { Throw "Failed to find the service instance" }
        # Start Service instances
        If($bdcServiceInstance.Status -eq "Disabled") {
            Write-Verbose "Starting $($bdcServiceInstance.TypeName)..."
            $bdcServiceInstance.Provision()
            If (-not $?) { Throw "Failed to start $($bdcServiceInstance.TypeName)" }
            # Wait
            Write-Host -ForegroundColor Yellow "Waiting for $($bdcServiceInstance.TypeName)..." -NoNewline
            while ($bdcServiceInstance.Status -ne "Online") {
                Write-Host -ForegroundColor Yellow "." -NoNewline
                Start-Sleep 1
                $bdcServiceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.BusinessData.SharedService.BdcServiceInstance"}
                $bdcServiceInstance = $bdcServiceInstances | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
            }
            Write-Host -BackgroundColor Yellow -ForegroundColor Black ($bdcServiceInstance.Status)
        } else {
            Write-Verbose "$($bdcServiceInstance.TypeName) already started."
        }
        # Create a Business Data Catalog Service Application
        $bdcDataServiceApp = Get-SPServiceApplication | ? {$_.GetType().ToString() -eq "Microsoft.SharePoint.BusinessData.SharedService.BdcServiceApplication"};
        if ($bdcDataServiceApp -eq $null) {
            # Create Service App
            Write-Verbose "Creating $global:bdcAppName..."
            $bdcDataServiceApp = New-SPBusinessDataCatalogServiceApplication -Name $global:bdcAppName -ApplicationPool $applicationPool -DatabaseServer $global:dbServer -DatabaseName $bdcDataDB
            if (-not $?) { Throw "Failed to create $global:bdcAppName" }
        } else {
            Write-Verbose "$global:bdcAppName already provisioned."
        }
        Write-Verbose "Done creating $global:bdcAppName."
    } catch {
        Write-Output $_
        Throw "Error provisioning Business Data Connectivity application"
    }
    # Grant rights.
    SP-GrantAdminAccessToServiceApplication -serviceApp $bdcDataServiceApp;

    Write-Host -ForegroundColor Green "Done Creating BCS Service App.";
}

function SP-CreateExcelServiceApp {
    Write-Host -ForegroundColor Green "Creating Excel Services App.";
    $spVer = (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell).Version.Major;
    if ($spVer -ge 16) {
        Write-Warning "Excel services not available from Sharepoint 2016";
        Write-Warning "Use Office Online Server https://technet.microsoft.com/en-us/library/jj219456(v=office.16).aspx";
        return;
    }
    # Create excel services.
    try {
        Write-Verbose "Provisioning $global:excelAppName..."
        $applicationPool = Get-HostedServicesAppPool;
        Write-Verbose "Checking local service instance..."
        # Get the service instance
        $excelServiceInstances = Get-SPServiceInstance | `
            ? {$_.GetType().ToString() -eq "Microsoft.Office.Excel.Server.MossHost.ExcelServerWebServiceInstance"}
        $excelServiceInstance = $excelServiceInstances | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
        if (-not $?) { Throw "Failed to find the service instance" }
        # Start Service instances
        if($excelServiceInstance.Status -eq "Disabled") {
            Write-Verbose "Starting $($excelServiceInstance.TypeName)..."
            $excelServiceInstance.Provision()
            if (-not $?) { Throw "Failed to start $($excelServiceInstance.TypeName) instance" }
            Write-Host -ForegroundColor Yellow "Waiting for $($excelServiceInstance.TypeName)..." -NoNewline
            while ($excelServiceInstance.Status -ne "Online") {
                Write-Host -ForegroundColor Yellow "." -NoNewline
                Start-Sleep 1
                $excelServiceInstances = Get-SPServiceInstance | `
                    ? {$_.GetType().ToString() -eq "Microsoft.Office.Excel.Server.MossHost.ExcelServerWebServiceInstance"}
                $excelServiceInstance = $excelServiceInstances | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
            }
            Write-Host -BackgroundColor Yellow -ForegroundColor Black ($excelServiceInstance.Status)
        }
        else {
            Write-Verbose "$($excelServiceInstance.TypeName) already started."
        }
        # Create an Excel Service Application
        $excelServiceApp = Get-SPServiceApplication | ? {$_.GetType().ToString() -eq "Microsoft.Office.Excel.Server.MossHost.ExcelServerWebServiceApplication"}
        if ($excelServiceApp -eq $null) {
            # Create Service App
            Write-Verbose "Creating $global:excelAppName..."
            # Check if our new cmdlets are available yet,  if not, re-load the SharePoint PS Snapin
            if (!(Get-Command New-SPExcelServiceApplication -ErrorAction SilentlyContinue)) {
                Write-Verbose "Re-importing SP PowerShell Snapin to enable new cmdlets..."
                Remove-PSSnapin Microsoft.SharePoint.PowerShell
                Load-SharePoint-PowerShell
            }
            $excelServiceApp = New-SPExcelServiceApplication -name $global:excelAppName -ApplicationPool $($applicationPool.Name) -Default
            if (-not $?) { Throw "Failed to create $global:excelAppName" }
            $caUrl = (Get-Item -Path "HKLM:\SOFTWARE\Microsoft\Shared Tools\Web Server Extensions\$spVer.0\WSS").GetValue("CentralAdministrationURL")
            New-SPExcelFileLocation -LocationType SharePoint -IncludeChildren -Address $caUrl -ExcelServiceApplication $global:excelAppName -ExternalDataAllowed 2 -WorkbookSizeMax 10 | Out-Null
        }
        else {
            Write-Verbose "$global:excelAppName already provisioned."
        }
        Write-Verbose "Configuring service app settings..."
        # Configure unattended accounts, based on:
        # http://blog.falchionconsulting.com/index.php/2010/10/service-accounts-and-managed-service-accounts-in-sharepoint-2010/
        Write-Verbose "Setting unattended account credentials..."
        # Reget application to prevent update conflict error message
        $excelServiceApp = Get-SPExcelServiceApplication
        # Get account credentials
        $excelAcct = $global:spServiceAcctName;
        $excelAcctPWD = $global:spServiceAcctPWD;
        $secPassword = ConvertTo-SecureString "$excelAcctPWD" -AsPlaintext -Force
        $unattendedAccount = New-Object System.Management.Automation.PsCredential $excelAcct,$secPassword
        # Set the group claim and admin principals
        $groupClaim = New-SPClaimsPrincipal -Identity "nt authority\authenticated users" -IdentityType WindowsSamAccountName
        $adminPrincipal = New-SPClaimsPrincipal -Identity "$($env:userdomain)\$($env:username)" -IdentityType WindowsSamAccountName
        # Set the field values
        $secureUserName = ConvertTo-SecureString $unattendedAccount.UserName -AsPlainText -Force
        $securePassword = $unattendedAccount.Password
        $credentialValues = $secureUserName, $securePassword
        # Set the Target App Name and create the Target App
        $name = "$($excelServiceApp.ID)-ExcelUnattendedAccount"
        Write-Verbose "Creating Secure Store Target Application $name..."
        $secureStoreTargetApp = New-SPSecureStoreTargetApplication -Name $name `
            -FriendlyName "Excel Services Unattended Account Target App" `
            -ApplicationType Group `
            -TimeoutInMinutes 3
        # Set the account fields
        $usernameField = New-SPSecureStoreApplicationField -Name "User Name" -Type WindowsUserName -Masked:$false
        $passwordField = New-SPSecureStoreApplicationField -Name "Password" -Type WindowsPassword -Masked:$false
        $fields = $usernameField, $passwordField
        # Get the service context
        $subId = [Microsoft.SharePoint.SPSiteSubscriptionIdentifier]::Default
        $context = [Microsoft.SharePoint.SPServiceContext]::GetContext($excelServiceApp.ServiceApplicationProxyGroup, $subId)
        # Check to see if the Secure Store App already exists
        $secureStoreApp = Get-SPSecureStoreApplication -ServiceContext $context -Name $name -ErrorAction SilentlyContinue
        if ($secureStoreApp -eq $null) { 
            # Doesn't exist so create.
            Write-Verbose "Creating Secure Store Application..."
            $secureStoreApp = New-SPSecureStoreApplication -ServiceContext $context `
                -TargetApplication $secureStoreTargetApp `
                -Administrator $adminPrincipal `
                -CredentialsOwnerGroup $groupClaim `
                -Fields $fields;
        }
        # Update the field values
        Write-Verbose "Updating Secure Store Group Credential Mapping..."
        Update-SPSecureStoreGroupCredentialMapping -Identity $secureStoreApp -Values $credentialValues
        # Set the unattended service account application ID
        Set-SPExcelServiceApplication -Identity $excelServiceApp -UnattendedAccountApplicationId $name
        Write-Verbose "Done creating $global:excelAppName."
    } catch {
        Write-Output $_
        Throw "Error provisioning Excel Service Application"
    }
    Write-Host -ForegroundColor Green "Done Creating Excel Services App.";
}

function SP-CreateAccess2010ServiceApp {
    Write-Host -ForegroundColor Green "Creating Access 2010 Services App.";
    # Create support for legacy Access Services
    $serviceInstanceType = "Microsoft.Office.Access.Server.MossHost.AccessServerWebServiceInstance"
    CreateGenericServiceApplication `
        -ServiceInstanceType $serviceInstanceType `
        -ServiceName $global:access2010AppName `
        -ServiceDBName ($global:dbPrefix + "_Service_Access2010") `
        -ServiceGetCmdlet "Get-SPAccessServiceApplication" `
        -ServiceProxyGetCmdlet "Get-SPServiceApplicationProxy" `
        -ServiceNewCmdlet "New-SPAccessServiceApplication -Default" `
        -ServiceProxyNewCmdlet "New-SPAccessServiceApplicationProxy" 
        # Fake cmdlet (and not needed for Access Services), but the CreateGenericServiceApplication function expects something
    Write-Host -ForegroundColor Green "Done Creating Access 2010 Services App.";
}

function SP-CreateVisioServiceApp {
    Write-Host -ForegroundColor Green "Creating Visio Services App";
    # Create Visio Services App
    $serviceInstanceType = "Microsoft.Office.Visio.Server.Administration.VisioGraphicsServiceInstance"
    CreateGenericServiceApplication `
        -ServiceInstanceType $serviceInstanceType `
        -ServiceName $global:visioAppName `
        -ServiceDBName ($global:dbPrefix + "_Service_Visio") `
        -ServiceGetCmdlet "Get-SPVisioServiceApplication" `
        -ServiceProxyGetCmdlet "Get-SPVisioServiceApplicationProxy" `
        -ServiceNewCmdlet "New-SPVisioServiceApplication" `
        -ServiceProxyNewCmdlet "New-SPVisioServiceApplicationProxy"

    if (Get-Command -Name Get-SPVisioServiceApplication -ErrorAction SilentlyContinue) {
        # http://blog.falchionconsulting.com/index.php/2010/10/service-accounts-and-managed-service-accounts-in-sharepoint-2010/
        Write-Verbose "Setting unattended account credentials..."
        $serviceApplication = Get-SPServiceApplication -name $global:visioAppName
        # Get account credentials
        $visioAcct = $global:spServiceAcctName;
        $visioAcctPWD = $global:spServiceAcctPwd;
        $secPassword = ConvertTo-SecureString "$visioAcctPWD" -AsPlaintext -Force
        $unattendedAccount = New-Object System.Management.Automation.PsCredential $visioAcct,$secPassword
        # Set the group claim and admin principals
        $groupClaim = New-SPClaimsPrincipal -Identity "nt authority\authenticated users" -IdentityType WindowsSamAccountName
        $adminPrincipal = New-SPClaimsPrincipal -Identity "$($env:userdomain)\$($env:username)" -IdentityType WindowsSamAccountName
        # Set the field values
        $secureUserName = ConvertTo-SecureString $unattendedAccount.UserName -AsPlainText -Force
        $securePassword = $unattendedAccount.Password
        $credentialValues = $secureUserName, $securePassword
        # Set the Target App Name and create the Target App
        $name = "$($serviceApplication.ID)-VisioUnattendedAccount"
        Write-Verbose "Creating Secure Store Target Application $name..."
        $secureStoreTargetApp = New-SPSecureStoreTargetApplication -Name $name `
            -FriendlyName "Visio Services Unattended Account Target App" `
            -ApplicationType Group `
            -TimeoutInMinutes 3
        # Set the account fields
        $usernameField = New-SPSecureStoreApplicationField -Name "User Name" -Type WindowsUserName -Masked:$false
        $passwordField = New-SPSecureStoreApplicationField -Name "Password" -Type WindowsPassword -Masked:$false
        $fields = $usernameField, $passwordField
        # Get the service context
        $subId = [Microsoft.SharePoint.SPSiteSubscriptionIdentifier]::Default
        $context = [Microsoft.SharePoint.SPServiceContext]::GetContext($serviceApplication.ServiceApplicationProxyGroup, $subId)
        # Check to see if the Secure Store App already exists
        $secureStoreApp = Get-SPSecureStoreApplication -ServiceContext $context -Name $name -ErrorAction SilentlyContinue
        if ($secureStoreApp -eq $null) {
            # Doesn't exist so create.
            Write-Verbose "Creating Secure Store Application..."
            $secureStoreApp = New-SPSecureStoreApplication -ServiceContext $context `
                -TargetApplication $secureStoreTargetApp `
                -Administrator $adminPrincipal `
                -CredentialsOwnerGroup $groupClaim `
                -Fields $fields
        }
        # Update the field values
        Write-Verbose "Updating Secure Store Group Credential Mapping..."
        Update-SPSecureStoreGroupCredentialMapping -Identity $secureStoreApp -Values $credentialValues
        # Set the unattended service account application ID
        Write-Verbose "Setting Application ID for Visio Service..."
        $serviceApplication | Set-SPVisioExternalData -UnattendedServiceAccountApplicationID $name
    }
    Write-Host -ForegroundColor Green "Done Creating Visio Services App";
}

function SP-CreatePerformancePointServiceApp {
    Write-Host -ForegroundColor Green "Creating PerformancePoint Services App";
    # Create PerformancePoint App.
    $serviceDB = ($global:dbPrefix + "_Service_PerformancePoint");
    $serviceInstanceType = "Microsoft.PerformancePoint.Scorecards.BIMonitoringServiceInstance"
    CreateGenericServiceApplication `
        -ServiceInstanceType $serviceInstanceType `
        -ServiceName $global:perfPointAppName `
        -ServiceDBName $serviceDB `
        -ServiceGetCmdlet "Get-SPPerformancePointServiceApplication" `
        -ServiceProxyGetCmdlet "Get-SPServiceApplicationProxy" `
        -ServiceNewCmdlet "New-SPPerformancePointServiceApplication" `
        -ServiceProxyNewCmdlet "New-SPPerformancePointServiceApplicationProxy"

    $application = Get-SPPerformancePointServiceApplication | ? {$_.Name -eq $serviceConfig.Name}
    if ($application) {
        $farmAcct = $global:spFarmAcctName;
        Write-Verbose "Granting $farmAcct rights to database $serviceDB..."
        Get-SPDatabase | Where {$_.Name -eq $serviceDB} | Add-SPShellAdmin -UserName $farmAcct
        Write-Verbose "Setting PerformancePoint Data Source Unattended Service Account..."
        $performancePointAcct = $global:spServiceAcctName;
        $performancePointAcctPWD = $global:spServiceAcctPwd;
        $secPassword = ConvertTo-SecureString "$performancePointAcctPWD" -AsPlaintext -Force
        $performancePointCredential = New-Object System.Management.Automation.PsCredential $performancePointAcct,$secPassword
        $application | Set-SPPerformancePointSecureDataValues -DataSourceUnattendedServiceAccount $performancePointCredential
    }
    Write-Host -ForegroundColor Green "Done Creating PerformancePoint Services App";
}

function SP-CreateWordAutomationServiceApp {
    Write-Host -ForegroundColor Green "Creating Word Automation Services App";
    # Create Word Automation Service App.
    $serviceDB = ($global:dbPrefix + "_Service_WordAutomation");
    $serviceInstanceType = "Microsoft.Office.Word.Server.Service.WordServiceInstance"
    CreateGenericServiceApplication `
        -ServiceInstanceType $serviceInstanceType `
        -ServiceName $global:wordAutoAppName `
        -ServiceDBName $serviceDB `
        -ServiceGetCmdlet "Get-SPServiceApplication" `
        -ServiceProxyGetCmdlet "Get-SPServiceApplicationProxy" `
        -ServiceNewCmdlet "New-SPWordConversionServiceApplication -DatabaseServer $global:dbServer -DatabaseName $serviceDB -Default" `
        -ServiceProxyNewCmdlet "New-SPWordConversionServiceApplicationProxy" 
        # Fake cmdlet, but the CreateGenericServiceApplication function expects something
    # Run the Word Automation Timer Job immediately; otherwise we will have a Health Analyzer error condition until the job runs as scheduled
    if (Get-SPServiceApplication | ? {$_.DisplayName -eq $($serviceConfig.Name)}) {
        Get-SPTimerJob | ? {$_.GetType().ToString() -eq "Microsoft.Office.Word.Server.Service.QueueJob"} | ForEach-Object {$_.RunNow()}
    }
    Write-Host -ForegroundColor Green "Done Creating Word Automation Services App";
}

function CreateGenericServiceApplication() {
    # Creata generic service application - used for office apps.
    param
    (
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()]
        [String]$serviceInstanceType,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()]
        [String]$serviceName,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()]
        [String]$serviceDBName,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()]
        [String]$serviceGetCmdlet,
        [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()]
        [String]$serviceProxyGetCmdlet,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()]
        [String]$serviceNewCmdlet,
        [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()]
        [String]$serviceProxyNewCmdlet,
        [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()]
        [String]$serviceProxyNewParams
    )
    try {
        $serviceProxyName = "$serviceName Proxy";
        $applicationPool = Get-HostedServicesAppPool
        Write-Verbose "Provisioning $serviceName..."
        # get the service instance
        $serviceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq $serviceInstanceType}
        $serviceInstance = $serviceInstances | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
        if (!$serviceInstance) { Throw "Failed to get service instance - check product version (Standard vs. Enterprise)" }
        # Start Service instance
        Write-Verbose "Checking $($serviceInstance.TypeName) instance..."
        if (($serviceInstance.Status -eq "Disabled") -or ($serviceInstance.Status -ne "Online")) {
            Write-Verbose "Starting $($serviceInstance.TypeName) instance..."
            $serviceInstance.Provision()
            if (-not $?) { Throw "Failed to start $($serviceInstance.TypeName) instance" }
            Write-Host -ForegroundColor Yellow "Waiting for $($serviceInstance.TypeName) instance..." -NoNewline
            while ($serviceInstance.Status -ne "Online") {
                Write-Host -ForegroundColor Yellow "." -NoNewline
                Start-Sleep 1
                $serviceInstances = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq $serviceInstanceType}
                $serviceInstance = $serviceInstances | ? {MatchComputerName $_.Server.Address $env:COMPUTERNAME}
            }
            Write-Host -BackgroundColor Yellow -ForegroundColor Black $($serviceInstance.Status)
        }
        else {
            Write-Verbose "$($serviceInstance.TypeName) instance already started."
        }
        # Check if our new cmdlets are available yet,  if not, re-load the SharePoint PS Snapin
        if (!(Get-Command $serviceGetCmdlet -ErrorAction SilentlyContinue)) {
            Write-Verbose "Re-importing SP PowerShell Snapin to enable new cmdlets..."
            Remove-PSSnapin Microsoft.SharePoint.PowerShell
            Load-SharePoint-PowerShell
        }
        $getServiceApplication = Invoke-Expression "$serviceGetCmdlet | ? {`$_.Name -eq `"$serviceName`"}"
        if ($getServiceApplication -eq $null) {
            Write-Verbose "Creating $serviceName..."
            If (($serviceInstanceType -eq "Microsoft.PerformancePoint.Scorecards.BIMonitoringServiceInstance")) {
                $newServiceApplication = Invoke-Expression `
                    "$serviceNewCmdlet -Name `"$serviceName`" -ApplicationPool `$applicationPool -DatabaseServer `$global:dbServer -DatabaseName `$serviceDBName"
            }
            else {
                $newServiceApplication = Invoke-Expression "$serviceNewCmdlet -Name `"$serviceName`" -ApplicationPool `$applicationPool"
            }
            $getServiceApplication = Invoke-Expression "$serviceGetCmdlet | ? {`$_.Name -eq `"$serviceName`"}"
            if ($getServiceApplication) {
                Write-Verbose "Provisioning $serviceName Proxy..."
                # Because apparently the teams developing the cmdlets for the various service apps didn't communicate with each other, 
                # we have to account for the different ways each proxy is provisioned!
                switch ($serviceInstanceType) {
                    "Microsoft.Office.Server.PowerPoint.SharePoint.Administration.PowerPointWebServiceInstance" `
                    {& $serviceProxyNewCmdlet -Name "$serviceProxyName" -ServiceApplication $newServiceApplication -AddToDefaultGroup | Out-Null}
                    "Microsoft.Office.Visio.Server.Administration.VisioGraphicsServiceInstance" `
                    {& $serviceProxyNewCmdlet -Name "$serviceProxyName" -ServiceApplication $newServiceApplication.Name | Out-Null}
                    "Microsoft.PerformancePoint.Scorecards.BIMonitoringServiceInstance" `
                    {& $serviceProxyNewCmdlet -Name "$serviceProxyName" -ServiceApplication $newServiceApplication -Default | Out-Null}
                    "Microsoft.Office.Excel.Server.MossHost.ExcelServerWebServiceInstance" {} # Do nothing because there is no cmdlet to create this services proxy
                    "Microsoft.Office.Access.Server.MossHost.AccessServerWebServiceInstance" {} # Do nothing because there is no cmdlet to create this services proxy
                    "Microsoft.Office.Word.Server.Service.WordServiceInstance" {} # Do nothing because there is no cmdlet to create this services proxy
    				"Microsoft.SharePoint.SPSubscriptionSettingsServiceInstance" `
                    {& $serviceProxyNewCmdlet -ServiceApplication $newServiceApplication | Out-Null}
                    "Microsoft.Office.Server.WorkManagement.WorkManagementServiceInstance" `
                    {& $serviceProxyNewCmdlet -Name "$serviceProxyName" -ServiceApplication $newServiceApplication -DefaultProxyGroup | Out-Null}
                    "Microsoft.Office.TranslationServices.TranslationServiceInstance" {} # Do nothing because the service app cmdlet automatically creates a proxy with the default name
                    "Microsoft.Office.Access.Services.MossHost.AccessServicesWebServiceInstance" `
                    {& $serviceProxyNewCmdlet -application $newServiceApplication | Out-Null}
                    "Microsoft.Office.Server.PowerPoint.Administration.PowerPointConversionServiceInstance" `
                    {& $serviceProxyNewCmdlet -Name "$serviceProxyName" -ServiceApplication $newServiceApplication -AddToDefaultGroup | Out-Null}
                    "Microsoft.Office.Project.Server.Administration.PsiServiceInstance" {} # Do nothing because the service app cmdlet automatically creates a proxy with the default name
                    Default {& $serviceProxyNewCmdlet -Name "$serviceProxyName" -ServiceApplication $newServiceApplication | Out-Null}
                }
                Write-Verbose "Done provisioning $serviceName. "
            }
            else {
                Write-Warning "An error occurred provisioning $serviceName! Check the log for any details, then try again."
            }
        }
        else {
            Write-Verbose "$serviceName already created."
        }
    }
    catch {
        Write-Output $_
    }
}

function SP-CreateAppManagementServiceApp {
    Write-Host -ForegroundColor Green "Creating App Management Service";
    # Create the app management service app.
    $serviceDB = $global:dbPrefix + "_Service_AppManagement";
    $serviceInstanceType = "Microsoft.SharePoint.AppManagement.AppManagementServiceInstance"
    CreateGenericServiceApplication `
        -ServiceInstanceType $serviceInstanceType `
        -ServiceName $global:appMgmtName `
        -ServiceDBName = $serviceDB `
        -ServiceGetCmdlet "Get-SPServiceApplication" `
        -ServiceProxyGetCmdlet "Get-SPServiceApplicationProxy" `
		-ServiceNewCmdlet "New-SPAppManagementServiceApplication -DatabaseServer $global:dbServer -DatabaseName $serviceDB" `
        -ServiceProxyNewCmdlet "New-SPAppManagementServiceApplicationProxy"
	# Configure your app domain and location
	Write-Verbose "Setting App Domain `"$($appDomain)`"..."
	Set-SPAppDomain -AppDomain $global:appDomain;
    Write-Host -ForegroundColor Green "Done Creating App Management Service";
}

function SP-CreateSubscriptionSettingsServiceApp {
    Write-Host -ForegroundColor Green "Creating App Subscription Service";
    # Create the subscription service app.
    $serviceDB = $global:dbPrefix + "_Service_AppSubscription";
    $serviceInstanceType = "Microsoft.SharePoint.SPSubscriptionSettingsServiceInstance"
    CreateGenericServiceApplication `
        -ServiceInstanceType $serviceInstanceType `
        -ServiceName $global:appSubsName `
        -ServiceDBName $serviceDB `
        -ServiceGetCmdlet "Get-SPServiceApplication" `
        -ServiceProxyGetCmdlet "Get-SPServiceApplicationProxy" `
		-ServiceNewCmdlet "New-SPSubscriptionSettingsServiceApplication -DatabaseServer $global:dbServer -DatabaseName $serviceDB" `
        -ServiceProxyNewCmdlet "New-SPSubscriptionSettingsServiceApplicationProxy"
		Write-Verbose "Setting Site Subscription name `"$($global:appSubscriptionName)`"..."
    # Wait for the service to be available.
    Start-Sleep 20;
	Set-SPAppSiteSubscriptionName -Name $global:appSubscriptionName -Confirm:$false
    Write-Host -ForegroundColor Green "Done Creating App Subscription Service";
}

function SP-CreateWorkManagementServiceApp {
    Write-Host -ForegroundColor Green "Creating Workflow Management Service";
    $spVer = (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell).Version.Major;
    if ($spVer -ge 16) {
        Write-Warning "Work Management service not available from Sharepoint 2016";
        return;
    }
    # Create the work management service app.
    $serviceInstanceType = "Microsoft.Office.Server.WorkManagement.WorkManagementServiceInstance"
    CreateGenericServiceApplication `
        -ServiceInstanceType $serviceInstanceType `
        -ServiceName $global:workMgmtName `
        -ServiceDBName ($global:dbPrefix + "_Service_WorkManagement") `
        -ServiceGetCmdlet "Get-SPServiceApplication" `
        -ServiceProxyGetCmdlet "Get-SPServiceApplicationProxy" `
        -ServiceNewCmdlet "New-SPWorkManagementServiceApplication" `
        -ServiceProxyNewCmdlet "New-SPWorkManagementServiceApplicationProxy";
    Write-Host -ForegroundColor Green "Done Creating Workflow Management Service";
}

function SP-CreateMachineTranslationServiceApp {
    Write-Host -ForegroundColor Green "Creating Machine Translation Service";
    # Create the translation service app.
    $translationDatabase = $global:dbPrefix + "_Service_TranslationSvc";
    $serviceInstanceType = "Microsoft.Office.TranslationServices.TranslationServiceInstance"
    CreateGenericServiceApplication `
        -ServiceInstanceType $serviceInstanceType `
        -ServiceName $global:transSvcName `
        -ServiceDBName $translationDatabase `
        -ServiceGetCmdlet "Get-SPServiceApplication" `
        -ServiceProxyGetCmdlet "Get-SPServiceApplicationProxy" `
        -ServiceNewCmdlet "New-SPTranslationServiceApplication -DatabaseServer $global:dbServer -DatabaseName $translationDatabase -Default" `
        -ServiceProxyNewCmdlet "New-SPTranslationServiceApplicationProxy";
    Write-Host -ForegroundColor Green "Done Creating Machine Translation Service";
}

function SP-CreateAccessServicesApp {
    Write-Host -ForegroundColor Green "Creating Access Service";
    # Create the Access Services App - Require Full Text Indexing on DB server.
    $serviceInstanceType = "Microsoft.Office.Access.Services.MossHost.AccessServicesWebServiceInstance"
    CreateGenericServiceApplication `
        -ServiceInstanceType $serviceInstanceType `
        -ServiceName $global:accessAppName `
        -ServiceDBName ($global:dbPrefix + "_Service_AccessServices") `
        -ServiceGetCmdlet "Get-SPAccessServicesApplication" `
        -ServiceProxyGetCmdlet "Get-SPServicesApplicationProxy" `
        -ServiceNewCmdlet "New-SPAccessServicesApplication -DatabaseServer $global:dbServer -Default" `
        -ServiceProxyNewCmdlet "New-SPAccessServicesApplicationProxy";
    Write-Host -ForegroundColor Green "Done Creating Access Service";
}

function SP-CreatePowerPointConversionServiceApp {
    Write-Host -ForegroundColor Green "Creating PowerPoint Conversion Service";
    # Create the PowerPoint conversion service.
    $serviceInstanceType = "Microsoft.Office.Server.PowerPoint.Administration.PowerPointConversionServiceInstance"
    CreateGenericServiceApplication `
        -ServiceInstanceType $serviceInstanceType `
        -ServiceName $global:pwrpntConvApp `
        -serviceDBName ($global:dbPrefix + "_Service_PowerPointConversion") `
        -ServiceGetCmdlet "Get-SPServiceApplication" `
        -ServiceProxyGetCmdlet "Get-SPServiceApplicationProxy" `
        -ServiceNewCmdlet "New-SPPowerPointConversionServiceApplication" `
        -ServiceProxyNewCmdlet "New-SPPowerPointConversionServiceApplicationProxy";
    Write-Host -ForegroundColor Green "Done Creating PowerPoint Conversion Service";
}

function SP-ConfigureDistributedCacheService {
    # Configure the distributed cache.
    Write-Host -ForegroundColor Green "Starting Distributed Cache";
    # Make sure a credential deployment job doesn't already exist
    if ((!(Get-SPTimerJob -Identity "windows-service-credentials-AppFabricCachingService"))) {
        $distributedCachingSvc = (Get-SPFarm).Services | where {$_.Name -eq "AppFabricCachingService"}
        # Ensure the local Distributed Cache services is actually running
        if ($distributedCachingSvc.Status -ne "Online") {
            Write-Verbose "Starting the Distributed Cache service."
            Add-SPDistributedCacheServiceInstance;
        }
        try {
            UpdateProcessIdentity $distributedCachingSvc;
        }
        catch {
            Write-Output $_
            Write-Warning "An error occurred updating the service account for service AppFabricCachingService."
        }
    }
    Write-Host -ForegroundColor Green "Done Starting Distributed Cache";
}

function SP-CreatePWAWebApp {
    $pwaContentDBName = ($global:dbPrefix + "_Content_PWA");
    SP-CreateWebApp -appPool "PWA App Pool" -webAppName "PWA" `
        -database $pwaContentDBName  -url $pwaWebAppUrl -port 80 -hostheader $pwaWebAppHostHeader
    # Do not provide a site collection template at this time.
    SP-CreateSiteCollection -appPool "PWA App Pool" -database $pwaContentDBName  `
        -siteCollectionName "Project Server" -siteURL $pwaWebAppUrl
}

function SP-ConfigureProjectServer {
    # Configure PWA.
    # There has to be a better way to check whether Project Server is installed...
    $projectServerInstalled = Test-Path -Path "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\$spVer\CONFIG\BIN\Microsoft.ProjectServer.dll"
    if ($projectServerInstalled) {
        $serviceInstanceType = "Microsoft.Office.Project.Server.Administration.PsiServiceInstance"
        CreateGenericServiceApplication `
            -ServiceInstanceType $serviceInstanceType `
            -ServiceName $projServerApp `
            -ServiceDBName ($global:dbPrefix + "_Service_ProjectServer") `
            -ServiceGetCmdlet "Get-SPServiceApplication" `
            -ServiceProxyGetCmdlet "Get-SPServiceApplicationProxy" `
			-ServiceNewCmdlet "New-SPProjectServiceApplication -Proxy:`$true" `
            -ServiceProxyNewCmdlet "New-SPProjectServiceApplicationProxy" 
            # We won't be using the proxy cmdlet though for Project Server
        # Update process account for Project services
        $projectServices = @("Microsoft.Office.Project.Server.Administration.ProjectEventService", `
            "Microsoft.Office.Project.Server.Administration.ProjectCalcService", `
            "Microsoft.Office.Project.Server.Administration.ProjectQueueService")
        foreach ($projectService in $projectServices) {
            $projectServiceInstances = (Get-SPFarm).Services | ? {$_.GetType().ToString() -eq $projectService}
            foreach ($projectServiceInstance in $projectServiceInstances) {
                UpdateProcessIdentity $projectServiceInstance
            }
        }
        # Create a Project Server Config DB
        $projServerDB = $global:dbPrefix + "_Config_PWA";
        Write-Verbose "Creating Project Server database `"$projServerDB`"...";
        $pwaDBState = Get-SPProjectDatabaseState -DatabaseServer $global:dbServer -Name $projServerDB;
        if (!$pwaDBState.Exists) {
            New-SPProjectDatabase -Name $projServerDB -ServiceApplication `
                (Get-SPServiceApplication | Where-Object {$_.Name -eq $projServerApp}) -DatabaseServer $global:dbServer -Tag "ProjectWebAppDB" | Out-Null
            if ($?) {Write-Host -ForegroundColor Black -BackgroundColor Blue "Done."}
            else {
                Write-Verbose "."
                throw {"Error creating the Project Server database."}
            }
        }
        else {
            Write-Host -ForegroundColor Black -BackgroundColor Blue "Already exits."
        }
        Write-Verbose "Creating PWA web app and site collection";
        SP-CreatePWAWebApp;
        # Configure the new PWA web app
        $web = Get-SPWeb $pwaWebAppUrl 
        $web.Properties["PWA_TAG"]="ProjectWebAppDB" 
        $web.Properties.Update() 
        Enable-SPFeature pwasite -URL $pwaWebAppUrl -ErrorAction SilentlyContinue 
        # Create the new web template
        $PwaWeb = $pwaWebAppUrl + "/PWA";
        Write-Verbose "Configuring PWA start URL as $PwaWeb";
        New-SPweb -URL $PwaWeb -Template pwa#0 -ErrorAction SilentlyContinue | Out-Null;
        Sleep 3 
        Upgrade-SPProjectWebInstance -Identity $PwaWeb -Confirm:$False  | Out-Null;
        # Switch permission mode
        Set-SPPRojectPermissionMode –Url $PwaWeb -AdministratorAccount $global:spAdminAcctName -Mode ProjectServer
    }
    else {
        throw "Project Server binaries not installed";
    }
}

function SP-ConfigureBaseProjectServer {
    # Configure PWA.
    # There has to be a better way to check whether Project Server is installed...
    $projectServerInstalled = Test-Path -Path "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\$spVer\CONFIG\BIN\Microsoft.ProjectServer.dll"
    if ($projectServerInstalled) {
        $serviceInstanceType = "Microsoft.Office.Project.Server.Administration.PsiServiceInstance"
        CreateGenericServiceApplication `
            -ServiceInstanceType $serviceInstanceType `
            -ServiceName $projServerApp `
            -ServiceDBName ($global:dbPrefix + "_Service_ProjectServer") `
            -ServiceGetCmdlet "Get-SPServiceApplication" `
            -ServiceProxyGetCmdlet "Get-SPServiceApplicationProxy" `
			-ServiceNewCmdlet "New-SPProjectServiceApplication -Proxy:`$true" `
            -ServiceProxyNewCmdlet "New-SPProjectServiceApplicationProxy" 
            # We won't be using the proxy cmdlet though for Project Server
        # Update process account for Project services
        $projectServices = @("Microsoft.Office.Project.Server.Administration.ProjectEventService", `
            "Microsoft.Office.Project.Server.Administration.ProjectCalcService", `
            "Microsoft.Office.Project.Server.Administration.ProjectQueueService")
        foreach ($projectService in $projectServices) {
            $projectServiceInstances = (Get-SPFarm).Services | ? {$_.GetType().ToString() -eq $projectService}
            foreach ($projectServiceInstance in $projectServiceInstances) {
                UpdateProcessIdentity $projectServiceInstance
            }
        }
    }
    else {
        throw "Project Server binaries not installed";
    }
}

