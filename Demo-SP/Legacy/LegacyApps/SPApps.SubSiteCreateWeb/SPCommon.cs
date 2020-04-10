using System;
using System.Diagnostics;
using System.Web;
using Microsoft.Online.SharePoint.TenantAdministration;
using Microsoft.SharePoint.Client;

namespace SPApps.SubSiteCreateWeb
{
    static class SPCommon
    {
        public static ClientContext GetAppOnlyContext(string url)
        {
            if (String.IsNullOrEmpty(url)) throw new ArgumentNullException("url");
            if (TokenHelper.IsHighTrustApp())
                return TokenHelper.GetS2SClientContextWithWindowsIdentity(new Uri(url), null);
            // TODO: Test app only context code with ACS in O365.
            var fullUri = new Uri(url);
            var appOnlyContext = TokenHelper.GetAppOnlyAccessToken(TokenHelper.SharePointPrincipal, fullUri.Authority, TokenHelper.GetRealmFromTargetUrl(fullUri));
            return TokenHelper.GetClientContextWithAccessToken(url, appOnlyContext.AccessToken);
        }

        public static void LoadTenant(ClientContext clientContext, Action<Tenant, ClientContext> del)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (null == del) throw new ArgumentNullException("del");
            try
            {
                // Get the site collection.
                // Note: Assume the site collection of the passed client context is the TenantAdmin site.
                clientContext.Load(clientContext.Web);
                clientContext.Load(clientContext.Web.CurrentUser);
                clientContext.ExecuteQuery();
                var hostWebUrl = clientContext.Web.Url;
                if (!hostWebUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase) &&
                    !hostWebUrl.StartsWith("http://", StringComparison.OrdinalIgnoreCase))
                    throw new HttpException("Host web does not start with HTTPS:// or HTTP://");
                var idx = hostWebUrl.Substring(8).IndexOf("/", StringComparison.Ordinal);
                var rootSiteUrl = idx >= 0
                    ? hostWebUrl.Substring(0, 8 + hostWebUrl.Substring(8).IndexOf("/", StringComparison.Ordinal))
                    : hostWebUrl;
                // Notice that this assumes that AdministrationSiteType as been set as TenantAdministration for root site collection
                // If this tenant admin URI is pointing to site collection which is host named site collection, code does create host 
                // named site collection as well
                // Connect to the tenant and then look for the site collection.
                using (var adminContext = GetAppOnlyContext(rootSiteUrl))
                {
                    var tenant = new Tenant(adminContext);
                    del(tenant, adminContext);
                }
            }
            catch (ServerException ex)
            {
                if (0 != String.CompareOrdinal(ex.Message, "File not found"))
                    Debug.WriteLine(ex.ToString());
            }
        }
    }
}