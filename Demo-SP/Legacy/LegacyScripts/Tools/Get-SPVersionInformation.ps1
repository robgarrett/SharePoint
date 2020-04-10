[CmdletBinding()]Param();

$global:srcWebPage = "http://www.toddklindt.com/sp2013builds"; # Thanks Todd.

if ((Get-PSSnapin -Name "Microsoft.SharePoint.PowerShell" -ErrorAction SilentlyContinue) -eq $null) {
    Add-PSSnapin "Microsoft.SharePoint.PowerShell";
}

try {
    $farm = Get-SPFarm;
    $buildVersion = $farm.BuildVersion;
    $buildVersionString = $buildVersion.ToString();
    $site = Invoke-WebRequest -UseBasicParsing -Uri $global:srcWebPage;
    $pattern = "\<td.*\>.+(" + $buildVersionString.Replace(".", "\.") + ").*\</td\>\s*\<td.*\>(.+)\</td\>\s*\<td.*\>(.+)\</td\>";
    $pattern += '\s*\<td.*\>.*\<a.+href="(.+)".*\>(.+)\</a\>\</td\>';
    $pattern += '\s*\<td.*\>.*\<a.+href="(.+)".*\>(.+)\</a\>\</td\>';
    Write-Verbose $pattern;
    $m = [Regex]::Match($site.RawContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline);
    if (!$m.Success) { throw "Could not find build number $buildVersionString in $global:srcWebPage"; }
    Write-Host -ForegroundColor white -NoNewline "Current Build Number: ";
    Write-Host -ForegroundColor yellow $buildVersionString;
    Write-Host -ForegroundColor white -NoNewline "Current Patch/CU: ";
    Write-Host -ForegroundColor yellow $m.Groups[2].Value;
    Write-Host -ForegroundColor white -NoNewline "KB of Current Patch/CU: ";
    Write-Host -ForegroundColor yellow $m.Groups[5].Value;
    Write-Host -ForegroundColor white -NoNewline "Download of Current Patch/CU: ";
    Write-Host -ForegroundColor yellow $m.Groups[6].Value;
    Write-Host
    $index = $m.Index + $m.Length;
    $pattern = "\<td.*\>.+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+).*\</td\>\s*\<td.*\>(.+)\</td\>\s*\<td.*\>(.+)\</td\>";
    $pattern += '\s*\<td.*\>.*\<a.+href="(.+)".*\>(.+)\</a\>\</td\>';
    $pattern += '\s*\<td.*\>.*\<a.+href="(.+)".*\>(.+)\</a\>\</td\>';
    $m = [Regex]::Match($site.RawContent.Substring($index), $pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline);
    if ($m.Success) {
        Write-Host -ForegroundColor white -NoNewline "Next Build Number: ";
        Write-Host -ForegroundColor green $m.Groups[1].Value;
        Write-Host -ForegroundColor white -NoNewline "Next Patch/CU: ";
        Write-Host -ForegroundColor green $m.Groups[2].Value;
        Write-Host -ForegroundColor white -NoNewline "KB of Next Patch/CU: ";
        Write-Host -ForegroundColor green $m.Groups[5].Value;
        Write-Host -ForegroundColor white -NoNewline "Download of Next Patch/CU: ";
        Write-Host -ForegroundColor green $m.Groups[6].Value;
    }

} catch {
    Write-Host -ForegroundColor Red $_.Exception;
}
