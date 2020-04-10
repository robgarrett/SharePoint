##################################
# Migration Profile Demo

# Src SQL Servers
$Global:Src2007_SQLServer = "SP2007SQL";
$Global:Src2010_SQLServer = "SP2010SQL";
$Global:Src2013_SQLServer = "SP2013SQL";

# Dest SQL Servers
$Global:Dest2010_SQLServer = "SP2010SQL";
$Global:Dest2013_SQLServer = "SP2013SQL";

# Backup Locations.
$Global:SCBackupLocation = "\\uberserver\sqlbackup";
$Global:BackupLocation = "\\uberserver\sqlbackup\";

# WebApp and Ports
$Global:2010_Port = 80;
$Global:2010_WebApp = "http://$($env:COMPUTERNAME)";
$Global:2013_Port = 443;
$Global:2013_WebApp = "https://sp2013";

# Consolidation settings
$Global:Consolidation_Port = 80;
$Global:Consolidation_WebApp = "http://$($env:COMPUTERNAME)";

# Databases
$Global:2007_Databases = @('SP2007_CONTENT');
$Global:2010_Databases = @('SP2010_CONTENT');
$Global:2013_Databases = @('SP2013_CONTENT');

# Mappings (2007-2010/2013).
$Global:DatabaseMappings2013 = @{`
'SP2010_CONTENT'='SP2013_CONTENT'; };
$Global:DatabaseMappings2010 = @{`
'SP2007_CONTENT'='SP2010_CONTENT'; };
$Global:DatabaseMappings = @{`
'SP2007_CONTENT'='SP2013_CONTENT'; };

# Managed Paths
$Global:ExplicitManagedPaths = @('teams');
$Global:WildcardManagedPaths = @();

# Site Collection Mappings
$Global:SiteCollectionMappings = @{ '/'='/teams'; };

# Known Dead Sites
$Global:DeadWebs = @();
