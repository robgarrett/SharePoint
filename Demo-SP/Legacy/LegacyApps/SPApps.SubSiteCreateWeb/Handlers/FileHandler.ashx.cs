using System.Web;

namespace SPApps.SubSiteCreateWeb.Handlers
{
    public class FileHandler : IHttpHandler
    {

        public void ProcessRequest(HttpContext context)
        {
            Logger.Logger.LogInfo("ProcessRequest in FileHandler for file upload", () =>
            {
                if (context.Request.Files.Count > 0)
                {
                    var files = context.Request.Files;
                    foreach (string key in files)
                    {
                        var file = files[key];
                        if (null == file) continue;
                        var fileName = file.FileName.Substring(
                            file.FileName.LastIndexOf("\\", System.StringComparison.Ordinal) + 1);
                        fileName = context.Server.MapPath("~/WSPs/" + fileName);
                        file.SaveAs(fileName);
                    }
                }
                context.Response.ContentType = "text/plain";
                context.Response.Write("File(s) uploaded successfully!");
            });
        }

        public bool IsReusable
        {
            get { return false; }
        }
    }
}