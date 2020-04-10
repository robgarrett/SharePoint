[CmdletBinding()]param();

Import-Module ServerManager;

Write-Host -ForegroundColor Yellow "Installing server features";
Add-WindowsFeature  NET-Framework-Core, AS-HTTP-Activation, Web-Static-Content, Web-Default-Doc, Web-Dir-Browsing, `
                    Web-Http-Errors, Web-Http-Logging, Web-Request-Monitor, Web-Filtering, Web-Stat-Compression, `
                    AS-Web-Support, Web-Metabase, Web-Asp-Net, Web-Windows-Auth -Restart;
Write-Host -ForegroundColor Yellow "Dowloading SQL CLR Types and Report Viewer";
$location = "c:\SCOMPrereqs";
if (!(Test-Path -path $location)) { New-Item -ItemType Directory $location; }
$webClient = New-Object System.Net.WebClient;
$webClient.DownloadFile("http://download.microsoft.com/download/F/B/7/FB728406-A1EE-4AB5-9C56-74EB8BDDF2FF/ReportViewer.msi", "$location\ReportViewer.msi");
$webClient.DownloadFile("http://go.microsoft.com/fwlink/?LinkID=239644&clcid=0x409", "$location\SQLSysClrTypes.msi");
Write-Host -ForegroundColor Yellow "Installing SQL CLR Types";
Start-Process -FilePath "$location\SQLSysClrTypes.msi" -ArgumentList "/q" -Wait;
Write-Host -ForegroundColor Yellow "Installing Report Viewer";
Start-Process -FilePath "$location\ReportViewer.msi" -ArgumentList "/q" -Wait;
