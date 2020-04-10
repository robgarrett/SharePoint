using System;
using Microsoft.SharePoint.Client;
using Microsoft.SharePoint.Client.EventReceivers;
using helper = SPAppHelper;

namespace DemoAppWeb.Services
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
            SPRemoteEventResult result = new SPRemoteEventResult();
            helper.Logger.LogInfo("ProcessEvent - {0}", () => {
                using (ClientContext clientContext = TokenHelper.CreateAppEventClientContext(properties, useAppWeb: false))
                {
                    if (clientContext != null)
                    {
                        if (properties.EventType == SPRemoteEventType.AppInstalled)
                        {
                            // Create the default demo document library and view.
                            helper.SPAppHelper.Instance.CreateDocumentLibrary(clientContext, Controllers.HomeController.DEFAULT_LIBNAME);
                            helper.SPAppHelper.Instance.CreateListView(clientContext, Controllers.HomeController.DEFAULT_LIBNAME, Controllers.HomeController.DEFAULT_VIEWNAME);
                            helper.SPAppHelper.Instance.CreateSitePage(clientContext, Controllers.HomeController.DEFAULT_PAGENAME, Controllers.HomeController.DEFAULT_LIBNAME);
                        }
                        else if (properties.EventType == SPRemoteEventType.AppUninstalling)
                        {
                            helper.SPAppHelper.Instance.RemoveDocumentLibrary(clientContext, Controllers.HomeController.DEFAULT_LIBNAME);
                            helper.SPAppHelper.Instance.RemoveSitePage(clientContext, Controllers.HomeController.DEFAULT_PAGENAME);
                        }
                    }
                }
            }, properties.EventType.ToString());
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
