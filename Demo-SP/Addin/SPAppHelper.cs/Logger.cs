using System;
using System.Reflection;

// Once per application.
[assembly: log4net.Config.XmlConfigurator(Watch = true)]

namespace SPAppHelper
{
    public static class Logger
    {
        private static readonly log4net.ILog _log =
            log4net.LogManager.GetLogger(MethodBase.GetCurrentMethod().DeclaringType);

        static Logger()
        {
            log4net.Config.XmlConfigurator.Configure();
        }

        public static void LogInfo(string message, params object[] pars)
        {
            if (!_log.IsInfoEnabled) return;
            _log.Info(string.Format(message, pars));
        }

        public static void LogWarn(string message, params object[] pars)
        {
            if (!_log.IsWarnEnabled) return;
            _log.Warn(string.Format(message, pars));
        }

        public static void LogError(string message, params object[] pars)
        {
            if (!_log.IsErrorEnabled) return;
            _log.Error(string.Format(message, pars));
        }

        public static void LogInfo(string message, Action del, params object[] pars)
        {
            if (null == del) throw new ArgumentNullException("del");
            LogInfo("BEGIN {0}", string.Format(message, pars));
            try
            {
                del();
            }
            finally
            {
                LogInfo("END {0}", string.Format(message, pars));
            }
        }

    }
}
