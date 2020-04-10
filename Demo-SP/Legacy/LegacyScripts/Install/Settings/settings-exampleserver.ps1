######################################
## Example Server Settings

# Prefix for all databases.
$global:dbPrefix = "MyFarm";
# SQL Server
$global:dbServer = "MySQLServer";

# Server Role (SharePoint 2016+).
$global:serverRole = "Application";
# Farm passphrase.
$global:passphrase = "MyPassPhrase";
# Port for Central Admin.
$global:CAportNumber = 2016;

# Accounts.
$global:spFarmAcctName = "DOMAIN\spfarm";
$global:spAdminAcctName = "DOMAIN\spadmin";
$global:spServiceAcctName = "DOMAIN\spservice";
$global:spServiceAcctPwd = "mypassword";
$global:spAppPoolAcctName = "DOMAIN\spapppool";
$global:spAppPoolAcctPwd = "mypassword";
$global:spSearchCrawlAcctName = "DOMAIN\spsearch";
$global:spSearchCrawlAcctPwd = "mypassword";

# MySite Host location
$global:mySiteHost = "http://$($env:computername):8080";

# Logging Settings.
$global:logDaysToKeepLogs = 2;
$global:logSpaceUsage = 5;

# SMTP Server for Outgoing Email.
$global:smtpServer = "localhost";
$global:fromEmailAddress = "no-reply@myserver.com";

# Location for search indexes.
$global:indexLocation = "c:\SPIndex";
# Array of servers with query components.
$global:queryServers = @($env:COMPUTERNAME);
# Array of servrs with crawl components.
$global:crawlServers = @($env:COMPUTERNAME);

# Configure UPSS
$global:disableUPSS = $false;
