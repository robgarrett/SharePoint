using System;
using System.Globalization;
using System.Security.Principal;
using System.Web.Http.Controllers;
using JetBrains.Annotations;

namespace SPContextHelper
{
    public class ControllerContext : BaseContext, ISessionContext
    {
        private readonly HttpActionContext _context;

        public ControllerContext(HttpActionContext context)
        {
            _context = context ?? throw new ArgumentNullException(nameof(context));
        }

        [PublicAPI]
        public T GetParam<T>(string key) where T : IConvertible
        {
            // Check the query string.
            var obj = ConvertFromString<T>(_context.ControllerContext.QueryString()[key]);
            // ReSharper disable once ConvertIfStatementToReturnStatement
            if (null != obj) return obj;
            // Check the cookie.
            return ConvertFromString<T>(_context.Request.GetCookie(key));
        }

        [PublicAPI]
        public void SetParam<T>(string key, T value) where T : IConvertible
        {
            // Set the cookie.
            if (null == value) return;
            _context.Response?.Headers.Add("Set-Cookie", $"{key}={value.ToString(CultureInfo.InvariantCulture)}");
        }

        [PublicAPI]
        public Uri GetRequestUrl => _context.Request.RequestUri;

        [PublicAPI]
        public WindowsIdentity GetLogonUser => _context.ControllerContext.RequestContext.Principal?.Identity as WindowsIdentity;

        [PublicAPI]
        public string GetHttpMethod => _context.ControllerContext.Request.Method.Method;
    }
}
