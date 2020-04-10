using System;
using System.Configuration;
using System.Threading.Tasks;
using Microsoft.IdentityModel.Clients.ActiveDirectory;

namespace DemoUserApp
{
    /*
     * The following URL details OAUTH flow with AAD.
     * https://docs.microsoft.com/en-us/azure/active-directory/develop/v1-protocols-oauth-code
     *
     * This application demos user credentials via the ADAL library and it's intended use is
     * in applications that require user+app context.
     *
	 * 1. Login to portal.azure.com
     * 2. Go to Active Directory.
     * 3. Go to App Registrations.
     * 4. Create a new Native App Registration.
     * 5. Copy the Application ID to the Client ID in the app.config file.
     * 6. Grant the application permissions to SharePoint.
	 * 7. Copy the redirect Uri to the app.config file.
     * 8. Change the tenant name and resource in the app.config file.
     */
    internal class Program
    {
        static void Main()
        {
            var tenant = ConfigurationManager.AppSettings["TenantId"];
            var resource = ConfigurationManager.AppSettings["Resource"];
            var authority = $"https://login.microsoftonline.com/{tenant}";
            var authContext = new AuthenticationContext(authority, new FileCache());
            var task = Task.Run(() => Authenticate(authContext));
            task.Wait();
            var authResult = task.Result;
            // Connect to SPO.
            using (var clientContext = TokenHelper.GetClientContextWithAccessToken(resource, authResult.AccessToken))
            {
                clientContext.Load(clientContext.Site);
                clientContext.Load(clientContext.Web);
                clientContext.ExecuteQuery();
                Console.WriteLine(clientContext.Web.Title);
            }
        }

        private static async Task<AuthenticationResult> Authenticate(AuthenticationContext context)
        {
            var clientId = ConfigurationManager.AppSettings["ClientId"];
            var resource = ConfigurationManager.AppSettings["Resource"];
            var redirectUri = ConfigurationManager.AppSettings["RedirectUri"];
            try
            {
                return await context.AcquireTokenSilentAsync(resource, clientId);
            }
            catch (AdalException ex)
            {
                // There is no access token in the cache, so prompt the user to sign-in.
                if (ex.ErrorCode == AdalError.UserInteractionRequired ||
                    ex.ErrorCode == AdalError.FailedToAcquireTokenSilently)
                {
                    return await context.AcquireTokenAsync(resource, clientId, new Uri(redirectUri),
                        new PlatformParameters(PromptBehavior.Always));
                }
                // Some other error.
                throw;
            }
        }
    }
}
