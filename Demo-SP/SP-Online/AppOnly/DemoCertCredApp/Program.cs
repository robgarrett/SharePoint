using System;
using System.Configuration;
using System.Linq;
using System.Security;
using System.Security.Cryptography.X509Certificates;
using System.Threading.Tasks;
using Microsoft.IdentityModel.Clients.ActiveDirectory;

namespace DemoCertCredApp
{
    /*
     * The following URL details OAUTH flow with AAD.
     * https://docs.microsoft.com/en-us/azure/active-directory/develop/v1-protocols-oauth-code
     *
     * This application demos certificate credentials via the ADAL library and it's intended use is
     * in app-only context service applications.
     *
     * 1. Login to portal.azure.com
     * 2. Go to Active Directory.
     * 3. Go to App Registrations.
     * 4. Create a new Web / Web API App Registration.
     * 5. Copy the Application ID to the Client ID in the app.config file.
     * 6. Grant the application permissions to SharePoint.
     * 7. Run the New-SelfSignedCertificateEx.ps1 script.
     * 8. Upload the pubkey.cer file from Debug\bin to Azure (use the new App Reg Portal).
     * 9. Change the tenant name and resource in the app.config file.
     */
    class Program
    {
        static void Main()
        {
            var tenant = ConfigurationManager.AppSettings["TenantName"];
            var clientId = ConfigurationManager.AppSettings["ClientId"];
            var certName = ConfigurationManager.AppSettings["CertName"];
            var resource = ConfigurationManager.AppSettings["Resource"];
            var authority = $"https://login.microsoftonline.com/{tenant}";
            // Get the cert from the local cert store.
            var cert = ReadCertificateFromStore(certName);
            if (null == cert) throw new SecurityException($"Cannot find cert {certName} in LocalMachine/My store");
            var certCred = new ClientAssertionCertificate(clientId, cert);
            var authContext = new AuthenticationContext(authority);
            var task = Task.Run(() => authContext.AcquireTokenAsync(resource, certCred));
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


        private static X509Certificate2 ReadCertificateFromStore(string certName)
        {
            var store = new X509Store(StoreName.My, StoreLocation.LocalMachine);
            store.Open(OpenFlags.ReadOnly);
            var certCollection = store.Certificates;
            // Find unexpired certificates.
            var currentCerts = certCollection.Find(X509FindType.FindByTimeValid, DateTime.Now, false);
            // From the collection of unexpired certificates, find the ones with the correct name.
            var signingCert = currentCerts.Find(X509FindType.FindBySubjectDistinguishedName, certName, false);
            // Return the first certificate in the collection, has the right name and is current.
            var cert = signingCert.OfType<X509Certificate2>().OrderByDescending(c => c.NotBefore).FirstOrDefault();
            store.Close();
            return cert;
        }
    }
}
