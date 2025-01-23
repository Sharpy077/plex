# Test script for Docker media server setup
param(
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$VerbosePreference = if ($Verbose) { "Continue" } else { "SilentlyContinue" }

function Test-NetworkSetup {
    Write-Verbose "Testing Docker networks..."
    
    $networks = docker network ls --format "{{.Name}}"
    $requiredNetworks = @("proxy", "media", "downloads", "monitoring", "vlan20")
    
    foreach ($network in $requiredNetworks) {
        if ($networks -notcontains $network) {
            Write-Error "Required network '$network' not found"
            return $false
        }
    }
    Write-Host "✅ Network setup verified" -ForegroundColor Green
    return $true
}

function Test-ContainerHealth {
    Write-Verbose "Testing container health..."
    
    $containers = docker ps --format "{{.Names}}"
    $requiredContainers = @(
        "traefik",
        "plex",
        "sonarr",
        "radarr",
        "lidarr",
        "readarr",
        "bazarr",
        "prowlarr",
        "qbittorrent",
        "prometheus",
        "alertmanager",
        "node-exporter",
        "cadvisor"
    )
    
    $allHealthy = $true
    foreach ($container in $requiredContainers) {
        $status = docker inspect --format "{{.State.Status}}" $container 2>$null
        $health = docker inspect --format "{{.State.Health.Status}}" $container 2>$null
        
        if ($status -ne "running") {
            Write-Error "Container '$container' is not running (Status: $status)"
            $allHealthy = $false
            continue
        }
        
        if ($health -and $health -ne "healthy") {
            Write-Error "Container '$container' is not healthy (Health: $health)"
            $allHealthy = $false
            continue
        }
        
        Write-Verbose "Container '$container' is healthy"
    }
    
    if ($allHealthy) {
        Write-Host "✅ All containers are running and healthy" -ForegroundColor Green
    }
    return $allHealthy
}

function Test-TraefikConfig {
    Write-Verbose "Testing Traefik configuration..."
    
    # Check if Traefik config files exist
    $configFiles = @(
        "./traefik/traefik.yml",
        "./traefik/config/middleware.yml"
    )
    
    foreach ($file in $configFiles) {
        if (-not (Test-Path $file)) {
            Write-Error "Traefik config file '$file' not found"
            return $false
        }
    }
    
    # Check if SSL certificates are being generated
    if (-not (Test-Path "./letsencrypt/acme.json")) {
        Write-Error "SSL certificate file not found"
        return $false
    }
    
    Write-Host "✅ Traefik configuration verified" -ForegroundColor Green
    return $true
}

function Test-MonitoringSetup {
    Write-Verbose "Testing monitoring setup..."
    
    # Check Prometheus config
    if (-not (Test-Path "./prometheus/prometheus.yml")) {
        Write-Error "Prometheus config file not found"
        return $false
    }
    
    # Check Alertmanager config
    if (-not (Test-Path "./alertmanager/config.yml")) {
        Write-Error "Alertmanager config file not found"
        return $false
    }
    
    # Verify Prometheus configuration
    $promCheck = docker exec prometheus promtool check config /etc/prometheus/prometheus.yml
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Prometheus configuration check failed"
        return $false
    }
    
    Write-Host "✅ Monitoring setup verified" -ForegroundColor Green
    return $true
}

function Test-MediaPaths {
    Write-Verbose "Testing media paths..."
    
    $paths = @(
        "./media/movies",
        "./media/tv",
        "./media/music",
        "./media/books",
        "./media/downloads",
        "./docker",
        "./backups"
    )
    
    foreach ($path in $paths) {
        if (-not (Test-Path $path)) {
            Write-Error "Required path '$path' not found"
            return $false
        }
        
        # Check write permissions
        try {
            $testFile = Join-Path $path ".write_test"
            New-Item -ItemType File -Path $testFile -Force | Out-Null
            Remove-Item $testFile -Force
        }
        catch {
            Write-Error "No write permission for path '$path'"
            return $false
        }
    }
    
    Write-Host "✅ Media paths verified" -ForegroundColor Green
    return $true
}

function Test-EnvironmentVariables {
    Write-Verbose "Testing environment variables..."
    
    if (-not (Test-Path ".env")) {
        Write-Error "Environment file '.env' not found"
        return $false
    }
    
    $requiredVars = @(
        "PUID",
        "PGID",
        "TZ",
        "COOKIE_DOMAIN",
        "ADMIN_EMAIL",
        "GITHUB_CLIENT_ID",
        "GITHUB_CLIENT_SECRET",
        "AUTH_SECRET"
    )
    
    $envContent = Get-Content ".env"
    foreach ($var in $requiredVars) {
        if (-not ($envContent -match "^$var=.+")) {
            Write-Error "Required environment variable '$var' not found or empty"
            return $false
        }
    }
    
    Write-Host "✅ Environment variables verified" -ForegroundColor Green
    return $true
}

# Run all tests
Write-Host "Starting system tests..." -ForegroundColor Cyan

$testResults = @(
    (Test-NetworkSetup),
    (Test-ContainerHealth),
    (Test-TraefikConfig),
    (Test-MonitoringSetup),
    (Test-MediaPaths),
    (Test-EnvironmentVariables)
)

# Summary
Write-Host "`nTest Summary:" -ForegroundColor Cyan
$passedTests = ($testResults | Where-Object { $_ -eq $true }).Count
$totalTests = $testResults.Count

Write-Host "Passed: $passedTests/$totalTests tests" -ForegroundColor $(if ($passedTests -eq $totalTests) { "Green" } else { "Red" })

# Exit with appropriate code
exit $(if ($passedTests -eq $totalTests) { 0 } else { 1 }) 