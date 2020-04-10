using Microsoft.SharePoint.Client;
using helper = SPAppHelper;
using System;
using System.Web.Mvc;

namespace DemoAppWeb.Controllers
{
    public class HomeController : Controller
    {
        internal static string DEFAULT_LIBNAME = "Sample DL";
        internal static string DEFAULT_VIEWNAME = "Sample View";
        internal static string DEFAULT_PAGENAME = "MyList";

        private Models.DemoDataModel _model = null;

        public HomeController()
        {
            _model = new Models.DemoDataModel
            {
                DocumentLibraryName = DEFAULT_LIBNAME,
                ViewName = DEFAULT_VIEWNAME,
                PageName = DEFAULT_PAGENAME
            };
            // Register events.
            helper.SPAppHelper.Instance.CreatedDocLib += Instance_CreatedDocLib;
            helper.SPAppHelper.Instance.DocLibExists += Instance_DocLibExists;
            helper.SPAppHelper.Instance.FileUploaded += Instance_FileUploaded;
            helper.SPAppHelper.Instance.ViewExists += Instance_ViewExists;
            helper.SPAppHelper.Instance.CreatedView += Instance_CreatedView;
            helper.SPAppHelper.Instance.PageExists += Instance_PageExists;
            helper.SPAppHelper.Instance.CreatedPage += Instance_CreatedPage;
            helper.SPAppHelper.Instance.ContentAddedToPage += Instance_ContentAddedToPage;
        }

        [SharePointContextFilter]
        public ActionResult Index()
        {
            _model.SPHostUrl = SharePointContext.GetRequestParameter(HttpContext.Request, "SPHostUrl");
            _model.SPLanguage = SharePointContext.GetRequestParameter(HttpContext.Request, "SPLanguage");
            _model.SPClientTag = SharePointContext.GetRequestParameter(HttpContext.Request, "SPClientTag");
            _model.SPProductNumber = SharePointContext.GetRequestParameter(HttpContext.Request, "SPProductNumber");
            helper.Logger.LogInfo("Home Controller - Index", () =>
            {
                User spUser = null;
                ExecuteWithContext(clientContext =>
                {
                    spUser = clientContext.Web.CurrentUser;
                    clientContext.Load(spUser, user => user.Title);
                    clientContext.ExecuteQuery();
                    ViewBag.UserName = spUser.Title;
                    ViewBag.UserIsAdmin = helper.SPAppHelper.Instance.CurrentUserIsAdmin(clientContext);
                });
            });
            return View(_model);
        }

        [HttpPost, SharePointContextFilter]
        public ActionResult Submit(Models.DemoDataModel model)
        {
            _model = model;
            if (string.IsNullOrEmpty(model.DocumentLibraryName)) model.DocumentLibraryName = DEFAULT_LIBNAME;
            if (string.IsNullOrEmpty(model.ViewName)) model.ViewName = DEFAULT_VIEWNAME;
            if (string.IsNullOrEmpty(model.PageName)) model.PageName = DEFAULT_PAGENAME;
            helper.Logger.LogInfo("Home Controller - Submit", () =>
            {
                User spUser = null;
                ExecuteWithContext(clientContext =>
                {
                    spUser = clientContext.Web.CurrentUser;
                    clientContext.Load(spUser, user => user.Title);
                    clientContext.ExecuteQuery();
                    ViewBag.UserName = spUser.Title;
                    ViewBag.UserIsAdmin = helper.SPAppHelper.Instance.CurrentUserIsAdmin(clientContext);
                    if (ModelState.IsValid)
                    {
                        // Process
                        helper.SPAppHelper.Instance.CreateDocumentLibrary(clientContext, model.DocumentLibraryName);
                        helper.SPAppHelper.Instance.CreateListView(clientContext, model.DocumentLibraryName, model.ViewName);
                        helper.SPAppHelper.Instance.CreateSitePage(clientContext, model.PageName, model.DocumentLibraryName);
                        helper.SPAppHelper.Instance.UploadDocumentToSharePoint(clientContext, model.file1, model.DocumentLibraryName);
                        helper.SPAppHelper.Instance.UploadDocumentToSharePoint(clientContext, model.file2, model.DocumentLibraryName);
                        helper.SPAppHelper.Instance.UploadDocumentToSharePoint(clientContext, model.file3, model.DocumentLibraryName);
                    }
                });
            });
            return View("Index", model);
        }

        protected void ExecuteWithContext(Action<ClientContext> del)
        {
            if (null == del) throw new ArgumentNullException("del");
            var spContext = SharePointContextProvider.Current.GetSharePointContext(HttpContext);
            using (var clientContext = spContext.CreateUserClientContextForSPHost())
            {
                if (clientContext != null) del(clientContext);
            }
        }

        private void Instance_DocLibExists(object sender, EventArgs e)
        {
            _model.Messages.Add(new System.Collections.Generic.KeyValuePair<string, Models.DemoDataModel.EventType>("DocLib Exists", Models.DemoDataModel.EventType.WARN));
        }

        private void Instance_CreatedDocLib(object sender, EventArgs e)
        {
            _model.Messages.Add(new System.Collections.Generic.KeyValuePair<string, Models.DemoDataModel.EventType>("DocLib Created", Models.DemoDataModel.EventType.INFO));
        }

        private void Instance_FileUploaded(object sender, helper.FileUploadedEventArgs e)
        {
            var message = string.Format("File {0} uploaded to document library", e.Filename);
            _model.Messages.Add(new System.Collections.Generic.KeyValuePair<string, Models.DemoDataModel.EventType>(message, Models.DemoDataModel.EventType.INFO));
        }

        private void Instance_CreatedView(object sender, EventArgs e)
        {
            _model.Messages.Add(new System.Collections.Generic.KeyValuePair<string, Models.DemoDataModel.EventType>("View Created", Models.DemoDataModel.EventType.INFO));
        }

        private void Instance_ViewExists(object sender, EventArgs e)
        {
            _model.Messages.Add(new System.Collections.Generic.KeyValuePair<string, Models.DemoDataModel.EventType>("View Exists", Models.DemoDataModel.EventType.WARN));
        }

        private void Instance_CreatedPage(object sender, EventArgs e)
        {
            _model.Messages.Add(new System.Collections.Generic.KeyValuePair<string, Models.DemoDataModel.EventType>("Page Created", Models.DemoDataModel.EventType.INFO));
        }

        private void Instance_PageExists(object sender, EventArgs e)
        {
            _model.Messages.Add(new System.Collections.Generic.KeyValuePair<string, Models.DemoDataModel.EventType>("Page Exists", Models.DemoDataModel.EventType.WARN));
        }

        private void Instance_ContentAddedToPage(object sender, EventArgs e)
        {
            _model.Messages.Add(new System.Collections.Generic.KeyValuePair<string, Models.DemoDataModel.EventType>("Content Added to Page", Models.DemoDataModel.EventType.INFO));
        }
    }
}
