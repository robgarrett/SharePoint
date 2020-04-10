
Add-PSSnapin Microsoft.SharePoint.PowerShell

ForEach ($Server in (Get-SPServer | ? {$_.Role -ne "Invalid"})) { 
   Write-Host "$($server.Address): $($server.Role)" 
   Invoke-Command $Server.Address {  
           Import-Module WebAdministration; 
           Get-ChildItem "IIS:\Sites\SharePoint Web Services" |  
           ? {$_.NodeType -eq "application"} | 
           Select Name | Format-Table -HideTableHeaders 
   }  
} 
