# Security Test Script

# Function to test a service
function Test-Service {
    param (
        [string]$name,
        [string]$url,
        [int]$expectedCode = 200
    )
    
    Write-Host "Testing $name..."
    try {
        $response = Invoke-WebRequest -Uri $url -Method GET -SkipCertificateCheck
        if ($response.StatusCode -eq $expectedCode) {
            Write-Host "✓ $name is properly secured (Status: $($response.StatusCode))" -ForegroundColor Green
        } else {
            Write-Host "✗ $name returned unexpected status code: $($response.StatusCode)" -ForegroundColor Red
        }
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 401) {
            Write-Host "✓ $name requires authentication (Status: 401)" -ForegroundColor Green
        } else {
            Write-Host "✗ $name error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Function to test WireGuard
function Test-WireGuard {
    Write-Host "Testing WireGuard..."
    $wg = Get-Process | Where-Object { $_.ProcessName -eq "wireguard" }
    if ($wg) {
        Write-Host "✓ WireGuard is running" -ForegroundColor Green
        
        # Test UDP port
        $udpTest = Test-NetConnection -ComputerName localhost -Port 51820 -InformationLevel Quiet
        if ($udpTest) {
            Write-Host "✓ WireGuard port 51820 is open" -ForegroundColor Green
        } else {
            Write-Host "✗ WireGuard port 51820 is closed" -ForegroundColor Red
        }
    } else {
        Write-Host "✗ WireGuard is not running" -ForegroundColor Red
    }
}

# Function to test SSL
function Test-SSL {
    param (
        [string]$domain
    )
    
    Write-Host "Testing SSL for $domain..."
    try {
        $cert = Invoke-WebRequest -Uri "https://$domain" -Method GET -SkipCertificateCheck
        $certInfo = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($cert.Certificate)
        
        Write-Host "Certificate Details:" -ForegroundColor Cyan
        Write-Host "  Issuer: $($certInfo.Issuer)"
        Write-Host "  Valid Until: $($certInfo.NotAfter)"
        Write-Host "  Protocol: $($cert.Protocol)"
        
        if ($certInfo.NotAfter -gt (Get-Date)) {
            Write-Host "✓ SSL certificate is valid" -ForegroundColor Green
        } else {
            Write-Host "✗ SSL certificate has expired" -ForegroundColor Red
        }
    } catch {
        Write-Host "✗ SSL test failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Main testing sequence
Write-Host "Starting Security Tests..." -ForegroundColor Cyan

# Test Authentication
Test-Service -name "Authelia" -url "https://auth.local"
Test-Service -name "Traefik Dashboard" -url "https://traefik.local"

# Test Services
$services = @(
    @{name="Radarr"; url="https://radarr.local"},
    @{name="Sonarr"; url="https://sonarr.local"},
    @{name="Lidarr"; url="https://lidarr.local"},
    @{name="Prowlarr"; url="https://prowlarr.local"},
    @{name="Bazarr"; url="https://bazarr.local"},
    @{name="Readarr"; url="https://readarr.local"},
    @{name="qBittorrent"; url="https://qbit.local"}
)

foreach ($service in $services) {
    Test-Service -name $service.name -url $service.url
}

# Test WireGuard
Test-WireGuard

# Test SSL Certificates
$domains = @(
    "auth.local",
    "traefik.local",
    "radarr.local",
    "sonarr.local"
)

foreach ($domain in $domains) {
    Test-SSL -domain $domain
}

Write-Host "`nSecurity Test Complete" -ForegroundColor Cyan 