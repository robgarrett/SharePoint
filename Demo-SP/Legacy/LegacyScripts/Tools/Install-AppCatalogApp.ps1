[CmdletBinding()]param();

if ((Get-PSSnapin -Name "Microsoft.SharePoint.PowerShell" -ErrorAction SilentlyContinue) -eq $null) {
    Add-PSSnapin "Microsoft.SharePoint.PowerShell";
}

$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes","Description."
$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No","Description."
$cancel = New-Object System.Management.Automation.Host.ChoiceDescription "&Cancel","Description."
$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no, $cancel)
 
$site = Get-SPSite "https://robdemo-sp.robdemo.local";
$web = $site.RootWeb;

Write-Verbose "Getting apps from the catalog";
$json = Invoke-RestMethod -UseDefaultCredentials -Method Get -Uri "https://robdemo-sp.robdemo.local/_layouts/15/addanapp.aspx?task=GetMyApps&sort=1&query=&myappscatalog=0&ci=1&vd=1";
$json | ? { $_.Catalog -eq 1 } | % {
    $appId = $_.ID;

    Write-Host -foreground Yellow "Title: $($_.Title)";
    Write-Host -foreground Yellow "AppID: $appId";
     
    $result = $host.ui.PromptForChoice("App Install", "Install App $($_.Title)", $options, 1)
    if ($result -eq 2) { break; }
    if ($result -eq 0) {

        Write-Verbose "Get the Corporate Catalog Accessor instance";
        $flags = [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance;
        $asm = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint");
        $ccaType = $asm.GetType("Microsoft.SharePoint.Marketplace.CorporateCuratedGallery.SPCorporateCatalogAccessor");
        $ccaCtor = $ccaType.GetConstructors($flags) | ? { $_.GetParameters().Count -eq 1; }
        $cca = $ccaCtor.Invoke(@($web));
    
        Write-Verbose "Getting App Package from the Catalog";
        $method = $ccaType.GetMethods($flags) | ? { $_.Name -ilike "GetAppPackage" -and ($_.GetParameters())[0].ParameterType.Name -eq "String" } 
        $stream = $method.Invoke($cca, @($appId));
    
        Write-Verbose "Installing App from Catalog";
        $spAppType = $asm.GetType("Microsoft.SharePoint.Administration.SPApp");
        $method = $spAppType.GetMethod("CreateAppUsingPackageMetadata", [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static);
        [Microsoft.SharePoint.Administration.SPApp]$spApp = $method.Invoke($null, @($stream, $web, 2, $false, $null, $null));
        $appInstanceId = $spApp.CreateAppInstance($web);
        Write-Host -ForegroundColor Yellow "AppInstanceID: $appInstanceId";
        $appInstance = [Microsoft.SharePoint.Administration.SPAppCatalog]::GetAppInstance($web, $appInstanceId);
        $appInstance.Install();
    }
}
