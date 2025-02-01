# Verify Network Configuration
param (
    [Parameter(Mandatory=$false)]
    [string]$MainVlan = "10.10.10.0/24",
    [string]$DockerVlan = "10.10.20.0/24",
    [string]$PublicIP = "202.128.124.242",
    [string]$TraefikConfigPath = ".\traefik\config\traefik.yml",
    [string]$MiddlewaresPath = ".\traefik\config\middlewares.yml",
    [string]$ReportPath = ".\reports\network-verification.md"
)

# Function for structured logging
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Check')]
        [string]$Level = 'Info'
    )
    $Colors = @{
        'Info' = 'Cyan'
        'Warning' = 'Yellow'
        'Error' = 'Red'
        'Success' = 'Green'
        'Check' = 'Blue'
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $Colors[$Level]

    # Add to report
    $global:Report += "$logMessage`n"
}

# Initialize report
$global:Report = @"
# Network Configuration Verification Report
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Configuration Parameters
- Main VLAN: $MainVlan
- Docker VLAN: $DockerVlan
- Public IP: $PublicIP

"@

Write-Log "Starting network configuration verification..." -Level Info

# Create report directory if it doesn't exist
$reportDir = Split-Path $ReportPath -Parent
if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

# Function to check IP range format
function Test-IpRange {
    param (
        [string]$Range
    )
    $ipRangePattern = "^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}$"
    return $Range -match $ipRangePattern
}

# Verify IP range formats
Write-Log "`n## IP Range Validation" -Level Check
if (Test-IpRange $MainVlan) {
    Write-Log "Main VLAN format is valid: $MainVlan" -Level Success
} else {
    Write-Log "Invalid Main VLAN format: $MainVlan" -Level Error
}

if (Test-IpRange $DockerVlan) {
    Write-Log "Docker VLAN format is valid: $DockerVlan" -Level Success
} else {
    Write-Log "Invalid Docker VLAN format: $DockerVlan" -Level Error
}

# Check Docker network configuration
Write-Log "`n## Docker Network Configuration" -Level Check
$dockerNetworks = docker network ls --format "{{.Name}}: {{.Driver}}"
Write-Log "Available Docker networks:" -Level Info
$dockerNetworks | ForEach-Object { Write-Log $_ -Level Info }

$proxyNetwork = docker network inspect proxy 2>$null | ConvertFrom-Json
if ($proxyNetwork) {
    $networkSubnet = $proxyNetwork.IPAM.Config[0].Subnet
    Write-Log "Proxy network subnet: $networkSubnet" -Level Info
    if ($networkSubnet -eq $DockerVlan) {
        Write-Log "Docker network is correctly configured" -Level Success
    } else {
        Write-Log "Docker network subnet mismatch. Expected: $DockerVlan, Found: $networkSubnet" -Level Warning
    }
} else {
    Write-Log "Proxy network not found" -Level Error
}

# Check Traefik configuration
Write-Log "`n## Traefik Configuration" -Level Check
if (Test-Path $TraefikConfigPath) {
    $traefikConfig = Get-Content $TraefikConfigPath -Raw
    Write-Log "Traefik configuration file found" -Level Success

    # Check trusted IPs
    if ($traefikConfig -match "trustedIPs:") {
        Write-Log "Trusted IPs configuration found" -Level Success
        if ($traefikConfig -match $MainVlan -and $traefikConfig -match $DockerVlan) {
            Write-Log "All required VLANs are trusted" -Level Success
        } else {
            Write-Log "Missing trusted VLANs in configuration" -Level Warning
        }
    } else {
        Write-Log "No trusted IPs configuration found" -Level Error
    }
} else {
    Write-Log "Traefik configuration file not found: $TraefikConfigPath" -Level Error
}

# Check Middlewares configuration
Write-Log "`n## Middleware Configuration" -Level Check
if (Test-Path $MiddlewaresPath) {
    $middlewaresConfig = Get-Content $MiddlewaresPath -Raw
    Write-Log "Middlewares configuration file found" -Level Success

    # Check IP whitelist
    if ($middlewaresConfig -match "ipWhiteList:") {
        Write-Log "IP whitelist configuration found" -Level Success
        if ($middlewaresConfig -match $MainVlan -and $middlewaresConfig -match $DockerVlan) {
            Write-Log "All required VLANs are whitelisted" -Level Success
        } else {
            Write-Log "Missing VLANs in whitelist configuration" -Level Warning
        }
    } else {
        Write-Log "No IP whitelist configuration found" -Level Error
    }
} else {
    Write-Log "Middlewares configuration file not found: $MiddlewaresPath" -Level Error
}

# Check network connectivity
Write-Log "`n## Network Connectivity" -Level Check

# Test internal connectivity
$mainVlanGateway = ($MainVlan -split "/")[0] -replace "\.\d+$", ".1"
$dockerVlanGateway = ($DockerVlan -split "/")[0] -replace "\.\d+$", ".1"

Write-Log "Testing connectivity to Main VLAN gateway ($mainVlanGateway)..." -Level Info
if (Test-Connection $mainVlanGateway -Count 1 -Quiet) {
    Write-Log "Main VLAN gateway is accessible" -Level Success
} else {
    Write-Log "Cannot reach Main VLAN gateway" -Level Warning
}

Write-Log "Testing connectivity to Docker VLAN gateway ($dockerVlanGateway)..." -Level Info
if (Test-Connection $dockerVlanGateway -Count 1 -Quiet) {
    Write-Log "Docker VLAN gateway is accessible" -Level Success
} else {
    Write-Log "Cannot reach Docker VLAN gateway" -Level Warning
}

# Check running containers and their networks
Write-Log "`n## Container Network Assignment" -Level Check
$containers = docker ps --format "{{.Names}}"
foreach ($container in $containers) {
    $containerInfo = docker inspect $container | ConvertFrom-Json
    $networkMode = $containerInfo.HostConfig.NetworkMode
    $networks = $containerInfo.NetworkSettings.Networks.PSObject.Properties.Name
    Write-Log "Container: $container" -Level Info
    Write-Log "- Network Mode: $networkMode" -Level Info
    Write-Log "- Networks: $($networks -join ', ')" -Level Info
}

# Save report
$global:Report | Set-Content -Path $ReportPath
Write-Log "`nVerification completed! Report saved to: $ReportPath" -Level Success

# Provide recommendations
Write-Log "`n## Recommendations" -Level Check
Write-Log "1. Ensure Omada Controller is configured for proper VLAN tagging" -Level Info
Write-Log "2. Verify firewall rules allow inter-VLAN communication" -Level Info
Write-Log "3. Monitor network performance using the monitoring script" -Level Info
Write-Log "4. Regularly check container network assignments" -Level Info
Write-Log "5. Keep Traefik configuration synchronized with VLAN changes" -Level Info