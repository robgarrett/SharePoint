#############################################################
# Fix the BCS DB if requires upgrade
# Rob Garrett

$0 = $myInvocation.MyCommand.Definition
$env:dp0 = [System.IO.Path]::GetDirectoryName($0)

# Source External Functions
. "$env:dp0\..\Install\Settings\Settings-$env:COMPUTERNAME.ps1"
. "$env:dp0\..\Install\spCommonFunctions.ps1"
. "$env:dp0\..\Install\spSQLFunctions.ps1"
. "$env:dp0\spMigrateFunctions.ps1"
 
function SPRun($version) {
    if ($version -eq "2010") {
        Use-RunAsV2 -additionalArg $global:argList;
    }
    else {
        Use-RunAs -additionalArg $global:argList;
    }
    SP-RegisterPS;
}

###########################
# Main

$global:argList = $MyInvocation.BoundParameters.GetEnumerator() | ? { $_.Value.GetType().Name -ne "SwitchParameter" } | % {"-$($_.Key)", "$($_.Value)"}
$switches = $MyInvocation.BoundParameters.GetEnumerator() | ? { $_.Value.GetType().Name -eq "SwitchParameter" } | % {"-$($_.Key)"}
if ($switches -ne $null) { $global:argList += $switches; }
$global:argList += $MyInvocation.UnboundArguments
SPRun -version 2013;
try {
    (Get-SPDatabase | ?{$_.type -eq "Microsoft.SharePoint.BusinessData.SharedService.BdcServiceDatabase"}).Provision()
}
catch {
    $message = $_.Exception.Message;
    Write-Host -ForegroundColor Red "Critial Error: " $message;
    Send-Email -to $Global:AlertEmail -subject "Migration Script ERROR" -body "Error for $profile - $message";
    if ($noPauseAtEnd) { Read-Host "Press Enter"; }
}

if (!$noPauseAtEnd) { Read-Host "Press Enter"; }


