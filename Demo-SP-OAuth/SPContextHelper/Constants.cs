using System;

namespace SPContextHelper
{
    internal static class Constants
    {
        public const string SPHostUrlKey = "SPHostUrl";
        public const string SPAppWebUrlKey = "SPAppWebUrl";
        public const string SPLanguageKey = "SPLanguage";
        public const string SPClientTagKey = "SPClientTag";
        public const string SPProductNumberKey = "SPProductNumber";
        public const string SPContextTokenCookieName = "SPContextToken";
        public static readonly TimeSpan AccessTokenLifetimeTolerance = TimeSpan.FromMinutes(5.0);
    }
}
