########################################################
# Iterate all site collections in the tenant.
#
# rogarrett@microsoft.com

[CmdletBinding()]Param([Parameter(Mandatory = $true)]$tenantUrl);

Import-Module $PSScriptRoot\SPO-Helper.psm1 -Force;

Try {
    Connect-SPOTenant -tenantUrl $tenantUrl -cb {
        Param([Parameter(Mandatory = $true)][Microsoft.Online.SharePoint.TenantAdministration.Tenant]$tenant);
        $siteProps = $tenant.GetSitePropertiesFromSharePoint("0", $true);
        $tenant.Context.Load($siteProps);
        $tenant.Context.ExecuteQuery();
        $siteProps.GetEnumerator() | ForEach-Object {
            $uri = [Uri]::new($_.Url);
            if ($uri.Host.EndsWith(".sharepoint.com")) {
                Write-Host -ForegroundColor Yellow "Processing $($_.Url)";
            }
        }
    }
} Catch {
    Write-Host -ForegroundColor Red $_.Exception;
}