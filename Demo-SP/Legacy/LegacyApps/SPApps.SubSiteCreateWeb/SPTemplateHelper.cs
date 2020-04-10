using System;
using System.Linq;
using Microsoft.SharePoint.Client;
using Microsoft.SharePoint.Client.Publishing;

namespace SPApps.SubSiteCreateWeb
{
    static class SPTemplateHelper
    {
        public static bool ValidateTemplate(ClientContext clientContext, string templateName)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (String.IsNullOrEmpty(templateName)) throw new ArgumentNullException("templateName");
            var result = false;
            SPCommon.LoadTenant(clientContext, (tenant, adminContext) =>
            {
                var templates = tenant.GetSPOTenantWebTemplates(1033, 15);
                adminContext.Load(templates);
                adminContext.ExecuteQuery();
                result = (Enumerable.Any(templates, template =>
                    template.Name == templateName ||
                    template.Title == templateName));
            });
            return result;
        }

        public static bool CustomSolutionExists(ClientContext clientContext, string wspName)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (String.IsNullOrEmpty(wspName)) throw new ArgumentNullException("wspName");
            var result = false;
            ProcessCustomSolution(clientContext, wspName, item => result = true);
            return result;
        }

        public static void UploadCustomSolution(ClientContext clientContext, string wspPath)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (String.IsNullOrEmpty(wspPath)) throw new ArgumentNullException("wspPath");
            var wspName = wspPath.Contains("\\")
                ? wspPath.Substring(wspPath.LastIndexOf("\\", StringComparison.Ordinal) + 1)
                : wspPath;
            // Check if the wsp exists already.
            if (!CustomSolutionExists(clientContext, wspName))
            {
                // Upload the file to the solution gallery.
                QuerySolutionGallery(clientContext, solutionGallery =>
                {
                    var file = new FileCreationInformation
                    {
                        Content = System.IO.File.ReadAllBytes(wspPath),
                        Url = wspName,
                        Overwrite = true
                    };
                    solutionGallery.RootFolder.Files.Add(file);
                    clientContext.ExecuteQuery();
                });
            }
            // Make sure the solution is activated.
            var fileRelUrl = "";
            QuerySolutionGallery(clientContext, solutionGallery =>
            {
                clientContext.Load(solutionGallery.RootFolder);
                clientContext.ExecuteQuery();
                fileRelUrl = String.Format("{0}{1}",
                    AppendSlash(solutionGallery.RootFolder.ServerRelativeUrl), wspName);
            });
            var wsp = new DesignPackageInfo
            {
                PackageGuid = Guid.Empty,
                PackageName = wspName.Substring(0, wspName.LastIndexOf(".wsp", StringComparison.OrdinalIgnoreCase))
            };
            try
            {
                clientContext.Load(clientContext.Site);
                DesignPackage.Install(clientContext, clientContext.Site, wsp, fileRelUrl);
                clientContext.ExecuteQuery();
            }
            catch (ServerException)
            {
                // Likely already activated.
            }
        }

        private static void QuerySolutionGallery(ClientContext clientContext, Action<List> del)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (null == del) throw new ArgumentNullException("del");
            // Get the site and root web
            clientContext.Load(clientContext.Site);
            clientContext.ExecuteQuery();
            clientContext.Load(clientContext.Site.RootWeb);
            clientContext.ExecuteQuery();
            // 121 == solutions gallery
            // http://msdn.microsoft.com/en-us/library/microsoft.sharepoint.splisttemplatetype.aspx
            var solutionGallery = clientContext.Site.RootWeb.GetCatalog(121);
            clientContext.ExecuteQuery();
            if (null == solutionGallery) throw new Exception("Cannot load the solutions gallery");
            del(solutionGallery);
        }

        private static void ProcessCustomSolution(ClientContext clientContext, string wspName, Action<ListItem> del)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (String.IsNullOrEmpty(wspName)) throw new ArgumentNullException("wspName");
            if (null == del) throw new ArgumentNullException("del");
            QuerySolutionGallery(clientContext, solutionGallery =>
            {
                // Query the solution gallery.
                var query = new CamlQuery
                {
                    ViewXml = String.Format(
                            "<View><Query><Where><Eq><FieldRef Name=\"FileRef\"/>" +
                            "<Value Type=\"Text\">{0}_catalogs/solutions/{1}</Value></Eq></Where></Query></View>",
                            AppendSlash(clientContext.Site.ServerRelativeUrl),
                            wspName)
                };
                var queryResult = solutionGallery.GetItems(query);
                clientContext.Load(queryResult, items => items.Include(i => i["FileRef"], i => i["File_x0020_Size"]));
                clientContext.ExecuteQuery();
                if (queryResult.Count > 0) del(queryResult[0]);
            });
        }

        private static string AppendSlash(string url)
        {
            if (null == url || url.EndsWith("/")) return url;
            return url + "/";
        }
    }
}
