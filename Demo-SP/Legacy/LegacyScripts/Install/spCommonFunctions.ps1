#############################################################
# SharePoint Common Functions
# Rob Garrett
# With the help from http://autospinstaller.codeplex.com/

function Check-Settings {
    Check-Setting -setting $global:dbPrefix -name "`$global:dbPrefix";
    Check-Setting -setting $global:passphrase -name "`$global:passphrase";
    Check-Setting -setting $global:dbServer -name "`$global:dbServer";
    Check-Setting -setting $global:serverRole -name "`$global:serverRole";
    Check-Setting -setting $global:spServiceAcctName -name "`$global:spServiceAcctName";
    Check-Setting -setting $global:spServiceAcctPwd -name "`$global:spServiceAcctPwd";
    Check-Setting -setting $global:spAppPoolAcctName -name "`$global:spAppPoolAcctName";
    Check-Setting -setting $global:spAppPoolAcctPwd -name "`$global:spAppPoolAcctPwd";
    Check-Setting -setting $global:CAportNumber -name "`$global:CAportNumber";
    Check-Setting -setting $global:smtpServer -name "`$global:smtpServer";
    Check-Setting -setting $global:fromEmailAddress -name "`$global:fromEmailAddress";
}

function Check-Setting {
    param($setting, $name);
    if ($setting -eq $null) { Write-Host -ForegroundColor red -BackgroundColor Yellow "'$name' not defined in settings file!"; }
}

function Use-RunAs { 
    # Check if script is running as Adminstrator and if not use RunAs 
    # Use Check Switch to check if admin  
    param([Switch]$Check, [string[]]$additionalArgs) 
    Write-Host -ForegroundColor Yellow "Running PowerShell Version $($host.version)";   
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")      
    if ($Check) { return $IsAdmin }     
 
    if ($MyInvocation.ScriptName -ne "") {  
        if (-not $IsAdmin)  {  
            try {
                $argsList = @();
                if ($host.version -eq '2.0') {
                    $argsList += @('-Version 2');     
                }  
                $argsList += @('-NoProfile', '-File', $MyInvocation.ScriptName);
                if ($additionalArgs -ne $null) {
                    $argsList += $additionalArgs;
                }
                Start-Process "$psHome\powershell.exe" -Verb Runas -ArgumentList $argsList -ErrorAction Stop
            } 
            catch { 
                Write-Warning "Error - Failed to restart script with runas " + $_.Exception.Message;  
                break               
            } 
            exit # Quit this session of powershell 
        }  
    }  
    else  {  
        Write-Warning "Error - Script must be saved as a .ps1 file first"  
        break  
    }
} 

function Use-RunAsV2 { 
    # Check if script is running as Adminstrator and if not use RunAs 
    # Use Check Switch to check if admin  
    param([Switch]$Check, [string[]]$additionalArgs) 
    Write-Host -ForegroundColor Yellow "Running PowerShell Version $($host.version)";   
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")      
    if ($Check) { return $IsAdmin }     
 
    if ($MyInvocation.ScriptName -ne "") {  
        if (-not $IsAdmin)  {  
            try {
                $argsList = @();
                $argsList += @('-Version 2');     
                $argsList += @('-NoProfile', '-File', $MyInvocation.ScriptName);
                if ($additionalArgs -ne $null) {
                    $argsList += $additionalArgs;
                }
                Start-Process "$psHome\powershell.exe" -Verb Runas -ArgumentList $argsList -ErrorAction Stop
            } 
            catch { 
                Write-Warning "Error - Failed to restart script with runas " + $_.Exception.Message;  
                break               
            } 
            exit # Quit this session of powershell 
        }  
    }  
    else  {  
        Write-Warning "Error - Script must be saved as a .ps1 file first"  
        break  
    }
} 


function SP-RegisterPS {
    $ver = $host | select version
    if ($ver.Version.Major -gt 1)  {$Host.Runspace.ThreadOptions = "ReuseThread"}
    if ( (Get-PSSnapin -Name Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue) -eq $null ) {
        Add-PsSnapin Microsoft.SharePoint.PowerShell
        Write-Verbose "SharePoint PowerShell Snapin installed";
    } else {
        Write-Verbose "SharePoint PowerShell Snapin already installed";
    }
    Set-location $home
}

function MatchComputerName($computersList, $computerName) {
    # Return true if computer name matches one on the list.
	if ($computersList -like "*$computerName*") { Return $true; }
    foreach ($v in $computersList) {
      if ($v.Contains("*") -or $v.Contains("#")) {
            # wildcard processing
            foreach ($item in -split $v) {
                $item = $item -replace "#", "[\d]"
                $item = $item -replace "\*", "[\S]*"
                if ($computerName -match $item) {return $true;}
            }
        }
    }
}

function Get-AdministratorsGroup {
    # Get the built in admin group.
    if(!$builtinAdminGroup) {
        $builtinAdminGroup = (Get-WmiObject -Class Win32_Group -computername $env:COMPUTERNAME -Filter `
            "SID='S-1-5-32-544' AND LocalAccount='True'" -errorAction "Stop").Name
    }
    return $builtinAdminGroup
}

function SP-AddResourcesLink([string]$title,[string]$url) {
    # Add a resource link in Central Admin.
    $centraladminapp = Get-SPWebApplication -IncludeCentralAdministration | ? {$_.IsAdministrationWebApplication}
    $centraladminurl = $centraladminapp.Url
    $centraladmin = (Get-SPSite $centraladminurl)
    $item = $centraladmin.RootWeb.Lists["Resources"].Items | Where { $_["URL"] -match ".*, $title" }
    if ($item -eq $null ) {
        $item = $centraladmin.RootWeb.Lists["Resources"].Items.Add();
    }
    $url = $centraladminurl + $url + ", $title";
    $item["URL"] = $url;
    $item.Update();
}

function Load-SharePoint-PowerShell {
    # Load SharePoint Plugin again.
    if ((Get-PsSnapin |?{$_.Name -eq "Microsoft.SharePoint.PowerShell"})-eq $null) {
        Write-Host
        Write-Host -ForegroundColor White " - Loading SharePoint PowerShell Snapin..."
        # Added the line below to match what the SharePoint.ps1 file implements (normally called via the SharePoint Management Shell Start Menu shortcut)
        if (Confirm-LocalSession) {$Host.Runspace.ThreadOptions = "ReuseThread"}
        Add-PsSnapin Microsoft.SharePoint.PowerShell -ErrorAction Stop | Out-Null
    }
}

function Confirm-LocalSession {
    # Another way
    # If ((Get-Process -Id $PID).ProcessName -eq "wsmprovhost") {Return $false}
    if ($Host.Name -eq "ServerRemoteHost") {
        return $false;
    }
    else {
        return $true;
    }   
}

function AddAccountToAdmin($spAccountName) {
    # Add account to local admins
    $builtinAdminGroup = Get-AdministratorsGroup
    $adminGroup = ([ADSI]"WinNT://$env:COMPUTERNAME/$builtinAdminGroup,group")
    # This syntax comes from Ying Li 
    # (http://myitforum.com/cs2/blogs/yli628/archive/2007/08/30/powershell-script-to-add-remove-a-domain-user-to-the-local-administrators-group-on-a-remote-machine.aspx)
    $localAdmins = $adminGroup.psbase.invoke("Members") | ForEach-Object {$_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)}
    $managedAccountGen = Get-SPManagedAccount | Where-Object {$_.UserName -eq $($spAccountName)}
    $managedAccountDomain,$managedAccountUser = $managedAccountGen.UserName -split "\\"
    if (!($localAdmins -contains $managedAccountUser)) {
        Write-Verbose "Adding $($managedAccountGen.Username) to local Administrators..."
        ([ADSI]"WinNT://$env:COMPUTERNAME/$builtinAdminGroup,group").Add("WinNT://$managedAccountDomain/$managedAccountUser")
        # Recycle the timer service, we do this to pick up the new tokens.
        Restart-Service -Name "SPTimerV4" -Force
        # Wait for the timer service
        Write-Host -ForegroundColor Yellow "Waiting for SharePoint Timer Service to start..." -NoNewline
        while ((Get-Service SPTimerV4).Status -ne "Running") {
            Write-Host -ForegroundColor Yellow "." -NoNewline
            Start-Sleep 1
        }
        Write-Host;
    }
}

function AddGroupToAdmin($spGroupName) {
    # Add account to local admins
    $builtinAdminGroup = Get-AdministratorsGroup
    $adminGroup = ([ADSI]"WinNT://$env:COMPUTERNAME/$builtinAdminGroup,group")
    # This syntax comes from Ying Li 
    # (http://myitforum.com/cs2/blogs/yli628/archive/2007/08/30/powershell-script-to-add-remove-a-domain-user-to-the-local-administrators-group-on-a-remote-machine.aspx)
    $localAdmins = $adminGroup.psbase.invoke("Members") | ForEach-Object {$_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)}
    $managedAccountDomain,$managedAccountGroup = $spGroupName -split "\\"
    if (!($localAdmins -contains $managedAccountGroup)) {
        Write-Verbose "Adding $($managedAccountGroup) to local Administrators..."
        ([ADSI]"WinNT://$env:COMPUTERNAME/$builtinAdminGroup,group").Add("WinNT://$managedAccountDomain/$managedAccountGroup")
        # Recycle the timer service, we do this to pick up the new tokens.
        Restart-Service -Name "SPTimerV4" -Force
        # Wait for the timer service
        Write-Host -ForegroundColor Yellow "Waiting for SharePoint Timer Service to start..." -NoNewline
        while ((Get-Service SPTimerV4).Status -ne "Running") {
            Write-Host -ForegroundColor Yellow "." -NoNewline
            Start-Sleep 1
        }
        Write-Host;
    }
}


function RemoveAccountFromAdmin($spAccountName) {
    # Add account to local admins
    $builtinAdminGroup = Get-AdministratorsGroup
    $adminGroup = ([ADSI]"WinNT://$env:COMPUTERNAME/$builtinAdminGroup,group")
    # This syntax comes from Ying Li 
    # (http://myitforum.com/cs2/blogs/yli628/archive/2007/08/30/powershell-script-to-add-remove-a-domain-user-to-the-local-administrators-group-on-a-remote-machine.aspx)
    $localAdmins = $adminGroup.psbase.invoke("Members") | ForEach-Object {$_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)}
    $managedAccountGen = Get-SPManagedAccount | Where-Object {$_.UserName -eq $($spAccountName)}
    $managedAccountDomain,$managedAccountUser = $managedAccountGen.UserName -split "\\"
    if (($localAdmins -contains $managedAccountUser)) {
        Write-Verbose "Removing $($managedAccountGen.Username) from local Administrators..."
        ([ADSI]"WinNT://$env:COMPUTERNAME/$builtinAdminGroup,group").Remove("WinNT://$managedAccountDomain/$managedAccountUser")
        # Recycle the timer service, we do this to pick up the new tokens.
        Restart-Service -Name "SPTimerV4" -Force
        # Wait for the timer service
        Write-Host -ForegroundColor Yellow "Waiting for SharePoint Timer Service to start..." -NoNewline
        while ((Get-Service SPTimerV4).Status -ne "Running") {
            Write-Host -ForegroundColor Yellow "." -NoNewline
            Start-Sleep 1
        }
        Write-Host;
    }
}

function ApplyLogFolderPermissions($path) {
    Write-Verbose "Writing permissions for folder $path";
    ApplyExplicitPermissions -path $path -identity "WSS_WPG" -permissions @("Read","Write");
    ApplyExplicitPermissions -path $path -identity "WSS_RESTRICTED_WPG_V4" -permissions @("Read","Write");
    ApplyExplicitPermissions -path $path -identity "WSS_ADMIN_WPG" -permissions @("FullControl");
}

function ApplyExplicitPermissions($path, $identity, $permissions) {
    $acl = (Get-Item $path).GetAccessControl("Access")
    foreach ($p in $permissions) {
        $perms = $identity,$p,"Allow";
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, $p, `
            "ContainerInherit,ObjectInherit", "None", "Allow");
        $acl.AddAccessRule($rule) 
    }
    Set-Acl -aclobject $acl $path 
}

function Send-Email($to, $subject, $body) {
    if ($Global:SendEmail -ne $null -and $Global:SendEmail -ne $true) { return; }
    try {
	    $smtpServer = "mailrelay.ferc.gov"
        #$smtpServer = $env:COMPUTERNAME;
	    $smtpFrom = "sharepointteam@ferc.gov"
 	    Send-MailMessage -from $smtpFrom -to $to -Subject $subject -Body $body -SmtpServer $smtpServer;
        Write-Host -ForegroundColor Cyan "Sent email to $to";
    }
    catch {
        Write-Host -ForegroundColor yellow "Unable to send email $($_.Exception.Message)";
    }
}
