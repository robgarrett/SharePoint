using System;
using System.Diagnostics;
using Microsoft.SharePoint.Client.EventReceivers;

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
                        case SPRemoteEventType.ItemUpdated:
                            CreateSite(properties);
                            EnsureGroupsAndPermissions(properties);
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
                        case SPRemoteEventType.ItemAdding:
                            CreateSite(properties);
                            EnsureGroupsAndPermissions(properties);
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

        private static void CreateSite(SPRemoteEventProperties properties)
        {
            Logger.Logger.LogInfo("CreateSite in ListEventReceiver", () =>
            {
                if (null == properties) throw new ArgumentNullException("properties");
                using (var clientContext = TokenHelper.CreateRemoteEventReceiverClientContext(properties))
                {
                    if (clientContext == null) return;
                    // Get the unique site name.
                    var siteName = AppHelper.GetSiteUniqueName(clientContext,
                        properties.ItemEventProperties.AfterProperties);
                    if (String.IsNullOrEmpty(siteName)) return;
                    SPSiteCreateHelper.CreateSite(clientContext, siteName);
                }
            });
        }


        private static void EnsureGroupsAndPermissions(SPRemoteEventProperties properties)
        {
            Logger.Logger.LogInfo("EnsureGroupPermissions in ListEventReceiver", () =>
            {
                if (null == properties) throw new ArgumentNullException("properties");
                using (var clientContext = TokenHelper.CreateRemoteEventReceiverClientContext(properties))
                {
                    if (clientContext == null) return;
                    // Get the unique site name.
                    var siteName = AppHelper.GetSiteUniqueName(clientContext,
                        properties.ItemEventProperties.AfterProperties);
                    if (String.IsNullOrEmpty(siteName)) return;
                    SPPermissionsHelper.EnsureGroupsAndPermissions(clientContext, siteName);
                }
            });
        }        
    }
}
