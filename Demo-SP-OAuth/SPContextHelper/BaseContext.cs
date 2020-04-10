using System;

namespace SPContextHelper
{
    public abstract class BaseContext
    {
        protected static T ConvertFromString<T>(string val) where T : IConvertible
        {
            if (null == val) return default(T);
            return (T)Convert.ChangeType(val, typeof(T));
        }
    }
}
