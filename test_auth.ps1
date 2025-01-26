# Test OAuth2 Authentication Flow
Write-Host "🔍 Starting OAuth2 authentication tests..."

function Test-Endpoint {
    param (
        [string]$Name,
        [string]$Url,
        [switch]$ExpectAuth,
        [switch]$ExpectPlexAuth
    )

    Write-Host -NoNewline "Testing $Name ($Url)... "
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -SkipCertificateCheck -MaximumRedirection 0 -ErrorAction SilentlyContinue
        $statusCode = $response.StatusCode
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
    }

    if ($ExpectAuth) {
        # Should redirect to auth (302) or require auth (401)
        if ($statusCode -in @(302, 401)) {
            Write-Host "✅ OK (Status: $statusCode - Authentication required)"
            return $true
        }
        else {
            Write-Host "❌ FAILED - Expected auth requirement, got status $statusCode"
            return $false
        }
    }
    elseif ($ExpectPlexAuth) {
        # Plex should return 401 for its own auth
        if ($statusCode -eq 401) {
            Write-Host "✅ OK (Status: 401 - Plex authentication required)"
            return $true
        }
        else {
            Write-Host "❌ FAILED - Expected Plex auth requirement (401), got status $statusCode"
            return $false
        }
    }
    else {
        # Should allow access (200)
        if ($statusCode -eq 200) {
            Write-Host "✅ OK (Status: 200)"
            return $true
        }
        else {
            Write-Host "❌ FAILED - Expected 200, got status $statusCode"
            return $false
        }
    }
}

# Test 1: OAuth2 Proxy Health
Write-Host -NoNewline "Checking OAuth2 Proxy health... "
try {
    $response = Invoke-WebRequest -Uri "http://localhost:4180/ping" -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ OK"
    }
    else {
        Write-Host "❌ FAILED - Status: $($response.StatusCode)"
    }
}
catch {
    Write-Host "❌ FAILED - Error: $_"
}

# Test 2: Protected Endpoints
$protectedEndpoints = @(
    @{Name = "Traefik Dashboard"; Url = "https://traefik.sharphorizons.tech" },
    @{Name = "Sonarr"; Url = "https://sonarr.sharphorizons.tech" },
    @{Name = "Radarr"; Url = "https://radarr.sharphorizons.tech" },
    @{Name = "Lidarr"; Url = "https://lidarr.sharphorizons.tech" },
    @{Name = "Readarr"; Url = "https://readarr.sharphorizons.tech" },
    @{Name = "Prowlarr"; Url = "https://prowlarr.sharphorizons.tech" },
    @{Name = "Bazarr"; Url = "https://bazarr.sharphorizons.tech" },
    @{Name = "qBittorrent"; Url = "https://qbit.sharphorizons.tech" }
)

foreach ($endpoint in $protectedEndpoints) {
    Test-Endpoint -Name $endpoint.Name -Url $endpoint.Url -ExpectAuth
}

# Test 3: Plex Endpoint (expects Plex auth)
Test-Endpoint -Name "Plex" -Url "https://plex.sharphorizons.tech" -ExpectPlexAuth

# Test 4: OAuth2 Callback URL
Write-Host -NoNewline "Testing OAuth2 callback URL... "
try {
    $response = Invoke-WebRequest -Uri "https://auth.sharphorizons.tech/oauth2/callback" -UseBasicParsing -SkipCertificateCheck -MaximumRedirection 0 -ErrorAction SilentlyContinue
    if ($response.StatusCode -eq 302) {
        Write-Host "✅ OK (Redirects as expected)"
    }
    else {
        Write-Host "❌ FAILED - Expected redirect, got status $($response.StatusCode)"
    }
}
catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 302) {
        Write-Host "✅ OK (Redirects as expected)"
    }
    else {
        Write-Host "❌ FAILED - Error: $_"
    }
}

Write-Host "🏁 OAuth2 authentication tests complete"

# Test OAuth2 configuration
$baseUrl = "https://auth.sharphorizons.tech"
$testUrls = @(
    "/oauth2/callback",
    "/oauth2/start",
    "/oauth2/sign_in",
    "/ping"
)

Write-Host "Testing OAuth2 Configuration..."
Write-Host "-----------------------------"

foreach ($path in $testUrls) {
    $url = $baseUrl + $path
    Write-Host "Testing $url"
    try {
        $response = Invoke-WebRequest -Uri $url -Method GET -SkipCertificateCheck
        Write-Host "Status: $($response.StatusCode)"
        Write-Host "Headers:"
        $response.Headers | Format-Table -AutoSize
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)"
    }
    Write-Host "-----------------------------"
}