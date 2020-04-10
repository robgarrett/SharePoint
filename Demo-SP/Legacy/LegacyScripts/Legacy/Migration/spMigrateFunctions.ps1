###################################################
# Functions to support SQL Migration

# Global Variables
$Global:DefaultData = '';
$Global:DefaultLog = '';
$Global:DefaultBackup = '';
$Global:mdfName = '';
$Global:ldfName = '';
$Global:dbSize = 0;

# SQL Commands
$Global:BackupDatabaseWithCompression_TSQL = @"
IF EXISTS(select * from sys.databases where name='{0}')
BEGIN
BACKUP DATABASE {0} TO DISK = '{1}'
   WITH COPY_ONLY, FORMAT, NAME = 'Full Backup of {0}', COMPRESSION;
END
"@;

$Global:BackupDatabase_TSQL = @"
IF EXISTS(select * from sys.databases where name='{0}')
BEGIN
BACKUP DATABASE {0} TO DISK = '{1}'
   WITH COPY_ONLY, FORMAT, NAME = 'Full Backup of {0}';
END
"@;

$Global:RestoreDatabase_TSQL = @"
IF EXISTS(select * from sys.databases where name='{0}')
BEGIN
ALTER DATABASE {0} SET single_user WITH ROLLBACK IMMEDIATE;
DROP DATABASE {0}
END
RESTORE DATABASE {0}
   FROM DISK = N'{1}'
   WITH REPLACE,
   MOVE '{2}' TO '{4}{0}.mdf',
   MOVE '{3}' TO '{5}{0}_log.ldf';
ALTER DATABASE {0} SET RECOVERY SIMPLE;

"@;

$Global:SetRODatabase_TSQL = @"
IF EXISTS(select * from sys.databases where name='{0}')
BEGIN
ALTER DATABASE {0} SET single_user WITH ROLLBACK IMMEDIATE;
ALTER DATABASE {0} SET READ_ONLY WITH NO_WAIT;
ALTER DATABASE {0} SET multi_user WITH ROLLBACK IMMEDIATE;
END
"@;

$Global:DeleteDatabase_TSQL = @"
IF EXISTS(select * from sys.databases where name='{0}')
BEGIN
ALTER DATABASE {0} SET single_user WITH ROLLBACK IMMEDIATE;
DROP DATABASE {0};
END
"@;

$Global:GetLogicalFiles_TSQL = "RESTORE FILELISTONLY FROM DISK='{0}'"

$Global:GetDefaultLocations_TSQL = @"
SELECT SERVERPROPERTY('instancedefaultdatapath') AS [DefaultData], 
SERVERPROPERTY('instancedefaultlogpath') AS [DefaultLog]
"@;

$Global:GetDefaultBackupPath_TSQL = @"
EXEC  master.dbo.xp_instance_regread  
 N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer',N'BackupDirectory' 
"@;

$Global:GetDBSize_TSQL = @"
USE [{0}]; 
SELECT SUM([size] * 8) AS Size FROM sysfiles;
"@;

$Global:DBExists_TSQL = "SELECT Count(*) FROM sys.databases WHERE name='{0}'";

$Global:MissingSetupFiles_TSQL = "SELECT * FROM AllDocs Where SetupPath='{0}'";

# Methods

function Process-AllDatabases([scriptblock]$s, $version) {
    $dbs = @();
    switch ($version) {
        "2007" {
            $server = $Global:Src2007_SQLServer;
            $dbs = $Global:2007_Databases;
        }
        "2010" {
            $server = $Global:Dest2010_SQLServer;
            if ($action.ToUpper() -eq "BACKUP") {
                $server = $Global:Src2010_SQLServer;
            }
            $dbs = $Global:2010_Databases;
            if ($action.ToUpper() -eq "RESTORE") {
                $dbs = $Global:2007_Databases; 
                # We're restoring the 2007 databases to 2010 farm. 
            }
        }
        "2013" {
            $server = $Global:Dest2013_SQLServer;
            if ($action.ToUpper() -eq "BACKUP") {
                $server = $Global:Src2013_SQLServer;
            }
            $dbs = $Global:2013_Databases;
            if ($dbs -eq $null -or $dbs.Length -eq 0 -or `
                ($action.ToUpper() -eq "RESTORE" -and $profile.ToUpper() -ne "PWA" -and $profile.ToUpper() -notlike "PROD*")) {
                # Use the 2010 names if 2013 not specified, or we're restoring from 2010.
                $dbs = $Global:2010_Databases;
            }
        }
        default {
            throw "Unknown SharePoint version";
        }
    }
    foreach ($db in $dbs) { 
        $s.Invoke($server, $db, $version); 
    }
}

function Get-VersionChoice {
    $sp2007 = New-Object System.Management.Automation.Host.ChoiceDescription "200&7", "2007."
    $sp2010 = New-Object System.Management.Automation.Host.ChoiceDescription "20&10", "2010."
    $sp2013 = New-Object System.Management.Automation.Host.ChoiceDescription "201&3", "2013."
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($sp2007, $sp2010, $sp2013)
    $result = $host.ui.PromptForChoice("SharePoint Version", "Which SharePoint version to apply operation?", $options, 0) 
    switch ($result) {
        0 { return "2007" }
        1 { return "2010"}
        2 { return "2013"}
    }
}

function yesno($title, $message) {
    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Yes."
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "No."
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
    $result = $host.ui.PromptForChoice($title, $message, $options, 1) 
    switch ($result) {
        0 {return $true;}
        1 {return $false}
    }
}

function Time($block) {
    $now = [System.DateTime]::Now;
    Write-Host -ForegroundColor yellow "Starting operation at" $now.ToShortDateString() $now.ToShortTimeString();
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $block
    $sw.Stop()
    $el = $sw.Elapsed
    $now = [System.DateTime]::Now;
    Write-Host -ForegroundColor yellow "Operation completed at" $now.ToShortDateString() $now.ToShortTimeString();
    Write-Host -foregroundcolor yellow ("Time elapsed: {0:D2}:{1:D2}:{2:D2}" -f $el.Hours, $el.Minutes, $el.Seconds);
}

function Create-ManagedPath($name, $wildcard, $version) {
    $webApp = Get-WebApp -version $version;
    $mp = Get-SPManagedPath -Identity $name -WebApplication $webApp -ErrorAction SilentlyContinue;
    if ($mp -eq $null) {
        Write-Host -ForegroundColor white " - creating managed path $name";
        if ($wildcard) {
            New-SPManagedPath -RelativeUrl $name -WebApplication $webApp | Out-Null;
        }
        else {
            New-SPManagedPath -RelativeUrl $name -WebApplication $webApp -Explicit | Out-Null;
        }
    }
}

function SetUserPolicy($wa, $userOrGroup, $isGroup) {
    # Not sure why, but username is not resolving to SID, so I am forcing it.
    $AdObj = New-Object System.Security.Principal.NTAccount($userOrGroup);
    $strSID = $AdObj.Translate([System.Security.Principal.SecurityIdentifier])
    $m = [Microsoft.SharePoint.Administration.Claims.SPClaimProviderManager]::Local;
    if ($isGroup) {
        $claim = New-SPClaimsPrincipal -identity $strSID.Value -IdentityType WindowsSecurityGroupSid;
    }
    else {
        $claim = New-SPClaimsPrincipal -identity $strSID.Value -IdentityType WindowsSamAccountName;
    }
    $account = $m.EncodeClaim($claim);
    $policy = $wa.Policies.Add($account, $userOrGroup);
    $policyRole = $wa.PolicyRoles.GetSpecialRole([Microsoft.SharePoint.Administration.SPPolicyRoleType]::FullControl);
    $policy.PolicyRoleBindings.Add($policyRole);
    $wa.Update();
}

function Get-DefaultLocations($server) {
    if ($Global:DefaultData -ne $null -and $Global:DefaultData -ne '' -and `
        $Global:DefaultLog -ne $null -and $Global:DefaultLog -ne '') { return; }
    SQL-ExecuteQuery -server $server -database "Master" -query $Global:GetDefaultLocations_TSQL -func {
        param($obj);
        $Global:DefaultData = $obj.DefaultData;
        $Global:DefaultLog = $obj.DefaultLog;
    }
}

function Get-BackupPath($server, $unc) {
    if ($Global:DefaultBackup -ne $null -and $Global:DefaultBackup -ne '') { return $Global:DefaultBackup; }
    SQL-ExecuteQuery -server $server -database "Master" -query $Global:GetDefaultBackupPath_TSQL -func {
        param($obj);
        if ($obj.Value -eq 'BackupDirectory') { $Global:DefaultBackup = $obj.Data; }
    }
    if ($unc -and ($Global:DefaultBackup -ne $null) -and ($Global:DefaultBackup -ne '')) {
        $p = $Global:DefaultBackup.ToUpper();
        if ($p.StartsWith("C:\")) {
            $Global:DefaultBackup = $p.Replace("C:\", "\\$env:computername\c$\");
        }
        elseif ($p.StartsWith("D:\")) {
            $Global:DefaultBackup = $p.Replace("D:\", "\\$env:computername\d$\");
        }
        if ($p.StartsWith("E:\")) {
            $Global:DefaultBackup = $p.Replace("E:\", "\\$env:computername\e$\");
        }
    }
}

function Get-LogicalNames($server, $file) {
    $query = [System.String]::Format($Global:GetLogicalFiles_TSQL, $file);
    SQL-ExecuteQuery -server $server -database "Master" -query $query -func {
        param($obj);
        if ($obj.Type -eq 'D') {
            $Global:mdfName = $obj.LogicalName;
        }
        elseif ($obj.Type -eq 'L') {
            $Global:ldfName = $obj.LogicalName;
        }
    }
}

function Get-DBSize($server, $db, $version) {
    $Global:dbSize = 0;
    Exec-IfDBExists -server $server -db $db -version $version -s {
        try {
            $query = [System.String]::Format($Global:GetDBSize_TSQL, $db);
            $Global:dbSize = SQL-ExecuteScalar -server $server -database "Master" -query $query;
        }
        catch {
            $Global:dbSize = 0;
        }
    }
    return $Global:dbSize;
}

function Get-DBMapping($db, $version) {
    if ($version -eq "2013" -and $Global:DatabaseMappings2013 -ne $null) {
        $newDB = $Global:DatabaseMappings2013.Get_Item($db);
    }
    if ($newDB -eq $null -and $version -eq "2010" -and $Global:DatabaseMappings2010 -ne $null) {
        $newDB = $Global:DatabaseMappings2010.Get_Item($db);
    }
    if ($newDB -eq $null -and $Global:DatabaseMappings -ne $null) {
        $newDB = $Global:DatabaseMappings.Get_Item($db);
    }
    if ($newDB -eq $null) { return $db; }
    return $newDB;
}

function Exec-IfDBExists($server, $db, [scriptblock]$s, [bool]$mapIfNotExist, $version) {
    $query = [System.String]::Format($Global:DBExists_TSQL, $db);
    $count = SQL-ExecuteScalar -server $server -db "Master" -query $query;
    if ($count -gt 0) { 
        $s.Invoke(); 
    }
    elseif ($mapIfNotExist) {
        $newDB = Get-DBMapping -db $db -version $version;
        if ($newDB -ne $null -and $newDB -ne '') { 
            Write-Host -ForegroundColor Yellow " - cannot find $db so attempting with $newDB";
            Exec-IfDBExists -server $server -db $newDB -s $s -mapIfNotExist $false -version $version;
        }
        else {
            Write-Host -ForegroundColor yellow " - cannot find $db on server $server or a mapping";
        }
    }
}

function Is-Consolidation($version) {
    return ($Global:Consolidation_WebApp -ne $null -and `
            $Global:Consolidation_Port -ne $null);
}

function Get-WebApp($version) {
    if ($version -ne "2010" -and $version -ne "2013") { throw "Cannot create web apps in 2007 farm"; }
    if ($version -eq "2013") {
        if ((Is-Consolidation -version $version)) {
            return "$($Global:Consolidation_WebApp):$($Global:Consolidation_Port)"; 
        }
        else {
            return "$($Global:2013_WebApp):$($Global:2013_Port)";
        }
    }
    else {
        return "$($Global:2010_WebApp):$($Global:2010_Port)";
    }
}

function Restore-FromPath($server, $newDB, $file) {
    if ($Global:SmallDB -and (Test-Path $file) -and (Get-Item $file).Length -gt 1gb) { return; } 
    # Get the default locations.
    Get-DefaultLocations -server $server;
    # Get the logical names.
    Get-LogicalNames -server $server -file $file;
    if ($Global:mdfName -eq $null -or $Global:mdfName -eq '') { throw "Unable to determine MDF default location"; }
    if ($Global:ldfName -eq $null -or $Global:ldfName -eq '') { throw "Unable to determine LDF default location"; }
    # Now issue the restore query.
    $query = ([System.String]::Format($Global:RestoreDatabase_TSQL, $newDB, $file, $Global:mdfName, `
        $Global:ldfName, $Global:DefaultData, $Global:DefaultLog));
    SQL-ExecuteNonQuery -server $server -database "Master" -query $query;
}

function Delete-SPWeb($spWeb) {
    # Delete sub webs first.
    $spWeb.Webs | % { Delete-SPWeb -spWeb $_; }
    Remove-SPWeb $spWeb -Confirm:$false;
}

function Update-UsersInDB($server, $db, $version) {
    Exec-IfDBExists -server $server -db $db -version $version -s {
        if ($Global:SmallDB -and (Get-DBSize -server $server -db $db -version $version) -gt 1000000) { return; }
        $spDb = Get-SPContentDatabase $db;
        foreach ($site in $spDb.Sites) {
            Write-Host -ForegroundColor white " - updating site collection contacts for $($site.ServerRelativeUrl)";        
            $username = "$($env:userdomain)\$($env:USERNAME)";
            Set-SPSite $site -OwnerAlias $username;            
        }
    }
}

function Rearrange-Sites($server, $db, $version) {
    if ($version -ne "2013" -or $Global:SiteCollectionMappings -eq $null) { return; }
    Exec-IfDBExists -server $server -db $db -version $version -mapIfNotExist $true -s {
        if ($Global:SmallDB -and (Get-DBSize -server $server -db $db -version $version) -gt 1000000) { return; }
        # Iterate the sites in the DB.
        $spDb = Get-SPContentDatabase $db -ErrorAction:SilentlyContinue;
        if ($spDb -eq $null) { throw "Unable to open content database $db"; }
        foreach ($site in $spDb.Sites) {
            # Look for the server relative URL in the mappings.
            $relURL = $site.ServerRelativeUrl;
            $newRelURL = $Global:SiteCollectionMappings.Get_Item($relURL);
            if ($newRelURL -eq $null -or $newRelURL -eq '' -or $newRelURL -eq $relURL) { continue; }
            $fullSrcUrl = $site.Url;
            $fullDestUrl = $site.WebApplication.Url;
            if ($fullDestUrl.EndsWith("/") -and $newRelURL.StartsWith("/")) {
                $fullDestUrl += $newRelURL.Substring(1);
            }
            else {
                $fullDestUrl += $newURL;
            }
            # See if we have the destination already.
            $existing = Get-SPSite $fullDestUrl;
            if ($existing -eq $null) {
                # Move within the current content database.
                Write-Host -ForegroundColor white " - copying $($site.Url) to $fullDestUrl";            
                Copy-SPSite $fullSrcUrl -TargetUrl $fullDestUrl -DestinationDatabase $db;
                $existing = Get-SPSite $fullDestUrl;
            }
            else {
                Write-Host -ForegroundColor yellow " - skipping move because $fullDestUrl already exists";
            }
            # Clean up if we copied to the new destination and the old still exists.
            if ($existing -ne $null -and (Get-SPSite $fullSrcUrl -ErrorAction:SilentlyContinue) -ne $null) {
                Write-Host -ForegroundColor white " - removing $fullSrcUrl";
                Remove-SPSite $fullSrcUrl -Confirm:$false;
                # Make sure site is actually deleted.
                Get-SPDeletedSite | Remove-SPDeletedSite -confirm:$false;
            }
        }
    }
}

function Create-WebApp() {
    $webApp = Get-WebApp -version $version;
    $wa = Get-SPWebApplication $webApp -ErrorAction:SilentlyContinue;
    # Create web app if it doesn't exist.
    if ($wa -eq $null) {
        Write-Host -ForegroundColor yellow " - Creating new web app $webApp";
        if ($version -eq "2013") {
            if ((Is-Consolidation -version $version)) {
                $port = $Global:Consolidation_Port;
            }
            else {
                $port = $Global:2013_Port;
            }
        } 
        else {
            $port = $Global:2010_Port;
        }
        $ap = New-SPAuthenticationProvider -UseWindowsIntegratedAuthentication -DisableKerberos 
        $wa = New-SPWebApplication -Name "SharePoint Migration - $port" -URL $webApp `
            -ApplicationPool "SharePoint $port App Pool" `
            -ApplicationPoolAccount (Get-SPManagedAccount $spAppPoolAcctName) `
            -DatabaseName "FERC_Content_Temp$($port)" `
            -AuthenticationProvider $ap;
        # Ensure Http Throttle Settings are in place.
        # http://social.technet.microsoft.com/Forums/office/en-US/577a8b86-be87-4974-8d7e-6746043aa094/ca-web-app-generel-
        # settings-updates-are-currently-disallowed-on-get-requests?forum=sharepointadminprevious
        Restart-Service SPTimerV4
        $wa.HttpThrottleSettings | Out-Null
        $wa.Update();
    }
}

function IterateSites($db, [scriptblock]$s) {
    $db = Get-SPDatabase | where { $_.Name -eq $db }
    # Iterate site collections then sites
    $db.Sites | ForEach-Object {
        #Write-Host -ForegroundColor white " - checking site collection $($_.Url)";
        $s.Invoke($_, "site collection");
        $_ | Get-SPWeb -Limit all | ForEach-Object {
            #Write-Host -ForegroundColor white " - checking site $($_.Url)";
            $s.Invoke($_, "site");
        }
    }
}

function Remove-MissingSetupFiles($server, $db, $version) {
    if ($Global:MissingSetupFiles -eq $null) { return; }
    Write-Host -ForegroundColor white "Removing missing setup files";
    foreach ($file in $Global:MissingSetupFiles) {
        Write-Host -ForegroundColor White " - Looking for SetupPath $file";
        $query = [System.String]::Format($Global:MissingSetupFiles_TSQL, $file);
        SQL-ExecuteQuery -server $server -database $db -query $query -func {
            param($obj);
            $fileId = $obj.Id;
            # Get the file reference
            IterateSites -db $db -s {
                param($obj, $objName);
                if ($objName -ne "site") { return; }
                $f = $obj.GetFile($fileId);
                if ($f -eq $null) { return; }
                Write-Host -ForegroundColor yellow "- found file $file";
                $web.Site.WebApplication.Url + $file.ServerRelativeUrl;
            }            
        }
    }
}

function Remove-MissingFeatures($db, $version) {
    if ($Global:MissingFeatures -eq $null) { return; }
    Write-Host -ForegroundColor white "Removing missing features";
    foreach($feature in $Global:MissingFeatures) {
        Write-Host -ForegroundColor white " - Looking for Feature $feature";
        IterateSites -db $db -s {
            param($obj, $objName);
            foreach($f in $obj.Features) {
                if ($f.Definition -eq $null -and $f.DefinitionId -eq $featureId) {
                    try {
                        $obj.Features.Remove($f.DefinitionId, $true)
                        Write-Host "Feature successfully removed feature $($f.DefinitionId) from" $objName ":" $obj.Url -foregroundcolor Yellow
                    }
                    catch {
                        Write-Host -ForegroundColor Red "There has been an error trying to remove the feature:" $f
                    }
                }
            }
        };
    }
}

function Move-Database($server, $db, $srcWebApp, $destWebApp) {
    # See if database already mounted
    $spDb = Get-SPContentDatabase $db -ErrorAction:SilentlyContinue;
    if ($spDb -ne $null) {
        Write-Host -ForegroundColor white " - dismounting database $db from $srcWebApp";
        Dismount-SPContentDatabase $db -Confirm:$false;
        Write-Host -ForegroundColor white " - mounting database $db on $destWebApp";
        Mount-SPContentDatabase -Name $db -WebApplication $destWebApp -DatabaseServer $server | Out-Null;
    }
}
