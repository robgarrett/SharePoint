########################################################
# Module for modern authentication connectivity for SPO.
# 
# rogarret@microsoft.com

[CmdletBinding()]Param();

Function Get-SPOTenantID {
    $request = [System.Net.WebRequest]::Create("https://microsoft.sharepoint.com/_vti_bin/client.svc");
    $request.Headers.Add("Authorization: Bearer ");
    Try {
        $response = $request.GetResponse();
    } Catch [System.Net.WebException] {
        if ($null -eq $_.Exception.Response) { return $null; }  
        $bearerResponseHeader = $_.Exception.Response.Headers["WWW-Authenticate"];
        if ([string]::IsNullOrEmpty($bearerResponseHeader)) { return $null };
        $bearer = "Bearer realm=`"";
        $bearerIndex = $bearerResponseHeader.IndexOf($bearer, [StringComparison]::Ordinal);
        if ($bearerIndex -lt 0) { return $null; }
        $realmIndex = $bearerIndex + $bearer.Length;
        if ($bearerResponseHeader.Length -lt $realmIndex + 36) { return $null; }
        $targetRealm = $bearerResponseHeader.Substring($realmIndex, 36);
        $realmGuid = [Guid]::Empty;
        if ([Guid]::TryParse($targetRealm, [ref]$realmGuid)) { return $realmGuid; }
        return $null;
    } Finally {
        if ($null -ne $response) { $response.Dispose(); }
    }
}

Function Connect-SPOTenant {
    Param(
        [Parameter(Mandatory = $true)][string]$tenantUrl,
        [Parameter(Mandatory = $true)][ScriptBlock]$cb);
    $outerCB = $cb;
    Connect-SPO -siteUrl $tenantUrl -cb {
        Param([Parameter(Mandatory = $true)][Microsoft.SharePoint.Client.ClientContext]$clientContext);   
        $tenant = [Microsoft.Online.SharePoint.TenantAdministration.Tenant]::new($clientContext); 
        &$outerCB -tenant $tenant;
    }
}

Function Connect-SPO {
    Param(
        [Parameter(Mandatory = $true)][string]$siteUrl,
        [Parameter(Mandatory = $true)][ScriptBlock]$cb);
    Try {
        Add-Type -Path "$PSScriptRoot\Microsoft.SharePoint.Client.dll";
        Add-Type -Path "$PSScriptRoot\Microsoft.SharePoint.Client.Runtime.dll"; 
        Add-Type -Path "$PSScriptRoot\Microsoft.Online.SharePoint.Client.Tenant.dll"; 
        # Microsoft uses federated authentication, so let's use ADAL.
        Add-Type -Path "$PSScriptRoot\Microsoft.IdentityModel.dll";
        Add-Type -Path "$PSScriptRoot\Microsoft.IdentityModel.Extensions.dll";
        Add-Type -Path "$PSScriptRoot\Microsoft.IdentityModel.Clients.ActiveDirectory.dll";
        # Get the tenant ID.
        $authority = "https://login.microsoftonline.com/common";
        $clientId = "1b730954-1685-4b74-9bfd-dac224a7b894";
        $redirectUri = "urn:ietf:wg:oauth:2.0:oob";
        $authContext = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext]::new($authority);
        $rootSiteUri = [Uri]::new($siteUrl);
        $rootSiteUrl = $rootSiteUri.GetLeftPart([System.UriPartial]::Authority);    
        Try {
            $task = $authContext.AcquireTokenSilentAsync($rootSiteUrl, $clientId);
            $task.Wait();
            $authResult = $task.Result;
        } Catch {
            $task = $authContext.AcquireTokenAsync(`
                $rootSiteUrl, $clientId, $redirectUri, `
                [Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters]::new(`
                    [Microsoft.IdentityModel.Clients.ActiveDirectory.PromptBehavior]::Always));
            $task.Wait();
            $authResult = $task.Result;
        }
        if ($null -eq $authResult) { return $null; }
        # Exchange access token for client context.
        $clientContext = [Microsoft.SharePoint.Client.ClientContext]::new($siteUrl);
        $clientContext.AuthenticationMode = [Microsoft.SharePoint.Client.ClientAuthenticationMode]::Anonymous;
        $clientContext.FormDigestHandlingEnabled = $false;
        _AddRequestHandler -clientContext $clientContext -token $authResult.AccessToken;
        $clientContext.Load($clientContext.Site);
        $clientContext.Load($clientContext.Web);
        $clientContext.Load($clientContext.Web.Lists);
        $clientContext.ExecuteQuery();
        Write-Verbose "Loaded context for site $($clientContext.Web.Title)";
        &$cb -clientContext $clientContext;
    } Finally {
        if ($null -ne $clientContext) { $clientContext.Dispose(); }
    }    
}

Function _AddRequestHandler {
    Param(
        [Parameter(Mandatory = $true)][Microsoft.SharePoint.Client.ClientContext]$clientContext, 
        [Parameter(Mandatory = $true)][string]$token
    );
    Add-Type -TypeDefinition @"
using System;
using Microsoft.SharePoint.Client;
namespace SPHelper {
    public static class ClientContextHelper {
        private static string _token = "";
        public static void AddRequestHandler(ClientContext ctx, string token) {
            _token = token;
            ctx.ExecutingWebRequest += new EventHandler<WebRequestEventArgs>(RequestHandler);
        }
        private static void RequestHandler(object sender, WebRequestEventArgs e) {
            e.WebRequestExecutor.RequestHeaders["Authorization"] = "Bearer " + _token;
        }
    }
}
"@ -ReferencedAssemblies "$PSScriptRoot\Microsoft.SharePoint.Client.dll", "$PSScriptRoot\Microsoft.SharePoint.Client.Runtime.dll";
    [SPHelper.ClientContextHelper]::AddRequestHandler($clientContext, $token);
}

Export-ModuleMember -Function Connect-SPO;
Export-ModuleMember -Function Connect-SPOTenant;
Export-ModuleMember -Function Get-SPOTenantID;
