#############################################################
# SharePoint Search Functions
# Rob Garrett
# With the help from http://autospinstaller.codeplex.com/

function Create-IndexLocation {
    if (!(Test-Path $global:indexLocation)) {
        Write-Verbose "Creating index location $global:indexLocation";
        New-Item $global:indexLocation -type directory | Out-Null;
    }
    $wmiPath = $global:indexLocation.Replace("\","\\")
    $wmiDirectory = Get-WmiObject -Class "Win32_Directory" -Namespace "root\cimv2" -ComputerName $env:COMPUTERNAME -Filter "Name='$wmiPath'"
    if (!($wmiDirectory.Compressed)) {
        Write-Verbose "Compressing index location $global:indexLocation";
        $compress = $wmiDirectory.CompressEx("","True")
    }
}

function SP-ChangeIndexLocation {
    if ($global:indexLocation -eq $null -or $global:indexLocation -eq '') {
        throw "indexLocation not set in the settings file.";
    }
    # Make sure it exists
    if (!(Test-Path $global:indexLocation)) { Create-IndexLocation; }
    Write-Verbose "Changing Search Index Location to $global:indexLocation";
    $searchSvc = Get-SPEnterpriseSearchServiceInstance -Local
    if ($searchSvc -eq $null) { Throw "Unable to retrieve search service." }
    $searchSvc | Set-SPEnterpriseSearchServiceInstance -DefaultIndexLocation $global:indexLocation
    Write-Verbose "Applying permissions to $global:indexLocation";
    ApplyExplicitPermissions -path $global:indexLocation -identity "WSS_WPG" -permissions @("Read","Write");
    ApplyExplicitPermissions -path $global:indexLocation -identity "WSS_RESTRICTED_WPG_V4" -permissions @("Read","Write");
    ApplyExplicitPermissions -path $global:indexLocation -identity "WSS_ADMIN_WPG" -permissions @("FullControl");
    $wmiPath = $global:indexLocation.Replace("\","\\")
    $wmiDirectory = Get-WmiObject -Class "Win32_Directory" -Namespace "root\cimv2" -ComputerName $env:COMPUTERNAME -Filter "Name='$wmiPath'"
    # Check if folder is already compressed
    if (!($wmiDirectory.Compressed)) {
        Write-Verbose "Compressing $global:indexLocation and subfolders..."
        $compress = $wmiDirectory.CompressEx("","True")
    }
}

function SP-CreateEnterpriseSearchServiceApp {
    $currentServer = Get-SPServer $env:COMPUTERNAME;
    $spVer = (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell).Version.Major;
    if ($spVer -ge 16 -and $currentServer.Role -ine "Search" -and $currentServer.Role -ine "Custom" -and $currentServer.Role -ine "SingleServerFarm") {
        Write-Warning "Current server is not a search, single server farm, or custom role";
        Write-Warning "Changing role to custom";
        Set-SPServer -Identity $env:COMPUTERNAME -Role Custom;
        while ($currentServer.Role -ine "Custom") {
            Sleep 1;
            $currentServer = Get-SPServer $env:COMPUTERNAME;
        }
    }
    Write-Host -ForegroundColor Green "Provisioning Enterprise Search App";
    if ($global:indexLocation -eq $null -or $global:indexLocation -eq '') {
        throw "indexLocation not set in the settings file.";
    }
    # Create enterprise search service application.
    $secSearchServicePassword = ConvertTo-SecureString -String $global:spServiceAcctPwd -AsPlainText -Force;
    Write-Verbose "Provisioning Enterprise Search...";
    $searchSvc = Get-SPEnterpriseSearchServiceInstance -Local
    if ($searchSvc -eq $null) { Throw "Unable to retrieve search service." }
    Write-Verbose "Configuring search service...";
    $internetIdentity = "Mozilla/4.0 (compatible; MSIE 4.01; Windows NT; MS Search 6.0 Robot)";
    Get-SPEnterpriseSearchService | Set-SPEnterpriseSearchService  `
        -ContactEmail $global:adminEmail -ConnectionTimeout 60 `
          -AcknowledgementTimeout 60 -ProxyType Default `
          -IgnoreSSLWarnings $false -InternetIdentity $internetIdentity -PerformanceLevel "PartlyReduced" `
          -ServiceAccount $global:spServiceAcctName -ServicePassword $secSearchServicePassword
    if ($?) {Write-Verbose "Done."}
    # Get application pools
    $pool = Get-SearchServiceApplicationPool;
    $adminPool = Get-SearchAdminApplicationPool "Search Admin App Pool";
    # From http://mmman.itgroove.net/2012/12/search-host-controller-service-in-starting-state-sharepoint-2013-8/
    # And http://blog.thewulph.com/?p=374
    Write-Verbose "Fixing registry permissions for Search Host Controller Service...";
    $acl = Get-Acl HKLM:\System\CurrentControlSet\Control\ComputerName
    $person = [System.Security.Principal.NTAccount] "WSS_WPG" # Trimmed down from the original "Users"
    $access = [System.Security.AccessControl.RegistryRights]::FullControl
    $inheritance = [System.Security.AccessControl.InheritanceFlags] "ContainerInherit, ObjectInherit"
    $propagation = [System.Security.AccessControl.PropagationFlags]::None
    $type = [System.Security.AccessControl.AccessControlType]::Allow
    $rule = New-Object System.Security.AccessControl.RegistryAccessRule($person, $access, $inheritance, $propagation, $type)
    $acl.AddAccessRule($rule)
    Set-Acl HKLM:\System\CurrentControlSet\Control\ComputerName $acl
    Write-Verbose "Done."
    # Checking the search service.
    Write-Verbose "Checking Search Service Instance...";
    if ($searchSvc.Status -eq "Disabled") {
        Write-Host -ForegroundColor Yellow "Starting Search Service..." -NoNewline
        $searchSvc | Start-SPEnterpriseSearchServiceInstance
        if (!$?) {Throw "Could not start the Search Service Instance."}
        $searchSvc = Get-SPEnterpriseSearchServiceInstance -Local
        while ($searchSvc.Status -ne "Online") {
            Write-Host -ForegroundColor Yellow "." -NoNewline
            Start-Sleep 1
            $searchSvc = Get-SPEnterpriseSearchServiceInstance -Local
        }
        Write-Host -BackgroundColor Yellow -ForegroundColor Black $($searchSvc.Status)
    }
    else {
        #Write-Verbose "Already $($searchSvc.Status)."
    }

    # Sync Topology
    Write-Verbose "Checking Search Query and Site Settings Service Instance...";
    $searchQueryAndSiteSettingsService = Get-SPEnterpriseSearchQueryAndSiteSettingsServiceInstance -Local
    if ($searchQueryAndSiteSettingsService.Status -eq "Disabled") {
        Write-Host -ForegroundColor Yellow "Starting Search Query and Site Settings Service..." -NoNewline
        $searchQueryAndSiteSettingsService | Start-SPEnterpriseSearchQueryAndSiteSettingsServiceInstance
        if (!$?) {Throw "Could not start the Search Query and Site Settings Service Instance."}
            Write-Host -ForegroundColor Yellow "Done."
        }
        else {
            Write-Host -ForegroundColor Yellow "Already $($searchQueryAndSiteSettingsService.Status)."
    }
    # Search Service App.
    Write-Verbose "Checking Search Service Application...";
    $searchApp = Get-SPEnterpriseSearchServiceApplication -Identity $global:searchAppName -ErrorAction SilentlyContinue
    if ($searchApp -eq $null) {
        Write-Verbose "Creating $($global:searchAppName)";
        $searchApp = New-SPEnterpriseSearchServiceApplication -Name $global:searchAppName `
            -DatabaseServer $global:dbServer `
            -DatabaseName $($global:dbPrefix + "_Service_SearchApp") `
            -ApplicationPool $pool `
            -AdminApplicationPool $adminPool `
            -Partitioned:$false
        if (!$?) {Throw "  - An error occurred creating the $($global:searchAppName) application."}
    }

    # Update the default Content Access Account
    Write-Verbose "$global:spSearchCrawlAcctName $global:spSearchCrawlAcctPWD"
    $pwd = ConvertTo-SecureString $global:spSearchCrawlAcctPWD -AsPlaintext -Force
    Update-SearchContentAccessAccount -saName $($global:searchAppName) -sa $searchApp -caa $global:spSearchCrawlAcctName -caapwd $pwd;

    # If the index location isn't already set to either the default location or our custom-specified location, set the default location for the search service instance
    if ($global:indexLocation -ne $searchSvc.DefaultIndexLocation) {
        Create-IndexLocation;
        Write-Verbose "Setting default index location on search service instance...";
        $searchSvc | Set-SPEnterpriseSearchServiceInstance -DefaultIndexLocation $global:indexLocation -ErrorAction SilentlyContinue
        if ($?) {Write-Verbose "Done setting index location."}
    }

    # Create the search topology
    SP-CreateSearchTopology -searchApp $searchApp -searchSvc $searchSvc;

    # Create proxy
    $searchAppProxyName = "$searchAppName Proxy";
    Write-Verbose "Checking search service application proxy...";
    if (!(Get-SPEnterpriseSearchServiceApplicationProxy -Identity $searchAppProxyName -ErrorAction SilentlyContinue)) {
        Write-Verbose "Creating search service application proxy";
        $searchAppProxy = New-SPEnterpriseSearchServiceApplicationProxy -Name $searchAppProxyName -SearchApplication $searchAppName
        if ($?) {Write-Verbose "Done creating search service application proxy";}
    }

    # Check the Search Host Controller Service for a known issue ("stuck on starting")
    Write-Verbose "Checking for stuck Search Host Controller Service (known issue)..."
    $searchHostServices = Get-SPServiceInstance | ? {$_.TypeName -eq "Search Host Controller Service"}
    foreach ($sh in $searchHostServices) {
        Write-Host -ForegroundColor White "   - Server: $($sh.Parent.Address)..." -NoNewline
        if ($sh.Status -eq "Provisioning") {
            Write-Host -ForegroundColor White "Re-provisioning..." -NoNewline
            $sh.Unprovision()
            $sh.Provision($true)
            Write-Host -ForegroundColor White "Done."
        }
        else {
            Write-Host -ForegroundColor White "OK."
        }
    }

    # Add link to resources list
    SP-AddResourcesLink $searchAppName ("searchadministration.aspx?appid=" +  $searchApp.Id);
    Write-Host -ForegroundColor Green "Done Provisioning Enterprise Search App";
}

function SP-CreateTopologyComponent {
    param($searchApp, $searchSvc, $searchTopology, $compName, $funcNewComp);
    # Create a topology component
    Write-Verbose "Checking $compName component...";
    $components = $clone.GetComponents() | Where-Object {$_.Name -like ($compName + "Component*")}
    if (!($components | Where-Object {MatchComputerName $_.ServerName $env:COMPUTERNAME})) {
        Write-Verbose "Creating search component $compName...";
        & $funcNewComp –SearchTopology $searchTopology -SearchServiceInstance $searchSvc | Out-Null
        if (!$?) { throw "Failed to create new search component"; }
        Write-Verbose "Done creating search component $compName";
    }
    # Get components on this server.
    return $clone.GetComponents() | Where-Object {$_.Name -like ($compName + "Component*") -and `
        $_.ServerName -imatch $env:COMPUTERNAME}; 
}

function SP-RemoveTopologyComponent {
    param($searchApp, $searchSvc, $searchTopology, $compName);
    Write-Verbose "Checking $compName component...";
    $components = $clone.GetComponents() | Where-Object `
        {$_.Name -like ($compName + "Component*") -and $_.ServerName -imatch $env:COMPUTERNAME}; 
    if ($components) {
        # Component exists on this server, so remove it.
        Write-Verbose "Removing search component...";
        foreach ($comp in $components) {
            Remove-SPEnterpriseSearchComponent -SearchTopology $searchTopology -Identity $comp -Confirm:$false;
        }
        Write-Verbose "Done Removing Search Component";
    }
    # Determine if this component lives in the farm on another server.
    return $clone.GetComponents() | Where-Object {$_.Name -like ($compName + "Component*") -and `
        $_.ServerName -inotmatch $env:COMPUTERNAME}; 
}

function SP-NewIndexSearchComponent {
    param($SearchTopology, $SearchServiceInstance);
    # Specify the RootDirectory parameter only if it's different than the default path
    $spVer = (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell).Version.Major;
    $dataDir = "$env:ProgramFiles\Microsoft Office Servers\$spVer.0\Data";
    if ($global:indexLocation -ne "$dataDir\Office Server\Applications") {
        if (!(Test-Path $global:indexLocation)) { Create-IndexLocation; }
        $rootDirectorySwitch = @{RootDirectory = $global:indexLocation }
    }
    else {
        $rootDirectorySwitch = @{}
    }
    New-SPEnterpriseSearchIndexComponent –SearchTopology $SearchTopology `
        -SearchServiceInstance $SearchServiceInstance @rootDirectorySwitch | Out-Null
}

function SP-CreateSearchTopology {
    param($searchApp, $searchSvc);
    # Look for a topology that has components, or is still Inactive, because that's probably our $clone
    $clone = $searchApp.Topologies | Where {$_.ComponentCount -gt 0 -and $_.State -eq "Inactive"} | Select-Object -First 1
    if (!$clone) {
        # Clone the active topology
        Write-Verbose "Cloning the active search topology..."
        #$clone = $searchApp.ActiveTopology.Clone();
        $clone = New-SPEnterpriseSearchTopology -SearchApplication $searchApp -Clone -SearchTopology $searchApp.ActiveTopology;
    }
    else {
        Write-Verbose "Using existing cloned search topology."
        # Since this clone probably doesn't have all its components added yet, we probably want to keep it if it isn't activated after this pass
        $keepClone = $true
    }

    # Count current components in clone.
    $count = $clone.ComponentCount;
    Write-Verbose "Clone has $count components...";

    # Note any new topology must have all the components to activate it.
    $activateTopology = $false;

    # Check if each search component is already assigned to the current server, 
    # then check that it's actually being requested for the current server, then create it as required.
    if ($global:crawlServers -icontains $env:COMPUTERNAME) {
        # This server is a crawl server.
        Write-Verbose "$env:COMPUTERNAME is a crawl server";
        # Admin Component
        Write-Verbose "Adding admin component to $env:COMPUTERNAME";
        $adminComponentReady = SP-CreateTopologyComponent `
            -searchApp $searchApp `
            -searchTopology $clone `
            -searchSvc $searchSvc `
            -compName "Admin" `
            -funcNewComp "New-SPEnterpriseSearchAdminComponent"

        # Content Processing Component
        Write-Verbose "Adding content processing component to $env:COMPUTERNAME";
        $contentProcessingComponentReady = SP-CreateTopologyComponent `
            -searchApp $searchApp `
            -searchTopology $clone `
            -searchSvc $searchSvc `
            -compName "ContentProcessing" `
            -funcNewComp "New-SPEnterpriseSearchContentProcessingComponent"

        # Analytics Component
        Write-Verbose "Adding analytics component to $env:COMPUTERNAME";
        $analyticsProcessingComponentReady = SP-CreateTopologyComponent `
            -searchApp $searchApp `
            -searchTopology $clone `
            -searchSvc $searchSvc `
            -compName "AnalyticsProcessing" `
            -funcNewComp "New-SPEnterpriseSearchAnalyticsProcessingComponent"

        # Crawl Component
        Write-Verbose "Adding crawl component to $env:COMPUTERNAME";
        $crawlComponentReady = SP-CreateTopologyComponent `
            -searchApp $searchApp `
            -searchTopology $clone `
            -searchSvc $searchSvc `
            -compName "Crawl" `
            -funcNewComp "New-SPEnterpriseSearchCrawlComponent"

        # Remove Query components?
        if (!($global:queryServers -icontains $env:COMPUTERNAME)) {
            Write-Verbose "$env:COMPUTERNAME is NOT a query server";
            # Index.
            Write-Verbose "Removing index component from $env:COMPUTERNAME";
            $indexComponentReady = SP-RemoveTopologyComponent `
                -searchApp $searchApp `
                -searchTopology $clone `
                -searchSvc $searchSvc `
                -compName "Index"
            # Query.
            Write-Verbose "Removing query component from $env:COMPUTERNAME";
            $queryComponentReady = SP-RemoveTopologyComponent `
                -searchApp $searchApp `
                -searchTopology $clone `
                -searchSvc $searchSvc `
                -compName "QueryProcessing"
        }
    }

    if ($global:queryServers -icontains $env:COMPUTERNAME) {
        # This server is a query server.
        Write-Verbose "$env:COMPUTERNAME is a query server";
        # Index Component
        Write-Verbose "Adding index component to $env:COMPUTERNAME";
        $indexComponentReady = SP-CreateTopologyComponent `
            -searchApp $searchApp `
            -searchTopology $clone `
            -searchSvc $searchSvc `
            -compName "Index" `
            -funcNewComp "SP-NewIndexSearchComponent"

        # Query Processing Component
        Write-Verbose "Adding query component to $env:COMPUTERNAME";
        $queryComponentReady = SP-CreateTopologyComponent `
            -searchApp $searchApp `
            -searchTopology $clone `
            -searchSvc $searchSvc `
            -compName "QueryProcessing" `
            -funcNewComp "New-SPEnterpriseSearchQueryProcessingComponent"

        # Remove crawl components?
        if (!($global:crawlServers -icontains $env:COMPUTERNAME)) {
            Write-Verbose "$env:COMPUTERNAME is NOT a crawl server";
            # Admin Component
            Write-Verbose "Removing admin component from $env:COMPUTERNAME";
            $adminComponentReady = SP-RemoveTopologyComponent `
                -searchApp $searchApp `
                -searchTopology $clone `
                -searchSvc $searchSvc `
                -compName "Admin"

            # Content Processing Component
            Write-Verbose "Removing content processing component from $env:COMPUTERNAME";
            $contentProcessingComponentReady = SP-RemoveTopologyComponent `
                -searchApp $searchApp `
                -searchTopology $clone `
                -searchSvc $searchSvc `
                -compName "ContentProcessing"

            # Analytics Component
            Write-Verbose "Removing analytics component from $env:COMPUTERNAME";
            $analyticsProcessingComponentReady = SP-RemoveTopologyComponent `
                -searchApp $searchApp `
                -searchTopology $clone `
                -searchSvc $searchSvc `
                -compName "AnalyticsProcessing"

            # Crawl Component
            Write-Verbose "Removing crawl component from $env:COMPUTERNAME";
            $crawlComponentReady = SP-RemoveTopologyComponent `
                -searchApp $searchApp `
                -searchTopology $clone `
                -searchSvc $searchSvc `
                -compName "Crawl"
        }
    }

    # Activate new topology if all components in the farm.
    if ($adminComponentReady -and $contentProcessingComponentReady -and $analyticsProcessingComponentReady -and `
        $indexComponentReady -and $crawlComponentReady -and $queryComponentReady) {$activateTopology = $true}
    # Check if any new search components were added 
    # (or if we have a clone with more/less components than the current active topology) and if we're ready to activate the topology
    Write-Verbose "Clone components: $($clone.ComponentCount) Current Search App components: $($searchApp.ActiveTopology.ComponentCount)";

    if ($newComponentsCreated -or ($clone.ComponentCount -ne $searchApp.ActiveTopology.ComponentCount)) {
        if ($activateTopology) {
            Write-Verbose "Activating Search Topology...";
            $clone.Activate()
            if ($?) {
                Write-Verbose "Done activating search topology";
                # Clean up original or previous unsuccessfully-provisioned search topologies
                $inactiveTopologies = $searchApp.Topologies | Where {$_.State -eq "Inactive"}
                if ($inactiveTopologies -ne $null) {
                    Write-Verbose "Removing old, inactive search topologies:"
                    foreach ($inactiveTopology in $inactiveTopologies) {
                        Write-Host -ForegroundColor White "   -"$inactiveTopology.TopologyId.ToString()
                        $inactiveTopology.Delete()
                    }
                }
            }
        }
        else {
            Write-Verbose "Not activating topology yet as there seem to be components still pending."
        }
    }
    elseif ($keepClone -ne $true) {
        # Delete the newly-cloned topology since nothing was done 
        # TODO: Check that the search topology is truly complete and there are no more servers to install
        Write-Verbose "Deleting unneeded cloned topology..."
        $clone.Delete()
    }
    # Clean up any empty, inactive topologies
    $emptyTopologies = $searchApp.Topologies | Where {$_.ComponentCount -eq 0 -and $_.State -eq "Inactive"}
    if ($emptyTopologies -ne $null) {
        Write-Verbose "Removing empty and inactive search topologies:"
        foreach ($emptyTopology in $emptyTopologies) {
            Write-Verbose $emptyTopology.TopologyId.ToString()
            $emptyTopology.Delete()
        }
    }
}

function Update-SearchContentAccessAccount {
    param($saName, $sa, $caa, $caapwd);
    # Set the crawl account.
    try {
        Write-Verbose "Setting content access account for $saName..."
        $sa | Set-SPEnterpriseSearchServiceApplication -DefaultContentAccessAccountName $caa -DefaultContentAccessAccountPassword $caapwd -ErrorVariable err
    }
    catch {
        if ($err -like "*update conflict*") {
            Write-Warning "An update conflict error occured, trying again."
            Update-SearchContentAccessAccount $saName, $sa, $caa, $caapwd
            $sa | Set-SPEnterpriseSearchServiceApplication -DefaultContentAccessAccountName $caa -DefaultContentAccessAccountPassword $caapwd -ErrorVariable err
        }
        else {
            throw $_
        }
    }
    finally {Clear-Variable err}
}


function Get-SearchServiceApplicationPool {
    # Try and get the application pool if it already exists
    # SLN: Updated names
    $pool = Get-SPServiceApplicationPool -Identity $global:searchSvcAppPoolName -ErrorVariable err -ErrorAction SilentlyContinue
    if ($err) {
        # The application pool does not exist so create.
        Write-Verbose "Getting $($global:spServiceAcctName) account for application pool..."
        $managedAccountSearch = (Get-SPManagedAccount -Identity $global:spAppPoolAcctName -ErrorVariable err -ErrorAction SilentlyContinue)
        if ($err) {
            $appPoolConfigPWD = (ConvertTo-SecureString $global:spAppPoolAcctPwd -AsPlainText -force)
            $accountCred = New-Object System.Management.Automation.PsCredential $global:spAppPoolAcctName,$appPoolConfigPWD
            $managedAccountSearch = New-SPManagedAccount -Credential $accountCred
        }
        Write-Verbose "Creating $($global:searchSvcAppPoolName)..."
        $pool = New-SPServiceApplicationPool -Name $($global:searchSvcAppPoolName) -Account $managedAccountSearch
    }
    return $pool
}

function Get-SearchAdminApplicationPool {
    # Try and get the application pool if it already exists
    # SLN: Updated names
    $pool = Get-SPServiceApplicationPool -Identity $global:searchAdminAppPoolName -ErrorVariable err -ErrorAction SilentlyContinue
    if ($err) {
        # The application pool does not exist so create.
        Write-Verbose "Getting $($global:spAppPoolAcctName) account for application pool..."
        $managedAccountSearch = (Get-SPManagedAccount -Identity $global:spAppPoolAcctName -ErrorVariable err -ErrorAction SilentlyContinue)
        if ($err) {
            $appPoolConfigPWD = (ConvertTo-SecureString $global:spAppPoolAcctPwd -AsPlainText -force)
            $accountCred = New-Object System.Management.Automation.PsCredential $spAppPoolAcctName,$appPoolConfigPWD
            $managedAccountSearch = New-SPManagedAccount -Credential $accountCred
        }
        Write-Verbose "Creating $($global:searchAdminAppPoolName)..."
        $pool = New-SPServiceApplicationPool -Name $($global:searchAdminAppPoolName) -Account $managedAccountSearch
    }
    return $pool
}

