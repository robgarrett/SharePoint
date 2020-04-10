using System;
using System.Security.Principal;

namespace SPContextHelper
{
    public interface ISessionContext
    {
        T GetParam<T>(string key) where T : IConvertible;
        void SetParam<T>(string key, T value) where T : IConvertible;
        Uri GetRequestUrl { get; }
        WindowsIdentity GetLogonUser { get; }
        string GetHttpMethod { get; }
    }
}
