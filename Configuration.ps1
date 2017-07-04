configuration DomainJoin 
{ 
   param 
    ( 
        [Parameter(Mandatory)]
        [String]$domainName,

        [Parameter(Mandatory)]
        [PSCredential]$adminCreds
    ) 
    
    Import-DscResource -ModuleName xActiveDirectory, xComputerManagement

    $domainCreds = New-Object System.Management.Automation.PSCredential ("$domainName\$($adminCreds.UserName)", $adminCreds.Password)
   
    Node localhost
    {
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
        }

        WindowsFeature ADPowershell
        {
            Name = "RSAT-AD-PowerShell"
            Ensure = "Present"
        } 

        xComputer DomainJoin
        {
            Name = $env:COMPUTERNAME
            DomainName = $domainName
            Credential = $domainCreds
            DependsOn = "[WindowsFeature]ADPowershell" 
        }	 
	}
}



configuration Gateway
{
   param 
    ( 
        [Parameter(Mandatory)]
        [String]$domainName,

        [Parameter(Mandatory)]
        [PSCredential]$adminCreds
    ) 


    Node localhost
    {
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
            ConfigurationMode = "ApplyOnly"
        }

        DomainJoin DomainJoin
        {
            domainName = $domainName 
            adminCreds = $adminCreds 
        }

        WindowsFeature RDS-Gateway
        {
            Ensure = "Present"
            Name = "RDS-Gateway"
        }

        WindowsFeature RDS-Web-Access
        {
            Ensure = "Present"
            Name = "RDS-Web-Access"
        }
    }
}



configuration SessionHost
{
   param 
    ( 
        [Parameter(Mandatory)]
        [String]$domainName,

        [Parameter(Mandatory)]
        [PSCredential]$adminCreds
    ) 


    Node localhost
    {
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
            ConfigurationMode = "ApplyOnly"
        }

        DomainJoin DomainJoin
        {
            domainName = $domainName 
            adminCreds = $adminCreds 
        }

        WindowsFeature RDS-RD-Server
        {
            Ensure = "Present"
            Name = "RDS-RD-Server"
        }
    }
}




configuration RDSDeployment
{
   param 
    ( 
        [Parameter(Mandatory)]
        [String]$domainName,

        [Parameter(Mandatory)]
        [PSCredential]$adminCreds,

        # Connection Broker Node name
        [String]$connectionBroker,
        
        # Web Access Node name
        [String]$webAccessServer,

        # Gateway external FQDN
        [String]$externalFqdn,
        
        # RD Session Host count and naming prefix
        [Int]$numberOfRdshInstances = 1,
        [String]$sessionHostNamingPrefix = "SessionHost-",

        # Collection Name
        [String]$collectionName,

        # Connection Description
        [String]$collectionDescription

    ) 

    Import-DscResource -ModuleName PSDesiredStateConfiguration -ModuleVersion 1.1
    Import-DscResource -ModuleName xActiveDirectory, xComputerManagement, xRemoteDesktopSessionHost
   
    $localhost = [System.Net.Dns]::GetHostByName((hostname)).HostName

    $username = $adminCreds.UserName -split '\\' | select -last 1
    $domainCreds = New-Object System.Management.Automation.PSCredential ("$domainName\$username", $adminCreds.Password)


    if (-not $connectionBroker)   { $connectionBroker = $localhost }
    if (-not $webAccessServer)    { $webAccessServer  = $localhost }

    if ($sessionHostNamingPrefix)
    { 
        $sessionHosts = @( 0..($numberOfRdshInstances-1) | % { "$sessionHostNamingPrefix$_.$domainname"} )
    }
    else
    {
        $sessionHosts = @( $localhost )
    }

    if (-not $collectionName)         { $collectionName = "Desktop Collection" }
    if (-not $collectionDescription)  { $collectionDescription = "A sample RD Session collection up in cloud." }


    Node localhost
    {

        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
            ConfigurationMode = "ApplyOnly"
        }

        DomainJoin DomainJoin
        {
            domainName = $domainName 
            adminCreds = $adminCreds 
        }

        WindowsFeature ADDSTools
        {
            Name = "RSAT-ADDS-Tools"
        } 

        WindowsFeature RSAT-RDS-Tools
        {
            Ensure = "Present"
            Name = "RSAT-RDS-Tools"
            IncludeAllSubFeature = $true
        }

        WindowsFeature RDS-Licensing
        {
            Ensure = "Present"
            Name = "RDS-Licensing"
        }

        xRDSessionDeployment Deployment
        {
            DependsOn = "[DomainJoin]DomainJoin"

            ConnectionBroker = $connectionBroker
            WebAccessServer  = $webAccessServer

            SessionHosts     = $sessionHosts

            PsDscRunAsCredential = $domainCreds
        }


        xRDServer AddLicenseServer
        {
            DependsOn = "[xRDSessionDeployment]Deployment"
            
            Role    = 'RDS-Licensing'
            Server  = $connectionBroker

            PsDscRunAsCredential = $domainCreds
        }

        xRDLicenseConfiguration LicenseConfiguration
        {
            DependsOn = "[xRDServer]AddLicenseServer"

            ConnectionBroker = $connectionBroker
            LicenseServers   = @( $connectionBroker )

            LicenseMode = 'PerUser'

            PsDscRunAsCredential = $domainCreds
        }


        xRDServer AddGatewayServer
        {
            DependsOn = "[xRDLicenseConfiguration]LicenseConfiguration"
            
            Role    = 'RDS-Gateway'
            Server  = $webAccessServer

            GatewayExternalFqdn = $externalFqdn

            PsDscRunAsCredential = $domainCreds
        }

        xRDGatewayConfiguration GatewayConfiguration
        {
            DependsOn = "[xRDServer]AddGatewayServer"

            ConnectionBroker = $connectionBroker
            GatewayServer    = $webAccessServer

            ExternalFqdn = $externalFqdn

            GatewayMode = 'Custom'
            LogonMethod = 'AllowUserToSelectDuringConnection'

            UseCachedCredentials = $true
            BypassLocal = $false

            PsDscRunAsCredential = $domainCreds
        } 
        

        xRDSessionCollection Collection
        {
            DependsOn = "[xRDGatewayConfiguration]GatewayConfiguration"

            ConnectionBroker = $connectionBroker

            CollectionName = $collectionName
            CollectionDescription = $collectionDescription
            
            SessionHosts = $sessionHosts

            PsDscRunAsCredential = $domainCreds
        }

    }
	
configuration PrintServer
{
   param 
    ( 
        [Parameter(Mandatory)]
        [String]$domainName,

        [Parameter(Mandatory)]
        [PSCredential]$adminCreds
    ) 


    Node localhost
    {
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
            ConfigurationMode = "ApplyOnly"
        }

        DomainJoin DomainJoin
        {
            domainName = $domainName 
            adminCreds = $adminCreds 
        }

        WindowsFeature Print-Services
        {
            Ensure = "Present"
            Name = "Print-Services"
        }
		
		WindowsFeature Print-Server
        {
            Ensure = "Present"
            Name = "Print-Server"
        }
		WindowsFeature Print-LPD-Service
        {
            Ensure = "Present"
            Name = "Print-LPD-Service"
        }		
    }
}
configuration ApplicationServer
{
   param 
    ( 
        [Parameter(Mandatory)]
        [String]$domainName,

        [Parameter(Mandatory)]
        [PSCredential]$adminCreds
    ) 


    Node localhost
    {
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
            ConfigurationMode = "ApplyOnly"
        }

        DomainJoin DomainJoin
        {
            domainName = $domainName 
            adminCreds = $adminCreds 
        }

        WindowsFeature Application-Server
        {
            Ensure = "Present"
            Name = "Application-Server"
        }
    }
}
configuration FileServer
{
   param 
    ( 
        [Parameter(Mandatory)]
        [String]$domainName,

        [Parameter(Mandatory)]
        [PSCredential]$adminCreds
    ) 


    Node localhost
    {
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
            ConfigurationMode = "ApplyOnly"
        }

        DomainJoin DomainJoin
        {
            domainName = $domainName 
            adminCreds = $adminCreds 
        }

		WindowsFeature FileAndStorage-Services
		{
            Ensure = "Present"
            Name = "FileAndStorage-Services"
        }
		WindowsFeature File-Services
        {
            Ensure = "Present"
            Name = "File-Services"
        }
		WindowsFeature FS-FileServer
        {
            Ensure = "Present"
            Name = "FS-FileServer"
        }
		WindowsFeature Storage-Services
        {
            Ensure = "Present"
            Name = "Storage-Services"
        }
		WindowsFeature FS-DFS-Namespace
        {
            Ensure = "Present"
            Name = "FS-DFS-Namespace"
        }
		WindowsFeature FS-DFS-Replication
        {
            Ensure = "Present"
            Name = "FS-DFS-Replication"
        }
		WindowsFeature FS-Resource-Manager
        {
            Ensure = "Present"
            Name = "FS-Resource-Manager"
        }
		WindowsFeature NET-Framework-Features
        {
            Ensure = "Present"
            Name = "NET-Framework-Features"
        }
		WindowsFeature NET-Framework-Core
        {
            Ensure = "Present"
            Name = "NET-Framework-Core"
        }
		WindowsFeature NET-WCF-Services45
        {
            Ensure = "Present"
            Name = "NET-WCF-Services45"
        }
		WindowsFeature NET-WCF-TCP-PortSharing45
        {
            Ensure = "Present"
            Name = "NET-WCF-TCP-PortSharing45"
        }

		WindowsFeature RDC
        {
            Ensure = "Present"
            Name = "RDC"
        }
		WindowsFeature FS-SMB1
        {
            Ensure = "Present"
            Name = "FS-SMB1"
        }
		WindowsFeature Telnet-Client
        {
            Ensure = "Present"
            Name = "Telnet-Client"
        }	
		WindowsFeature RSAT-Role-Tools
        {
            Ensure = "Present"
            Name = "RSAT-Role-Tools"
        }
		WindowsFeature RSAT-File-Services
        {
            Ensure = "Present"
            Name = "RSAT-File-Services"
        }
		WindowsFeature RSAT-DFS-Mgmt-Con
        {
            Ensure = "Present"
            Name = "RSAT-DFS-Mgmt-Con"
        }
		WindowsFeature RSAT-FSRM-Mgmt
        {
            Ensure = "Present"
            Name = "RSAT-FSRM-Mgmt"
        }
		WindowsFeature Windows-Identity-Foundation
        {
            Ensure = "Present"
            Name = "Windows-Identity-Foundation"
        }
		WindowsFeature Search-Service
        {
            Ensure = "Present"
            Name = "Search-Service"
        }
		WindowsFeature Windows-Server-Backup
        {
            Ensure = "Present"
            Name = "Windows-Server-Backup"
        }
    }
}
configuration WebServer
{
   param 
    ( 
        [Parameter(Mandatory)]
        [String]$domainName,

        [Parameter(Mandatory)]
        [PSCredential]$adminCreds
    ) 


    Node localhost
    {
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
            ConfigurationMode = "ApplyOnly"
        }

        DomainJoin DomainJoin
        {
            domainName = $domainName 
            adminCreds = $adminCreds 
        }

		WindowsFeature FileAndStorage-Services
		{
            Ensure = "Present"
            Name = "FileAndStorage-Services"
        }
		WindowsFeature File-Services
        {
            Ensure = "Present"
            Name = "File-Services"
        }
		WindowsFeature FS-FileServer
        {
            Ensure = "Present"
            Name = "FS-FileServer"
        }
		WindowsFeature Storage-Services
        {
            Ensure = "Present"
            Name = "Storage-Services"
        }
		WindowsFeature Web-Server
        {
            Ensure = "Present"
            Name = "Web-Server"
        }
		WindowsFeature Web-WebServer
        {
            Ensure = "Present"
            Name = "Web-WebServer"
        }
		WindowsFeature Web-Common-Http
        {
            Ensure = "Present"
            Name = "Web-Common-Http"
        }
		WindowsFeature Web-Default-Doc
        {
            Ensure = "Present"
            Name = "Web-Default-Doc"
        }
		WindowsFeature Web-Dir-Browsing
        {
            Ensure = "Present"
            Name = "Web-Dir-Browsing"
        }
		WindowsFeature Web-Http-Errors
        {
            Ensure = "Present"
            Name = "Web-Http-Errors"
        }
		WindowsFeature Web-Static-Content
        {
            Ensure = "Present"
            Name = "Web-Static-Content"
        }
		WindowsFeature Web-Http-Redirect
        {
            Ensure = "Present"
            Name = "Web-Http-Redirect"
        }
		WindowsFeature Web-Health
        {
            Ensure = "Present"
            Name = "Web-Health"
        }
		WindowsFeature Web-Http-Logging
        {
            Ensure = "Present"
            Name = "Web-Http-Logging"
        }
		WindowsFeature Web-Request-Monitor
        {
            Ensure = "Present"
            Name = "Web-Request-Monitor"
        }
		WindowsFeature Web-Performance
        {
            Ensure = "Present"
            Name = "Web-Performance"
        }
		WindowsFeature Web-Stat-Compression
        {
            Ensure = "Present"
            Name = "Web-Stat-Compression"
        }
		WindowsFeature Web-Security
        {
            Ensure = "Present"
            Name = "Web-Security"
        }
		WindowsFeature Web-Filtering
        {
            Ensure = "Present"
            Name = "Web-Filtering"
        }
		WindowsFeature Web-Basic-Auth
        {
            Ensure = "Present"
            Name = "Web-Basic-Auth"
        }
		WindowsFeature Web-App-Dev
        {
            Ensure = "Present"
            Name = "Web-App-Dev"
        }
		WindowsFeature Web-Net-Ext
        {
            Ensure = "Present"
            Name = "Web-Net-Ext"
        }
		WindowsFeature Web-Net-Ext45
        {
            Ensure = "Present"
            Name = "Web-Net-Ext45"
        }
		WindowsFeature Web-Asp-Net
        {
            Ensure = "Present"
            Name = "Web-Asp-Net"
        }
		WindowsFeature Web-Asp-Net45
        {
            Ensure = "Present"
            Name = "Web-Asp-Net45"
        }
		WindowsFeature Web-ISAPI-Ext
        {
            Ensure = "Present"
            Name = "Web-ISAPI-Ext"
        }
		WindowsFeature Web-ISAPI-Filter
        {
            Ensure = "Present"
            Name = "Web-ISAPI-Filter"
        }
		WindowsFeature Web-Mgmt-Tools
        {
            Ensure = "Present"
            Name = "Web-Mgmt-Tools"
        }
		WindowsFeature Web-Mgmt-Console
        {
            Ensure = "Present"
            Name = "Web-Mgmt-Console"
        }
		WindowsFeature NET-Framework-Features
        {
            Ensure = "Present"
            Name = "NET-Framework-Features"
        }
		WindowsFeature NET-Framework-Core
        {
            Ensure = "Present"
            Name = "NET-Framework-Core"
        }
		WindowsFeature NET-Framework-45-Features
        {
            Ensure = "Present"
            Name = "NET-Framework-45-Features"
        }
		WindowsFeature NET-Framework-45-Core
        {
            Ensure = "Present"
            Name = "NET-Framework-45-Core"
        }
		WindowsFeature NET-Framework-45-ASPNET
        {
            Ensure = "Present"
            Name = "NET-Framework-45-ASPNET"
        }
		WindowsFeature NET-WCF-Services45
        {
            Ensure = "Present"
            Name = "NET-WCF-Services45"
        }
		WindowsFeature NET-WCF-TCP-PortSharing45
        {
            Ensure = "Present"
            Name = "NET-WCF-TCP-PortSharing45"
        }
		WindowsFeature RDC
        {
            Ensure = "Present"
            Name = "RDC"
        }
		WindowsFeature FS-SMB1
        {
            Ensure = "Present"
            Name = "FS-SMB1"
        }
		WindowsFeature Telnet-Client
        {
            Ensure = "Present"
            Name = "Telnet-Client"
        }	
    }
}
}