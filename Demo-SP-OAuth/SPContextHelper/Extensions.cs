using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Web.Http.Controllers;

namespace SPContextHelper
{
    public static class Extensions
    {
        public static Uri ToUri(this string url)
        {
            if (string.IsNullOrEmpty(url)) return null;
            if (url.Contains("%")) url = WebUtility.UrlDecode(url);
            return new Uri(url);
        }

        public static NameValueCollection QueryString(this HttpControllerContext context)
        {
            var result = new NameValueCollection();
            var qs = context.Request.RequestUri.Query;
            qs = qs.Substring(qs.IndexOf("?", StringComparison.Ordinal) + 1);
            foreach (var part in qs.Split('&'))
            {
                var pair = part.Split('=');
                if (pair.Length == 2)
                    result.Add(pair[0], pair[1]);
            }

            return result;
        }

        public static string GetHeader(this HttpRequestMessage request, string key)
        {
            return !request.Headers.TryGetValues(key, out IEnumerable<string> keys) ? null : keys.First();
        }

        public static string GetCookie(this HttpRequestMessage request, string cookieName)
        {
            var cookie = request.Headers.GetCookies(cookieName).FirstOrDefault();
            return cookie?[cookieName].Value;
        }
    }
}
