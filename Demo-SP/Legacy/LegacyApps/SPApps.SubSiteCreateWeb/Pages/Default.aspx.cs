using System;

namespace SPApps.SubSiteCreateWeb
{
    public partial class Default : System.Web.UI.Page
    {
        protected void Page_PreInit(object sender, EventArgs e)
        {
            Uri redirectUrl;
            switch (SharePointContextProvider.CheckRedirectionStatus(Context, out redirectUrl))
            {
                case RedirectionStatus.Ok:
                    return;
                case RedirectionStatus.ShouldRedirect:
                    Response.Redirect(redirectUrl.AbsoluteUri, true);
                    break;
                case RedirectionStatus.CanNotRedirect:
                    Response.Write("An error occurred while processing your request.");
                    Response.End();
                    break;
            }
        }

        protected void Page_Load(object sender, EventArgs e)
        {
            Logger.Logger.LogInfo("Page_Load in App", () =>
            {
                try
                {
                    var spContext = SharePointContextProvider.Current.GetSharePointContext(Context);
                    // Display admin panel if user is a site collection admin.
                    using (var clientContext = spContext.CreateUserClientContextForSPHost())
                    {
                        adminPanel.Visible = AppHelper.CurrentUserIsAdmin(clientContext);
                        if (adminPanel.Visible)
                        {
                            if (Page.IsPostBack) return;
                            var listName = AppHelper.GetProperty(clientContext, Constants.LISTNAME_PROPERTY) as string;
                            var fieldName = AppHelper.GetProperty(clientContext, Constants.FIELDNAME_PROPERTY) as string;
                            var template =
                                AppHelper.GetProperty(clientContext, Constants.TEMPLATENAME_PROPERY) as string;
                            var wspNameStr = AppHelper.GetProperty(clientContext, Constants.WSPNAME_PROPERTY) as string;
                            var siteOwnerName =
                                AppHelper.GetProperty(clientContext, Constants.SITEOWNER_PROPERTY) as string;
                            var managedPathName =
                                AppHelper.GetProperty(clientContext, Constants.WILDCARD_MANAGEDPROPERTY) as string;
                            var uniquePerms = AppHelper.GetProperty(clientContext, Constants.UNIQUEPERMS_PROPERTY);
                            var useSC = AppHelper.GetProperty(clientContext, Constants.SITECOL_PROPERTY);
                            bindToList.Text = listName ?? "";
                            bindToField.Text = fieldName ?? "";
                            templateName.Text = template ?? "";
                            wspName.Text = wspNameStr ?? "";
                            siteOwner.Text = siteOwnerName ?? "";
                            managedPath.Text = managedPathName ?? "";
                            useUniquePerms.Checked = uniquePerms != null &&
                                0 == String.Compare(uniquePerms.ToString(), "TRUE", StringComparison.OrdinalIgnoreCase);
                            useSiteCollection.Checked = useSC != null &&
                                0 == String.Compare(useSC.ToString(), "TRUE", StringComparison.OrdinalIgnoreCase);
                            useSiteCollection.InputAttributes.Add("data-bind", "checked: useSiteCollections");
                            koBinding.Text =
                                "<script type='text/javascript'>var viewModel = { useSiteCollections: ko.observable(" +
                                (useSiteCollection.Checked ? "true" : "false") +
                                ") }; ko.applyBindings(viewModel);</script>";
                        }
                        else
                        {
                            nonAdminPanel.Visible = true;
                        }
                    }
                }
                catch (Exception ex)
                {
                    Logger.Logger.LogError(ex.ToString());
                    throw;
                }
            });
        }

        protected void updateBtn_Click(object sender, EventArgs e)
        {
            Logger.Logger.LogInfo("Update Button clicked in App", () =>
            {
                var spContext = SharePointContextProvider.Current.GetSharePointContext(Context);
                using (var clientContext = spContext.CreateAppOnlyClientContextForSPHost())
                {
                    try
                    {
                        // Set the properties.
                        var listName = bindToList.Text.Trim();
                        var fieldName = bindToField.Text.Trim();
                        var template = templateName.Text.Trim();
                        var wspNameStr = wspName.Text.Trim();
                        var wspPathStr = Server.MapPath(String.Format("~/WSPs/{0}", wspNameStr));
                        var managedPathName = managedPath.Text.Trim();
                        var siteOwnerName = siteOwner.Text.Trim();
                        AppHelper.SetProperty(clientContext, Constants.LISTNAME_PROPERTY, listName);
                        AppHelper.SetProperty(clientContext, Constants.FIELDNAME_PROPERTY, fieldName);
                        AppHelper.SetProperty(clientContext, Constants.TEMPLATENAME_PROPERY, template);
                        AppHelper.SetProperty(clientContext, Constants.WSPNAME_PROPERTY, wspNameStr);
                        AppHelper.SetProperty(clientContext, Constants.WSPPATH_PROPERTY, wspPathStr);
                        AppHelper.SetProperty(clientContext, Constants.WILDCARD_MANAGEDPROPERTY, managedPathName);
                        AppHelper.SetProperty(clientContext, Constants.SITEOWNER_PROPERTY, siteOwnerName);
                        AppHelper.SetProperty(clientContext, Constants.UNIQUEPERMS_PROPERTY, useUniquePerms.Checked);
                        AppHelper.SetProperty(clientContext, Constants.SITECOL_PROPERTY, useSiteCollection.Checked);
                        // Rebind the list.
                        if (!String.IsNullOrEmpty(listName) && !String.IsNullOrEmpty(fieldName))
                            AppHelper.RegisterRemoteEvents(clientContext);
                    }
                    catch (Exception ex)
                    {
                        Logger.Logger.LogError(ex.ToString());
                        throw;
                    }
                    // Redirect to SPHost.
                    Response.Redirect(spContext.SPHostUrl.AbsoluteUri, true);
                }
            });
        }
    }
}