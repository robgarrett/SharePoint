using System;
using System.Configuration;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading.Tasks;
using DemoServicePrincipals.Models;
using Microsoft.Graph;
using Microsoft.Identity.Client;
using Newtonsoft.Json;
using User = Microsoft.Graph.User;

namespace DemoServicePrincipals
{
    /// <summary>
    /// This sample uses Microsoft Graph API (version 2 of ADAL).
    /// </summary>
    /// <remarks>
    /// Example:
    /// https://spr.com/azure-active-directory-creating-applications-spns-powershell/
    /// </remarks>
    internal static class Program
    {
        private const string _resource = "https://graph.microsoft.com/beta";

        private static void Main()
        {
            var userTask = Task.Run(GetGraphDataAsync);
            userTask.Wait();
            Console.WriteLine(userTask.Result.UserPrincipalName);
            var userTask2 = Task.Run(() => SendGraphRequest<User>($"{_resource}/me"));
            userTask2.Wait();
            var response = userTask2.Result;
            Console.WriteLine(response.DisplayName);
            // List service principals.
            var listSPsTask = Task.Run(() => SendGraphRequest<ServicePrincipalCollection>($"{_resource}/ServicePrincipals"));
            listSPsTask.Wait();
            var sps = listSPsTask.Result;
            sps.ServicePrincipals.ToList().ForEach(sp => Console.WriteLine(sp.DisplayName));
            // Create an application.
            // Create a service principal for the application.
        }

        private static async Task<string> GetAccessTokenStringAsync()
        {
            var task = Task.Run(() =>
            {
                var getTokenTask = GetAccessTokenAsync();
                getTokenTask.Wait();
                return getTokenTask.Result.AccessToken;
            });
            return await task;
        }

        private static async Task<AuthenticationResult> GetAccessTokenAsync()
        {
            var redirectUri = ConfigurationManager.AppSettings["RedirectUri"];
            var clientId = ConfigurationManager.AppSettings["ClientId"];
            var tenantName = ConfigurationManager.AppSettings["TenantName"];
            var authority = $"https://login.microsoftonline.com/{tenantName}";
            // Get the access token and wait for the result.
            var clientApp = new PublicClientApplication(clientId, authority, TokenCacheHelper.GetFilecache())
            {
                RedirectUri = redirectUri
            };
            string[] scopes =
            {
                    "User.Read",
                    "Directory.Read.All",
                    "Directory.ReadWrite.All",
                    "Directory.AccessAsUser.All"
                };
            var accountsTask = Task.Run(() => clientApp.GetAccountsAsync());
            AuthenticationResult authResult;
            var user = accountsTask.Result.FirstOrDefault();
            try
            {
                // Try to get the token without bothering the user.
                authResult = await clientApp.AcquireTokenSilentAsync(scopes, user);
            }
            catch (MsalUiRequiredException)
            {
                // Requires a login prompt.
                authResult = await clientApp.AcquireTokenAsync(scopes);
            }
            return authResult;
        }

        private static async Task<User> GetGraphDataAsync()
        {
            var graphClient = new GraphServiceClient(_resource,
                new DelegateAuthenticationProvider(async (requestMessage) =>
                    {
                        requestMessage.Headers.Authorization = new AuthenticationHeaderValue("bearer", await GetAccessTokenStringAsync());
                    }));

            return await graphClient.Me.Request().GetAsync();
        }

        public static async Task<T> SendGraphRequest<T>(string requestUrl)
        {
            using (var httpClient = new HttpClient())
            {
                // Set up the HTTP GET request
                var apiRequest = new HttpRequestMessage(HttpMethod.Get, requestUrl);
                apiRequest.Headers.UserAgent.Add(new ProductInfoHeaderValue("OAuthStarter", "1.0"));
                apiRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", await GetAccessTokenStringAsync());
                apiRequest.Headers.Add("client-request-id", Guid.NewGuid().ToString());
                apiRequest.Headers.Add("return-client-request-id", "true");
                // Get response JSON.
                var response = await httpClient.SendAsync(apiRequest);
                return JsonConvert.DeserializeObject<T>(response.Content.ReadAsStringAsync().Result);
            }
        }
    }
}
