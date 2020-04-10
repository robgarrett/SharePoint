using System;
using System.Globalization;
using System.Web;
using JetBrains.Annotations;

namespace SPContextHelper
{
    public sealed class ExplicitRequestContext : RequestContext
    {
        private string _spHostUrl;

        public ExplicitRequestContext(string url, HttpContext context) : base(context)
        {
            if (string.IsNullOrEmpty(url)) throw new ArgumentNullException(nameof(url));
            _spHostUrl = url;
        }

        public ExplicitRequestContext(string url, HttpContextBase context) : base(context)
        {
            if (string.IsNullOrEmpty(url)) throw new ArgumentNullException(nameof(url));
            _spHostUrl = url;
        }

        [PublicAPI]
        public override T GetParam<T>(string key)
        {
            // Have we asked for the sp host url explicitly.
            if (0 == string.CompareOrdinal(key, "SPHostUrl"))
                return ConvertFromString<T>(_spHostUrl);
            return base.GetParam<T>(key);
        }

        [PublicAPI]
        public override void SetParam<T>(string key, T value)
        {
            if (0 == string.CompareOrdinal(key, "SPHostUrl"))
                _spHostUrl = value.ToString(CultureInfo.InvariantCulture);
            base.SetParam(key, value);
        }
    }
}
