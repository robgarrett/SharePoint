using System;
using System.IdentityModel.Tokens;
using System.Linq;
using System.Net;
using System.Web;
using JetBrains.Annotations;

namespace SPContextHelper
{
    public abstract class CustomSharePointContextProvider
    {
        public enum RedirectionStatus
        {
            Ok,
            ShouldRedirect,
            CanNotRedirect
        }

        #region Nested Providers

        private class CustomSharePointAcsContextProvider : CustomSharePointContextProvider
        {
            protected override CustomSharePointContext CreateSharePointContext(
                Uri spHostUrl, Uri spAppWebUrl, string spLanguage, string spClientTag,
                string spProductNumber, ISessionContext context)
            {
                if (null == spHostUrl) throw new ArgumentNullException(nameof(spHostUrl));
                if (string.IsNullOrEmpty(spLanguage)) throw new ArgumentNullException(nameof(spLanguage));
                if (string.IsNullOrEmpty(spClientTag)) throw new ArgumentNullException(nameof(spClientTag));
                if (string.IsNullOrEmpty(spProductNumber)) throw new ArgumentNullException(nameof(spProductNumber));
                if (null == context) throw new ArgumentNullException(nameof(context));
                var spContextString = GetContextString(context);
                if (string.IsNullOrEmpty(spContextString)) return null;
                var requestUrl = context.GetRequestUrl;
                if (null == requestUrl) return null;
                SharePointContextToken contextToken;
                try
                {
                    contextToken = TokenHelper.ReadAndValidateContextToken(spContextString, requestUrl.Authority);
                }
                catch (Microsoft.IdentityModel.Tokens.SecurityTokenExpiredException)
                {
                    // ACS Token Expired - remove the context token from context store.
                    // TODO: Need a new context token from SharePoint.
                    context.SetParam<string>(Constants.SPContextTokenCookieName, null);
                    return null;
                }
                catch (WebException)
                {
                    return null;
                }
                catch (AudienceUriValidationFailedException)
                {
                    return null;
                }
                return new CustomSharePointContext.CustomSharePointAcsContext(
                    spHostUrl, spAppWebUrl, spLanguage, spClientTag, spProductNumber, spContextString, contextToken);
            }

            protected override bool ValidateSharePointContext(
                CustomSharePointContext spContext, ISessionContext context)
            {
                if (null == context) throw new ArgumentNullException(nameof(context));
                if (!(spContext is CustomSharePointContext.CustomSharePointAcsContext spAcsContext)) return false;
                var spHostUrl = CustomSharePointContext.GetSPHostUrl(context);
                var spContextString = GetContextString(context);
                return spHostUrl == spAcsContext.SPHostUrl &&
                    !string.IsNullOrEmpty(spAcsContext.ContextToken) &&
                    (string.IsNullOrEmpty(spContextString) || spContextString == spAcsContext.ContextToken);
            }

            protected override CustomSharePointContext LoadSharePointContext(ISessionContext context)
            {
                if (null == context) throw new ArgumentNullException(nameof(context));
                // Load context parameters from session store.
                var spHostUrl = context.GetParam<string>(Constants.SPHostUrlKey).ToUri();
                var spAppWebUrl = context.GetParam<string>(Constants.SPAppWebUrlKey).ToUri();
                var spLanguage = context.GetParam<string>(Constants.SPLanguageKey);
                var spClientTag = context.GetParam<string>(Constants.SPClientTagKey);
                var spProductNumber = context.GetParam<string>(Constants.SPProductNumberKey);
                return CreateSharePointContext(spHostUrl, spAppWebUrl, spLanguage, spClientTag, spProductNumber, context);
            }

            protected override void SaveSharePointContext(CustomSharePointContext spContext, ISessionContext context)
            {
                if (!(spContext is CustomSharePointContext.CustomSharePointAcsContext)) return;
                if (null == context) throw new ArgumentNullException(nameof(context));
                // Update the session store with parameters.
                var spAcsContext = (CustomSharePointContext.CustomSharePointAcsContext)spContext;
                context.SetParam(Constants.SPContextTokenCookieName, spAcsContext.ContextToken);
                if (null != spAcsContext.SPHostUrl)
                    context.SetParam(Constants.SPHostUrlKey, spAcsContext.SPHostUrl?.ToString());
                if (null != spAcsContext.SPAppWebUrl)
                    context.SetParam(Constants.SPAppWebUrlKey, spAcsContext.SPAppWebUrl.ToString());
                context.SetParam(Constants.SPClientTagKey, spAcsContext.SPClientTag);
                context.SetParam(Constants.SPLanguageKey, spAcsContext.SPLanguage);
                context.SetParam(Constants.SPProductNumberKey, spAcsContext.SPProductNumber);
            }

            private static string GetContextString(ISessionContext context)
            {
                // Check cookie first.
                var contextString = context.GetParam<string>(Constants.SPContextTokenCookieName);
                if (!string.IsNullOrEmpty(contextString)) return contextString;
                string[] paramNames = { "AppContext", "AppContextToken", "AccessToken", "SPAppToken" };
                return paramNames.Select(context.GetParam<string>).FirstOrDefault(val => !string.IsNullOrEmpty(val));
            }
        }

        private class CustomSharePointHighTrustContextProvider : CustomSharePointContextProvider
        {
            protected override CustomSharePointContext CreateSharePointContext(
                Uri spHostUrl, Uri spAppWebUrl, string spLanguage, string spClientTag,
                string spProductNumber, ISessionContext context)
            {
                if (null == spHostUrl) throw new ArgumentNullException(nameof(spHostUrl));
                if (string.IsNullOrEmpty(spLanguage)) throw new ArgumentNullException(nameof(spLanguage));
                if (string.IsNullOrEmpty(spClientTag)) throw new ArgumentNullException(nameof(spClientTag));
                if (string.IsNullOrEmpty(spProductNumber)) throw new ArgumentNullException(nameof(spProductNumber));
                if (null == context) throw new ArgumentNullException(nameof(context));
                var logonUserIdentity = context.GetLogonUser;
                if (logonUserIdentity == null || !logonUserIdentity.IsAuthenticated || logonUserIdentity.IsGuest || logonUserIdentity.User == null)
                    return null;
                return new CustomSharePointContext.CustomSharePointHighTrustContext(
                    spHostUrl, spAppWebUrl, spLanguage, spClientTag, spProductNumber, logonUserIdentity);

            }

            protected override bool ValidateSharePointContext(
                CustomSharePointContext spContext, ISessionContext context)
            {
                if (null == context) throw new ArgumentNullException(nameof(context));
                if (!(spContext is CustomSharePointContext.CustomSharePointHighTrustContext spHighTrustContext)) return false;
                var spHostUrl = CustomSharePointContext.GetSPHostUrl(context);
                var logonUserIdentity = context.GetLogonUser;
                return spHostUrl == spHighTrustContext.SPHostUrl &&
                       logonUserIdentity != null &&
                       logonUserIdentity.IsAuthenticated &&
                       !logonUserIdentity.IsGuest &&
                       logonUserIdentity.User == spHighTrustContext.LogonUserIdentity.User;
            }

            protected override CustomSharePointContext LoadSharePointContext(ISessionContext context)
            {
                if (null == context) throw new ArgumentNullException(nameof(context));
                // Load context parameters from session store.
                var spHostUrl = context.GetParam<string>(Constants.SPHostUrlKey).ToUri();
                var spAppWebUrl = context.GetParam<string>(Constants.SPAppWebUrlKey).ToUri();
                var spLanguage = context.GetParam<string>(Constants.SPLanguageKey);
                var spClientTag = context.GetParam<string>(Constants.SPClientTagKey);
                var spProductNumber = context.GetParam<string>(Constants.SPProductNumberKey);
                return CreateSharePointContext(spHostUrl, spAppWebUrl, spLanguage, spClientTag, spProductNumber, context);
            }

            protected override void SaveSharePointContext(CustomSharePointContext spContext, ISessionContext context)
            {
                if (null == spContext) return;
                if (null == context) throw new ArgumentNullException(nameof(context));
                // Update the session store with parameters.
                var spHTContext = (CustomSharePointContext.CustomSharePointHighTrustContext)spContext;
                if (null != spHTContext.SPHostUrl)
                    context.SetParam(Constants.SPHostUrlKey, spHTContext.SPHostUrl?.ToString());
                if (null != spHTContext.SPAppWebUrl)
                    context.SetParam(Constants.SPAppWebUrlKey, spHTContext.SPAppWebUrl.ToString());

                context.SetParam(Constants.SPClientTagKey, spHTContext.SPClientTag);
                context.SetParam(Constants.SPLanguageKey, spHTContext.SPLanguage);
                context.SetParam(Constants.SPProductNumberKey, spHTContext.SPProductNumber);
            }
        }

        #endregion Nested Providers

        #region Abstracts

        protected abstract CustomSharePointContext CreateSharePointContext(
            Uri spHostUrl, Uri spAppWebUrl, string spLanguage, string spClientTag,
            string spProductNumber, ISessionContext context);

        protected abstract bool ValidateSharePointContext(
            CustomSharePointContext spContext, ISessionContext context);

        protected abstract CustomSharePointContext LoadSharePointContext(ISessionContext context);

        protected abstract void SaveSharePointContext(CustomSharePointContext spContext, ISessionContext context);

        #endregion Abstracts

        [PublicAPI]
        public static CustomSharePointContextProvider Current { get; private set; }

        static CustomSharePointContextProvider()
        {
            if (!TokenHelper.IsHighTrustApp())
                Current = new CustomSharePointAcsContextProvider();
            else
                Current = new CustomSharePointHighTrustContextProvider();
        }

        [PublicAPI]
        public static void Register(CustomSharePointContextProvider provider)
        {
            Current = provider ?? throw new ArgumentNullException(nameof(provider));
        }

        [PublicAPI]
        public static RedirectionStatus CheckRedirectionStatus(ISessionContext context, out Uri redirectUrl)
        {
            redirectUrl = null;
            if (null == context) return RedirectionStatus.CanNotRedirect;
            try
            {
                if (null != Current.GetSharePointContext(context)) return RedirectionStatus.Ok;
            }
            catch (Exception)
            {
                // Something went wrong.
                return RedirectionStatus.CanNotRedirect;
            }
            redirectUrl = GetAppRedirectUrl(context);
            return null == redirectUrl ? 
                RedirectionStatus.CanNotRedirect : 
                RedirectionStatus.ShouldRedirect;
        }

        [PublicAPI]
        public CustomSharePointContext GetSharePointContext(ISessionContext context)
        {
            if (null == context) throw new ArgumentNullException(nameof(context));
            var spContext = LoadSharePointContext(context);
            if (null != spContext && ValidateSharePointContext(spContext, context))
            {
                // Make sure we save the context each time because load may have
                // captured values from the query string, whereas save uses cookies.
                SaveSharePointContext(spContext, context);
                return spContext;
            }
            spContext = CreateSharePointContext(context);
            if (null != spContext) SaveSharePointContext(spContext, context);
            return spContext;
        }

        [PublicAPI]
        public CustomSharePointContext CreateSharePointContext(ISessionContext context)
        {
            if (null == context) throw new ArgumentNullException(nameof(context));
            var spHostUrl = CustomSharePointContext.GetSPHostUrl(context);
            if (null == spHostUrl) return null;
            var spLanguage = context.GetParam<string>(Constants.SPLanguageKey);
            if (string.IsNullOrEmpty(spLanguage)) return null;
            var spClientTag = context.GetParam<string>(Constants.SPClientTagKey);
            if (string.IsNullOrEmpty(spClientTag)) return null;
            var spProductNumber = context.GetParam<string>(Constants.SPProductNumberKey);
            if (string.IsNullOrEmpty(spProductNumber)) return null;
            var spAppWebUrlString = TokenHelper.EnsureTrailingSlash(context.GetParam<string>(Constants.SPAppWebUrlKey));
            if (!Uri.TryCreate(spAppWebUrlString, UriKind.Absolute, out var spAppWebUrl) ||
                !(spAppWebUrl.Scheme == Uri.UriSchemeHttp || spAppWebUrl.Scheme == Uri.UriSchemeHttps))
                spAppWebUrl = null;
            return CreateSharePointContext(spHostUrl, spAppWebUrl, spLanguage, spClientTag, spProductNumber, context);
        }

        private static Uri GetAppRedirectUrl(ISessionContext context)
        {
            if (null == context) throw new ArgumentNullException(nameof(context));
            // Make sure we don't redirect over and over again.
            const string SPHasRedirectedToSharePointKey = "SPHasRedirectedToSharePoint";
            if (!string.IsNullOrEmpty(context.GetParam<string>(SPHasRedirectedToSharePointKey))) return null;
            var spHostUrl = CustomSharePointContext.GetSPHostUrl(context);
            if (null == spHostUrl) return null;
            var requestUrl = context.GetRequestUrl;
            if (null == requestUrl) return null;
            var queryNameValueCollection = HttpUtility.ParseQueryString(requestUrl.Query);
            // Removes the values that are included in {StandardTokens}, as {StandardTokens} 
            // will be inserted at the beginning of the query string.
            queryNameValueCollection.Remove(Constants.SPHostUrlKey);
            queryNameValueCollection.Remove(Constants.SPAppWebUrlKey);
            queryNameValueCollection.Remove(Constants.SPLanguageKey);
            queryNameValueCollection.Remove(Constants.SPClientTagKey);
            queryNameValueCollection.Remove(Constants.SPProductNumberKey);
            // Adds SPHasRedirectedToSharePoint=1.
            queryNameValueCollection.Add(SPHasRedirectedToSharePointKey, "1");
            var returnUrlBuilder = new UriBuilder(requestUrl) { Query = queryNameValueCollection.ToString() };
            // Inserts StandardTokens.
            const string StandardTokens = "{StandardTokens}";
            var returnUrlString = returnUrlBuilder.Uri.AbsoluteUri;
            returnUrlString = returnUrlString.Insert(returnUrlString.IndexOf("?", StringComparison.Ordinal) + 1, StandardTokens + "&");
            var redirectUrlString = TokenHelper.GetAppContextTokenRequestUrl(spHostUrl.AbsoluteUri, Uri.EscapeDataString(returnUrlString));
            return new Uri(redirectUrlString, UriKind.Absolute);
        }
    }
}
