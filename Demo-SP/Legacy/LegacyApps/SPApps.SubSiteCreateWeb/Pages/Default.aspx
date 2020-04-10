<%@ Page Language="C#" AutoEventWireup="true" CodeBehind="Default.aspx.cs" Inherits="SPApps.SubSiteCreateWeb.Default" %>

<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">

<html xmlns="http://www.w3.org/1999/xhtml">
<head runat="server">
    <meta http-equiv="X-UA-Compatible" content="IE-8" />
    <title>Sub Site Provision App</title>
    <!-- Required for chrome control -->
    <script src="../Scripts/jquery-1.9.1.min.js" type="text/javascript"></script>
    <script src="../Scripts/App.js" type="text/javascript"></script>
    <script src="../Scripts/knockout-3.2.0.js" type="text/javascript"></script>
    <link rel="stylesheet" href="../Styles/Styles.css" type="text/css"/>
    <style type="text/css">
        #uploadBox {
            display: table;
            height: 100px;
            width: 100%;
            border: solid 1px #ababab;
        }

    </style>
</head>
<body>
    <script language="javascript" type="text/javascript">
        var selectedFiles = [];
        var selectedFileNames = [];

        $(document).ready(function() {
            var box = document.getElementById("uploadBox");
            box.addEventListener("dragenter", OnDrag, false);
            box.addEventListener("dragover", OnDrag, false);
            box.addEventListener("drop", OnDrop, false);
            $("#uploadButton").click(function () {
                var data = new FormData();
                for (var i = 0; i < selectedFiles.length; i++) {
                    data.append(selectedFiles[i].name, selectedFiles[i]);
                }
                $("body").css("cursor", "progress");
                $.ajax({
                    type: "POST",
                    url: "../Handlers/FileHandler.ashx",
                    contentType: false,
                    processData: false,
                    data: data,
                    success: function (result) {
                        $("body").css("cursor", "default");
                        alert(result);
                        $("#uploadBox").text("Drag WSP files here to upload.");
                        selectedFiles.length = 0;
                        selectedFileNames.length = 0;
                        $("#uploadButton").disable(true);
                    },
                    error: function () {
                        $("body").css("cursor", "default");
                        alert("There was error uploading files!");
                    }
                });
            });
        });

        String.prototype.endsWith = function (str) {
            return (this.toLowerCase().match(str.toLowerCase() + "$") == str.toLowerCase());
        }

        function OnDrag(e) {
            e.stopPropagation();
            e.preventDefault();
        }

        function OnDrop(e) {
            e.stopPropagation();
            e.preventDefault();
            var files = e.target.files || e.dataTransfer.files;
            for (var i = 0, f; f = files[i]; i++) {
                if (f.name.endsWith(".wsp") && $.inArray(f.name.toLowerCase(), selectedFileNames) === -1) {
                    selectedFileNames.push(f.name.toLowerCase());
                    selectedFiles.push(f);
                    $("#wspName").val(f.name);
                }
            }

            jQuery.fn.extend({
                disable: function (state) {
                    return this.each(function () {
                        this.disabled = state;
                    });
                }
            });

            $("#uploadBox").text(selectedFiles.length + " file(s) selected for uploading!");
            $("#uploadButton").disable(selectedFiles.length === 0);
        }
    </script>
    <form id="form1" runat="server">
        <div id="chrome_control_container"></div>
        <div>
            <asp:Panel runat="server" ID="adminPanel">
                <table class="ms-table padded">
                    <tr class="ms-tableRow">
                        <td class="ms-tableCell">Bind to List:</td>
                        <td class="ms-tableCell">
                            <asp:TextBox runat="server" ID="bindToList" /></td>
                    </tr>
                    <tr class="ms-tableRow">
                        <td class="ms-tableCell">Bind to Field (Site Name):</td>
                        <td class="ms-tableCell">
                            <asp:TextBox runat="server" ID="bindToField" /></td>
                    </tr>
                    <tr class="ms-tableRow">
                        <td class="ms-tableCell">Provision Site Collections instead of Sub-Site:</td>
                        <td class="ms-tableCell">
                            <asp:CheckBox runat="server" ID="useSiteCollection" /></td>
                    </tr>
                    <tr class="ms-tableRow" data-bind="visible: !useSiteCollections()">
                        <td class="ms-tableCell">Template Name:</td>
                        <td class="ms-tableCell">
                            <asp:TextBox runat="server" ID="templateName"></asp:TextBox></td>
                    </tr>
                    <tr class="ms-tableRow" data-bind="visible: !useSiteCollections()">
                        <td class="ms-tableCell">Site Uses Unique Permissions:</td>
                        <td class="ms-tableCell">
                            <asp:CheckBox runat="server" ID="useUniquePerms" /></td>
                    </tr>
                    <tr class="ms-tableRow" data-bind="visible: useSiteCollections">
                        <td class="ms-tableCell">Wildcard Managed Path Name:</td>
                        <td class="ms-tableCell">
                            <asp:TextBox runat="server" ID="managedPath"></asp:TextBox></td>
                    </tr>
                    <tr class="ms-tableRow" data-bind="visible: useSiteCollections">
                        <td class="ms-tableCell">Site Collection Owner:</td>
                        <td class="ms-tableCell">
                            <asp:TextBox runat="server" ID="siteOwner"></asp:TextBox></td>
                    </tr>
                    <tr class="ms-tableRow" data-bind="visible: useSiteCollections">
                        <td class="ms-tableCell">Custom Solution Name (name.wsp):</td>
                        <td class="ms-tableCell">
                            <asp:TextBox runat="server" ID="wspName"></asp:TextBox></td>
                    </tr>
                    <tr class="ms-tableRow" data-bind="visible: useSiteCollections">
                        <td class="ms-tableCell" colspan="2">
                            <div id="uploadBox">Drag WSP files here to upload.</div>
                            <br/>
                            <input disabled="disabled" type="button" id="uploadButton" value="Click to upload files"/>
                        </td>
                    </tr>
                    <tr class="ms-tableRow">
                        <td colspan="2" class="ms-tableCell" style="text-align: right;">
                            <asp:Button runat="server" ID="updateBtn" Text="Save" OnClick="updateBtn_Click" /></td>
                    </tr>
                </table>
                <asp:Literal runat="server" ID="koBinding"/>
            </asp:Panel>
            <asp:Panel runat="server" ID="nonAdminPanel" Visible="false">
                <p>This app has no need for UI and serves as a component to manage host-web list events in a given list.</p>
            </asp:Panel>
        </div>
    </form>
</body>
</html>
