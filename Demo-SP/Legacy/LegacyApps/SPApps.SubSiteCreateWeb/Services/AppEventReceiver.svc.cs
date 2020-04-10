using Microsoft.SharePoint.Client.EventReceivers;

namespace SPApps.SubSiteCreateWeb.Services
{
    public class AppEventReceiver : IRemoteEventService
    {
        public SPRemoteEventResult ProcessEvent(SPRemoteEventProperties properties)
        {
            var result = new SPRemoteEventResult();
            Logger.Logger.LogInfo("ProcessEvent called for AppEventReceiver", () =>
            {
                // Deal with application installed event.
                switch (properties.EventType)
                {
                    case SPRemoteEventType.AppInstalled:
                    case SPRemoteEventType.AppUninstalling:
                        using (var clientContext = TokenHelper.CreateAppEventClientContext(properties, false))
                            AppHelper.UnregisterRemoteEvents(clientContext);
                        break;
                }
            });
            return result;
        }

        public void ProcessOneWayEvent(SPRemoteEventProperties properties)
        {
            // This method is not used by app events
        }

    }
}
