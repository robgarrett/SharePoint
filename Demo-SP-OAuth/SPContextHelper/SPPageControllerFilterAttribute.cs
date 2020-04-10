using System;
using System.Web.Mvc;

namespace SPContextHelper
{
    public class SPPageControllerFilterAttribute : ActionFilterAttribute, IAuthorizationFilter
    {
        public override void OnActionExecuting(ActionExecutingContext filterContext)
        {
            if (filterContext == null) throw new ArgumentNullException(nameof(filterContext));
            var context = new RequestContext(filterContext.HttpContext);
            switch (CustomSharePointContextProvider.CheckRedirectionStatus(context, out var redirectUrl))
            {
                case CustomSharePointContextProvider.RedirectionStatus.Ok:
                    return;
                case CustomSharePointContextProvider.RedirectionStatus.ShouldRedirect:
                    filterContext.Result = new RedirectResult(redirectUrl.AbsoluteUri);
                    break;
                case CustomSharePointContextProvider.RedirectionStatus.CanNotRedirect:
                    filterContext.Result = new ViewResult { ViewName = "Error" };
                    break;
                default:
                    throw new ArgumentOutOfRangeException();
            }
        }

        public void OnAuthorization(AuthorizationContext filterContext)
        {
            // Are we SPO or On-Prem?
            // SPO does not need authentication because we use ACS.
            if (!TokenHelper.IsHighTrustApp()) return;
            if (filterContext == null) throw new ArgumentNullException(nameof(filterContext));
            // Make sure the anonymous attribute isn't present.
            if (filterContext.ActionDescriptor.IsDefined(typeof(AllowAnonymousAttribute), true) ||
                filterContext.ActionDescriptor.ControllerDescriptor.IsDefined(typeof(AllowAnonymousAttribute), true))
                return;
            if (null == filterContext.HttpContext) throw new NullReferenceException("HttpContext is null");
            var user = filterContext.HttpContext.User;
            if (user.Identity.IsAuthenticated)
            {
                // We're authenticated.
                var cache = filterContext.HttpContext.Response.Cache;
                cache.SetProxyMaxAge(new TimeSpan(0L));
                return;
            }
            // We're not authenticated.
            filterContext.Result = new HttpUnauthorizedResult();
        }
    }
}
