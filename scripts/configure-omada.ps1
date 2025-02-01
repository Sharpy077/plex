# Omada Controller Configuration Script
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$ControllerIP = "10.10.10.250", # Updated for OC200

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Username = $(Read-Host -Prompt "Enter Omada Controller username"),

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [SecureString]$Password = $(Read-Host -Prompt "Enter Omada Controller password" -AsSecureString),

    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$CertPath = "$PSScriptRoot\..\certs\omada",

    [Parameter(Mandatory=$false)]
    [switch]$SetupHTTPS,

    [Parameter(Mandatory=$false)]
    [switch]$TestMode,

    [Parameter(Mandatory=$false)]
    [string]$BackupPath = "$PSScriptRoot\..\backups\omada"
)

# Enable verbose logging
if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent) {
    $VerbosePreference = 'Continue'
}

# Function for structured logging
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $Colors = @{
        'Info' = 'Cyan'
        'Warning' = 'Yellow'
        'Error' = 'Red'
        'Success' = 'Green'
    }

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$Timestamp] [$Level] $Message" -ForegroundColor $Colors[$Level]

    # Add to log file if needed
    if ($TestMode) {
        $LogPath = Join-Path $PSScriptRoot "omada-config.log"
        "[$Timestamp] [$Level] $Message" | Add-Content -Path $LogPath
    }
}

# Function to backup current configuration
function Backup-OmadaConfig {
    param (
        [Parameter(Mandatory=$true)]
        [System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory=$true)]
        [string]$BackupDir
    )

    try {
        # Create backup directory if it doesn't exist
        if (-not (Test-Path $BackupDir)) {
            New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
            Write-Log "Created backup directory at: $BackupDir" -Level Success
        }

        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $backupFile = Join-Path $BackupDir "omada_backup_$timestamp.json"

        if ($TestMode) {
            Write-Log "Test Mode: Would backup configuration to $backupFile" -Level Info
            return $true
        }

        # Backup endpoints
        $endpoints = @(
            @{
                name = "service_groups"
                url = "$ServiceGroupUrl"
            },
            @{
                name = "port_forwarding"
                url = "$PortForwardUrl"
            },
            @{
                name = "firewall_acl"
                url = "$ACLUrl"
            },
            @{
                name = "controller_settings"
                url = "$SettingsUrl"
            }
        )

        $backupData = @{}

        foreach ($endpoint in $endpoints) {
            Write-Log "Backing up $($endpoint.name)..." -Level Info
            $response = $Client.GetAsync($endpoint.url).Result

            if (-not $response.IsSuccessStatusCode) {
                throw "Failed to backup $($endpoint.name): $($response.StatusCode)"
            }

            $content = $response.Content.ReadAsStringAsync().Result
            $backupData[$endpoint.name] = $content | ConvertFrom-Json
        }

        # Save backup to file
        $backupData | ConvertTo-Json -Depth 10 | Set-Content -Path $backupFile
        Write-Log "Configuration backup saved to: $backupFile" -Level Success
        return $true

    } catch {
        Write-Log "Error creating backup: $_" -Level Error
        return $false
    }
}

Write-Log "Configuring Omada Controller at $ControllerIP..." -Level Info

# Convert SecureString to plain text for API auth
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
$PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

# API endpoints for OC200 (starting with HTTP)
$BaseUrl = "http://$ControllerIP`:8088"
$ApiUrl = "$BaseUrl/api/v2"
$LoginUrl = "$ApiUrl/login"
$ServiceGroupUrl = "$ApiUrl/sites/default/setting/service/groups"
$PortForwardUrl = "$ApiUrl/sites/default/setting/portforward"
$ACLUrl = "$ApiUrl/sites/default/setting/firewall/acl"
$SettingsUrl = "$ApiUrl/sites/default/setting/controller"

Write-Log "Testing connection to Omada Controller..." -Level Info
try {
    # Create HttpClientHandler with SSL validation disabled
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.ServerCertificateCustomValidationCallback = {
        param($sender, $cert, $chain, $errors)
        return $true
    }

    # Create HttpClient with the handler
    $httpClient = [System.Net.Http.HttpClient]::new($handler)
    $httpClient.Timeout = [System.TimeSpan]::FromSeconds(30)

    if ($TestMode) {
        Write-Log "Test Mode: Would test connection to $BaseUrl" -Level Info
    } else {
        Write-Log "Testing basic connection..." -Level Info
        $testResponse = $httpClient.GetAsync($BaseUrl).Result
        if (-not $testResponse.IsSuccessStatusCode) {
            throw "Connection test failed with status code: $($testResponse.StatusCode)"
        }
        Write-Log "Successfully connected to Omada Controller" -Level Success
    }

    # Attempt login
    Write-Log "Attempting to log in as $Username..." -Level Info
    $LoginBody = @{
        username = $Username
        password = $PlainPassword
    } | ConvertTo-Json

    if ($TestMode) {
        Write-Log "Test Mode: Would send login request to $LoginUrl" -Level Info
        Write-Log "Test Mode: Using test token for authentication" -Level Info
        $token = "test-token-12345"
    } else {
        Write-Log "Sending login request to $LoginUrl" -Level Info
        $loginContent = [System.Net.Http.StringContent]::new($LoginBody, [System.Text.Encoding]::UTF8, "application/json")
        $loginResponse = $httpClient.PostAsync($LoginUrl, $loginContent).Result
        $loginResponseContent = $loginResponse.Content.ReadAsStringAsync().Result | ConvertFrom-Json

        if ($loginResponseContent.errorCode -ne 0) {
            throw "Login failed: $($loginResponseContent.msg)"
        }

        $token = $loginResponseContent.result.token
        if (-not $token) {
            throw "Failed to get authentication token"
        }
    }
    Write-Log "Successfully logged into Omada Controller" -Level Success

    # Backup existing configuration
    Write-Log "Creating configuration backup..." -Level Info
    if (-not (Backup-OmadaConfig -Client $httpClient -BackupDir $BackupPath)) {
        Write-Log "Failed to create backup. Aborting configuration to prevent data loss." -Level Error
        exit 1
    }

} catch {
    Write-Log "Error connecting to Omada Controller: $_" -Level Error
    Write-Log "Please verify the following:" -Level Warning
    Write-Log "1. Controller is accessible at $BaseUrl" -Level Warning
    Write-Log "2. Username ($Username) and password are correct" -Level Warning
    Write-Log "3. Controller is fully initialized" -Level Warning
    Write-Log "Debug Information:" -Level Info
    Write-Log "Response: $($_.Exception.Response)" -Level Info
    Write-Log "Status Code: $($_.Exception.Response.StatusCode.value__)" -Level Info
    Write-Log "Status Description: $($_.Exception.Response.StatusDescription)" -Level Info
    exit 1
}

# HTTPS Certificate Setup
if ($SetupHTTPS) {
    Write-Log "Setting up HTTPS for Omada Controller..." -Level Info

    # Create certificate directory if it doesn't exist
    if (-not (Test-Path $CertPath)) {
        New-Item -ItemType Directory -Path $CertPath -Force | Out-Null
        Write-Log "Created certificate directory at: $CertPath" -Level Success
    }

    if ($TestMode) {
        Write-Log "Test Mode: Would generate self-signed certificate" -Level Info
        Write-Log "Test Mode: Would export certificate to $CertPath\omada.pfx" -Level Info
    } else {
        # Generate self-signed certificate for initial setup
        Write-Log "Generating self-signed certificate..." -Level Info
        $cert = New-SelfSignedCertificate -DnsName "omada.sharphorizons.tech" `
            -CertStoreLocation "Cert:\LocalMachine\My" `
            -NotAfter (Get-Date).AddYears(1) `
            -KeyAlgorithm RSA `
            -KeyLength 2048 `
            -KeyExportPolicy Exportable `
            -KeyUsage DigitalSignature, KeyEncipherment `
            -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1")

        # Export certificate and private key
        $certPassword = ConvertTo-SecureString -String "omada-temp-pass" -Force -AsPlainText
        $certPath = Join-Path $CertPath "omada.pfx"
        Export-PfxCertificate -Cert $cert -FilePath $certPath -Password $certPassword | Out-Null

        Write-Log "Certificate generated successfully:" -Level Success
        Write-Log "- Location: $certPath" -Level Info
        Write-Log "- Password: omada-temp-pass" -Level Warning
    }
}

# Headers for subsequent requests
$Headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

# Configure network services and rules
try {
    Write-Log "Starting network services configuration" -Level Info

    # Create Docker Services group
    Write-Log "Configuring Docker Services group" -Level Info
    $ServiceGroup = @{
        name = "Docker Services"
        services = @(
            @{
                protocol = "TCP"
                port = "80"
                description = "HTTP"
            },
            @{
                protocol = "TCP"
                port = "443"
                description = "HTTPS"
            },
            @{
                protocol = "TCP"
                port = "8082"
                description = "Metrics"
            }
        )
    } | ConvertTo-Json

    try {
        # Create Docker Services group using HttpClient
        $ServiceGroupContent = [System.Net.Http.StringContent]::new($ServiceGroup, [System.Text.Encoding]::UTF8, "application/json")

        # Add headers to the HttpClient instead of content
        if (-not $TestMode) {
            $httpClient.DefaultRequestHeaders.Clear()
            $httpClient.DefaultRequestHeaders.Add("Authorization", "Bearer $token")
        }

        if ($TestMode) {
            Write-Log "Test Mode: Would send request to $ServiceGroupUrl" -Level Info
            Write-Log "Test Mode: Request content: $ServiceGroup" -Level Info
            $serviceGroupId = "test-group-id"
        } else {
            $ServiceGroupResponse = $httpClient.PostAsync($ServiceGroupUrl, $ServiceGroupContent).Result
            if (-not $ServiceGroupResponse.IsSuccessStatusCode) {
                throw "Failed to create service group: $($ServiceGroupResponse.StatusCode)"
            }
            $serviceGroupId = ($ServiceGroupResponse.Content.ReadAsStringAsync().Result | ConvertFrom-Json).id
        }
        Write-Log "Created Service Group: Docker Services" -Level Success

        # Create Port Forwarding rules for entire network
        $PortForward = @{
            name = "Docker Services"
            status = "enabled"
            protocol = "TCP"
            sourcePort = "80,443"
            internalPort = "80,443"
            sourceIp = "0.0.0.0/0"
            internalIp = "10.10.10.0/24"
            serviceGroup = $serviceGroupId
        } | ConvertTo-Json

        # Create Port Forwarding rules using HttpClient
        $PortForwardContent = [System.Net.Http.StringContent]::new($PortForward, [System.Text.Encoding]::UTF8, "application/json")

        if ($TestMode) {
            Write-Log "Test Mode: Would create port forwarding rules" -Level Info
            Write-Log "Test Mode: $($PortForward)" -Level Info
        } else {
            $PortForwardResponse = $httpClient.PostAsync($PortForwardUrl, $PortForwardContent).Result
            if (-not $PortForwardResponse.IsSuccessStatusCode) {
                throw "Failed to create port forwarding rules: $($PortForwardResponse.StatusCode)"
            }
        }
        Write-Log "Created Port Forwarding rules" -Level Success

        # Create ACL rules
        $ACLRules = @(
            @{
                name = "Allow Internal Docker Access"
                status = "enabled"
                policy = "allow"
                protocol = "TCP"
                sourceIp = "10.10.10.0/24"
                destinationPort = "80,443,8082"
                direction = "in"
            },
            @{
                name = "Allow External HTTPS"
                status = "enabled"
                policy = "allow"
                protocol = "TCP"
                sourceIp = "0.0.0.0/0"
                destinationPort = "443"
                direction = "in"
            },
            @{
                name = "Allow External HTTP for ACME"
                status = "enabled"
                policy = "allow"
                protocol = "TCP"
                sourceIp = "0.0.0.0/0"
                destinationPort = "80"
                direction = "in"
            }
        )

        # Create ACL rules using HttpClient
        foreach ($Rule in $ACLRules) {
            $RuleContent = [System.Net.Http.StringContent]::new(($Rule | ConvertTo-Json), [System.Text.Encoding]::UTF8, "application/json")

            if ($TestMode) {
                Write-Log "Test Mode: Would create ACL rule: $($Rule.name)" -Level Info
                Write-Log "Test Mode: $($Rule | ConvertTo-Json)" -Level Info
            } else {
                $RuleResponse = $httpClient.PostAsync($ACLUrl, $RuleContent).Result
                if (-not $RuleResponse.IsSuccessStatusCode) {
                    throw "Failed to create ACL rule '$($Rule.name)': $($RuleResponse.StatusCode)"
                }
            }
            Write-Log "Created ACL rule: $($Rule.name)" -Level Success
        }

        Write-Log "Omada Controller configuration completed!" -Level Success
        Write-Log @"
Next steps:
1. Access Omada Controller at http://$($ControllerIP):8088
2. Go to Settings > Controller Settings > Security
3. Import the certificate from $certPath using password: omada-temp-pass
4. Enable HTTPS (port 8043) after importing the certificate
5. Verify port forwarding rules are active
6. Test internal network access
7. Monitor EAP783 adoption when installed
"@ -Level Warning

    } finally {
        # Dispose of HttpClient
        if ($httpClient) {
            $httpClient.Dispose()
            Write-Log "Cleaned up HTTP client resources" -Level Info
        }
    }

} catch {
    Write-Log "Error configuring network services: $_" -Level Error
    if ($httpClient) {
        $httpClient.Dispose()
    }
    exit 1
}

# If we're in test mode, display test summary
if ($TestMode) {
    Write-Log "Test Mode Summary:" -Level Info
    Write-Log "All operations completed successfully in test mode" -Level Success
    Write-Log "Check omada-config.log for detailed test output" -Level Info
}