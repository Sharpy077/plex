# Script to validate login configuration for all services
# Requires admin privileges to create log directory if it doesn't exist

# Enable output to terminal
$VerbosePreference = "Continue"
Write-Host "Starting login validation script..."
Write-Verbose "Setting up validation environment..."

# Validates SSL certificates and OAuth2 authentication
Write-Verbose "Configuring SSL/TLS settings..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Create logs directory if it doesn't exist
$logDir = ".\logs"
Write-Verbose "Checking for logs directory at $logDir"
if (!(Test-Path $logDir)) {
    Write-Verbose "Creating logs directory..."
    New-Item -ItemType Directory -Path $logDir -Force
    Write-Host "Created logs directory at $logDir"
}

param(
    [string]$LogFile = ".\logs\login-check.log"
)

# Function to write to log with verbose output
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] - $Message"
    Write-Host $logMessage
    Write-Verbose "Writing to log: $logMessage"
    Add-Content -Path $LogFile -Value $logMessage
}

function Test-OAuth2Proxy {
    try {
        Write-Log "Testing OAuth2 Proxy login..."
        Write-Verbose "Sending request to OAuth2 Proxy endpoint..."
        $response = Invoke-WebRequest -Uri "https://auth.sharphorizons.tech/ping" -Method GET -UseBasicParsing -SkipCertificateCheck
        Write-Verbose "Response received: Status $($response.StatusCode)"
        if ($response.StatusCode -eq 200) {
            Write-Log "OAuth2 Proxy login successful" "SUCCESS"
            return $true
        }
        else {
            Write-Log "OAuth2 Proxy login failed with status code $($response.StatusCode)" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "OAuth2 Proxy login failed: $_" "ERROR"
        Write-Verbose "Exception details: $($_.Exception)"
        return $false
    }
}

function Test-QBittorrent {
    try {
        Write-Log "Testing qBittorrent login..."
        Write-Verbose "Sending request to qBittorrent API..."
        $response = Invoke-WebRequest -Uri "https://qbit.sharphorizons.tech/api/v2/app/version" -Method GET -UseBasicParsing -SkipCertificateCheck
        Write-Verbose "Response received: Status $($response.StatusCode)"
        if ($response.StatusCode -eq 200) {
            Write-Log "qBittorrent login successful" "SUCCESS"
            return $true
        }
        else {
            Write-Log "qBittorrent login failed with status code $($response.StatusCode)" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "qBittorrent login failed: $_" "ERROR"
        Write-Verbose "Exception details: $($_.Exception)"
        return $false
    }
}

function Test-ArrService {
    param(
        [string]$ServiceName,
        [string]$Port,
        [string]$ApiKey,
        [string]$Domain
    )

    try {
        Write-Log "Testing $ServiceName login..."
        Write-Verbose "Preparing request headers for $ServiceName..."
        $headers = @{
            "X-Api-Key" = $ApiKey
        }
        Write-Verbose "Sending request to $ServiceName API at https://$Domain/api/v3/health"
        $response = Invoke-WebRequest -Uri "https://$Domain/api/v3/health" -Headers $headers -Method GET -UseBasicParsing -SkipCertificateCheck
        Write-Verbose "Response received: Status $($response.StatusCode)"
        if ($response.StatusCode -eq 200) {
            Write-Log "$ServiceName login successful" "SUCCESS"
            return $true
        }
        else {
            Write-Log "$ServiceName login failed with status code $($response.StatusCode)" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "$ServiceName login failed: $_" "ERROR"
        Write-Verbose "Exception details: $($_.Exception)"
        return $false
    }
}

# Create log directory if it doesn't exist
$logDir = Split-Path $LogFile -Parent
Write-Verbose "Ensuring log directory exists at $logDir"
if (-not (Test-Path $logDir)) {
    Write-Verbose "Creating log directory..."
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

try {
    Write-Log "Starting login validation..."
    Write-Verbose "Beginning validation process..."

    # Test OAuth configuration
    Write-Log "Validating OAuth configuration..."
    Write-Verbose "Checking for required secrets..."

    # Check for required secrets
    $requiredSecrets = @(
        "./docker/secrets/github_client_id.secret",
        "./docker/secrets/github_client_secret.secret",
        "./docker/secrets/auth_secret.secret"
    )

    foreach ($secret in $requiredSecrets) {
        Write-Verbose "Checking for secret file: $secret"
        if (-not (Test-Path $secret)) {
            Write-Log "Missing required secret: $secret" "ERROR"
            exit 1
        }
        Write-Verbose "Secret file found: $secret"
    }

    # Test OAuth2 Proxy
    Write-Verbose "Testing OAuth2 Proxy..."
    $oauthSuccess = Test-OAuth2Proxy

    if ($oauthSuccess) {
        Write-Log "OAuth configuration validation successful" "SUCCESS"
    }
    else {
        Write-Log "OAuth configuration validation failed" "ERROR"
    }

    # Test qBittorrent
    Write-Verbose "Testing qBittorrent..."
    $qbitSuccess = Test-QBittorrent

    # Test *arr services
    Write-Verbose "Testing *arr services..."
    $services = @{
        "Prowlarr" = @{
            Port       = "9696"
            ApiKeyFile = "./docker/secrets/prowlarr_api_key.secret"
            Domain     = "prowlarr.sharphorizons.tech"
        }
        "Radarr"   = @{
            Port       = "7878"
            ApiKeyFile = "./docker/secrets/radarr_api_key.secret"
            Domain     = "radarr.sharphorizons.tech"
        }
        "Sonarr"   = @{
            Port       = "8989"
            ApiKeyFile = "./docker/secrets/sonarr_api_key.secret"
            Domain     = "sonarr.sharphorizons.tech"
        }
        "Lidarr"   = @{
            Port       = "8686"
            ApiKeyFile = "./docker/secrets/lidarr_api_key.secret"
            Domain     = "lidarr.sharphorizons.tech"
        }
        "Readarr"  = @{
            Port       = "8787"
            ApiKeyFile = "./docker/secrets/readarr_api_key.secret"
            Domain     = "readarr.sharphorizons.tech"
        }
    }

    foreach ($service in $services.Keys) {
        Write-Verbose "Testing service: $service"
        Write-Verbose "Reading API key from $($services[$service].ApiKeyFile)"
        $apiKey = Get-Content $services[$service].ApiKeyFile -Raw
        $apiKey = $apiKey.Trim()  # Trim whitespace and newlines
        Write-Verbose "API key loaded for $service"
        Test-ArrService -ServiceName $service -Port $services[$service].Port -ApiKey $apiKey -Domain $services[$service].Domain
    }

    Write-Log "All login validations completed!" "SUCCESS"
    Write-Verbose "Validation process complete"
}
catch {
    Write-Log "Login validation script failed: $_" "ERROR"
    Write-Verbose "Exception details: $($_.Exception)"
    Write-Log $_.ScriptStackTrace "ERROR"
    exit 1
}