using JetBrains.Annotations;
using Microsoft.IdentityModel.S2S.Protocols.OAuth2;
using Microsoft.SharePoint.Client;
using System;
using System.Security.Principal;

namespace SPContextHelper
{
    public abstract class CustomSharePointContext
    {
        #region Nested Contexts

        public class CustomSharePointAcsContext : CustomSharePointContext
        {
            private readonly string _contextToken;
            private readonly SharePointContextToken _contextTokenObj;

            [PublicAPI] public string ContextToken => _contextTokenObj.ValidTo > DateTime.UtcNow ? _contextToken : null;
            [PublicAPI] public string CacheKey => _contextTokenObj.ValidTo > DateTime.UtcNow ? _contextTokenObj.CacheKey : null;
            [PublicAPI] public string RefreshToken => _contextTokenObj.ValidTo > DateTime.UtcNow ? _contextTokenObj.RefreshToken : null;

            public override string UserAccessTokenForSPHost
            {
                get
                {
                    return GetAccessTokenString(ref _userAccessTokenForSPHost, () =>
                        TokenHelper.GetAccessToken(_contextTokenObj, SPHostUrl.Authority));
                }
            }

            public override string AppOnlyAccessTokenForSPHost
            {
                get
                {
                    return GetAccessTokenString(ref _appOnlyAccessTokenForSPHost, () =>
                        TokenHelper.GetAppOnlyAccessToken(TokenHelper.SharePointPrincipal, SPHostUrl.Authority, TokenHelper.GetRealmFromTargetUrl(SPHostUrl)));
                }
            }

            public override string UserAccessTokenForSPAppWeb
            {
                get
                {
                    return GetAccessTokenString(ref _userAccessTokenForSPAppWeb, () =>
                        TokenHelper.GetAccessToken(_contextTokenObj, SPAppWebUrl.Authority));
                }
            }

            public override string AppOnlyAccessTokenForSPAppWeb
            {
                get
                {
                    return GetAccessTokenString(ref _appOnlyAccessTokenForSPAppWeb, () =>
                        TokenHelper.GetAppOnlyAccessToken(TokenHelper.SharePointPrincipal, SPHostUrl.Authority, TokenHelper.GetRealmFromTargetUrl(SPAppWebUrl)));
                }
            }

            public CustomSharePointAcsContext(
                Uri spHostUrl,
                Uri spAppWebUrl,
                string spLanguage,
                string spClientTag,
                string spProductNumber,
                string contextToken,
                SharePointContextToken contextTokenObj) :
                base(spHostUrl, spAppWebUrl, spLanguage, spClientTag, spProductNumber)
            {
                if (string.IsNullOrEmpty(contextToken)) throw new ArgumentNullException(nameof(contextToken));
                _contextTokenObj = contextTokenObj ?? throw new ArgumentNullException(nameof(contextTokenObj));
                _contextToken = contextToken;
            }

            private static string GetAccessTokenString(ref Tuple<string, DateTime> accessToken, Func<OAuth2AccessTokenResponse> tokenRenewalHandler)
            {
                // Check if our access token has expired, if so, then ask Acs to refresh.
                RenewAccessTokenIfNeeded(ref accessToken, tokenRenewalHandler);
                return IsAccessTokenValid(accessToken) ? accessToken.Item1 : null;
            }

            private static void RenewAccessTokenIfNeeded(ref Tuple<string, DateTime> accessToken, Func<OAuth2AccessTokenResponse> tokenRenewalHandler)
            {
                if (IsAccessTokenValid(accessToken)) { return; }
                var oAuth2AccessTokenResponse = tokenRenewalHandler();
                var expiresOn = oAuth2AccessTokenResponse.ExpiresOn;
                if (expiresOn - oAuth2AccessTokenResponse.NotBefore > Constants.AccessTokenLifetimeTolerance)
                {
                    // Make the access token get renewed a bit earlier than the time when it expires
                    // so that the calls to SharePoint with it will have enough time to complete successfully.
                    expiresOn -= Constants.AccessTokenLifetimeTolerance;
                }
                accessToken = Tuple.Create(oAuth2AccessTokenResponse.AccessToken, expiresOn);
            }

        }

        public class CustomSharePointHighTrustContext : CustomSharePointContext
        {
            public WindowsIdentity LogonUserIdentity { get; }

            public override string UserAccessTokenForSPHost
            {
                get
                {
                    return GetAccessTokenString(ref _userAccessTokenForSPHost, () =>
                        TokenHelper.GetS2SAccessTokenWithWindowsIdentity(SPHostUrl, LogonUserIdentity));
                }
            }

            public override string AppOnlyAccessTokenForSPHost
            {
                get
                {
                    return GetAccessTokenString(ref _appOnlyAccessTokenForSPHost, () =>
                        TokenHelper.GetS2SAccessTokenWithWindowsIdentity(SPHostUrl, null));
                }
            }

            public override string UserAccessTokenForSPAppWeb
            {
                get
                {
                    return GetAccessTokenString(ref _userAccessTokenForSPAppWeb, () =>
                        TokenHelper.GetS2SAccessTokenWithWindowsIdentity(SPAppWebUrl, LogonUserIdentity));
                }
            }

            public override string AppOnlyAccessTokenForSPAppWeb
            {
                get
                {
                    return GetAccessTokenString(ref _appOnlyAccessTokenForSPAppWeb, () =>
                        TokenHelper.GetS2SAccessTokenWithWindowsIdentity(SPAppWebUrl, null));
                }
            }

            public CustomSharePointHighTrustContext(
                Uri spHostUrl,
                Uri spAppWebUrl,
                string spLanguage,
                string spClientTag,
                string spProductNumber,
                WindowsIdentity logonUserIdentity) :
                base(spHostUrl, spAppWebUrl, spLanguage, spClientTag, spProductNumber)
            {
                LogonUserIdentity = logonUserIdentity ?? throw new ArgumentNullException(nameof(logonUserIdentity));
            }

            private static string GetAccessTokenString(ref Tuple<string, DateTime> accessToken, Func<string> tokenRenewalHandler)
            {
                RenewAccessTokenIfNeeded(ref accessToken, tokenRenewalHandler);
                return IsAccessTokenValid(accessToken) ? accessToken.Item1 : null;
            }

            private static void RenewAccessTokenIfNeeded(ref Tuple<string, DateTime> accessToken, Func<string> tokenRenewalHandler)
            {
                if (IsAccessTokenValid(accessToken)) { return; }
                var expiresOn = DateTime.UtcNow.Add(TokenHelper.HighTrustAccessTokenLifetime);
                if (TokenHelper.HighTrustAccessTokenLifetime > Constants.AccessTokenLifetimeTolerance)
                {
                    // Make the access token get renewed a bit earlier than the time when it expires
                    // so that the calls to SharePoint with it will have enough time to complete successfully.
                    expiresOn -= Constants.AccessTokenLifetimeTolerance;
                }
                accessToken = Tuple.Create(tokenRenewalHandler(), expiresOn);
            }
        }

        #endregion Nested Contexts

        #region Abstracts

        public abstract string UserAccessTokenForSPHost { get; }
        public abstract string AppOnlyAccessTokenForSPHost { get; }
        public abstract string UserAccessTokenForSPAppWeb { get; }
        public abstract string AppOnlyAccessTokenForSPAppWeb { get; }

        #endregion Abstracts

        #region Properties

        public Uri SPHostUrl { get; }
        public Uri SPAppWebUrl { get; }
        public string SPLanguage { get; }
        public string SPClientTag { get; }
        public string SPProductNumber { get; }

        #endregion Properties

        #region Fields

        protected Tuple<string, DateTime> _userAccessTokenForSPAppWeb;
        protected Tuple<string, DateTime> _userAccessTokenForSPHost;
        protected Tuple<string, DateTime> _appOnlyAccessTokenForSPHost;
        protected Tuple<string, DateTime> _appOnlyAccessTokenForSPAppWeb;

        #endregion Fields

        protected CustomSharePointContext(Uri spHostUrl, Uri spAppWebUrl, string spLanguage, string spClientTag, string spProductNumber)
        {
            if (string.IsNullOrEmpty(spLanguage)) throw new ArgumentNullException(nameof(spLanguage));
            if (string.IsNullOrEmpty(spClientTag)) throw new ArgumentNullException(nameof(spClientTag));
            if (string.IsNullOrEmpty(spProductNumber)) throw new ArgumentNullException(nameof(spProductNumber));
            SPHostUrl = spHostUrl ?? throw new ArgumentNullException(nameof(spHostUrl));
            SPAppWebUrl = spAppWebUrl;
            SPLanguage = spLanguage;
            SPClientTag = spClientTag;
            SPProductNumber = spProductNumber;
        }

        [PublicAPI]
        public ClientContext CreateUserClientContextForSPHost()
        {
            return CreateClientContext(SPHostUrl, UserAccessTokenForSPHost);
        }

        [PublicAPI]
        public ClientContext CreateAppOnlyClientContextForSPHost()
        {
            return CreateClientContext(SPHostUrl, AppOnlyAccessTokenForSPHost);
        }

        [PublicAPI]
        public ClientContext CreateUserClientContextForSPAppWeb()
        {
            return CreateClientContext(SPAppWebUrl, UserAccessTokenForSPAppWeb);
        }

        [PublicAPI]
        public ClientContext CreateAppOnlyClientContextForSPAppWeb()
        {
            return CreateClientContext(SPAppWebUrl, AppOnlyAccessTokenForSPAppWeb);
        }

        [PublicAPI]
        public static Uri GetSPHostUrl(ISessionContext context)
        {
            if (null == context) throw new ArgumentNullException(nameof(context));
            return context.GetParam<string>(Constants.SPHostUrlKey).ToUri();
        }

        [PublicAPI]
        public static CustomSharePointContext GetSharePointContext(ISessionContext context)
        {
            if (null == context) throw new ArgumentNullException(nameof(context));
            return CustomSharePointContextProvider.Current.GetSharePointContext(context);
        }

        protected static bool IsAccessTokenValid(Tuple<string, DateTime> accessToken)
        {
            return !string.IsNullOrEmpty(accessToken?.Item1) && accessToken.Item2 > DateTime.UtcNow;
        }

        private static ClientContext CreateClientContext(Uri spSiteUrl, string accessToken)
        {
            if (null != spSiteUrl && !string.IsNullOrEmpty(accessToken))
                return TokenHelper.GetClientContextWithAccessToken(spSiteUrl.ToString(), accessToken);
            return null;
        }
    }
}
