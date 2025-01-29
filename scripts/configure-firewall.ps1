# Requires elevation (Run as Administrator)
#Requires -RunAsAdministrator

# Import environment variables from .env file
$envPath = Join-Path $PSScriptRoot "../.env"
Get-Content $envPath | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        Set-Item -Path "Env:$name" -Value $value
    }
}

# Function to create firewall rules
function New-FirewallRule {
    param (
        [string]$Name,
        [string]$DisplayName,
        [string]$Description,
        [int]$Port,
        [string]$Protocol = "TCP",
        [string]$Direction = "Inbound",
        [string]$Action = "Allow"
    )

    # Check if rule exists
    $existingRule = Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue

    if ($existingRule) {
        Write-Host "Rule '$DisplayName' already exists. Updating..." -ForegroundColor Yellow
        Remove-NetFirewallRule -DisplayName $DisplayName
    }

    # Create new rule
    New-NetFirewallRule -Name $Name `
        -DisplayName $DisplayName `
        -Description $Description `
        -Direction $Direction `
        -Protocol $Protocol `
        -LocalPort $Port `
        -Action $Action `
        -Enabled True

    Write-Host "Created/Updated rule: $DisplayName" -ForegroundColor Green
}

# Create rule group for Plex Media Server
Write-Host "Creating Plex Media Server firewall rules..." -ForegroundColor Cyan

# Main web access rules
New-FirewallRule -Name "Traefik_HTTP" `
    -DisplayName "Traefik HTTP (Port 80)" `
    -Description "Allow inbound HTTP traffic for Traefik" `
    -Port $env:TRAEFIK_HTTP_PORT

New-FirewallRule -Name "Traefik_HTTPS" `
    -DisplayName "Traefik HTTPS (Port 443)" `
    -Description "Allow inbound HTTPS traffic for Traefik" `
    -Port $env:TRAEFIK_HTTPS_PORT

# Metrics port (restricted to local network)
New-FirewallRule -Name "Traefik_Metrics" `
    -DisplayName "Traefik Metrics (Port 8082)" `
    -Description "Allow inbound metrics traffic for Traefik" `
    -Port $env:TRAEFIK_METRICS_PORT

# Plex Media Server ports
$plexPorts = @(
    @{Port = $env:PLEX_PORT; Protocol = "TCP"; Name = "Plex_Main"},
    @{Port = 3005; Protocol = "TCP"; Name = "Plex_Control"},
    @{Port = 8324; Protocol = "TCP"; Name = "Plex_Secondary"},
    @{Port = 32469; Protocol = "TCP"; Name = "Plex_DLNA"},
    @{Port = 1900; Protocol = "UDP"; Name = "Plex_Discovery"},
    @{Port = 32410; Protocol = "UDP"; Name = "Plex_GDM1"},
    @{Port = 32412; Protocol = "UDP"; Name = "Plex_GDM2"},
    @{Port = 32413; Protocol = "UDP"; Name = "Plex_GDM3"},
    @{Port = 32414; Protocol = "UDP"; Name = "Plex_GDM4"}
)

foreach ($port in $plexPorts) {
    New-FirewallRule -Name "PlexMediaServer_$($port.Name)" `
        -DisplayName "Plex Media Server ($($port.Protocol) Port $($port.Port))" `
        -Description "Allow inbound $($port.Protocol) traffic for Plex Media Server" `
        -Port $port.Port `
        -Protocol $port.Protocol
}

# Create rules for other services (internal access only)
$internalServices = @(
    @{Name = "Prowlarr"; Port = $env:PROWLARR_PORT},
    @{Name = "Radarr"; Port = $env:RADARR_PORT},
    @{Name = "Sonarr"; Port = $env:SONARR_PORT},
    @{Name = "Lidarr"; Port = $env:LIDARR_PORT},
    @{Name = "Readarr"; Port = $env:READARR_PORT},
    @{Name = "Bazarr"; Port = $env:BAZARR_PORT},
    @{Name = "Prometheus"; Port = $env:PROMETHEUS_PORT},
    @{Name = "Alertmanager"; Port = $env:ALERTMANAGER_PORT},
    @{Name = "NodeExporter"; Port = $env:NODE_EXPORTER_PORT},
    @{Name = "Cadvisor"; Port = $env:CADVISOR_PORT},
    @{Name = "OAuth2Proxy"; Port = $env:OAUTH2_PROXY_PORT}
)

foreach ($service in $internalServices) {
    New-FirewallRule -Name "$($service.Name)_Internal" `
        -DisplayName "$($service.Name) (Port $($service.Port))" `
        -Description "Allow inbound traffic for $($service.Name)" `
        -Port $service.Port
}

Write-Host "`nFirewall rules configuration completed!" -ForegroundColor Green
Write-Host "Please ensure your router/network firewall is configured to forward ports 80 and 443 to this server." -ForegroundColor Yellow