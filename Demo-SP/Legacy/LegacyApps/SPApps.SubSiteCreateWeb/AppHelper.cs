using System.Diagnostics;
using Microsoft.SharePoint.Client;
using System;
using System.Collections.Generic;
using System.ServiceModel;
using System.Web;

namespace SPApps.SubSiteCreateWeb
{
    static class AppHelper
    {
        public static void RegisterRemoteEvents(ClientContext clientContext)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            try
            {
                // Get the list
                Logger.Logger.LogInfo("Registering Remote Events", () =>
                {
                    var listName = GetProperty(clientContext, Constants.LISTNAME_PROPERTY) as string;
                    if (String.IsNullOrEmpty(listName)) return;
                    var srcList = clientContext.Web.Lists.GetByTitle(listName);
                    clientContext.Load(clientContext.Web);
                    clientContext.ExecuteQuery();
                    // Get the operation context and remote event service URL.
                    string remoteUrl;
                    if (null != OperationContext.Current)
                    {
                        var url = OperationContext.Current.Channel.LocalAddress.Uri.AbsoluteUri;
                        var opContext = url.Substring(0, url.LastIndexOf("/", StringComparison.Ordinal));
                        remoteUrl = String.Format("{0}/ListEventReceiver.svc", opContext);
                    }
                    else if (null != HttpContext.Current)
                    {
                        var url = GetSiteRoot();
                        var opContext = url.Substring(0, url.LastIndexOf("/", StringComparison.Ordinal));
                        remoteUrl = String.Format("{0}/Services/ListEventReceiver.svc", opContext);
                    }
                    else
                        return;
                    // Register the remote event receiver for the host web.
                    if (!IsRemoteEventRegistered(clientContext, EventReceiverType.ItemAdding))
                    {
                        srcList.EventReceivers.Add(new EventReceiverDefinitionCreationInformation
                                {
                                    EventType = EventReceiverType.ItemAdding,
                                    ReceiverName = Constants.LISTEVTRCVR_NAME,
                                    ReceiverUrl = remoteUrl,
                                    SequenceNumber = 10000
                                });
                        clientContext.ExecuteQuery();
                    }
                    if (IsRemoteEventRegistered(clientContext, EventReceiverType.ItemUpdated)) return;
                    srcList.EventReceivers.Add(new EventReceiverDefinitionCreationInformation
                    {
                        EventType = EventReceiverType.ItemUpdated,
                        ReceiverName = Constants.LISTEVTRCVR_NAME,
                        ReceiverUrl = remoteUrl,
                        SequenceNumber = 10001
                    });
                    clientContext.ExecuteQuery();
                });
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
                Logger.Logger.LogError(ex.ToString());
            }
        }

        public static bool IsRemoteEventRegistered(ClientContext clientContext, EventReceiverType type)
        {
            var result = false;
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            try
            {
                // Get the list
                Logger.Logger.LogInfo("Checking if remote events registered", () =>
                {
                    var listName = GetProperty(clientContext, Constants.LISTNAME_PROPERTY) as string;
                    if (String.IsNullOrEmpty(listName)) return;
                    var srcList = clientContext.Web.Lists.GetByTitle(listName);
                    clientContext.Load(clientContext.Web);
                    clientContext.ExecuteQuery();
                    // Iterate all event receivers.
                    clientContext.Load(srcList.EventReceivers);
                    clientContext.ExecuteQuery();
                    // ReSharper disable once LoopCanBeConvertedToQuery
                    foreach (var er in srcList.EventReceivers)
                        if (er.ReceiverName == Constants.LISTEVTRCVR_NAME && er.EventType == type)
                        {
                            result = true;
                            break;
                        }
                });
                return result;
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
                Logger.Logger.LogError(ex.ToString());
            }
            return false;
        }

        public static void UnregisterRemoteEvents(ClientContext clientContext)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            try
            {
                Logger.Logger.LogInfo("unregistering remote events", () =>
                {
                    // Get the list
                    var listName = GetProperty(clientContext, Constants.LISTNAME_PROPERTY) as string;
                    if (String.IsNullOrEmpty(listName)) return;
                    var srcList = clientContext.Web.Lists.GetByTitle(listName);
                    clientContext.Load(clientContext.Web);
                    clientContext.ExecuteQuery();
                    // Remove all event receivers.
                    clientContext.Load(srcList.EventReceivers);
                    clientContext.ExecuteQuery();
                    var toDelete = new List<EventReceiverDefinition>();
                    // ReSharper disable once LoopCanBeConvertedToQuery
                    foreach (var er in srcList.EventReceivers)
                        if (er.ReceiverName == Constants.LISTEVTRCVR_NAME)
                            toDelete.Add(er);
                    foreach (var er in toDelete)
                    {
                        er.DeleteObject();
                        clientContext.ExecuteQuery();
                    }
                });
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
                Logger.Logger.LogError(ex.ToString());
            }
        }

        public static bool CurrentUserIsAdmin(ClientContext clientContext)
        {
            var result = false;
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            try
            {
                Logger.Logger.LogInfo("Is Current User an Admin?", () =>
                {
                    clientContext.Load(clientContext.Web);
                    clientContext.Load(clientContext.Web.CurrentUser);
                    clientContext.ExecuteQuery();
                    result = clientContext.Web.CurrentUser.IsSiteAdmin;
                });
                return result;
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
                Logger.Logger.LogError(ex.ToString());
                return false;
            }
        }

        public static void SetProperty(ClientContext clientContext, string key, object value)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (String.IsNullOrEmpty(key)) throw new ArgumentNullException("key");
            try
            {
                Logger.Logger.LogInfo("Set Property Value {0} {1}", () =>
                {
                    // TODO: Append the app ID so we can use multiple instances.
                    clientContext.Load(clientContext.Web);
                    clientContext.Load(clientContext.Web.AllProperties);
                    clientContext.ExecuteQuery();
                    clientContext.Web.AllProperties[key] = value;
                    clientContext.Web.Update();
                    clientContext.ExecuteQuery();
                }, key, value);
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
                Logger.Logger.LogError(ex.ToString());
            }
        }

        public static object GetProperty(ClientContext clientContext, string key)
        {
            object result = null;
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (String.IsNullOrEmpty(key)) throw new ArgumentNullException("key");
            try
            {
                Logger.Logger.LogInfo("Getting Property Value {0}", () =>
                {
                    // TODO: Append the app ID so we can use multiple instances.
                    clientContext.Load(clientContext.Web);
                    clientContext.Load(clientContext.Web.AllProperties);
                    clientContext.ExecuteQuery();
                    result = clientContext.Web.AllProperties.FieldValues.ContainsKey(key)
                        ? clientContext.Web.AllProperties[key]
                        : null;
                }, key);
                return result;
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
                Logger.Logger.LogError(ex.ToString());
                return null;
            }
        }

        public static string GetSiteUniqueName(ClientContext clientContext, Dictionary<string, object> properties)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            try
            {
                var fieldName = GetProperty(clientContext, Constants.FIELDNAME_PROPERTY) as string;
                return String.IsNullOrEmpty(fieldName) ? null : properties[fieldName].ToString();
            }
            catch (Exception ex)
            {
                Logger.Logger.LogError(ex.ToString());
                return null;
            }
        }

        public static string GetSiteOwners()
        {
            // TODO: Add ability to get site owners later.
            return String.Empty;
        }

        public static string GetSiteMembers()
        {
            // TODO: Add ability to get site members later.
            return String.Empty;
        }

        private static string GetSiteRoot()
        {
            if (HttpContext.Current == null) return null;
            var request = HttpContext.Current.Request;
            var siteRoot = request.Url.AbsoluteUri
                .Replace(request.Url.AbsolutePath, String.Empty)        // trim the current page off
                .Replace(request.Url.Query, string.Empty);              // trim the query string off
            if (request.Url.Segments.Length == 4)
                // If hosted in a virtual directory, restore that segment
                siteRoot += "/" + request.Url.Segments[1];
            if (!siteRoot.EndsWith("/"))
                siteRoot += "/";
            return siteRoot;
        }
    }
}