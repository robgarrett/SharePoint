using System;
using log4net.Appender;
using log4net.Core;
using System.Diagnostics;
using System.Net;
using System.Web;
using System.Web.Services.Description;
using System.CodeDom;
using System.CodeDom.Compiler;
using System.Web.Caching;

namespace SPAppHelper
{
    public class ULSAppender : AppenderSkeleton
    {
        private static string CACHE_KEY = "ULSLogger";

        protected override void Append(LoggingEvent loggingEvent)
        {
            var eventMessage = RenderLoggingEvent(loggingEvent);
            Trace.WriteLine(eventMessage);
            // Send to SharePoint ULS.
            GenerateProxy((proxy, type) => 
            {
                var flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Public;
                var prop = type.GetProperty("Credentials", flags);
                prop.SetValue(proxy, CredentialCache.DefaultCredentials);
                var method = type.GetMethod("SendClientScriptErrorReport", flags);
                method.Invoke(proxy, new object[] {
                    eventMessage,   // Message
                    "",             // File
                    0,              // Line
                    "",             // Client
                    "",             // Stack
                    "",             // Team
                    ""              // Original file
                });
            });
        }

        private static void GenerateProxy(Action<object, Type> del)
        {
            if (null == del) throw new ArgumentNullException("del");
            try
            {
                if (null == HttpContext.Current) return;
                var proxy = HttpContext.Current.Cache[CACHE_KEY];
                if (null == proxy)
                {
                    var spUrl = HttpContext.Current.Request.QueryString["SPHostUrl"];
                    if (string.IsNullOrEmpty(spUrl)) spUrl = HttpContext.Current.Request.Form["SPHostUrl"];
                    if (string.IsNullOrEmpty(spUrl)) return;
                    var wsUrl = string.Format("{0}/_vti_bin/Diagnostics.asmx?wsdl", spUrl);
                    var request = (HttpWebRequest)WebRequest.Create(wsUrl);
                    request.Credentials = CredentialCache.DefaultCredentials;
                    var response = (HttpWebResponse)request.GetResponse();
                    using (var stream = response.GetResponseStream())
                    {
                        // Get a WSDL file describing a service.
                        var serviceDescription = ServiceDescription.Read(stream);
                        // Initialize a service description importer.
                        var importer = new ServiceDescriptionImporter();
                        importer.ProtocolName = "Soap12";  // Use SOAP 1.2.
                        importer.AddServiceDescription(serviceDescription, null, null);
                        // Report on the service descriptions.
                        Debug.WriteLine("Importing {0} service descriptions with {1} associated schemas.",
                            importer.ServiceDescriptions.Count, importer.Schemas.Count);
                        // Generate a proxy client.
                        importer.Style = ServiceDescriptionImportStyle.Client;
                        // Generate properties to represent primitive values.
                        importer.CodeGenerationOptions = System.Xml.Serialization.CodeGenerationOptions.GenerateProperties;
                        // Initialize a Code-DOM tree into which we will import the service.
                        var nmspace = new CodeNamespace();
                        var unit1 = new CodeCompileUnit();
                        unit1.Namespaces.Add(nmspace);
                        // Import the service into the Code-DOM tree. This creates proxy code
                        // that uses the service.
                        var warning = importer.Import(nmspace, unit1);
                        if (0 == warning)
                        {
                            // Generate and print the proxy code in C#.
                            var provider1 = CodeDomProvider.CreateProvider("CSharp");
                            // Compile the assembly with the appropriate references
                            string[] assemblyReferences = new string[] { "System.Web.Services.dll", "System.Xml.dll", "System.dll" };
                            var parms = new CompilerParameters(assemblyReferences);
                            var results = provider1.CompileAssemblyFromDom(parms, unit1);
                            foreach (CompilerError oops in results.Errors)
                            {
                                Debug.WriteLine("======== Compiler error ============");
                                Debug.WriteLine(oops.ErrorText);
                            }
                            //Invoke the web service method
                            proxy = results.CompiledAssembly.CreateInstance("SharePointDiagnostics");
                            if (null == proxy) throw new Exception("Failed to instantiate web service proxy");
                            // Add proxy to cache.
                            HttpContext.Current.Cache.Insert(CACHE_KEY, proxy, null, Cache.NoAbsoluteExpiration, Cache.NoSlidingExpiration);
                        }
                        else
                        {
                            Debug.WriteLine("Warning: " + warning);
                        }
                    }
                }
                del(proxy, proxy.GetType());
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
            }
        }
    }
}
