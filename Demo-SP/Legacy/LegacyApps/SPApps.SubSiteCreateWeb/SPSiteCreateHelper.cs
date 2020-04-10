using System;
using System.Linq;
using System.Web;
using Microsoft.Online.SharePoint.TenantAdministration;
using Microsoft.SharePoint.Client;
using System.Text.RegularExpressions;

namespace SPApps.SubSiteCreateWeb
{
    internal static class SPSiteCreateHelper
    {
        public static bool SiteExists(ClientContext clientContext, string siteName)
        {
            if (String.IsNullOrEmpty(siteName)) throw new ArgumentNullException("siteName");
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            var result = false;
            // Determine if we're looking for a site collection.
            var useSC = AppHelper.GetProperty(clientContext, Constants.SITECOL_PROPERTY);
            var preferSiteCollection = useSC != null && 0 == String.Compare(useSC.ToString(), "TRUE",
                StringComparison.OrdinalIgnoreCase);
            if (preferSiteCollection)
                result = SiteCollectionExists(clientContext, siteName);
            else
                ProcessSite(clientContext, siteName, w => { result = true; });
            return result;
        }

        public static void CreateSite(ClientContext clientContext, string siteName)
        {
            if (String.IsNullOrEmpty(siteName)) throw new ArgumentNullException("siteName");
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            // Determine if we're looking for a site collection.
            var useSC = AppHelper.GetProperty(clientContext, Constants.SITECOL_PROPERTY);
            var preferSiteCollection = useSC != null && 0 == String.Compare(useSC.ToString(), "TRUE", StringComparison.OrdinalIgnoreCase);
            // Tidy the site name
            var regex = new Regex("[^a-zA-Z0-9]");
            var siteNameUrl = regex.Replace(siteName, "");
            if (!preferSiteCollection)
            {
                // Create as subsite.
                if (!SiteExists(clientContext, siteName))
                    CreateSite(clientContext, siteName, siteNameUrl);
                return;
            }
            // Does the site collection already exist?
            if (!SiteCollectionExists(clientContext, siteName))
                CreateSiteCollection(clientContext, siteName, siteNameUrl);
            // Site collection now exists - load the custom WSP.
            var wspName = AppHelper.GetProperty(clientContext, Constants.WSPPATH_PROPERTY) as string;
            if (String.IsNullOrEmpty(wspName)) return;
            var fullUrl = GetUrlFromSiteName(clientContext, siteName);
            using (var childContext = SPCommon.GetAppOnlyContext(fullUrl))
                SPTemplateHelper.UploadCustomSolution(childContext, wspName);
        }

        public static void ProcessSite(ClientContext clientContext, string siteName, Action<Web> del)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (String.IsNullOrEmpty(siteName)) throw new ArgumentNullException("siteName");
            if (null == del) throw new ArgumentNullException("del");
            // Tidy the site name
            var regex = new Regex("[^a-zA-Z0-9]");
            var siteNameUrl = regex.Replace(siteName, "");
            // Get the web.
            var rootWeb = clientContext.Web;
            clientContext.Load(rootWeb, w => w.Webs);
            clientContext.ExecuteQuery();
            clientContext.Load(rootWeb, w => w.ServerRelativeUrl);
            clientContext.ExecuteQuery();
            var fullUrl = rootWeb.ServerRelativeUrl.EndsWith("/") ?
                String.Format("{0}{1}", rootWeb.ServerRelativeUrl, siteNameUrl) :
                String.Format("{0}/{1}", rootWeb.ServerRelativeUrl, siteNameUrl);
            var web = clientContext.Web.Webs.FirstOrDefault(w => 0 == String.CompareOrdinal(w.ServerRelativeUrl, fullUrl));
            if (null != web) del(web);
        }

        private static void CreateSite(ClientContext clientContext, string siteName, string siteNameUrl)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (String.IsNullOrEmpty(siteName)) throw new ArgumentNullException("siteName");
            if (String.IsNullOrEmpty(siteNameUrl)) throw new ArgumentNullException("siteNameUrl");
            // Create a new Site
            clientContext.Load(clientContext.Web);
            clientContext.ExecuteQuery();
            // Get available templates.
            var templates = clientContext.Web.GetAvailableWebTemplates(1033, true);
            clientContext.Load(templates);
            clientContext.ExecuteQuery();
            var templateName = "STS#1";
            var templateStr = AppHelper.GetProperty(clientContext, Constants.TEMPLATENAME_PROPERY);
            if (null != templateStr)
            {
                // See if template is installed.
                var template = templates.FirstOrDefault(wt =>
                    0 == String.Compare(wt.Name, templateStr.ToString(), StringComparison.OrdinalIgnoreCase));
                if (null != template) templateName = template.Name;
            }
            var uniquePerms = AppHelper.GetProperty(clientContext, Constants.UNIQUEPERMS_PROPERTY);
            var useUniqePerms = uniquePerms != null &&
                0 == String.Compare(uniquePerms.ToString(), "TRUE", StringComparison.OrdinalIgnoreCase);
            var webCreation = new WebCreationInformation
            {
                Title = siteName,
                Description = "",
                Url = siteNameUrl,
                WebTemplate = templateName,
                UseSamePermissionsAsParentSite = !useUniqePerms
            };
            var newWeb = clientContext.Web.Webs.Add(webCreation);
            clientContext.Load(newWeb, w => w.Title);
            clientContext.ExecuteQuery();
        }

        private static bool SiteCollectionExists(ClientContext clientContext, string siteName)
        {
            var result = false;
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (String.IsNullOrEmpty(siteName)) throw new ArgumentNullException("siteName");
            SPCommon.LoadTenant(clientContext, (tenant, adminContext) =>
            {
                var webUrl = GetUrlFromSiteName(clientContext, siteName);
                var spp = tenant.GetSitePropertiesByUrl(webUrl, true);
                adminContext.Load(spp);
                adminContext.ExecuteQuery();
                result = true;
            });
            return result;
        }

        // This method relies on the April 2014 CU in SP2013.
        // http://blogs.msdn.com/b/vesku/archive/2014/06/09/provisioning-site-collections-using-sp-app-model-in-on-premises-with-just-csom.aspx
        private static void CreateSiteCollection(ClientContext clientContext, string siteName, string siteNameUrl)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (String.IsNullOrEmpty(siteName)) throw new ArgumentNullException("siteName");
            if (String.IsNullOrEmpty(siteNameUrl)) throw new ArgumentNullException("siteNameUrl");
            // Create site collection.
            SPCommon.LoadTenant(clientContext, (tenant, adminContext) =>
            {
                var webUrl = GetUrlFromSiteName(clientContext, siteName);
                // Ensure the user
                var username = AppHelper.GetProperty(clientContext, Constants.SITEOWNER_PROPERTY) as string;
                if (String.IsNullOrEmpty(username)) throw new Exception("Default site owner not set");
                clientContext.Load(clientContext.Web);
                clientContext.ExecuteQuery();
                var user = clientContext.Web.EnsureUser(username);
                if (null == user) throw new Exception(String.Format("User {0} not found", username));
                clientContext.Load(user);
                clientContext.ExecuteQuery();
                var properties = new SiteCreationProperties
                {
                    Url = webUrl,
                    Owner = user.LoginName,
                    Title = siteName,
                    // Use a blank site template until we can add customizations to the created site collection
                    // On-Prem won't allow creation of site collection w/o valid template.
                    Template = "STS#1"
                };
                // Start the SPO operation to create the site
                // Note in O365 this operation is asynchronous whereas on prem it synchronous.
                var op = tenant.CreateSite(properties);
                adminContext.Load(op, i => i.IsComplete);
                adminContext.ExecuteQuery();
            });
        }

        private static string GetUrlFromSiteName(ClientContext clientContext, string siteName)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (String.IsNullOrEmpty(siteName)) throw new ArgumentNullException("siteName");
            // Tidy the site name
            var regex = new Regex("[^a-zA-Z0-9]");
            var siteNameUrl = regex.Replace(siteName, "");
            // Get the site collection.
            // Note: Assume the site collection of the passed client context is the TenantAdmin site.
            clientContext.Load(clientContext.Web);
            clientContext.Load(clientContext.Web.CurrentUser);
            clientContext.ExecuteQuery();
            var hostWebUrl = clientContext.Web.Url;
            if (!hostWebUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                throw new HttpException("Host web does not start with HTTPS://");
            var idx = hostWebUrl.Substring(8).IndexOf("/", StringComparison.Ordinal);
            var rootSiteUrl = idx >= 0
                ? hostWebUrl.Substring(0, 8 + hostWebUrl.Substring(8).IndexOf("/", StringComparison.Ordinal))
                : hostWebUrl;
            var managedPathName = AppHelper.GetProperty(clientContext, Constants.WILDCARD_MANAGEDPROPERTY) as string;
            if (String.IsNullOrEmpty(managedPathName)) managedPathName = "sites";
            return string.Format("{0}/{1}/{2}", rootSiteUrl, managedPathName, siteNameUrl);
        }
    }
}
