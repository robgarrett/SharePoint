using Microsoft.SharePoint.Client;
using System;
using System.Xml;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO.Compression;
using System.ServiceModel;

namespace SPApps.UpdateAppCatWeb
{
    static class AppHelper
    {
        private const string LISTNAME = "Apps for SharePoint";
        private const string RERNAME = "Apps_Remote_Event_Receiver";

        public static void TouchExistingApps(ClientContext clientContext)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            try
            {
                Logger.Logger.LogInfo("Touching existing apps", () =>
                {
                    var appCat = clientContext.Web.Lists.GetByTitle(LISTNAME);
                    clientContext.Load(clientContext.Web);
                    clientContext.Load(appCat);
                    var query = CamlQuery.CreateAllItemsQuery();
                    var items = appCat.GetItems(query);
                    clientContext.Load(items);
                    clientContext.ExecuteQuery();
                    foreach (var item in items)
                        item.Update();
                    clientContext.ExecuteQuery();
                });
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
                Logger.Logger.LogError(ex.ToString());
            }
        }

        public static void RegisterRemoteEvents(ClientContext clientContext)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            try
            {
                // Get the Apps List.
                Logger.Logger.LogInfo("Registering remote events", () =>
                {
                    var appCat = clientContext.Web.Lists.GetByTitle(LISTNAME);
                    clientContext.Load(clientContext.Web);
                    clientContext.ExecuteQuery();
                    // Get the operation context and remote event service URL.
                    var remoteUrl = GetServiceUrl("ListEventReceiver.svc");
                    // Add RER for Item Added.
                    if (!IsRemoteEventRegistered(clientContext, EventReceiverType.ItemAdded))
                    {
                        appCat.EventReceivers.Add(new EventReceiverDefinitionCreationInformation
                        {
                            EventType = EventReceiverType.ItemAdded,
                            ReceiverName = RERNAME,
                            ReceiverUrl = remoteUrl,
                            SequenceNumber = 10000,
                            Synchronization = EventReceiverSynchronization.Synchronous
                        });
                        clientContext.ExecuteQuery();
                    }
                    // Add RER for Item Updated
                    if (IsRemoteEventRegistered(clientContext, EventReceiverType.ItemUpdated)) return;
                    appCat.EventReceivers.Add(new EventReceiverDefinitionCreationInformation
                    {
                        EventType = EventReceiverType.ItemUpdated,
                        ReceiverName = RERNAME,
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
                    var srcList = clientContext.Web.Lists.GetByTitle(LISTNAME);
                    clientContext.Load(clientContext.Web);
                    clientContext.ExecuteQuery();
                    // Iterate all event receivers.
                    clientContext.Load(srcList.EventReceivers);
                    clientContext.ExecuteQuery();
                    foreach (var er in srcList.EventReceivers)
                        if (0 == string.Compare(er.ReceiverName, RERNAME, true, CultureInfo.CurrentCulture) && er.EventType == type)
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
                Logger.Logger.LogInfo("Unregistering remote events", () =>
                {
                    // Get the App Catalog.
                    var appCat = clientContext.Web.Lists.GetByTitle(LISTNAME);
                    clientContext.Load(clientContext.Web);
                    clientContext.ExecuteQuery();
                    // Remove all event receivers.
                    clientContext.Load(appCat.EventReceivers);
                    clientContext.ExecuteQuery();
                    var toDelete = new List<EventReceiverDefinition>();
                    // ReSharper disable once LoopCanBeConvertedToQuery
                    foreach (var er in appCat.EventReceivers)
                    {
                        if (er.ReceiverName == RERNAME) toDelete.Add(er);
                    }
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

        internal static void ProcessAppList(ClientContext clientContext)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            try
            {
                Logger.Logger.LogInfo("Processing app catalog", () =>
                {
                    // Get the App Catalog and App List Item.
                    var appCat = clientContext.Web.Lists.GetByTitle(LISTNAME);
                    clientContext.Load(clientContext.Web);
                    clientContext.Load(appCat);
                    var query = CamlQuery.CreateAllItemsQuery();
                    var items = appCat.GetItems(query);
                    clientContext.Load(items);
                    clientContext.ExecuteQuery();
                    foreach (var item in items)
                        ProcessAppListItem(clientContext, item);
                });
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
                Logger.Logger.LogError(ex.ToString());
            }
        }

        internal static void ProcessAppListItem(ClientContext clientContext, int itemID)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (itemID <= 0) throw new ArgumentOutOfRangeException("itemID");
            try {
                // Get the App Catalog and App List Item.
                var appCat = clientContext.Web.Lists.GetByTitle(LISTNAME);
                clientContext.Load(clientContext.Web);
                clientContext.Load(appCat);
                var item = appCat.GetItemById(itemID);
                clientContext.Load(item);
                clientContext.ExecuteQuery();
                ProcessAppListItem(clientContext, item);
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
                Logger.Logger.LogError(ex.ToString());
            }
        }

        internal static void ProcessAppListItem(ClientContext clientContext, ListItem item)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (null == item) throw new ArgumentNullException("item");
            try
            {
                Logger.Logger.LogInfo("Processing list item with ID {0}", () => {
                    clientContext.Load(item.File);
                    var stream = item.File.OpenBinaryStream();
                    clientContext.ExecuteQuery();
                    var fileInfo = new FileSaveBinaryInformation();
                    fileInfo.ContentStream = new System.IO.MemoryStream();
                    // Load the app manifest file.
                    ProcessManifest(stream.Value, fileInfo.ContentStream, (manifest, ns) => {
                        // Load the properties.
                        var propNode = manifest.SelectSingleNode("x:App/x:Properties", ns);
                        // Look for the endpoints.
                        var installedNode = propNode.SelectSingleNode("x:InstalledEventEndpoint", ns);
                        var upgradedNode = propNode.SelectSingleNode("x:UpgradedEventEndpoint", ns);
                        var uninstalledNode = propNode.SelectSingleNode("x:UninstallingEventEndpoint", ns);
                        if (null == installedNode)
                        {
                            installedNode = manifest.CreateElement("InstalledEventEndpoint", manifest.DocumentElement.NamespaceURI);
                            propNode.AppendChild(installedNode);
                        }
                        if (null == upgradedNode)
                        {
                            upgradedNode = manifest.CreateElement("UpgradedEventEndpoint", manifest.DocumentElement.NamespaceURI);
                            propNode.AppendChild(upgradedNode);
                        }
                        if (null == uninstalledNode)
                        {
                            uninstalledNode = manifest.CreateElement("UninstallingEventEndpoint", manifest.DocumentElement.NamespaceURI);
                            propNode.AppendChild(uninstalledNode);
                        }
                        // NOTE: We're replacing the app installing and upgrading events so we can manage app lifecycle.
                        // If the deployed originally used these events, we've overridden them.
                        installedNode.InnerText = GetServiceUrl("AppMgmtReceiver.svc");
                        upgradedNode.InnerText = GetServiceUrl("AppMgmtReceiver.svc");
                        uninstalledNode.InnerText = GetServiceUrl("AppMgmtReceiver.svc");
                    });
                    // Save the manifest back to SharePoint.
                    fileInfo.ContentStream.Seek(0, System.IO.SeekOrigin.Begin);
                    item.File.SaveBinary(fileInfo);
                    clientContext.Load(item.File);
                    clientContext.ExecuteQuery();
                }, item.Id);
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
                Logger.Logger.LogError(ex.ToString());
            }
        }

        private static void ProcessManifest(System.IO.Stream inStream, System.IO.Stream outStream, Action<XmlDocument, XmlNamespaceManager> manifestDel)
        {
            if (null == inStream) throw new ArgumentNullException("inStream");
            if (null == outStream) throw new ArgumentNullException("outStream");
            if (null == manifestDel) throw new ArgumentNullException("manifestDel");
            using (var memory = new System.IO.MemoryStream())
            {
                var buffer = new byte[1024 * 64];
                int nread = 0, total = 0;
                while ((nread = inStream.Read(buffer, 0, buffer.Length)) > 0)
                {
                    memory.Write(buffer, 0, nread);
                    total += nread;
                }
                memory.Seek(0, System.IO.SeekOrigin.Begin);
                // Open the app manifest.
                using (var zipArchive = new ZipArchive(memory, ZipArchiveMode.Update, true))
                {
                    var entry = zipArchive.GetEntry("AppManifest.xml");
                    if (null == entry) throw new Exception("Could not find AppManifest.xml in the app archive");
                    var manifest = new XmlDocument();
                    using (var sr = new System.IO.StreamReader(entry.Open()))
                    {
                        manifest.LoadXml(sr.ReadToEnd());
                        sr.Close();
                    }
                    var ns = new XmlNamespaceManager(manifest.NameTable);
                    ns.AddNamespace("x", "http://schemas.microsoft.com/sharepoint/2012/app/manifest");
                    // Call the delegate.
                    manifestDel(manifest, ns);
                    // Write back to the archive.
                    using (var sw = new System.IO.StreamWriter(entry.Open()))
                    {
                        sw.Write(manifest.OuterXml);
                        sw.Close();
                    }
                }
                // Memory stream now contains the updated archive
                memory.Seek(0, System.IO.SeekOrigin.Begin);
                // Write result to output stream.
                buffer = new byte[1024 * 64];
                nread = 0; total = 0;
                while ((nread = memory.Read(buffer, 0, buffer.Length)) > 0)
                {
                    outStream.Write(buffer, 0, nread);
                    total += nread;
                }
            }
        }

        private static string GetServiceUrl(string serviceEndpoint)
        {
            if (string.IsNullOrEmpty(serviceEndpoint)) throw new ArgumentNullException("serviceEndpoint");
            if (null == OperationContext.Current) throw new Exception("Could not get service URL from the operational context.");
            var url = OperationContext.Current.Channel.LocalAddress.Uri.AbsoluteUri;
            var opContext = url.Substring(0, url.LastIndexOf("/", StringComparison.Ordinal));
            return string.Format("{0}/{1}", opContext, serviceEndpoint);
        }
    }
}