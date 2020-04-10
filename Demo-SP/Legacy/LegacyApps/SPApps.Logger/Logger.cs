using System;
using System.Reflection;

namespace SPApps.Logger
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
            _log.Info(String.Format(message, pars));
        }

        public static void LogWarn(string message, params object[] pars)
        {
            if (!_log.IsWarnEnabled) return;
            _log.Warn(String.Format(message, pars));
        }

        public static void LogError(string message, params object[] pars)
        {
            if (!_log.IsErrorEnabled) return;
            _log.Error(String.Format(message, pars));
        }

        public static void LogInfo(string message, Action del, params object[] pars)
        {
            if (null == del) throw new ArgumentNullException("del");
            LogInfo("BEGIN {0}", String.Format(message, pars));
            try
            {
                del();
            }
            finally
            {
                LogInfo("END {0}", String.Format(message, pars));
            }
        }
    }
}
