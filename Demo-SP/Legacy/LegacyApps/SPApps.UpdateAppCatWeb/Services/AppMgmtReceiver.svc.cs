using System;
using Microsoft.SharePoint.Client.EventReceivers;

namespace SPApps.UpdateAppCatWeb.Services
{
    public class AppMgmtReceiver : IRemoteEventService
    {
        /// <summary>
        /// Handles app events that occur after the app is installed or upgraded, or when app is being uninstalled.
        /// </summary>
        /// <param name="properties">Holds information about the app event.</param>
        /// <returns>Holds information returned from the app event.</returns>
        public SPRemoteEventResult ProcessEvent(SPRemoteEventProperties properties)
        {
            var result = new SPRemoteEventResult();
            Logger.Logger.LogInfo("ProcessEvent called for AppMgmtReceiver", () =>
            {
                using (var clientContext = TokenHelper.CreateAppEventClientContext(properties, false))
                {
                    switch (properties.EventType)
                    {
                        case SPRemoteEventType.AppInstalled:
                            result.Status = SPRemoteEventServiceStatus.CancelWithError;
                            result.ErrorMessage = "You are not allowed to install this app!";
                            break;
                        case SPRemoteEventType.AppUpgraded:
                            break;
                    }
                }
            });
            return result;
        }

        /// <summary>
        /// This method is a required placeholder, but is not used by app events.
        /// </summary>
        /// <param name="properties">Unused.</param>
        public void ProcessOneWayEvent(SPRemoteEventProperties properties)
        {
            var result = new SPRemoteEventResult();
            Logger.Logger.LogInfo("ProcessEvent called for AppMgmtReceiver", () =>
            {
                using (var clientContext = TokenHelper.CreateAppEventClientContext(properties, false))
                {
                    switch (properties.EventType)
                    {
                        case SPRemoteEventType.AppInstalled:
                            break;
                        case SPRemoteEventType.AppUpgraded:
                            break;
                    }
                }
            });
        }

    }
}
