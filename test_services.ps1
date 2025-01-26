# Test Services Script for Windows
Write-Host "🔍 Starting services verification..."

function Test-ServiceHealth {
    param (
        [string]$ServiceName,
        [string]$ContainerName,
        [string]$HealthEndpoint = ""
    )

    Write-Host -NoNewline "Testing $ServiceName... "

    try {
        # Check if container is running
        $container = docker ps --filter "name=^/${ContainerName}$" --format "{{.Status}}"
        if (-not $container) {
            Write-Host "❌ FAILED - Container not running"
            return $false
        }

        if ($container -notmatch "^Up ") {
            Write-Host "❌ FAILED - Container status: $container"
            return $false
        }

        # If health endpoint is provided, test it
        if ($HealthEndpoint) {
            $response = Invoke-WebRequest -Uri $HealthEndpoint -UseBasicParsing -SkipCertificateCheck
            if ($response.StatusCode -ne 200) {
                Write-Host "❌ FAILED - Health check returned status $($response.StatusCode)"
                return $false
            }
        }

        Write-Host "✅ OK"
        return $true
    }
    catch {
        Write-Host "❌ FAILED - Error: $_"
        return $false
    }
}

# Test 1: Check if Docker is running
Write-Host -NoNewline "Checking Docker service... "
try {
    $null = docker info 2>$null
    Write-Host "✅ OK"
}
catch {
    Write-Host "❌ FAILED - Docker is not running"
    exit 1
}

# Test 2: Check Traefik
Test-ServiceHealth -ServiceName "Traefik" -ContainerName "traefik"

# Test 3: Check OAuth2 Proxy
Test-ServiceHealth -ServiceName "OAuth2 Proxy" -ContainerName "oauth2-proxy"

# Test 4: Check Media Services
$mediaServices = @(
    @{Name = "Plex"; Container = "plex" },
    @{Name = "Sonarr"; Container = "sonarr" },
    @{Name = "Radarr"; Container = "radarr" },
    @{Name = "Lidarr"; Container = "lidarr" },
    @{Name = "Readarr"; Container = "readarr" },
    @{Name = "Prowlarr"; Container = "prowlarr" },
    @{Name = "Bazarr"; Container = "bazarr" },
    @{Name = "qBittorrent"; Container = "qbittorrent" }
)

foreach ($service in $mediaServices) {
    Test-ServiceHealth -ServiceName $service.Name -ContainerName $service.Container
}

# Test 5: Check Network Connectivity
Write-Host -NoNewline "Testing internal network connectivity... "
try {
    $network = docker network inspect proxy --format "{{range .Containers}}{{.Name}} {{end}}"
    if ($network) {
        Write-Host "✅ OK"
        Write-Host "Connected containers: $network"
    }
    else {
        Write-Host "❌ FAILED - No containers connected to proxy network"
    }
}
catch {
    Write-Host "❌ FAILED - Error inspecting network"
}

# Test 6: Check Traefik Dashboard
Write-Host -NoNewline "Testing Traefik Dashboard... "
try {
    $response = Invoke-WebRequest -Uri "https://traefik.sharphorizons.tech" -UseBasicParsing -SkipCertificateCheck
    Write-Host "✅ OK"
}
catch {
    Write-Host "❌ FAILED - Cannot access Traefik Dashboard"
}

Write-Host "🏁 Services verification complete"