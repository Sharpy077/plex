# Test Setup Script for Windows
Write-Host "🔍 Starting setup verification..."

# Test 1: Check Docker network
Write-Host -NoNewline "Testing Docker network 'proxy'... "
try {
    $network = docker network inspect proxy 2>$null
    Write-Host "✅ OK"
}
catch {
    Write-Host "❌ FAILED - Network not found"
    docker network create proxy
    Write-Host "🔧 Created proxy network"
}

# Test 2: Check required directories
Write-Host -NoNewline "Checking required directories... "
$DIRS = @(
    "docker\secrets",
    "config\plex",
    "config\qbittorrent",
    "config\prowlarr",
    "config\radarr",
    "config\sonarr",
    "config\lidarr",
    "config\readarr",
    "config\bazarr",
    "tv",
    "movies",
    "music",
    "downloads",
    "traefik\config",
    "letsencrypt"
)

$FAILED = $false
foreach ($dir in $DIRS) {
    if (-not (Test-Path $dir -PathType Container)) {
        Write-Host "❌ Missing: $dir"
        $FAILED = $true
    }
}
if (-not $FAILED) { Write-Host "✅ OK" }

# Test 3: Check configuration files
Write-Host -NoNewline "Checking configuration files... "
$CONFIG_FILES = @(
    "traefik\config\middlewares.yml",
    ".env"
)

$FAILED = $false
foreach ($file in $CONFIG_FILES) {
    if (-not (Test-Path $file -PathType Leaf)) {
        Write-Host "❌ Missing: $file"
        $FAILED = $true
    }
}
if (-not $FAILED) { Write-Host "✅ OK" }

# Test 4: Check environment variables
Write-Host -NoNewline "Checking environment variables... "
if (Test-Path ".env" -PathType Leaf) {
    $REQUIRED_VARS = @(
        "COOKIE_SECRET",
        "GITHUB_CLIENT_ID",
        "GITHUB_CLIENT_SECRET",
        "TZ",
        "PUID",
        "PGID"
    )

    $FAILED = $false
    $envContent = Get-Content ".env"
    foreach ($var in $REQUIRED_VARS) {
        if (-not ($envContent -match "^${var}=")) {
            Write-Host "❌ Missing: $var in .env"
            $FAILED = $true
        }
    }
    if (-not $FAILED) { Write-Host "✅ OK" }
}
else {
    Write-Host "❌ FAILED - .env file not found"
}

# Test 5: Check Docker Compose file
Write-Host -NoNewline "Validating docker-compose.yml... "
try {
    $null = docker-compose config 2>$null
    Write-Host "✅ OK"
}
catch {
    Write-Host "❌ FAILED - Invalid docker-compose.yml"
}

Write-Host "🏁 Setup verification complete"