#########################################
# Determine MinRole Services
# http://blog.sharedove.com/adisjugo/index.php/2015/12/10/minroles-under-the-hood/

[CmdletBinding()]param()

$0 = $myInvocation.MyCommand.Definition
$env:dp0 = [System.IO.Path]::GetDirectoryName($0)

. "$env:dp0\spCommonFunctions.ps1"

try {
    SP-RegisterPS;
    $farm = Get-SPFarm;
    $farm.Servers | % {
        $server = $_;
        Write-Host "Server name: $($server.Name)";   
        Write-Host "Server role: $($server.Role.ToString())"; 
        $serverCompliantWithRole = $true;
        $_.ServiceInstances | % {
            $service = $farm.GetObject($_.Service.Id);
            if ($service.CompliantWithMinRole.HasValue) {
                $isServiceCompliant = $service.CompliantWithMinRole.Value;
            } else {
                $isServiceCompliant = $true;
            }
            Write-Verbose "Compliant with $($server.Role.ToString()) : $($isServiceCompliant.ToString())";
            $serverCompliantWithRole = ($serverCompliantWithRole -and $isServiceCompliant);
        }
        Write-Host "Is server compliant with MinRole: $($serverCompliantWithRole.ToString())";
        Write-Host "-------------------------------";
    }

    $servicesInRole = @{};
    $minRoleValues = [System.Enum]::GetNames([Microsoft.SharePoint.Administration.SPServerRole]);
    $minRoleValues | % { $servicesInRole.Add($_, (New-Object System.Collections.ArrayList)); }

    $farm.Services | % {
        $service = $_;
        $service.Instances | % {
            $serviceInstance = $_;
            # Check in which minrole the service can reside.
            $minRoleValues | % {
                if ($serviceInstance.ShouldProvision($_)) {
                    [System.Collections.ArrayList]$item = $servicesInRole.Get_Item($_);
                    if (!$item.Contains($service.TypeName)) {
                        $item.Add($service.TypeName) | Out-Null;
                    }
                }    
            }
        }

    }

    $servicesInRole.Keys | % {
        Write-Host "MinRole: $_";
        [System.Collections.ArrayList]$item = $servicesInRole.Get_Item($_);
        $item | % {
            Write-Host "Service: $_";
        }
        Write-Host;
    }


} catch {
    Write-Host -ForegroundColor Red "Critial Error: " $_.Exception.Message;
}