#################################
# SharePoint Analyze Functions

$global:scriptPath = split-path $SCRIPT:MyInvocation.MyCommand.Path -parent;
$global:streamWriter = $null;
$global:xmlWriter = $null;

function IterateList {
    param(
        [Parameter(Mandatory=$true)][Microsoft.SharePoint.Client.ClientContext]$context,
        [Parameter(Mandatory=$true)][Microsoft.SharePoint.Client.List]$list,
        [Parameter()][scriptblock]$eachListItem);
    $context.Load($list);
    $context.Load($list.RootFolder);
    $context.ExecuteQuery();
    if ($eachListItem -ne $null) {
        $query = New-Object Microsoft.SharePoint.Client.CamlQuery;
        $query.ViewXml = "<View><RowLimit>200</RowLimit></View>";
        do {
            $listItems = $list.getItems($query);
            $context.Load($listItems);
            $context.ExecuteQuery();
            $query.ListItemCollectionPosition = $listItems.ListItemCollectionPosition;
            $listItems | % {
                . $eachListItem -context $context -listItem $_;          
            }
        }
        while($query.ListItemCollectionPosition -ne $null);
    }
}

function AnalyzeLoadCSOM {
    try {
        $sPath = $global:scriptPath;
        Write-Verbose "Loading CSOM client DLLs";
        $asm1 = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client");
        $asm2 = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client.Runtime");
        if ($asm1 -eq $null -or $asm2 -eq $null) {
            throw "Cannot find Microsoft.SharePoint.Client or Microsoft.SharePoint.Client.Runtime in the GAC";
        }        
        $assemblies = @( $asm1.FullName, $asm2.FullName, "System.Core");
        $csharp = "
          using Microsoft.SharePoint.Client;
          namespace SharePointClient
          {
              public class PSClientContext: ClientContext
              {
                  public PSClientContext(string siteUrl) : base(siteUrl) {}
                  // need a plain Load method here, the base method is a generic method
                  // which isn't supported in PowerShell.
                  public void Load(ClientObject objectToLoad)
                  { base.Load(objectToLoad); }
              }
          }"
        Write-Verbose "Loading custom loader class";
        Add-Type -TypeDefinition $csharp -ReferencedAssemblies $assemblies;
    } catch {
        Write-Host -ForegroundColor Red $_.Exception;
    }
}

function CreateXmlWriter {
    try {
        Write-Verbose "Creating XmlWriter";
        $settings = New-Object System.Xml.XmlWriterSettings;
        $settings.Indent = $true;
        $settings.OmitXmlDeclaration = $false;
        $global:streamWriter = New-Object System.IO.StreamWriter -ArgumentList "$global:scriptPath\report.xml", $false;
        $global:xmlWriter = [System.Xml.XmlWriter]::Create($global:streamWriter, $settings);
        
    } catch {
        Write-Host -ForegroundColor Red $_.Exception;
    }
}

function xwStart {
    $global:xmlWriter.WriteStartElement($args[0]);
    for($i = 1; $i -lt $args.Count; $i += 2) {
        $global:xmlWriter.WriteAttributeString($args[$i], $args[($i+1)]);
    }
}

function xwEmpty {
    $global:xmlWriter.WriteStartElement($args[0]);
    for($i = 1; $i -lt $args.Count; $i += 2) {
        $global:xmlWriter.WriteAttributeString($args[$i], $args[($i+1)]);
    }
    $global:xmlWriter.WriteEndElement();
}

function xwEnd {
    $global:xmlWriter.WriteEndElement();
}

function AnalyzeSiteCollections {
    try {
        CreateXmlWriter;
        xwStart "Report";
        Write-Verbose "Iterating site collections";
        $global:siteCollections | % { 
            try {
                $siteUrl = $_;
                xwStart "Site" "url" $siteUrl;
                Write-Verbose "Getting client context for $siteUrl";
                $context = New-Object SharePointClient.PSClientContext($siteUrl);
                if ($context -eq $null) { throw "Unable to get context for $siteUrl"; }
                $site = $context.Site;
                $context.Load($site);
                $context.Load($site.RootWeb);
                $context.ExecuteQuery();
                Write-Verbose "Opened site collection $($site.Url)";
                $rootWeb = $site.RootWeb;
                $context.Load($rootWeb);
                $context.ExecuteQuery();
                Write-Verbose "Opened RootWeb $($rootWeb.Title)";
                AnalyzeSiteCollectionAdmins -context $context -site $site;
                AnalyzeGroups -context $context -web $site.RootWeb;
                AnalyzeSiteCollectionFeatures -context $context -site $site;
                xwStart "Webs";
                AnalyzeWeb -context $context -web $site.RootWeb;
                xwEnd;
            } catch {
                Write-Host -ForegroundColor Red $_.Exception;
            } finally {
                xwEnd;
            }
        }
    } finally {
        $global:xmlWriter.WriteEndElement();
        $global:xmlWriter.Close();
        $global:streamWriter.Close();
        $global:xmlWriter.Dispose();
        $global:streamWriter.Dispose();
    }
}

function AnalyzeSiteCollectionFeatures {
    param(
        [Parameter(Mandatory=$true)][Microsoft.SharePoint.Client.ClientContext]$context,
        [Parameter(mandatory=$true)][Microsoft.SharePoint.Client.Site]$site);
    Write-Verbose "Iterating Site Collection Features";
    xwStart "Features";
    try {
        $context.Load($site.Features);
        $context.ExecuteQuery();
        $site.Features | % {
            Write-Verbose "Found site collection feature with ID $($_.DefinitionId)";
            xwEmpty "Feature" "scope" "Site" "id" $_.DefinitionId;
        }
    } catch {
        Write-Verbose "Unable to get site collection features for $($site.Url)";
    } finally {
        xwEnd;
    }
}

function AnalyzeSiteCollectionAdmins {
    param(
        [Parameter(Mandatory=$true)][Microsoft.SharePoint.Client.ClientContext]$context,
        [Parameter(mandatory=$true)][Microsoft.SharePoint.Client.Site]$site);
    Write-Verbose "Getting site collection administrators";
    xwStart "SiteAdmins";
    try {
        $context.Load($site.RootWeb.SiteUserInfoList);
        $context.ExecuteQuery();
        IterateList -context $context -list $site.RootWeb.SiteUserInfoList -eachListItem {
            param(
                [Parameter(Mandatory=$true)][Microsoft.SharePoint.Client.ClientContext]$context,
                [Parameter(mandatory=$true)][Microsoft.SharePoint.Client.ListItem]$listItem);
            if ($listItem["IsSiteAdmin"] -eq $true) {
                Write-Verbose "Found site admin $($listItem["Title"]) ($($listItem["Name"]))";
                xwEmpty "SiteAdmin" "title" ($listItem["Title"]) "login" ($listItem["Name"])
            }
        }
    } catch {
        Write-Verbose "Unable to get site collection admins for $($site.Url)";
    } finally {
        xwEnd;   
    }
}

function AnalyzeWeb {
    param(
        [Parameter(Mandatory=$true)][Microsoft.SharePoint.Client.ClientContext]$context,
        [Parameter(mandatory=$true)][Microsoft.SharePoint.Client.Web]$web);
    Write-Verbose "Analyzing web $($web.ServerRelativeUrl)";
    xwStart "Web" "url" $web.ServerRelativeUrl;
    try {
        $context.Load($web.Webs);
        $context.Load($web.Features);
        $context.ExecuteQuery();
        # Default Groups
        AssociatedGroups -context $context -web $web;
        # Features
        xwStart "Features";
        try {
            $web.Features | % {
                Write-Verbose "Found web feature with ID $($_.DefinitionId)";
                xwEmpty "Feature" "scope" "Web" "id" $_.DefinitionId;
            }
        } finally {
            xwEnd;
        }
        # Permissions
        AnalyzePermissions -context $context -web $web;
        # Iterate sub webs.
        xwStart "Webs";
        try {
            $web.Webs | % {
                $childWeb = $_;
                $context.Load($childWeb);
                $context.ExecuteQuery();
                AnalyzeWeb -context $context -web $childWeb;    
            }
        } finally {
            xwEnd;
        }

    } catch {
        Write-Verbose "Unable to process web $($web.ServerRelativeUrl)";
    } finally {
        xwEnd;
    }
}

function AssociatedGroups {
    param(
        [Parameter(Mandatory=$true)][Microsoft.SharePoint.Client.ClientContext]$context,
        [Parameter(mandatory=$true)][Microsoft.SharePoint.Client.Web]$web);
    Write-Verbose "Getting web associated groups";
    xwStart "AssociatedGroups";
    try {
        $context.Load($web.AssociatedMemberGroup);
        $context.Load($web.AssociatedOwnerGroup);
        $context.Load($web.AssociatedVisitorGroup);
        $context.ExecuteQuery();
        xwEmpty "Group" "type" "Members" "name" $web.AssociatedMemberGroup.Title;
        xwEmpty "Group" "type" "Owners" "name" $web.AssociatedOwnerGroup.Title; 
        xwEmpty "Group" "type" "Visitors" "name" $web.AssociatedVisitorGroup.Title; 
    } catch {
        Write-Verbose "Unable to get associated groups for $($web.ServerRelativeUrl)";
    } finally {
        xwEnd;
    }
}

function AnalyzeGroups {
    param(
        [Parameter(Mandatory=$true)][Microsoft.SharePoint.Client.ClientContext]$context,
        [Parameter(mandatory=$true)][Microsoft.SharePoint.Client.Web]$web);
    Write-Verbose "Getting groups";
    xwStart "Groups";
    try {
        $context.Load($web.SiteGroups);
        $context.ExecuteQuery();
        $web.SiteGroups | % {
            $group = $_;
            $context.Load($group);
            $context.ExecuteQuery();
            Write-Verbose "Found web group $($group.Title)";
            xwStart "Group" "title" $group.Title;
            # Iterate users in each group.
            $groupUsers = $group.Users;
            $context.Load($groupUsers);
            $context.ExecuteQuery();
            $groupUsers | % {
                Write-Verbose "Found user $($_.LoginName) in group $($group.Title)";
                xwEmpty "User" "id" $_.Id "title" $_.Title "login" $_.LoginName;
            }
            xwEnd;
        };
    } catch { 
        Write-Verbose "Unable to get groups for web $($web.ServerRelativeUrl)";
    } finally {
        xwEnd;
    }
}

function AnalyzePermissions {
    param(
        [Parameter(Mandatory=$true)][Microsoft.SharePoint.Client.ClientContext]$context,
        [Parameter(mandatory=$true)][Microsoft.SharePoint.Client.Web]$web);
    Write-Verbose "Getting web permissions";
    if ($web.HasUniqueRoleAssignments -eq $true) {
        $unique = "Yes";
    } else {
        $unique = "No";
    }
    xwStart "Permissions" "brokenInheritance" $unique;
    try {
        $context.Load($web.RoleAssignments);
        $context.Load($web.RoleDefinitions);
        $context.ExecuteQuery();
        $web.RoleAssignments | % {
            # Role Assignment maps secured object (web) to a permission level (Role Definition).
            $roleAssignment = $_;
            $context.Load($roleAssignment.Member);
            $context.Load($roleAssignment.RoleDefinitionBindings);
            $context.ExecuteQuery();
            xwStart "Permission" "principal" $roleAssignment.Member.LoginName "type" $roleAssignment.Member.PrincipalType;
            #Iterate the permission levels.
            $roleAssignment.RoleDefinitionBindings | % {
                $binding = $_;
                xwEmpty "PermissionLevel" "name" $binding.Name;
            }
            xwEnd;
        }
    } catch {
        Write-Verbose "Unable to get permissions for web $($web.ServerRelativeUrl)";
    } finally {
        xwEnd;
    }
}

