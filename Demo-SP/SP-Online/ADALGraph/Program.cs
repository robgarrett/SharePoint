using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading.Tasks;
using adal = Microsoft.IdentityModel.Clients.ActiveDirectory;

namespace ADALGraph
{
    /// <summary>
    /// Access Graph with an access token.
    /// https://blogs.msdn.microsoft.com/mrochon/2015/11/19/using-oauth2-with-soap/
    /// </summary>
    internal static class Program
    {
        private const string _msGraph = "https://graph.microsoft.com";
        private const string _adGraph = "https://graph.windows.net";
        private const string _authority = "https://login.microsoftonline.com/common";
        private const string _clientId = "1b730954-1685-4b74-9bfd-dac224a7b894";
        private const string _redirectUri = "urn:ietf:wg:oauth:2.0:oob";

        private class ResponseResult
        {
            // ReSharper disable UnusedAutoPropertyAccessor.Local
            public System.Net.HttpStatusCode StatusCode { get; set; }
            public string Content { get; set; }
            public Exception Exception { get; set; }
            public HttpResponseHeaders Headers { get; set; }
            // ReSharper restore UnusedAutoPropertyAccessor.Local
        }

        private static void Main()
        {
            var cache = new FileCache();
            var authContext = new adal.AuthenticationContext(_authority, cache);
            var task = Task.Run(() => Authenticate(authContext, _msGraph));
            task.Wait();
            var authResult = task.Result;
            // Connect to MS Graph API using the access token as bearer.
            var httpTask = Task.Run(() => SendRequestToGraphAsync(
                new Uri("https://graph.microsoft.com/beta/servicePrincipals"),
                HttpMethod.Get, authResult.AccessToken));
            httpTask.Wait();
            Console.WriteLine(httpTask.Result.Content);
        }

        private static async Task<adal.AuthenticationResult> Authenticate(adal.AuthenticationContext context, string resource)
        {
            
            try
            {
                return await context.AcquireTokenSilentAsync(resource, _clientId);
            }
            catch (adal.AdalException ex)
            {
                // There is no access token in the cache, so prompt the user to sign-in.
                if (ex.ErrorCode == adal.AdalError.UserInteractionRequired ||
                    ex.ErrorCode == adal.AdalError.FailedToAcquireTokenSilently)
                {
                    return await context.AcquireTokenAsync(resource, _clientId, new Uri(_redirectUri),
                        new adal.PlatformParameters(adal.PromptBehavior.Auto));
                }
                // Some other error.
                throw;
            }
        }

        private static async Task<ResponseResult> SendRequestToGraphAsync(Uri url, HttpMethod method,
            string accessToken, string content = null)
        {
            var client = new HttpClient();
            HttpRequestMessage request = null;
            StringContent requestContent = null;
            HttpResponseMessage respMessage = null;
            var result = new ResponseResult();
            try
            {
                request = new HttpRequestMessage(method, url);
                request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
                request.Headers.Authorization = new AuthenticationHeaderValue("bearer", accessToken);
                if (method != HttpMethod.Get && !string.IsNullOrEmpty(content))
                {
                    requestContent = new StringContent(content, Encoding.UTF8, "application/json");
                    request.Content = requestContent;
                    request.Headers.Add("Prefer", "return=representation");
                }

                respMessage = client.SendAsync(request).Result;
                result.StatusCode = respMessage.StatusCode;
                result.Headers = respMessage.Headers;
                result.Content = await respMessage.Content.ReadAsStringAsync();
            }
            catch (Exception ex)
            {
                result.Exception = ex;
            }
            finally
            {
                requestContent?.Dispose();
                respMessage?.Dispose();
                request?.Dispose();
            }

            return result;
        }
    }
}
