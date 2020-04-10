using SPContextHelper;
using System.Web.Http;

namespace SPAdminWebAPIWeb.Controllers
{
    [SPWebApiControllerFilter]
    public class DataController : ApiController
    {
        [HttpGet, ActionName("Test")]
        public IHttpActionResult Test()
        {
            return Ok("Hello");
        }

        [HttpGet, ActionName("SiteName")]
        public IHttpActionResult SiteName()
        {
            var context = new ControllerContext(ActionContext);
            var spContext = CustomSharePointContext.GetSharePointContext(context);
            using (var clientContext = spContext.CreateUserClientContextForSPHost())
            {
                clientContext.Load(clientContext.Web);
                clientContext.ExecuteQuery();
                return Ok(clientContext.Web.Title);
            }
        }
    }
}
