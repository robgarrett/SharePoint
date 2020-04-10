using SPContextHelper;
using System.Web.Mvc;

namespace SPAdminWebAPIWeb.Controllers
{
    [SPPageControllerFilter]
    public class HomeController : Controller
    {
        public ActionResult Index()
        {
            var context = new RequestContext(HttpContext);
            var spContext = CustomSharePointContext.GetSharePointContext(context);
            using (var clientContext = spContext.CreateUserClientContextForSPHost())
            {
                if (clientContext == null) return View();
                var spUser = clientContext.Web.CurrentUser;
                clientContext.Load(spUser, user => user.Title);
                clientContext.ExecuteQuery();
                ViewBag.UserName = spUser.Title;
            }
            return View();
        }
    }
}
