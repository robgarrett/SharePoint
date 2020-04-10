using System;
using Microsoft.SharePoint.Client.EventReceivers;

namespace SPApps.UpdateAppCatWeb.Services
{
    public class AppEventReceiver : IRemoteEventService
    {
        /// <summary>
        /// Handles app events that occur after the app is installed or upgraded, or when app is being uninstalled.
        /// </summary>
        /// <param name="properties">Holds information about the app event.</param>
        /// <returns>Holds information returned from the app event.</returns>
        public SPRemoteEventResult ProcessEvent(SPRemoteEventProperties properties)
        {
            var result = new SPRemoteEventResult();
            Logger.Logger.LogInfo("ProcessEvent called for AppEventReceiver", () =>
            {
                using (var clientContext = TokenHelper.CreateAppEventClientContext(properties, false))
                {
                    switch (properties.EventType)
                    {
                        case SPRemoteEventType.AppInstalled:
                            // Remove any old RER first.
                            AppHelper.UnregisterRemoteEvents(clientContext);
                            // Install a RER for the App Catalog.
                            AppHelper.RegisterRemoteEvents(clientContext);
                            // Iterate existing apps and process them.
                            AppHelper.ProcessAppList(clientContext);
                            break;
                        case SPRemoteEventType.AppUninstalling:
                            // Remove RER from the App Catalog.
                            AppHelper.UnregisterRemoteEvents(clientContext);
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
            throw new NotImplementedException();
        }

    }
}
