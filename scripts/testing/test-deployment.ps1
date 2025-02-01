# Deployment and Authentication Test Script
param (
    [Parameter(Mandatory = $false)]
    [string]$Domain = "sharphorizons.tech",
    [string]$MainVlan = "10.10.10.0/24",
    [string]$DockerVlan = "10.10.20.0/24",
    [string]$PublicIP = "202.128.124.242"
)

# Function for structured logging
function Write-TestLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Test')]
        [string]$Level = 'Info',
        [string]$Component = 'General'
    )
    $Colors = @{
        'Info'    = 'Cyan'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
        'Success' = 'Green'
        'Test'    = 'Magenta'
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] [$Component] $Message"
    Write-Host $logMessage -ForegroundColor $Colors[$Level]

    # Also save to log file
    $logFile = ".\logs\deployment_test_$(Get-Date -Format 'yyyyMMdd').log"
    $logMessage | Out-File -FilePath $logFile -Append
}

function Test-NetworkConnectivity {
    param (
        [string]$TargetHost,
        [int]$Port,
        [string]$Service
    )
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $connection = $tcp.BeginConnect($TargetHost, $Port, $null, $null)
        $wait = $connection.AsyncWaitHandle.WaitOne(1000, $false)
        if ($wait) {
            $tcp.EndConnect($connection)
            Write-TestLog "Connection to $Service ($TargetHost`:$Port) successful" -Level Success -Component Network
            return $true
        }
        Write-TestLog "Connection to $Service ($TargetHost`:$Port) failed - timeout" -Level Error -Component Network
        return $false
    }
    catch {
        Write-TestLog "Connection to $Service ($TargetHost`:$Port) failed - $_" -Level Error -Component Network
        return $false
    }
    finally {
        if ($tcp) { $tcp.Close() }
    }
}

function Test-HttpEndpoint {
    param (
        [string]$Url,
        [string]$Service,
        [switch]$ExpectRedirect
    )
    try {
        $response = Invoke-WebRequest -Uri $Url -MaximumRedirection 0 -ErrorAction SilentlyContinue
        $statusCode = $response.StatusCode

        if ($ExpectRedirect -and $statusCode -eq 302) {
            Write-TestLog "Expected redirect from $Service ($Url) - Status: $statusCode" -Level Success -Component HTTP
            Write-TestLog "Redirect location: $($response.Headers.Location)" -Level Info -Component HTTP
            return $true
        }
        elseif (!$ExpectRedirect -and $statusCode -eq 200) {
            Write-TestLog "$Service ($Url) responded successfully - Status: $statusCode" -Level Success -Component HTTP
            return $true
        }
        else {
            Write-TestLog "$Service ($Url) unexpected status code: $statusCode" -Level Warning -Component HTTP
            return $false
        }
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 302 -and $ExpectRedirect) {
            Write-TestLog "Expected redirect from $Service ($Url)" -Level Success -Component HTTP
            Write-TestLog "Redirect location: $($_.Exception.Response.Headers.Location)" -Level Info -Component HTTP
            return $true
        }
        else {
            Write-TestLog "$Service ($Url) test failed - $_" -Level Error -Component HTTP
            return $false
        }
    }
}

# Create logs directory if it doesn't exist
if (-not (Test-Path ".\logs")) {
    New-Item -ItemType Directory -Path ".\logs" | Out-Null
}

Write-TestLog "Starting deployment and authentication testing..." -Level Info

# Step 1: Verify Docker and Network Status
Write-TestLog "Testing Docker service status..." -Level Test -Component Docker
$dockerStatus = docker info 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-TestLog "Docker service is running" -Level Success -Component Docker
}
else {
    Write-TestLog "Docker service check failed: $dockerStatus" -Level Error -Component Docker
    exit 1
}

# Step 2: Check Network Configuration
Write-TestLog "Checking network configuration..." -Level Test -Component Network
$networks = docker network ls --format "{{.Name}}"
if ($networks -contains "docker_services") {
    Write-TestLog "docker_services network exists" -Level Success -Component Network
}
else {
    Write-TestLog "docker_services network missing" -Level Error -Component Network
    exit 1
}

# Step 3: Test Basic Network Connectivity
Write-TestLog "Testing basic network connectivity..." -Level Test -Component Network
@(
    @{TargetHost = "traefik.$Domain"; Port = 443; Service = "Traefik" },
    @{TargetHost = "auth.$Domain"; Port = 443; Service = "OAuth2 Proxy" },
    @{TargetHost = "plex.$Domain"; Port = 443; Service = "Plex" }
) | ForEach-Object {
    Test-NetworkConnectivity -TargetHost $_.TargetHost -Port $_.Port -Service $_.Service
}

# Step 4: Test HTTP Endpoints
Write-TestLog "Testing HTTP endpoints..." -Level Test -Component HTTP
@(
    @{Url = "http://traefik.$Domain"; Service = "Traefik Dashboard"; ExpectRedirect = $true },
    @{Url = "http://auth.$Domain"; Service = "OAuth2 Proxy"; ExpectRedirect = $true },
    @{Url = "http://plex.$Domain"; Service = "Plex"; ExpectRedirect = $true }
) | ForEach-Object {
    Test-HttpEndpoint -Url $_.Url -Service $_.Service -ExpectRedirect:$_.ExpectRedirect
}

# Step 5: Test HTTPS Endpoints
Write-TestLog "Testing HTTPS endpoints..." -Level Test -Component HTTPS
@(
    @{Url = "https://traefik.$Domain"; Service = "Traefik Dashboard" },
    @{Url = "https://auth.$Domain"; Service = "OAuth2 Proxy" },
    @{Url = "https://plex.$Domain"; Service = "Plex" }
) | ForEach-Object {
    Test-HttpEndpoint -Url $_.Url -Service $_.Service
}

# Step 6: Test Authentication Flow
Write-TestLog "Testing authentication flow..." -Level Test -Component Auth

# Test OAuth2 Proxy Authentication
$authUrl = "https://auth.$Domain/oauth2/start"
Write-TestLog "Testing OAuth2 authentication endpoint: $authUrl" -Level Info -Component Auth
try {
    $response = Invoke-WebRequest -Uri $authUrl -MaximumRedirection 0 -ErrorAction SilentlyContinue
    Write-TestLog "OAuth2 authentication endpoint responded with status: $($response.StatusCode)" -Level Info -Component Auth
}
catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 302) {
        $location = $_.Exception.Response.Headers.Location
        Write-TestLog "OAuth2 authentication redirecting to: $location" -Level Success -Component Auth
    }
    else {
        Write-TestLog "OAuth2 authentication test failed: $_" -Level Error -Component Auth
    }
}

# Step 7: Test Service Health
Write-TestLog "Testing service health..." -Level Test -Component Health
docker ps --format "{{.Names}}" | ForEach-Object {
    $health = docker inspect --format "{{.State.Health.Status}}" $_
    if ($health) {
        Write-TestLog "Service $_ health status: $health" -Level Info -Component Health
    }
    else {
        Write-TestLog "Service $_ has no health check configured" -Level Warning -Component Health
    }
}

# Step 8: Generate Summary Report
$summaryFile = ".\logs\deployment_test_summary_$(Get-Date -Format 'yyyyMMdd_HHmmss').md"
@"
# Deployment Test Summary
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Network Configuration
- Main VLAN: $MainVlan
- Docker VLAN: $DockerVlan
- Public IP: $PublicIP
- Domain: $Domain

## Service Status
$(docker ps --format "| {{.Names}} | {{.Status}} | {{.Ports}} |" | ForEach-Object { $_ })

## Authentication Configuration
- OAuth2 Proxy: https://auth.$Domain
- Traefik Dashboard: https://traefik.$Domain
- Plex: https://plex.$Domain

## Test Results
$(Get-Content ".\logs\deployment_test_$(Get-Date -Format 'yyyyMMdd').log" | ForEach-Object { "- $_" })

## Recommendations
1. Review any failed connection tests
2. Verify OAuth2 configuration if authentication tests failed
3. Check service health status for any unhealthy containers
4. Verify SSL certificate status for all domains
5. Monitor error logs for any recurring issues
"@ | Set-Content $summaryFile

Write-TestLog "Testing completed! Summary saved to: $summaryFile" -Level Success