[CmdletBinding()]Param(
	[Parameter(Mandatory=$true)][string]$ResourceGroupName,
	[Parameter(Mandatory=$false)][string]$Location = "East US"
);

$0 = $myInvocation.MyCommand.Definition 
$env:dp0 = [System.IO.Path]::GetDirectoryName($0) 

Import-Module Azure -ErrorAction SilentlyContinue;
Set-StrictMode -Version 3

try {
	# Get the Resource Group.
	$rg = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue;
	if ($rg -eq $null) { throw "Cannot find resource group $ResourceGroupName"; }
	$vms = Get-AzureRmVM -ResourceGroupName $rg.ResourceGroupName;
	$vms | % {
		Write-Host -ForegroundColor Yellow "Stopping VM $($_.Name)";
		$_ | Stop-AzureRmVM -ResourceGroupName $rg.ResourceGroupName -Force -Verbose;
	}	
} catch {
	Write-Error $_.Exception;
}

