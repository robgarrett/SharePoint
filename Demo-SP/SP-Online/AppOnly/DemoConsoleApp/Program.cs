using System;

namespace DemoConsoleApp
{
    /// <summary>
    /// This is a console app that demonstrates oauth validation with SharePoint via an app context.
    /// </summary>
    /// <remarks>
    /// 1. Register a new app in SharePoint using https://tenant.sharepoint.com/sites/dev/_layouts/15/appregnew.aspx.
    /// 1.1 Generate a client ID (App ID) - copy it to notepad.
    /// 1.2 Generate a client secret - copy it to notepad.
    /// 1.3 Provide an app title.
    /// 1.4 Provide a unique URI for the app.
    /// 1.5 URI is the site collection where the app is registered.
    /// 2. Click the Create button to create the App Service Principal.
    /// 2.1 Click the OK button
    /// 3. Set the permission for the app using https://tenant.sharepoint.com/sites/dev/_layouts/15/appinv.aspx.
    /// 3.1 Copy the client ID into the App ID box and click the Lookup button.
    /// 3.2 Paste permission XML into the space provided, e.g:
    /// <![CDATA[
    /// <AppPermissionRequests AllowAppOnlyPolicy="true">
    ///   <AppPermissionRequest Scope="http://sharepoint/content/sitecollection" Right="Read" />
    /// </AppPermissionRequests>
    /// ]]>
    /// 3.3 Click the Create Button.
    /// 3.4 Click the Trust It Button on the next page.
    /// 4. Get the site realm using https://tenant.sharepoint.com/sites/dev/_layouts/15/appprincipals.aspx.
    /// 4.1 Copy the GUID after the ampersand for the relevant app - this is the tenant ID.
    /// 5. Update the app.config file with the client ID, secret, and tenant ID.
    /// 6. Review the code below.
    /// </remarks>
    class Program
    {
        static void Main(string[] args)
        {
            var siteUri = new Uri("https://robgarrett365.sharepoint.com");
            var SharePointPrincipalID = "00000003-0000-0ff1-ce00-000000000000";
            var token = TokenHelper.GetAppOnlyAccessToken(SharePointPrincipalID, siteUri.Authority, null).AccessToken;
            var clientContext = TokenHelper.GetClientContextWithAccessToken(siteUri.ToString(), token);
            clientContext.Load(clientContext.Site);
            clientContext.Load(clientContext.Site.RootWeb);
            clientContext.ExecuteQuery();
            Console.WriteLine("RootWeb title is: {0}", clientContext.Web.Title);
        }
    }
}
