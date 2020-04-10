using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace DemoHighTrustConsole
{
    class Program
    {
        /// <summary>
        /// This is a console app that demonstrates oauth validation with SharePoint via an app context.
        /// </summary>
        /// <remarks>
        /// 1. Register a new app in SharePoint using https://sharepoint-onpremises/_layouts/15/appregnew.aspx.
        /// 1.1 Generate a client ID (App ID) - copy it to notepad.
        /// 1.2 Generate a client secret - copy it to notepad.
        /// 1.3 Provide an app title.
        /// 1.4 Provide a unique URI for the app.
        /// 1.5 URI is the site collection where the app is registered (or https//localhost).
        /// 2. Click the Create button to create the App Service Principal.
        /// 2.1 Click the OK button
        /// 3. Set the permission for the app using https://sharepoint-onpremises/_layouts/15/appinv.aspx.
        /// 3.1 Copy the client ID into the App ID box and click the Lookup button.
        /// 3.2 Paste permission XML into the space provided, e.g:
        /// <![CDATA[
        /// <AppPermissionRequests AllowAppOnlyPolicy="true">
        ///   <AppPermissionRequest Scope="http://sharepoint/content/sitecollection" Right="Read" />
        /// </AppPermissionRequests>
        /// ]]>
        /// 3.3 Click the Create Button.
        /// 3.4 Click the Trust It Button on the next page.
        /// 4. Obtain the Issuer ID for your on-premises SharePoint trusted token issuer.
        /// 5. Update the app.config file with the client ID, certificate location (PFX), certificate password, and Issuer ID.
        /// 6. Review the code below.
        static void Main(string[] args)
        {
            var siteUrl = "https://sharepoint-onpremises";
            var siteUri = new Uri(siteUrl);
            // Get the access token from SharePoint via OAUTH.
            // The token helper will use the clientID to look up access and check permissions.
            string accessToken = TokenHelper.GetS2SAccessTokenWithWindowsIdentity(siteUri, null);
            // Create a client context for CSOM with the access token.
            // The explicit call to use the S2S Access token, above, ensures we're a high-trust app.
            using (var clientContext = TokenHelper.GetClientContextWithAccessToken(siteUrl, accessToken))
            {
                var web = clientContext.Web;
                clientContext.Load(web);
                clientContext.ExecuteQuery();
                Console.WriteLine(web.Title);
            }
        }
    }
}
