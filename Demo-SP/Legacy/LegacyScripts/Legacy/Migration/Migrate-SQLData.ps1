#############################################################
# Migrate SQL Data
# Rob Garrett

Param(
    [Parameter(Mandatory=$true)][String]$action, 
    [Parameter(Mandatory=$true)][String]$profile,
    [Parameter(Mandatory=$true)][String]$spVersion,
    [switch]$noPauseAtEnd, [switch]$alertMe);

$0 = $myInvocation.MyCommand.Definition
$env:dp0 = [System.IO.Path]::GetDirectoryName($0)

# Source External Functions
. "$env:dp0\..\Install\Settings\Settings-$env:COMPUTERNAME.ps1"
. "$env:dp0\..\Install\spCommonFunctions.ps1"
. "$env:dp0\..\Install\spSQLFunctions.ps1"
. "$env:dp0\spMigrateFunctions.ps1"
. "$env:dp0\profile$profile.ps1"
 
# Global variables
$Global:EmulateSQL = $false;
$Global:SmallDB = $false;
#$Global:AlertEmail = "phone@txt.att.net";
$Global:AlertEmail = "person@email.com";
$Global:SendEmail = $alertMe;

function SPRun($version) {
    if ($version -eq "2010") {
        Use-RunAsV2 -additionalArg $global:argList;
    }
    else {
        Use-RunAs -additionalArg $global:argList;
    }
    SP-RegisterPS;
}

######## Read-Only Databases 

function SetRO-Database($server, $db, $version) {
    if ($Global:SmallDB -and (Get-DBSize -server $server -db $db -version $version) -gt 1000000) { return; }
    $query = [System.String]::Format($Global:SetRODatabase_TSQL, $db);
    Read-Host "About to set $db to read-only, confirm by pressing enter";
    Write-Host -ForegroundColor white " - Setting database $db to read-only";
    SQL-ExecuteNonQuery -server $server -database "Master" -query $query;
}

######## Backup Databases

function Backup-Database($server, $db, $version) {
    if ($Global:SmallDB -and (Get-DBSize -server $server -db $db -version $version) -gt 1000000) { return; }
    $file = "$($Global:BackupLocation)$($version)\$($db).bak";
    if ($version -ne "2007") {
        $query = [System.String]::Format($Global:BackupDatabaseWithCompression_TSQL, $db, $file);
    }
    else {
        $query = [System.String]::Format($Global:BackupDatabase_TSQL, $db, $file);
    }
    Write-Host -ForegroundColor white " - Backing up DB $db to $file";
    SQL-ExecuteNonQuery -server $server -database "Master" -query $query;
}

######## Restore Databases

function Restore_Database($server, $db, $version) {
    if ($version -eq "2010") {
        $file = "$($Global:BackupLocation)2007\$($db).bak";
        # 2007 databases map to a new name.
        $newDB = Get-DBMapping -db $db -version $version;
        if ($newDB -eq $null) { $newDB = $db; }
        Write-Host -ForegroundColor white " - Restoring $db as $newDB";
        Restore-FromPath -server $server -newDB $newDB -file $file;
    }
    elseif ($version -eq "2013") {
        $file = "$($Global:BackupLocation)2010\$($db).bak";
        if (!(Test-Path $file)) { $file = "$($Global:BackupLocation)2013\$($db).bak"; }
        if (!(Test-Path $file)) { throw "Backup file does not exist $file;" }
        $newDB = Get-DBMapping -db $db -version $version;
        if ($newDB -eq $null) { $newDB = $db; }
        # 2013 databases might use the same as 2010.
        if ($newDB -eq $null -or $newDB -eq '') { $newDB = $db; }
        Write-Host -ForegroundColor white " - Restoring $db as $newDB";
        Restore-FromPath -server $server -newDB $newDB -file $file;
    }
    else {
        throw "Restoring to a SharePoint 2007 farm is not supported";
    }
}

######## Mount Databases

function Mount-DBs($version) {
    Process-AllDatabases -version $spVersion -s ${function:Mount-Database};
}
            
function Mount-PWADatabase($server, $db, $version) {
    Write-Host -ForegroundColor white " - mounting PWA instance database $db";
    $username = "$($env:userdomain)\$($env:USERNAME)";
    $webApp = Get-WebApp -version $version;
    Set-SPSite -Identity "$webApp/PWA" -OwnerAlias $username;
    try {
        try {
            Mount-SPProjectDatabase -Name $db -WebApplication $webApp;
            Mount-SPProjectWebInstance –DatabaseName $db –SiteCollection "$webApp/PWA"
        }
        catch {}
    }
    catch {}
    finally {
        $results = Test-SPProjectDatabase -Name $db | ? { $_.Error -eq $true; }
        if ($results.Count -gt 0) { 
            Write-Host -ForegroundColor red $results;
            throw "Failed to mount PWA database instance $db"; 
        }
        $results = Test-SPProjectWebInstance "$webApp/PWA" | ? { $_.Status -eq "FailedError"; };
        if ($results.Count -gt 0) { 
            Write-Host -ForegroundColor red $results;
            throw "Failed to mount PWA web instance for $db"; 
        }
    }
}

function Mount-Database($server, $db, $version) {
    Create-WebApp;
    Exec-IfDBExists -server $server -db $db -version $version -mapIfNotExist $true -s {
        if ($Global:SmallDB -and (Get-DBSize -server $server -db $db -version $version) -gt 1000000) { return; }
        # Is the database a PWA Instance?
        if ($Global:PWADatabases -ne $null -and $Global:PWADatabases.Contains($db)) {
            Mount-PWADatabase -server $server -db $db -version $version;
            return;
        }
        # See if database already mounted
        if ((Get-SPContentDatabase $db) -eq $null) {
            $webApp = Get-WebApp -version $version;
            Write-Host -ForegroundColor white " - testing database $db with web application $webApp";
            $results = Test-SPContentDatabase -Name $db -WebApplication $webApp -ServerInstance $server | ? { $_.UpgradeBlocking -eq $true }
            if ($results -ne $null) { 
                Write-Host -ForegroundColor red " - $db has upgrade blocking issues, skipping...";
                return; 
            } 
            # Proceed with the mount.
            Write-Host -ForegroundColor white " - mounting database $db on web application $webApp";
            if ($version -eq "2010") {
                Mount-SPContentDatabase -Name $db -WebApplication $webApp -UpdateUserExperience -DatabaseServer $server | Out-Null;
            } 
            else {
                Mount-SPContentDatabase -Name $db -WebApplication $webApp -DatabaseServer $server | Out-Null;
            }
        }
        else {
            Write-Host -ForegroundColor Yellow " - database $db already mounted, skipping...";
        }
    }
}

######## Consolidate Databases

function Consolidate($version) {
    # Create managed paths.
    foreach ($path in $Global:ExplicitManagedPaths) { Create-ManagedPath -name $path -wildcard $false -version $version; }
    foreach ($path in $Global:WildcardManagedPaths) { Create-ManagedPath -name $path -wildcard $true -version $version; }
    # Process each database.
    Process-AllDatabases -version $version -s ${function:Consolidate-Database};
}

function Consolidate-Database($server, $db, $version) {
    if ($version -ne "2010" -and $version -ne "2013") { throw "Can only consolidate on SharePoint 2010 and 2013 farms." }
    Exec-IfDBExists -server $server -db $db -version $version -mapIfNotExist $true -s {
        if ($Global:PWADatabases -ne $null -and $Global:PWADatabases.Contains($db)) { return; }
        if ($Global:SmallDB -and (Get-DBSize -server $server -db $db -version $version) -gt 1000000) { return; }
        $webApp = Get-WebApp -version $version;
        $spDb = Get-SPContentDatabase $db;
        if ($spDb -eq $null) { throw "Cannot open database $db"; }
        foreach ($dbSite in $spDb.Sites) {
            $url = $dbSite.ServerRelativeUrl.ToLower();
            if ($url.StartsWith("/ssp/admin") -or $url.StartsWith("/my/") -or $url -eq "/my") {
                Write-Host -ForegroundColor white " - Deleting old site $url site collection from $db";
                Remove-SPSite $dbSite.Url -Confirm:$false;
                # Make sure site is actually deleted.
                Get-SPDeletedSite | Remove-SPDeletedSite -confirm:$false;
                if ($url.StartsWith("/ssp/admin")) {
                    $mPath = Get-SPManagedPath -Identity "ssp/admin" -WebApplication $webApp -ErrorAction:SilentlyContinue;
                    if ($mPath -ne $null) {
                        Remove-SPManagedPath -Identity "ssp/admin" -WebApplication $webApp -Confirm:$false;
                    }
                }
                continue;
            }
        }
        # Update the site collections admins
        Update-UsersInDB -server $server -db $db -version $version;
        if ($version -eq "2013") { 
            Remove-DeadWebs;
            if ($profile -ne "PWA") { 
                # Run the visual update if on SharePoint 2013.
                Visual-Upgrade -server $server -db $db -version $version; 
                # Move site collections around.
                Rearrange-Sites -server $server -db $db -version $version;
            }
        }
        # Move database if it's under the consolidation web app.
	if ((Is-Consolidation -verison $version -and $version -eq "2013")) {
            $srcWebApp = "$($Global:Consolidation_WebApp):$Global:Consolidation_Port";
            $destWebApp = "$($Global:2013_WebApp):$Global:2013_Port";
            Move-Database -server $server -db $db -srcWebApp $srcWebApp -destWebApp $destWebApp;
        }
    }
}

function Remove-DeadWebs {
    # Remove Dead Webs.
    if ($Global:DeadWebs -ne $null) {
        foreach ($web in $Global:DeadWebs) {
            $spWeb = Get-SPWeb $web -ErrorAction:SilentlyContinue;
            if ($spWeb -ne $null) {
                Write-Host -ForegroundColor white " - deleting dead website $web";
                Delete-SPWeb -spWeb $spWeb;
            }
            
        }
    }
    # Remove Dead Site Collections
    if ($Global:DeadSites -ne $null) {
        foreach ($site in $Global:DeadSites) {
            $spSite = Get-SPSite $site -ErrorAction:SilentlyContinue;
            if ($spSite -ne $null) {
                Write-Host -ForegroundColor white " - deleting dead site collection $site";
                Remove-SPSite $spSite -Confirm:$false;
                # Make sure site is actually deleted.
                Get-SPDeletedSite | Remove-SPDeletedSite -confirm:$false;
            }
            
        }
    }
}

function Visual-Upgrade($server, $db, $version) {
    if ($version -ne "2013") { throw "Can only perform visual upgrade on SharePoint 2013 farm."; }
    Exec-IfDBExists -server $server -db $db -version $version -mapIfNotExist $true -s {
        #Write-Host -ForegroundColor white "Performing Visual Upgrade for SharePoint 2013";
        if ($Global:SmallDB -and (Get-DBSize -server $server -db $db -version $version) -gt 1000000) { return; }
        $spDb = Get-SPContentDatabase $db;
        foreach ($site in $spDb.Sites) {
            Write-Host -ForegroundColor white " - testing visual upgrade on $($site.ServerRelativeUrl)";
            $results = Test-SPSite $site;
            if ($results.FailedErrorCount -gt 0) {
                Write-Host -ForegroundColor Yellow " - skipping $($site.ServerRelativeUrl) because of failures in test";
                continue;
            }
            Write-Host -ForegroundColor white " - performing visual upgrade on $($site.ServerRelativeUrl)";
            Upgrade-SPSite $site –VersionUpgrade
        }
    }
}

######## Test Databases

function Test-Farm($version) {
    # Process each database.
    Process-AllDatabases -version $version -s ${function:Test-Database};
}

function Test-Database($server, $db, $version) {
    if ($version -ne "2013" -and $version -ne "2010") { throw "Test content database not available on SharePoint 2007"; }
    Exec-IfDBExists -server $server -db $db -version $version -s {
        Write-Host -ForegroundColor white "Performing Tests for SharePoint 2013";
        if ($Global:SmallDB -and (Get-DBSize -server $server -db $db -version $version) -gt 1000000) { return; }
        $spDb = Get-SPContentDatabase $db;
        foreach ($site in $spDb.Sites) {
            Write-Host -ForegroundColor white " - testing site $($site.ServerRelativeUrl)";
            $results = Test-SPSite $site;
            if ($results.FailedErrorCount -gt 0) {
                Write-Host -ForegroundColor red " - detected errors...";
                $results.Results |? { $_.Status -eq "FailedError" } | % {
                    Write-Host -ForegroundColor red $_.MessageAsText;
                }
                Read-Host "Press Enter to continue";
            }
            elseif ($results.FailedWarningCount -gt 0) {
                Write-Host -ForegroundColor yellow " - detected warnings...";
                $results.Results |? { $_.Status -eq "FailedWarning" } | % {
                    Write-Host -ForegroundColor yellow $_.MessageAsText;
                }
                Read-Host "Press Enter to continue";
            }
            else {
                Write-Host -ForegroundColor green " - no issues...";
            }
        }
    }
}

######## Clean Farm

function Clean-Farm($version, [bool]$deleteWebApp) {
    if ($version -ne "2010" -and $version -ne "2013") { throw "Can only clean SharePoint 2010 and 2013 farms"; }
    # Dismount content databases.
    Process-AllDatabases -version $version -s ${function:Dismount-Database}; 
    if ($deleteWebApp) {
        $webApp = Get-WebApp -version $version;
        $wa = Get-SPWebApplication $webApp -ErrorAction SilentlyContinue;
        if ($wa -ne $null) {
            Write-Host -ForegroundColor white " - deleting web app $webApp";
            Remove-SPWebApplication -Identity $webApp -DeleteIISSite -RemoveContentDatabases -Confirm:$false;
        }
    }
}

function Dismount-Database($server, $db, $version) {
    Exec-IfDBExists -server $server -db $db -version $version -mapIfNotExist $true -s {
        if ($Global:SmallDB -and (Get-DBSize -server $server -db $db -version $version) -gt 1000000) { return; }
        # Is the database a PWA Instance?
        $webApp = Get-WebApp -version $version;
        if ($Global:PWADatabases -ne $null -and $Global:PWADatabases.Contains($db)) {
            Dismount-SPProjectWebInstance –SiteCollection "$webApp/PWA"    
            Dismount-SPProjectDatabase -Name $db -WebApplication $webApp -Confirm:$false;
        }
        else {
            # See if database already mounted
            $spDb = Get-SPContentDatabase $db -ErrorAction:SilentlyContinue;
            if ($spDb -ne $null) {
                Write-Host -ForegroundColor white " - dismounting database $db";
                Remove-SPContentDatabase $spDb -Force -Confirm:$False;
            }
            else {
                Write-Host -ForegroundColor white " - database $db not mounted";
            }
        }
    }
}

######## Delete Databases

function Delete-Database($server, $db, $version) {
    if ($version -eq "2007" ) { throw "Cannot delete databases from SharePoint 2007 farm"; }
    Exec-IfDBExists -server $server -db $db -version $version -mapIfNotExist $true -s {
        # Remove from SharePoint first.
        $spDb = Get-SPContentDatabase $db -ErrorAction:SilentlyContinue;
        if ($spDb -ne $null) { Remove-SPContentDatabase $db -Confirm:$false -Force; }
        $query = [System.String]::Format($Global:DeleteDatabase_TSQL, $db);
        Write-Host -ForegroundColor white " - Deleting DB $db";
        SQL-ExecuteNonQuery -server $server -database "Master" -query $query;
    }
}

###########################
# Main

$global:argList = $MyInvocation.BoundParameters.GetEnumerator() | ? { $_.Value.GetType().Name -ne "SwitchParameter" } | % {"-$($_.Key)", "$($_.Value)"}
$switches = $MyInvocation.BoundParameters.GetEnumerator() | ? { $_.Value.GetType().Name -eq "SwitchParameter" } | % {"-$($_.Key)"}
if ($switches -ne $null) { $global:argList += $switches; }
$global:argList += $MyInvocation.UnboundArguments
SPRun -version $spVersion;
try {
    if ($spVersion -ne "2007" -and $spVersion -ne "2010" -and $spVersion -ne "2013") {
        throw "spVersion is not 2007, 2010, or 2013";
    }
    switch($action.ToUpper()) {
        "READONLY" {
            if (yesno -title "Set databases to readonly" -message "Are you sure?") {
                Time -block { Process-AllDatabases -version $spVersion -s ${function:SetRO-Database}; }
            }
        }
        "BACKUP" {
            Write-Host -ForegroundColor white "Backing up databases from SQL Server";
            Time -block { Process-AllDatabases -version $spVersion -s ${function:Backup-Database}; }
            Send-Email -to $Global:AlertEmail -subject "Migration Script Alert" -body `
                "Backup of $spVersion farm for $profile complete";
        }
        "RESTORE" {
            Write-Host -ForegroundColor white "Restoring databases to SQL Server";
            Time -block { Process-AllDatabases -version $spVersion -s ${function:Restore_Database}; }
            Send-Email -to $Global:AlertEmail -subject "Migration Script Alert" -body `
                "Restore to farm $spVersion for $profile complete";
        }
        "MOUNT" {
            Write-Host -ForegroundColor white "Mounting databases on SharePoint farm.";
            Time -block { Mount-DBs -version $spVersion; }
            Send-Email -to $Global:AlertEmail -subject "Migration Script Alert" -body `
                "Mounting on farm $spVersion for $profile complete";
        }
        "CONSOLIDATE" {
            Write-Host -ForegroundColor white "Consolidating databases on SharePoint farm.";
            Time -block { Consolidate -version $spVersion; }
            Send-Email -to $Global:AlertEmail -subject "Migration Script Alert" -body `
                "Consolidation on $spVersion farm for $profile complete";
        }
        "DELETE" {
            Write-Host -ForegroundColor white "Deleting databases from SharePoint farm.";
            Time -block { Process-AllDatabases -version $spVersion -s ${function:Delete-Database}; }
        }
        "CLEAN" {
            Write-Host -ForegroundColor white "Cleaning up SharePoint farm.";
            Time -block { Clean-Farm -version $spVersion -deleteWebApp $false; }
            Send-Email -to $Global:AlertEmail -subject "Migration Script Alert" -body `
                "Cleaning on $spVersion farm for $profile complete";
        }
        "TEST" {
            SPRun -version $spVersion;
            Write-Host -ForegroundColor white "Testing SharePoint farm.";
            Time -block { Test-Farm -version $spVersion; }
        }
        default {
            Write-Host -ForegroundColor yellow "Usage: $($MyInvocation.ScriptName) -action <cmd>";
            Write-Host;
            Write-Host -ForegroundColor yellow "Actions:";
            Write-Host;
        }
    }
}
catch {
    $message = $_.Exception.Message;
    Write-Host -ForegroundColor Red "Critial Error: " $message;
    Send-Email -to $Global:AlertEmail -subject "Migration Script ERROR" -body "Error for $profile - $message";
    if ($noPauseAtEnd) { Read-Host "Press Enter"; }
}

if (!$noPauseAtEnd) { Read-Host "Press Enter"; }


