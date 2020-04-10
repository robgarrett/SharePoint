using System;
using System.Diagnostics;
using Microsoft.SharePoint.Client.EventReceivers;
using SPApps.UpdateAppCatWeb;

namespace SPApps.SubSiteCreateWeb.Services
{
    public class ListEventReceiver : IRemoteEventService
    {
        public void ProcessOneWayEvent(SPRemoteEventProperties properties)
        {
            Logger.Logger.LogInfo("ProcessOneWayEvent called on ListEventReceiver", () =>
            {
                if (null == properties) throw new ArgumentNullException("properties");
                try
                {
                    switch (properties.EventType)
                    {
                        case SPRemoteEventType.ItemAdded:
                            break;
                    }
                }
                catch (Exception ex)
                {
                    Logger.Logger.LogError(ex.ToString());
                    Debug.WriteLine(ex.ToString());
                }
            });
        }

        public SPRemoteEventResult ProcessEvent(SPRemoteEventProperties properties)
        {
            var result = new SPRemoteEventResult();
            Logger.Logger.LogInfo("ProcessEvent called on ListEventReceiver", () =>
            {
                if (null == properties) throw new ArgumentNullException("properties");
                try
                {
                    switch (properties.EventType)
                    {
                        case SPRemoteEventType.ItemAdded:
                            using (var clientContext = TokenHelper.CreateRemoteEventReceiverClientContext(properties))
                                AppHelper.ProcessAppListItem(clientContext, properties.ItemEventProperties.ListItemId);
                            break;
                    }

                }
                catch (Exception ex)
                {
                    Logger.Logger.LogError(ex.ToString());
                    Debug.WriteLine(ex.ToString());
                }
            });
            return result;
        }
    }
}
