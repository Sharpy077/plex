# Network Standardization Script
param (
    [Parameter(Mandatory=$false)]
    [string]$MainVlan = "10.10.10.0/24",
    [string]$DockerVlan = "10.10.20.0/24",
    [string]$TrustedVlanRange = "10.10.0.0/16",
    [string]$PublicIP = "202.128.124.242/32"
)

# Function for structured logging
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    $Colors = @{
        'Info' = 'Cyan'
        'Warning' = 'Yellow'
        'Error' = 'Red'
        'Success' = 'Green'
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $Colors[$Level]
}

Write-Log "Starting network standardization..." -Level Info

# Step 1: Update Docker Networks
Write-Log "Checking Docker networks..." -Level Info
try {
    # Get all containers and their networks
    $containers = docker ps -a --format "{{.Names}}|{{.Networks}}"

    # Create the docker_services network if it doesn't exist
    $networkExists = docker network ls --format "{{.Name}}" | Where-Object { $_ -eq "docker_services" }
    if (-not $networkExists) {
        Write-Log "Creating docker_services network..." -Level Info
        docker network create docker_services --subnet $DockerVlan --gateway ($DockerVlan -replace "0/24", "1")
    }

    # Remove old proxy networks
    @("plex_proxy", "proxy") | ForEach-Object {
        $network = $_
        if (docker network ls --format "{{.Name}}" | Where-Object { $_ -eq $network }) {
            Write-Log "Removing old network: $network" -Level Info
            docker network rm $network
        }
    }

    # Migrate containers to docker_services network
    $containers | ForEach-Object {
        $container, $networks = $_.Split("|")
        if ($networks -match "(plex_proxy|proxy)") {
            Write-Log "Migrating $container to docker_services network..." -Level Info
            docker network disconnect $networks $container
            docker network connect docker_services $container
        }
    }
} catch {
    Write-Log "Error updating Docker networks: $_" -Level Error
}

# Step 2: Update Traefik Configuration
Write-Log "Updating Traefik configuration..." -Level Info

# Update trusted IPs in traefik.yml
$traefikConfig = Get-Content ".\traefik\config\traefik.yml" -Raw
$updatedConfig = $traefikConfig -replace "(?ms)trustedIPs:.*?]", @"
trustedIPs:
        - "$TrustedVlanRange"  # All internal VLANs
        - "$PublicIP"          # Public IP
"@

Set-Content ".\traefik\config\traefik.yml" $updatedConfig

# Update middlewares.yml
$middlewaresConfig = Get-Content ".\traefik\config\middlewares.yml" -Raw
$updatedMiddlewares = $middlewaresConfig -replace "(?ms)sourceRange:.*?]", @"
sourceRange:
          - "$TrustedVlanRange"  # All internal VLANs
          - "$PublicIP"          # Public IP
"@

Set-Content ".\traefik\config\middlewares.yml" $updatedMiddlewares

# Step 3: Update Security Configuration
Write-Log "Updating security configuration..." -Level Info
$securityConfig = @"
# Network Security Configuration
trusted_networks:
  internal:
    - $MainVlan      # Main VLAN
    - $DockerVlan    # Docker VLAN
    - $TrustedVlanRange  # All potential internal VLANs
  external:
    - $PublicIP      # Public IP

# Access Rules
rules:
  default:
    allow:
      - $TrustedVlanRange
    deny:
      - "0.0.0.0/0"

  services:
    traefik:
      allow:
        - $TrustedVlanRange
        - $PublicIP
    plex:
      allow:
        - $TrustedVlanRange
        - $PublicIP
    monitoring:
      allow:
        - $MainVlan
        - $DockerVlan
"@

if (-not (Test-Path ".\config\security")) {
    New-Item -ItemType Directory -Path ".\config\security" -Force | Out-Null
}
Set-Content ".\config\security\network-rules.yml" $securityConfig

# Step 4: Restart affected services
Write-Log "Restarting services..." -Level Info
try {
    docker-compose up -d traefik
    Write-Log "Traefik service restarted" -Level Success
} catch {
    Write-Log "Error restarting services: $_" -Level Error
}

Write-Log "Network standardization completed!" -Level Success
Write-Log "Please verify the configuration using verify-network-config.ps1" -Level Info