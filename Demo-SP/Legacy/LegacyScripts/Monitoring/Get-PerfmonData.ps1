[CmdletBinding()]Param();

$0 = $myInvocation.MyCommand.Definition
$env:dp0 = [System.IO.Path]::GetDirectoryName($0)

## Sample Space
$global:sampleTimeInSeconds = 1;
$global:maxGraphTimeinSeconds = 2;

## Server Topology
$global:spServers = @("robdemo-sp");
$global:sqlServers = @("robdemo-sql");

## Common Counters
$global:commonCounters = @(
    "\Memory\Available MBytes",
    "\Memory\% Committed Bytes In Use",
    #"\Memory\Page Faults/sec",
    #"\Memory\Pages Input/sec",
    #"\Memory\Page Reads/sec",
    #"\Memory\Pages/sec",
    "\Memory\Pool Paged Bytes",
    "\Memory\Pool Nonpaged Bytes",
    "\Network Interface(*)\Bytes Total/sec",
    "\Network Interface(*)\Packets/sec",
    #"\PhysicalDisk(*)\Current Disk Queue Length",
    #"\PhysicalDisk(*)\% Disk Time",
    "\PhysicalDisk(*)\Disk Read Bytes/sec",
    "\PhysicalDisk(*)\Disk Write Bytes/sec",
    "\PhysicalDisk(*)\Avg. Disk sec/Transfer", 
    "\Process(*)\% Processor Time",
    #"\Process(*)\Page Faults/sec",
    #"\Process(*)\Page File Bytes Peak",
    #"\Process(*)\Page File Bytes",
    "\Process(*)\Private Bytes",
    #"\Process(*)\Virtual Bytes Peak",
    #"\Process(*)\Virtual Bytes",
    "\Process(*)\Working Set Peak",
    "\Process(*)\Working Set",
    "\Processor(*)\% Processor Time"
    #"\Processor(*)\Interrupts/sec",
    #"\Redirector\Server Sessions Hung",
    #"\System\Context Switches/sec",
    #"\System\Processor Queue Length",
    #"\Server\Work Item Shortages"
);

$global:spCounters = @(
    "\ASP.NET\Application Restarts",
    "\ASP.NET\Request Execution Time",
    "\ASP.NET\Requests Rejected",
    "\ASP.NET\Requests Queued",
    "\ASP.NET\Worker Process Restarts",
    "\ASP.NET\Request Wait Time",
    "\ASP.NET Applications(*)\Requests/Sec",
    "\Web Service(*)\Bytes Received/sec",
    "\Web Service(*)\Bytes Sent/sec",
    "\Web Service(*)\Total Connection Attempts (all instances)",
    "\Web Service(*)\Current Connections",
    "\Web Service(*)\Get Requests/sec",
    "\SharePoint Foundation(*)\Sql Query Executing  time",
    "\SharePoint Foundation(*)\Executing Sql Queries",
    "\SharePoint Foundation(*)\Responded Page Requests Rate",
    "\SharePoint Foundation(*)\Executing Time/Page Request",
    "\SharePoint Foundation(*)\Current Page Requests",
    "\SharePoint Foundation(*)\Reject Page Requests Rate",
    "\SharePoint Foundation(*)\Incoming Page Requests Rate",
    "\SharePoint Foundation(*)\Active Threads"
);

$global:sqlCounters = @(
    "\SQLServer:Buffer Manager\Buffer cache hit ratio",
    "\SQLServer:Databases(*)\Transactions/sec",
    "\SQLServer:Databases(*)\Data File(s) Size (KB)",
    "\SQLServer:Databases(*)\Log File(s) Size (KB)",
    "\SQLServer:General Statistics\User Connections",
    "\SQLServer:Locks(*)\Lock Wait Time (ms)",
    "\SQLServer:Locks(*)\Lock Waits/sec",
    "\SQLServer:Locks(*)\Number of Deadlocks/sec",
    "\SQLServer:Transactions\Free Space in tempdb (KB)",
    "\SQLServer:SQL Statistics\Batch Requests/sec"
);

function Get-Counters {
    param([string]$computerName, $counters);
    Get-Counter -Counter $counters -SampleInterval $global:sampleTimeInSeconds `
        -MaxSamples ($global:maxGraphTimeinSeconds / $global:sampleTimeInSeconds) -ComputerName $computerName;
}

## SP servers
Write-Host -ForegroundColor Yellow "SP Servers";
$global:spServers | % { 
    Get-Counters -computerName $_ -counters ($global:commonCounters + $global:spCounters) | `
    Export-Counter -Path "$($env:dp0)\$($_).blg" -FileFormat BLG -Force;
}
## SQL Servers
Write-Host -ForegroundColor Yellow "SQL Servers";
$global:sqlServers | % { 
    Get-Counters -computerName $_ -counters ($global:commonCounters + $global:sqlCounters) | `
    Export-Counter -Path "$($env:dp0)\$($_).blg" -FileFormat BLG -Force;
}
