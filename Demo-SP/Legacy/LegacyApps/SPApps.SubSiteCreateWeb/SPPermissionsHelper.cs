using System;
using System.Diagnostics;
using System.Linq;
using Microsoft.SharePoint.Client;

namespace SPApps.SubSiteCreateWeb
{
    static class SPPermissionsHelper
    {
        public static void EnsureGroupsAndPermissions(ClientContext clientContext, string siteName)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (String.IsNullOrEmpty(siteName)) throw new ArgumentNullException("siteName");
            // Determine if we're looking for a site collection, in which case leave groups & permissions alone.
            var useSC = AppHelper.GetProperty(clientContext, Constants.SITECOL_PROPERTY);
            var preferSiteCollection = useSC != null && 0 == String.Compare(useSC.ToString(), "TRUE",
                StringComparison.OrdinalIgnoreCase);
            if (preferSiteCollection) return;
            var uniquePerms = AppHelper.GetProperty(clientContext, Constants.UNIQUEPERMS_PROPERTY);
            var useUniqePerms = uniquePerms != null &&
                0 == String.Compare(uniquePerms.ToString(), "TRUE", StringComparison.OrdinalIgnoreCase);
            if (!useUniqePerms) return;
            SPSiteCreateHelper.ProcessSite(clientContext, siteName, w =>
            {
                // Create default group and assign group permissions.
                // ReSharper disable AccessToDisposedClosure
                CreateDefaultGroups(clientContext, w, siteName);
                AssignGroupPermissions(clientContext, w);
                // Get the participants and assigned to.
                var participants = AppHelper.GetSiteMembers();
                var assigned = AppHelper.GetSiteOwners();
                // Update the permissions.
                UpdatePermissions(clientContext, w, siteName, participants, assigned);
                // ReSharper restore AccessToDisposedClosure
            });
        }

        private static void CreateDefaultGroups(ClientContext clientContext, Web web, string siteName)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (null == web) throw new ArgumentNullException("web");
            if (String.IsNullOrEmpty(siteName)) return;
            // Create default groups
            var groups = new[] 
                    {
                        new GroupCreationInformation 
                        { 
                            Title = String.Format("{0} Owners", siteName),
                            Description = "Add users to this group to give them full control of the site."
                        },
                        new GroupCreationInformation 
                        { 
                            Title = String.Format("{0} Members", siteName),
                            Description = "Add users to this group to give them contributor access to the site."
                        },
                        new GroupCreationInformation 
                        { 
                            Title = String.Format("{0} Visitors", siteName),
                            Description = "Add users to this group to give them read access to the site."
                        }
                    };
            for (var i = 0; i < 3; i++)
            {
                try
                {
                    var group = web.SiteGroups.Add(groups[i]);
                    switch (i)
                    {
                        case 0:
                            web.AssociatedOwnerGroup = @group;
                            web.AssociatedOwnerGroup.Update();
                            break;
                        case 1:
                            web.AssociatedMemberGroup = @group;
                            web.AssociatedMemberGroup.Update();
                            break;
                        default:
                            web.AssociatedVisitorGroup = @group;
                            web.AssociatedVisitorGroup.Update();
                            break;
                    }
                    group.Update();
                    web.Update();
                    clientContext.ExecuteQuery();
                }
                catch (Exception ex)
                {
                    Debug.WriteLine(ex.ToString());
                    throw;
                }
            }
        }

        private static void AssignGroupPermissions(ClientContext clientContext, Web web)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (null == web) throw new ArgumentNullException("web");
            try
            {
                var roleAssignments = web.RoleAssignments;
                clientContext.Load(roleAssignments);
                clientContext.ExecuteQuery();
                // Owners
                var owner = web.RoleDefinitions.GetByType(RoleType.Administrator);
                var rdbOwners = new RoleDefinitionBindingCollection(clientContext) { owner };
                web.RoleAssignments.Add(web.AssociatedOwnerGroup, rdbOwners);
                web.Update();
                // Contributors.
                var contributor = web.RoleDefinitions.GetByType(RoleType.Contributor);
                var rdbMembers = new RoleDefinitionBindingCollection(clientContext) { contributor };
                web.RoleAssignments.Add(web.AssociatedMemberGroup, rdbMembers);
                web.Update();
                // Readers
                var reader = web.RoleDefinitions.GetByType(RoleType.Reader);
                var rdbVisitors = new RoleDefinitionBindingCollection(clientContext) { reader };
                web.RoleAssignments.Add(web.AssociatedVisitorGroup, rdbVisitors);
                web.Update();
                clientContext.ExecuteQuery();
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
                throw;
            }
        }

        private static void UpdatePermissions(ClientContext clientContext, Web web, string siteName, string participants, string assigned)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (null == web) throw new ArgumentNullException("web");
            if (String.IsNullOrEmpty(siteName)) return;
            try
            {
                // Make sure the particpants are in the members group.
                var participantUsernames = GetUsernames(participants);
                if (null != participantUsernames && participantUsernames.Length > 0)
                {
                    clientContext.Load(web, w => w.AssociatedMemberGroup, w => w.SiteGroups);
                    clientContext.ExecuteQuery();
                    var group = web.AssociatedMemberGroup;
                    if (null == group) throw new NullReferenceException("Member group not set on web");
                    EmptyGroup(clientContext, web, group);
                    foreach (var username in participantUsernames)
                        AssignUserToGroup(clientContext, web, group, username);
                }
                // Make sure the assigned are in the owners group.
                var assignedUsernames = GetUsernames(assigned);
                if (null != assignedUsernames && assignedUsernames.Length > 0)
                {
                    clientContext.Load(web, w => w.AssociatedOwnerGroup, w => w.SiteGroups);
                    clientContext.ExecuteQuery();
                    var group = web.AssociatedOwnerGroup;
                    if (null == group) throw new NullReferenceException("Owner group not set on web");
                    foreach (var username in assignedUsernames)
                        AssignUserToGroup(clientContext, web, group, username);
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
                throw;
            }
        }

        private static void AssignUserToGroup(ClientContext clientContext, Web web, Group group, string username)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (null == web) throw new ArgumentNullException("web");
            if (null == group) throw new ArgumentNullException("group");
            if (String.IsNullOrEmpty(username)) throw new ArgumentNullException("username");
            var user = web.EnsureUser(username);
            if (null == user) throw new Exception(String.Format("User {0} not found", username));
            clientContext.Load(user);
            clientContext.Load(group.Users);
            clientContext.ExecuteQuery();
            group.Users.AddUser(user);
            group.Update();
            clientContext.ExecuteQuery();
        }

        private static void EmptyGroup(ClientContext clientContext, Web web, Group group)
        {
            if (null == clientContext) throw new ArgumentNullException("clientContext");
            if (null == web) throw new ArgumentNullException("web");
            if (null == group) throw new ArgumentNullException("group");
            clientContext.Load(group.Users);
            clientContext.ExecuteQuery();
            while (group.Users.Count > 0)
            {
                var user = group.Users[0];
                clientContext.Load(user);
                clientContext.ExecuteQuery();
                group.Users.RemoveById(user.Id);
                group.Update();
                // Reload the list.
                clientContext.Load(group.Users);
                clientContext.ExecuteQuery();
            }
        }

        private static string[] GetUsernames(string usersString)
        {
            if (String.IsNullOrEmpty(usersString)) return null;
            var parts = usersString.Split(new[] { ";#" }, StringSplitOptions.None);
            if (parts.Length % 2 != 0) throw new FormatException("Users string is invalid");
            // Return just the odd values.
            return parts.Where((value, index) => index % 2 != 0).ToArray();
        }
    }
}