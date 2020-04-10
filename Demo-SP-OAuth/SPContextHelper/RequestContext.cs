using System;
using System.Globalization;
using System.Security.Principal;
using System.Web;
using JetBrains.Annotations;

namespace SPContextHelper
{
    public class RequestContext : BaseContext, ISessionContext
    {
        private readonly HttpContextBase _context;

        public RequestContext(HttpContext context)
        {
            if (null == context) throw new ArgumentNullException(nameof(context));
            _context = new HttpContextWrapper(context);
        }

        public RequestContext(HttpContextBase context)
        {
            _context = context ?? throw new ArgumentNullException(nameof(context));
        }

        [PublicAPI]
        public virtual T GetParam<T>(string key) where T : IConvertible
        {
            // Check for cookie first.
            var cookie = _context.Request.Cookies[key];
            if (null != cookie) return ConvertFromString<T>(cookie.Value);
            // Check the query string.
            var obj = ConvertFromString<T>(_context.Request.QueryString[key]);
            // ReSharper disable once ConvertIfStatementToReturnStatement
            if (null != obj) return obj;
            // Try the posted form data.
            return _context.Request.HttpMethod == "POST" ?
                ConvertFromString<T>(_context.Request[key]) : default(T);
        }

        [PublicAPI]
        public virtual void SetParam<T>(string key, T value) where T : IConvertible
        {
            // Save a cookie, so it can be used by thr WebAPI filter (if we need it).
            if (null != _context.Response.Cookies[key])
                _context.Response.Cookies.Remove(key);
            // We don't allow blank value cookies.
            if (null == value) return;
            var cookie = new HttpCookie(key, value.ToString(CultureInfo.InvariantCulture))
            {
                Secure = true,
                HttpOnly = true
            };
            _context.Response.AppendCookie(cookie);
        }

        [PublicAPI]
        public Uri GetRequestUrl => _context.Request.Url;

        [PublicAPI]
        public WindowsIdentity GetLogonUser => _context.Request.LogonUserIdentity;

        [PublicAPI]
        public string GetHttpMethod => _context.Request.HttpMethod;
    }
}
