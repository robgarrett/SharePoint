using System;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Http.Controllers;
using ActionFilterAttribute = System.Web.Http.Filters.ActionFilterAttribute;
using IAuthorizationFilter = System.Web.Http.Filters.IAuthorizationFilter;

namespace SPContextHelper
{
    public class SPWebApiControllerFilterAttribute : ActionFilterAttribute, IAuthorizationFilter
    {
        public override void OnActionExecuting(HttpActionContext filterContext)
        {
            if (filterContext == null) throw new ArgumentNullException(nameof(filterContext));
            var context = new ControllerContext(filterContext);
            var result = CustomSharePointContextProvider.CheckRedirectionStatus(context, out _);
            if (result == CustomSharePointContextProvider.RedirectionStatus.Ok) return;
            filterContext.Response = filterContext.Request.CreateErrorResponse(
                HttpStatusCode.MethodNotAllowed, "Could not create context");
        }

        public Task<HttpResponseMessage> ExecuteAuthorizationFilterAsync(HttpActionContext actionContext, CancellationToken cancellationToken,
            Func<Task<HttpResponseMessage>> continuation)
        {
            if (!TokenHelper.IsHighTrustApp()) return continuation();
            var principal = actionContext.ControllerContext.RequestContext.Principal;
            if (principal?.Identity != null && principal.Identity.IsAuthenticated) return continuation();
            var response = actionContext.ControllerContext.Request.CreateErrorResponse(HttpStatusCode.Unauthorized, "Unauthorized");
            return Task.FromResult(response);
        }
    }
}
