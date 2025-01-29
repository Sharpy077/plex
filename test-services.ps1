# Test Services Script
# This script performs comprehensive testing of all services in the media server setup

# Function to test DNS resolution
function Test-DNSResolution {
    param (
        [string]$Domain,
        [string]$ExpectedIP = "202.128.124.242"
    )
    Write-Host "`nTesting DNS resolution for $Domain..." -ForegroundColor Cyan
    try {
        $result = Resolve-DnsName -Name $Domain -ErrorAction Stop
        $ip = $result | Where-Object { $_.Type -eq 'A' } | Select-Object -ExpandProperty IPAddress
        if ($ip -eq $ExpectedIP) {
            Write-Host "[PASS] DNS resolution successful: $Domain -> $ip" -ForegroundColor Green
            return $true
        } else {
            Write-Host "[FAIL] DNS resolution mismatch: $Domain -> $ip (Expected: $ExpectedIP)" -ForegroundColor Red
            return $false
        }
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Host ("[FAIL] DNS resolution failed for " + $Domain + ": " + $errorMsg) -ForegroundColor Red
        return $false
    }
}

# Function to test HTTPS connectivity
function Test-HTTPSConnection {
    param (
        [string]$URL
    )
    Write-Host "`nTesting HTTPS connectivity for $URL..." -ForegroundColor Cyan
    try {
        $response = Invoke-WebRequest -Uri "https://$URL" -Method Head -UseBasicParsing -SkipCertificateCheck
        Write-Host "[PASS] HTTPS connection successful: $URL (Status: $($response.StatusCode))" -ForegroundColor Green
        return $true
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Host ("[FAIL] HTTPS connection failed for " + $URL + ": " + $errorMsg) -ForegroundColor Red
        return $false
    }
}

# Function to test service health
function Test-ServiceHealth {
    param (
        [string]$ServiceName,
        [string]$ContainerName
    )
    Write-Host "`nTesting health for $ServiceName..." -ForegroundColor Cyan
    try {
        $status = docker container inspect -f '{{.State.Status}}' $ContainerName 2>$null
        $health = docker container inspect -f '{{.State.Health.Status}}' $ContainerName 2>$null

        if ($status -eq "running") {
            if ($health) {
                Write-Host "[PASS] Service $ServiceName is running (Health: $health)" -ForegroundColor Green
            } else {
                Write-Host "[PASS] Service $ServiceName is running" -ForegroundColor Green
            }
            return $true
        } else {
            Write-Host "[FAIL] Service $ServiceName is not running (Status: $status)" -ForegroundColor Red
            return $false
        }
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Host ("[FAIL] Failed to check service " + $ServiceName + ": " + $errorMsg) -ForegroundColor Red
        return $false
    }
}

# Main testing sequence
Write-Host "Starting comprehensive service tests..." -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow

# Define services to test
$services = @(
    @{Name="Traefik"; Domain="traefik.sharphorizons.tech"; Container="traefik"},
    @{Name="OAuth2 Proxy"; Domain="auth.sharphorizons.tech"; Container="oauth2-proxy"},
    @{Name="Plex"; Domain="plex.sharphorizons.tech"; Container="plex"},
    @{Name="qBittorrent"; Domain="qbittorrent.sharphorizons.tech"; Container="qbittorrent"},
    @{Name="Prowlarr"; Domain="prowlarr.sharphorizons.tech"; Container="prowlarr"},
    @{Name="Radarr"; Domain="radarr.sharphorizons.tech"; Container="radarr"},
    @{Name="Sonarr"; Domain="sonarr.sharphorizons.tech"; Container="sonarr"},
    @{Name="Metrics"; Domain="metrics.sharphorizons.tech"; Container="traefik"}
)

# Test results tracking
$results = @{
    DNSTests = 0
    DNSPassed = 0
    HTTPSTests = 0
    HTTPSPassed = 0
    ServiceTests = 0
    ServicePassed = 0
}

# Run tests for each service
foreach ($service in $services) {
    Write-Host "`nTesting $($service.Name)..." -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Yellow

    # DNS Test
    $results.DNSTests++
    if (Test-DNSResolution -Domain $service.Domain) {
        $results.DNSPassed++
    }

    # HTTPS Test
    $results.HTTPSTests++
    if (Test-HTTPSConnection -URL $service.Domain) {
        $results.HTTPSPassed++
    }

    # Service Health Test
    $results.ServiceTests++
    if (Test-ServiceHealth -ServiceName $service.Name -ContainerName $service.Container) {
        $results.ServicePassed++
    }
}

# Display summary
Write-Host "`nTest Summary" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "DNS Tests: $($results.DNSPassed)/$($results.DNSTests) passed" -ForegroundColor $(if ($results.DNSPassed -eq $results.DNSTests) { "Green" } else { "Red" })
Write-Host "HTTPS Tests: $($results.HTTPSPassed)/$($results.HTTPSTests) passed" -ForegroundColor $(if ($results.HTTPSPassed -eq $results.HTTPSTests) { "Green" } else { "Red" })
Write-Host "Service Tests: $($results.ServicePassed)/$($results.ServiceTests) passed" -ForegroundColor $(if ($results.ServicePassed -eq $results.ServiceTests) { "Green" } else { "Red" })

# Calculate overall status
$totalTests = $results.DNSTests + $results.HTTPSTests + $results.ServiceTests
$totalPassed = $results.DNSPassed + $results.HTTPSPassed + $results.ServicePassed
$passRate = [math]::Round(($totalPassed / $totalTests) * 100, 2)

Write-Host "`nOverall Status: $passRate% tests passed" -ForegroundColor $(if ($passRate -eq 100) { "Green" } elseif ($passRate -gt 80) { "Yellow" } else { "Red" })
