using System.IO;
using System.Security.Cryptography;
using Microsoft.Identity.Client;

namespace DemoServicePrincipals
{
    internal static class TokenCacheHelper
    {
        private static TokenCache _tokenCache;
        public static readonly string CacheFilePath = @".\TokenCache.dat";
        private static readonly object FileLock = new object();

        public static TokenCache GetFilecache()
        {
            if (null != _tokenCache) return _tokenCache;
            _tokenCache = new TokenCache();
            _tokenCache.SetBeforeAccess(BeforeAccessNotification);
            _tokenCache.SetAfterAccess(AfterAccessNotification);
            lock (FileLock)
            {
                _tokenCache.Deserialize(File.Exists(CacheFilePath)
                    ? ProtectedData.Unprotect(File.ReadAllBytes(CacheFilePath), 
                        null, DataProtectionScope.CurrentUser)
                    : null);
            }
            return _tokenCache;
        }

        public static void Clear()
        {
            lock(FileLock)
                if (File.Exists(CacheFilePath)) File.Delete(CacheFilePath);
        }

        private static void BeforeAccessNotification(TokenCacheNotificationArgs args)
        {
            lock (FileLock)
            {
                args.TokenCache.Deserialize(File.Exists(CacheFilePath) ?
                    ProtectedData.Unprotect(File.ReadAllBytes(CacheFilePath), 
                        null, DataProtectionScope.CurrentUser) : 
                    null);
            }
        }

        private static void AfterAccessNotification(TokenCacheNotificationArgs args)
        {
            if (!args.TokenCache.HasStateChanged) return;
            lock (FileLock)
            {
                File.WriteAllBytes(CacheFilePath, ProtectedData.Protect(
                    args.TokenCache.Serialize(), null, DataProtectionScope.CurrentUser));
                args.TokenCache.HasStateChanged = false;
            }
        }
    }
}
