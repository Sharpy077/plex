# Omada Configuration Analysis Script
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$ControllerIP = "10.10.10.250",

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Username = $(Read-Host -Prompt "Enter Omada Controller username"),

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [SecureString]$Password = $(Read-Host -Prompt "Enter Omada Controller password" -AsSecureString),

    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "$PSScriptRoot\..\analysis\omada"
)

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
}

# Function to analyze configuration differences
function Compare-Configurations {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$CurrentConfig,
        [Parameter(Mandatory=$true)]
        [string]$OutputDir
    )

    $analysisReport = @"
# Omada Controller Configuration Analysis
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Controller IP: $ControllerIP

## Current Configuration Analysis

### Service Groups
"@

    # Analyze Service Groups
    $serviceGroups = $CurrentConfig.service_groups
    $analysisReport += "`nFound $($serviceGroups.Count) service groups:`n"
    foreach ($group in $serviceGroups) {
        $analysisReport += "- $($group.name)`n"
        foreach ($service in $group.services) {
            $analysisReport += "  - $($service.protocol):$($service.port) ($($service.description))`n"
        }
    }

    # Analyze Port Forwarding
    $analysisReport += "`n### Port Forwarding Rules`n"
    $portForwarding = $CurrentConfig.port_forwarding
    $analysisReport += "Found $($portForwarding.Count) port forwarding rules:`n"
    foreach ($rule in $portForwarding) {
        $analysisReport += "- $($rule.name): $($rule.sourcePort) -> $($rule.internalPort) ($($rule.status))`n"
    }

    # Analyze ACL Rules
    $analysisReport += "`n### Firewall ACL Rules`n"
    $aclRules = $CurrentConfig.firewall_acl
    $analysisReport += "Found $($aclRules.Count) ACL rules:`n"
    foreach ($rule in $aclRules) {
        $analysisReport += "- $($rule.name): $($rule.policy) from $($rule.sourceIp) to port $($rule.destinationPort)`n"
    }

    # Analyze Controller Settings
    $analysisReport += "`n### Controller Settings`n"
    $settings = $CurrentConfig.controller_settings
    $analysisReport += "Current Settings:`n"
    $analysisReport += "- HTTPS Enabled: $($settings.https_enabled)`n"
    $analysisReport += "- HTTP Port: $($settings.http_port)`n"
    $analysisReport += "- HTTPS Port: $($settings.https_port)`n"

    # Recommendations
    $analysisReport += "`n## Recommendations`n"

    # Check for missing security groups
    if (-not ($serviceGroups | Where-Object { $_.name -eq "Docker Services" })) {
        $analysisReport += "- Add 'Docker Services' group for containerized applications`n"
    }

    # Check for HTTPS configuration
    if (-not $settings.https_enabled) {
        $analysisReport += "- Enable HTTPS for secure controller access`n"
    }

    # Check for proper ACL rules
    $hasInternalAccess = $aclRules | Where-Object { $_.sourceIp -eq "10.10.10.0/24" }
    if (-not $hasInternalAccess) {
        $analysisReport += "- Add internal network access rules for Docker services`n"
    }

    # Save analysis report
    $reportPath = Join-Path $OutputDir "configuration_analysis.md"
    $analysisReport | Set-Content -Path $reportPath
    Write-Log "Analysis report saved to: $reportPath" -Level Success

    return $analysisReport
}

# Main execution
Write-Log "Starting Omada Controller configuration analysis..." -Level Info

# Create output directory
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-Log "Created output directory at: $OutputPath" -Level Success
}

# Convert SecureString to plain text for API auth
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
$PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

# API endpoints
$BaseUrl = "http://$ControllerIP`:8088"

try {
    # Setup HTTP client with cookie handling
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.ServerCertificateCustomValidationCallback = { $true }
    $handler.AllowAutoRedirect = $false
    $handler.UseCookies = $true
    $handler.CookieContainer = New-Object System.Net.CookieContainer
    $httpClient = [System.Net.Http.HttpClient]::new($handler)
    $httpClient.Timeout = [System.TimeSpan]::FromSeconds(30)

    # Get the session ID first
    Write-Log "Getting session ID..." -Level Info
    $initialResponse = $httpClient.GetAsync("$BaseUrl/api/").Result
    if ($initialResponse.StatusCode -eq [System.Net.HttpStatusCode]::Found) {
        $location = $initialResponse.Headers.GetValues('Location') | Select-Object -First 1
        Write-Log "Redirect location: $location" -Level Info
        if ($location -match '/([^/]+)/login') {
            $sessionId = $matches[1]
            Write-Log "Found session ID: $sessionId" -Level Success
        } else {
            throw "Could not extract session ID from location: $location"
        }
    } else {
        throw "Expected redirect, got: $($initialResponse.StatusCode)"
    }

    # Set up API URLs with session ID
    $ApiUrl = "$BaseUrl/$sessionId"
    $LoginUrl = "$ApiUrl/login"
    $ServiceGroupUrl = "$ApiUrl/api/v2/sites/default/setting/service/groups"
    $PortForwardUrl = "$ApiUrl/api/v2/sites/default/setting/portforward"
    $ACLUrl = "$ApiUrl/api/v2/sites/default/setting/firewall/acl"
    $SettingsUrl = "$ApiUrl/api/v2/sites/default/setting/controller"

    # Login
    Write-Log "Connecting to Omada Controller..." -Level Info
    $LoginBody = @{
        username = $Username
        password = $PlainPassword
    } | ConvertTo-Json -Compress

    Write-Log "Attempting login to $LoginUrl" -Level Info
    $loginContent = [System.Net.Http.StringContent]::new($LoginBody, [System.Text.Encoding]::UTF8, "application/json")
    $loginResponse = $httpClient.PostAsync($LoginUrl, $loginContent).Result

    if (-not $loginResponse.IsSuccessStatusCode) {
        $errorContent = $loginResponse.Content.ReadAsStringAsync().Result
        throw "Login request failed with status code: $($loginResponse.StatusCode). Response: $errorContent"
    }

    $loginResponseContent = $loginResponse.Content.ReadAsStringAsync().Result | ConvertFrom-Json
    Write-Log "Login response: $($loginResponse.Content.ReadAsStringAsync().Result)" -Level Info

    if ($loginResponseContent.errorCode -ne 0) {
        throw "Login failed: $($loginResponseContent.msg)"
    }

    # Get the token from cookies
    $cookies = $handler.CookieContainer.GetCookies([System.Uri]::new($LoginUrl))
    foreach ($cookie in $cookies) {
        Write-Log "Cookie: $($cookie.Name) = $($cookie.Value)" -Level Info
    }
    $token = $cookies["TPOMADA_SESSIONID"]?.Value
    if ($token) {
        Write-Log "Got session token from cookies" -Level Success
        $httpClient.DefaultRequestHeaders.Add("Cookie", "TPOMADA_SESSIONID=$token")
    }

    # Collect current configuration
    Write-Log "Collecting current configuration..." -Level Info
    $currentConfig = @{}

    # Get Service Groups
    $response = $httpClient.GetAsync($ServiceGroupUrl).Result
    $currentConfig["service_groups"] = ($response.Content.ReadAsStringAsync().Result | ConvertFrom-Json).result

    # Get Port Forwarding Rules
    $response = $httpClient.GetAsync($PortForwardUrl).Result
    $currentConfig["port_forwarding"] = ($response.Content.ReadAsStringAsync().Result | ConvertFrom-Json).result

    # Get ACL Rules
    $response = $httpClient.GetAsync($ACLUrl).Result
    $currentConfig["firewall_acl"] = ($response.Content.ReadAsStringAsync().Result | ConvertFrom-Json).result

    # Get Controller Settings
    $response = $httpClient.GetAsync($SettingsUrl).Result
    $currentConfig["controller_settings"] = ($response.Content.ReadAsStringAsync().Result | ConvertFrom-Json).result

    # Save raw configuration
    $configPath = Join-Path $OutputPath "current_config.json"
    $currentConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath
    Write-Log "Current configuration saved to: $configPath" -Level Success

    # Analyze configuration
    Write-Log "Analyzing configuration..." -Level Info
    $analysis = Compare-Configurations -CurrentConfig ([PSCustomObject]$currentConfig) -OutputDir $OutputPath
    Write-Log "Configuration analysis completed!" -Level Success
    Write-Log "`nAnalysis Report:" -Level Info
    Write-Host $analysis

} catch {
    Write-Log "Error analyzing configuration: $_" -Level Error
    exit 1
} finally {
    if ($httpClient) {
        $httpClient.Dispose()
    }
}