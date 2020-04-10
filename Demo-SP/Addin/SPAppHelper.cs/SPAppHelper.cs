using System;
using System.Diagnostics;
using Microsoft.SharePoint.Client;
using Microsoft.SharePoint.Client.WebParts;
using System.Linq;
using System.Web;
using System.Xml;

namespace SPAppHelper
{
    public class SPAppHelper
    {
        public event EventHandler CreatedDocLib;
        public event EventHandler DocLibExists;
        public event EventHandler CreatedView;
        public event EventHandler ViewExists;
        public event EventHandler PageExists;
        public event EventHandler CreatedPage;
        public event EventHandler ContentAddedToPage;
        public event EventHandler<FileUploadedEventArgs> FileUploaded;

        private static SPAppHelper _instance = null;

        static SPAppHelper()
        {
            // Static constructor called when first static accessed.
            _instance = new SPAppHelper();
        }

        public static SPAppHelper Instance { get { return _instance; } }

        public bool CurrentUserIsAdmin(ClientContext clientContext)
        {
            var result = false;
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            try
            {
                Logger.LogInfo("Is Current User an Admin?", () =>
                {
                    clientContext.Load(clientContext.Web);
                    clientContext.Load(clientContext.Web.CurrentUser);
                    clientContext.ExecuteQuery();
                    result = clientContext.Web.CurrentUser.IsSiteAdmin;
                });
                return result;
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
                Logger.LogError(ex.ToString());
                return false;
            }
        }

        public void CreateDocumentLibrary(ClientContext clientContext, string documentLibName)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (string.IsNullOrEmpty(documentLibName)) throw new ArgumentNullException("documentLibName");
            // See if we already have the document library.
            try
            {
                if (!ProcessDocumentLibrary(clientContext, documentLibName, null))
                {
                    Logger.LogInfo("Creating document library {0}", () =>
                    {
                        var lci = new ListCreationInformation
                        {
                            Description = "Demo Document Library, created by Provider-hosted App",
                            Title = documentLibName,
                            TemplateType = 101, // Document Library
                            };
                        var newLib = clientContext.Web.Lists.Add(lci);
                        clientContext.Load(newLib);
                        clientContext.ExecuteQuery();
                        if (null != CreatedDocLib) CreatedDocLib(this, new EventArgs());
                    }, documentLibName);
                }
                else
                {
                    if (null != DocLibExists) DocLibExists(this, new EventArgs());
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("Failed to create document library {0}, details: {1}", documentLibName, ex.ToString());
            }
        }

        public void RemoveDocumentLibrary(ClientContext clientContext, string documentLibName)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (string.IsNullOrEmpty(documentLibName)) throw new ArgumentNullException("documentLibName");
            // See if we already have the document library.
            try
            {
                ProcessDocumentLibrary(clientContext, documentLibName, list => {
                    list.DeleteObject();
                    clientContext.ExecuteQuery();
                });
            }
            catch (Exception ex)
            {
                Logger.LogError("Failed to delete document library {0}, details: {1}", documentLibName, ex.ToString());
            }
        }

        public void CreateListView(ClientContext clientContext, string documentLibName, string viewName)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (string.IsNullOrEmpty(documentLibName)) throw new ArgumentNullException("documentLibName");
            if (string.IsNullOrEmpty(viewName)) throw new ArgumentNullException("viewName");
            // See if we already have the document library.
            try
            {
                if (!ProcessDocumentLibrary(clientContext, documentLibName, list => {
                    var viewCollection = list.Views;
                    if (viewCollection.Count(v => v.Title == viewName) == 0)
                    {
                        string[] viewFields = { "Title", "FileLeafRef" };
                        var vci = new ViewCreationInformation
                        {
                            Title = viewName,
                            RowLimit = 50,
                            ViewFields = viewFields,
                            ViewTypeKind = ViewType.None,
                            SetAsDefaultView = false
                        };
                        viewCollection.Add(vci);
                        clientContext.ExecuteQuery();
                        if (null != CreatedView) CreatedView(this, new EventArgs());
                    } 
                    else
                    {
                        if (null != ViewExists) ViewExists(this, new EventArgs());
                    }
                }))
                {
                    throw new Exception("Could not find document libarary " + documentLibName);
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("Failed to create view {2} on document library {0}, details: {1}", documentLibName, ex.ToString(), viewName);
            }
        }

        private bool ProcessDocumentLibrary(ClientContext clientContext, string documentLibName, Action<List> del)
        {
            bool result = false;
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (string.IsNullOrEmpty(documentLibName)) throw new ArgumentNullException("documentLibName");
            Logger.LogInfo("Checking for document library {0}", () =>
            {
                var listCollection = clientContext.Web.Lists;
                clientContext.Load(listCollection, lists => lists.Include(
                    list => list.Title).Where(list => list.Title == documentLibName));
                clientContext.ExecuteQuery();
                if (listCollection.Count > 0)
                {
                    if (null != del)
                    {
                        var lib = listCollection[0];
                        clientContext.Load(lib);
                        clientContext.Load(lib.RootFolder);
                        clientContext.Load(lib.ContentTypes);
                        clientContext.Load(lib.Views);
                        clientContext.ExecuteQuery();
                        del(lib);
                    }
                    result = true;
                }
            }, documentLibName);
            return result;
        }

        public void UploadDocumentToSharePoint(ClientContext clientContext, HttpPostedFileBase file, string documentLibName)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (string.IsNullOrEmpty(documentLibName)) throw new ArgumentNullException("documentLibName");
            if (null == file) return;
            try
            {
                if (!ProcessDocumentLibrary(clientContext, documentLibName, list => {
                    // Get the default document content type ID.
                    var contentType = clientContext.LoadQuery(list.ContentTypes.Where(f => f.Name == "Document"));
                    clientContext.ExecuteQuery();
                    // Get file ready to upload.
                    var filename = file.FileName.Substring(file.FileName.LastIndexOf("\\") + 1);
                    var fci = new FileCreationInformation
                    {
                        ContentStream = file.InputStream,
                        Overwrite = true,
                        Url = string.Format("{0}/{1}/{2}", clientContext.Web.Url, 
                            list.RootFolder.Name, filename)
                    };
                    // Set the metadata.
                    var uploadFile = list.RootFolder.Files.Add(fci);
                    uploadFile.ListItemAllFields["ContentTypeId"] = contentType.FirstOrDefault().Id.ToString();
                    uploadFile.ListItemAllFields.Update();
                    clientContext.Load(uploadFile);
                    clientContext.ExecuteQuery();
                    // Check in if we have plublishing.
                    if (uploadFile.MinorVersion != 0)
                    {
                        uploadFile.Publish("Uploaded by Demo App");
                        clientContext.ExecuteQuery();
                    }
                    if (null != FileUploaded) FileUploaded(this, new FileUploadedEventArgs(filename));
                }))
                {
                    throw new Exception("Could not find document libarary " + documentLibName);
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("Failed to upoad file {0} to document library, details: {1}", file.FileName, ex.ToString());
            }
        }

        public void CreateSitePage(ClientContext clientContext, string pageName, string documentLibName)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (string.IsNullOrEmpty(documentLibName)) throw new ArgumentNullException("documentLibName");
            if (string.IsNullOrEmpty(pageName)) throw new ArgumentNullException("pageName");
            try
            {
                if (!ProcessDocumentLibrary(clientContext, documentLibName, list => {
                    // Get the site pages library.
                    var listCollection = clientContext.Web.Lists;
                    clientContext.Load(listCollection, lists => lists.Include(l => l.Title).Where(l => l.Title == "Site Pages"));
                    clientContext.ExecuteQuery();
                    if (listCollection.Count != 1) throw new Exception("Could not find Site Pages library");
                    var sitePages = listCollection[0];
                    clientContext.Load(sitePages);
                    clientContext.Load(sitePages.RootFolder, f => f.ServerRelativeUrl);
                    clientContext.ExecuteQuery();
                    // Now we look for the wiki page
                    var libUrl = sitePages.RootFolder.ServerRelativeUrl;
                    var newPageUrl = string.Format("{0}/{1}.aspx", libUrl, pageName);
                    var currentPage = clientContext.Web.GetFileByServerRelativeUrl(newPageUrl);
                    clientContext.Load(currentPage, f => f.Exists);
                    clientContext.ExecuteQuery();
                    if (!currentPage.Exists)
                    {
                        var newPage = sitePages.RootFolder.Files.AddTemplateFile(newPageUrl, TemplateFileType.WikiPage);
                        clientContext.Load(newPage);
                        clientContext.ExecuteQuery();
                        if (null != CreatedPage) CreatedPage(this, new EventArgs());
                    } 
                    else
                    {
                        if (null != PageExists) PageExists(this, new EventArgs());
                    }
                    // Add content to the page.
                    var fullPageName = string.Format("{0}.aspx", pageName);
                    AddHtmlToWikiPage(clientContext, clientContext.Web, "SitePages", Globals.WikiPage_OneColumn, fullPageName);
                    var entity = new WebPartEntity
                    {
                        WebPartIndex = 1,
                        WebPartTitle = "Test Documents",
                        WebPartZone = "Left",
                        WebPartXml = string.Format(Globals.ListViewWebPart, list.Id, list.Title)
                    };
                    RemoveAllWebPartsFromWikiPages(clientContext, clientContext.Web, "SitePages", fullPageName);
                    AddWebPartToWikiPage(clientContext, clientContext.Web, "SitePages", entity, fullPageName, 1, 1, false);
                    if (null != ContentAddedToPage) ContentAddedToPage(this, new EventArgs());
                }))
                {
                    throw new Exception("Could not find document libarary " + documentLibName);
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("Failed to create page {0} with document library web part, details: {1}", pageName, ex.ToString());
            }
        }

        public void RemoveSitePage(ClientContext clientContext, string pageName)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (string.IsNullOrEmpty(pageName)) throw new ArgumentNullException("pageName");
            try
            {
                // Get the site pages library.
                var listCollection = clientContext.Web.Lists;
                clientContext.Load(listCollection, lists => lists.Include(l => l.Title).Where(l => l.Title == "Site Pages"));
                clientContext.ExecuteQuery();
                if (listCollection.Count != 1) throw new Exception("Could not find Site Pages library");
                var sitePages = listCollection[0];
                clientContext.Load(sitePages);
                clientContext.Load(sitePages.RootFolder, f => f.ServerRelativeUrl);
                clientContext.ExecuteQuery();
                // Now we look for the wiki page
                var libUrl = sitePages.RootFolder.ServerRelativeUrl;
                var newPageUrl = string.Format("{0}/{1}.aspx", libUrl, pageName);
                var currentPage = clientContext.Web.GetFileByServerRelativeUrl(newPageUrl);
                clientContext.Load(currentPage, f => f.Exists);
                clientContext.ExecuteQuery();
                if (currentPage.Exists)
                {
                    currentPage.DeleteObject();
                    clientContext.ExecuteQuery();
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("Failed to remove page {0}, details: {1}", pageName, ex.ToString());
            }
        }

        private static void AddHtmlToWikiPage(ClientContext clientContext, Web web, string folder, string html, string page)
        {
            // Get the pages lib.
            var pagesLib = web.GetFolderByServerRelativeUrl(folder);
            clientContext.Load(pagesLib.Files);
            clientContext.ExecuteQuery();
            // Look for the page.
            File file = null;
            foreach (var aspxFile in pagesLib.Files)
            {
                if (aspxFile.Name.Equals(page, StringComparison.InvariantCultureIgnoreCase))
                {
                    file = aspxFile;
                    break;
                }
            }
            if (file == null) return;
            // Load the page.
            clientContext.Load(file);
            clientContext.Load(file.ListItemAllFields);
            clientContext.ExecuteQuery();
            ListItem item = file.ListItemAllFields;
            item["WikiField"] = html;
            item.Update();
            clientContext.ExecuteQuery();
        }

        private void RemoveAllWebPartsFromWikiPages(ClientContext clientContext, Web web, string folder, string page)
        {
            // Get the pages lib.
            var pagesLib = web.GetFolderByServerRelativeUrl(folder);
            clientContext.Load(pagesLib.Files);
            clientContext.ExecuteQuery();
            // Look for the page.
            File webPartPage = null;
            foreach (var aspxFile in pagesLib.Files)
            {
                if (aspxFile.Name.Equals(page, StringComparison.InvariantCultureIgnoreCase))
                {
                    webPartPage = aspxFile;
                    break;
                }
            }
            if (webPartPage == null) return;
            // Get the webpart manager.
            LimitedWebPartManager limitedWebPartManager = webPartPage.GetLimitedWebPartManager(PersonalizationScope.Shared);
            clientContext.Load(limitedWebPartManager, wpm => wpm.WebParts);
            clientContext.ExecuteQuery();
            for (var i = 0; i < limitedWebPartManager.WebParts.Count; i++)
                limitedWebPartManager.WebParts[i].DeleteWebPart();
            clientContext.ExecuteQuery();
        }

        // With help from Office DEV PNP.
        private void AddWebPartToWikiPage(ClientContext clientContext, Web web, string folder, WebPartEntity webPart, string page, int row, int col, bool addSpace)
        {
            // Get the pages lib.
            var pagesLib = web.GetFolderByServerRelativeUrl(folder);
            clientContext.Load(pagesLib.Files);
            clientContext.ExecuteQuery();
            // Look for the page.
            File webPartPage = null;
            foreach (var aspxFile in pagesLib.Files)
            {
                if (aspxFile.Name.Equals(page, StringComparison.InvariantCultureIgnoreCase))
                {
                    webPartPage = aspxFile;
                    break;
                }
            }
            if (webPartPage == null) return;
            // Load the page.
            clientContext.Load(webPartPage);
            clientContext.Load(webPartPage.ListItemAllFields);
            clientContext.ExecuteQuery();
            string wikiField = (string)webPartPage.ListItemAllFields["WikiField"];
            // Get the webpart manager.
            LimitedWebPartManager limitedWebPartManager = webPartPage.GetLimitedWebPartManager(PersonalizationScope.Shared);
            WebPartDefinition oWebPartDefinition = limitedWebPartManager.ImportWebPart(webPart.WebPartXml);
            WebPartDefinition wpdNew = limitedWebPartManager.AddWebPart(oWebPartDefinition.WebPart, "wpz", 0);
            clientContext.Load(wpdNew);
            clientContext.ExecuteQuery();
            #region Structure
            //HTML structure in default team site home page (W16)
            //<div class="ExternalClass284FC748CB4242F6808DE69314A7C981">
            //  <div class="ExternalClass5B1565E02FCA4F22A89640AC10DB16F3">
            //    <table id="layoutsTable" style="width&#58;100%;">
            //      <tbody>
            //        <tr style="vertical-align&#58;top;">
            //          <td colspan="2">
            //            <div class="ms-rte-layoutszone-outer" style="width&#58;100%;">
            //              <div class="ms-rte-layoutszone-inner" style="word-wrap&#58;break-word;margin&#58;0px;border&#58;0px;">
            //                <div><span><span><div class="ms-rtestate-read ms-rte-wpbox"><div class="ms-rtestate-read 9ed0c0ac-54d0-4460-9f1c-7e98655b0847" id="div_9ed0c0ac-54d0-4460-9f1c-7e98655b0847"></div><div class="ms-rtestate-read" id="vid_9ed0c0ac-54d0-4460-9f1c-7e98655b0847" style="display&#58;none;"></div></div></span></span><p> </p></div>
            //                <div class="ms-rtestate-read ms-rte-wpbox">
            //                  <div class="ms-rtestate-read c7a1f9a9-4e27-4aa3-878b-c8c6c87961c0" id="div_c7a1f9a9-4e27-4aa3-878b-c8c6c87961c0"></div>
            //                  <div class="ms-rtestate-read" id="vid_c7a1f9a9-4e27-4aa3-878b-c8c6c87961c0" style="display&#58;none;"></div>
            //                </div>
            //              </div>
            //            </div>
            //          </td>
            //        </tr>
            //        <tr style="vertical-align&#58;top;">
            //          <td style="width&#58;49.95%;">
            //            <div class="ms-rte-layoutszone-outer" style="width&#58;100%;">
            //              <div class="ms-rte-layoutszone-inner" style="word-wrap&#58;break-word;margin&#58;0px;border&#58;0px;">
            //                <div class="ms-rtestate-read ms-rte-wpbox">
            //                  <div class="ms-rtestate-read b55b18a3-8a3b-453f-a714-7e8d803f4d30" id="div_b55b18a3-8a3b-453f-a714-7e8d803f4d30"></div>
            //                  <div class="ms-rtestate-read" id="vid_b55b18a3-8a3b-453f-a714-7e8d803f4d30" style="display&#58;none;"></div>
            //                </div>
            //              </div>
            //            </div>
            //          </td>
            //          <td class="ms-wiki-columnSpacing" style="width&#58;49.95%;">
            //            <div class="ms-rte-layoutszone-outer" style="width&#58;100%;">
            //              <div class="ms-rte-layoutszone-inner" style="word-wrap&#58;break-word;margin&#58;0px;border&#58;0px;">
            //                <div class="ms-rtestate-read ms-rte-wpbox">
            //                  <div class="ms-rtestate-read 0b2f12a4-3ab5-4a59-b2eb-275bbc617f95" id="div_0b2f12a4-3ab5-4a59-b2eb-275bbc617f95"></div>
            //                  <div class="ms-rtestate-read" id="vid_0b2f12a4-3ab5-4a59-b2eb-275bbc617f95" style="display&#58;none;"></div>
            //                </div>
            //              </div>
            //            </div>
            //          </td>
            //        </tr>
            //      </tbody>
            //    </table>
            //    <span id="layoutsData" style="display&#58;none;">true,false,2</span>
            //  </div>
            //</div>
            #endregion Structure
            // Parse the wiki page.
            var xd = new XmlDocument();
            xd.PreserveWhitespace = true;
            xd.LoadXml(wikiField);
            // Sometimes the wikifield content seems to be surrounded by an additional div? 
            var layoutsTable = xd.SelectSingleNode("div/div/table") as XmlElement;
            if (layoutsTable == null) layoutsTable = xd.SelectSingleNode("div/table") as XmlElement;
            var layoutsZoneInner = layoutsTable.SelectSingleNode(string.Format("tbody/tr[{0}]/td[{1}]/div/div", row, col)) as XmlElement;
            // - space element
            var space = xd.CreateElement("p");
            var text = xd.CreateTextNode(" ");
            space.AppendChild(text);
            // - wpBoxDiv
            var wpBoxDiv = xd.CreateElement("div");
            layoutsZoneInner.AppendChild(wpBoxDiv);
            if (addSpace) layoutsZoneInner.AppendChild(space);
            var attribute = xd.CreateAttribute("class");
            wpBoxDiv.Attributes.Append(attribute);
            attribute.Value = "ms-rtestate-read ms-rte-wpbox";
            attribute = xd.CreateAttribute("contentEditable");
            wpBoxDiv.Attributes.Append(attribute);
            attribute.Value = "false";
            // - div1
            var div1 = xd.CreateElement("div");
            wpBoxDiv.AppendChild(div1);
            div1.IsEmpty = false;
            attribute = xd.CreateAttribute("class");
            div1.Attributes.Append(attribute);
            attribute.Value = "ms-rtestate-read " + wpdNew.Id.ToString("D");
            attribute = xd.CreateAttribute("id");
            div1.Attributes.Append(attribute);
            attribute.Value = "div_" + wpdNew.Id.ToString("D");
            // - div2
            var div2 = xd.CreateElement("div");
            wpBoxDiv.AppendChild(div2);
            div2.IsEmpty = false;
            attribute = xd.CreateAttribute("style");
            div2.Attributes.Append(attribute);
            attribute.Value = "display:none";
            attribute = xd.CreateAttribute("id");
            div2.Attributes.Append(attribute);
            attribute.Value = "vid_" + wpdNew.Id.ToString("D");
            var  listItem = webPartPage.ListItemAllFields;
            listItem["WikiField"] = xd.OuterXml;
            listItem.Update();
            clientContext.ExecuteQuery();
        }
    }
}
