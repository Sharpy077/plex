# Update Docker Network Configuration
param (
    [Parameter(Mandatory=$false)]
    [string]$NetworkName = "proxy",
    [string]$Subnet = "10.10.20.0/24",
    [string]$Gateway = "10.10.20.1"
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
    Write-Host "[$Level] $Message" -ForegroundColor $Colors[$Level]
}

Write-Log "Starting Docker network update..." -Level Info

# Check if network exists
Write-Log "Checking for existing network '$NetworkName'..." -Level Info
$networkExists = docker network ls --format "{{.Name}}" | Where-Object { $_ -eq $NetworkName }

if ($networkExists) {
    Write-Log "Network '$NetworkName' exists. Checking current configuration..." -Level Info
    $currentConfig = docker network inspect $NetworkName | ConvertFrom-Json
    $currentSubnet = $currentConfig.IPAM.Config[0].Subnet
    $currentGateway = $currentConfig.IPAM.Config[0].Gateway

    Write-Log "Current configuration:" -Level Info
    Write-Log "- Subnet: $currentSubnet" -Level Info
    Write-Log "- Gateway: $currentGateway" -Level Info

    # Get list of containers using this network
    Write-Log "Checking for connected containers..." -Level Info
    $connectedContainers = docker network inspect $NetworkName --format '{{range $k, $v := .Containers}}{{$k}} {{end}}'

    if ($connectedContainers) {
        Write-Log "Found connected containers. Creating backup of container configuration..." -Level Warning
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupDir = ".\backups\docker\$timestamp"
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

        docker-compose config > "$backupDir\docker-compose.yml"
        Write-Log "Backup saved to $backupDir\docker-compose.yml" -Level Success

        Write-Log "Stopping connected containers..." -Level Warning
        docker-compose down
    }

    # Remove existing network
    Write-Log "Removing existing network..." -Level Warning
    docker network rm $NetworkName
    Start-Sleep -Seconds 2
}

# Create new network
Write-Log "Creating new network with updated configuration..." -Level Info
$createResult = docker network create `
    --driver bridge `
    --subnet $Subnet `
    --gateway $Gateway `
    --opt "com.docker.network.bridge.name=docker_$NetworkName" `
    --opt "com.docker.network.bridge.enable_ip_masquerade=true" `
    --opt "com.docker.network.bridge.enable_icc=true" `
    --opt "com.docker.network.bridge.host_binding_ipv4=0.0.0.0" `
    $NetworkName

if ($LASTEXITCODE -eq 0) {
    Write-Log "Network created successfully!" -Level Success
    Write-Log "New configuration:" -Level Info
    Write-Log "- Network Name: $NetworkName" -Level Info
    Write-Log "- Subnet: $Subnet" -Level Info
    Write-Log "- Gateway: $Gateway" -Level Info

    # Restart containers if they were running
    if ($connectedContainers) {
        Write-Log "Restarting containers..." -Level Info
        docker-compose up -d
        Write-Log "Containers restarted successfully" -Level Success
    }

    # Verify network configuration
    Write-Log "Verifying network configuration..." -Level Info
    $newConfig = docker network inspect $NetworkName | ConvertFrom-Json
    if ($newConfig.IPAM.Config[0].Subnet -eq $Subnet) {
        Write-Log "Network configuration verified successfully" -Level Success
    } else {
        Write-Log "Network configuration verification failed" -Level Error
        Write-Log "Expected subnet: $Subnet" -Level Error
        Write-Log "Actual subnet: $($newConfig.IPAM.Config[0].Subnet)" -Level Error
    }
} else {
    Write-Log "Failed to create network" -Level Error
    exit 1
}

Write-Log "Network update completed!" -Level Success