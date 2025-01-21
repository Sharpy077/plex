# Deployment and Configuration Script

# 1. Generate Secrets
Write-Host "Generating secrets..." -ForegroundColor Cyan
.\generate-secrets.ps1
$secrets = Get-Content .\secrets.json | ConvertFrom-Json

# 2. Update Configurations
Write-Host "Updating configurations..." -ForegroundColor Cyan

# Update Authelia configuration
$authelia_config = Get-Content .\authelia\configuration.yml -Raw
$authelia_config = $authelia_config.Replace("generate_a_secure_secret_here", $secrets.jwt_secret)
$authelia_config = $authelia_config.Replace("generate_another_secure_secret", $secrets.session_secret)
$authelia_config | Set-Content .\authelia\configuration.yml

# Generate Argon2 hashes for passwords
function Get-Argon2Hash {
    param (
        [string]$password
    )
    docker run --rm authelia/authelia:latest authelia hash-password $password
}

# Update users database
$admin_hash = Get-Argon2Hash -password $secrets.admin_password
$user_hash = Get-Argon2Hash -password $secrets.user_password

$users_db = Get-Content .\authelia\users_database.yml -Raw
$users_db = $users_db.Replace('$argon2id$v=19$m=65536,t=1,p=8$cGFzc3dvcmQ$hashedpassword', $admin_hash)
Set-Content .\authelia\users_database.yml $users_db

# 3. Create Required Directories
Write-Host "Creating directories..." -ForegroundColor Cyan
$directories = @(
    ".\docker\radarr",
    ".\docker\sonarr",
    ".\docker\lidarr",
    ".\docker\prowlarr",
    ".\docker\bazarr",
    ".\docker\readarr",
    ".\docker\qbittorrent",
    ".\docker\wireguard",
    ".\letsencrypt",
    ".\prometheus",
    ".\grafana",
    ".\alertmanager"
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force
    }
}

# 4. Start Services
Write-Host "Starting services..." -ForegroundColor Cyan
docker compose down
docker compose up -d

# 5. Run Security Tests
Write-Host "Running security tests..." -ForegroundColor Cyan
Start-Sleep -Seconds 30  # Wait for services to start
.\security-test.ps1

# 6. Schedule Tasks
Write-Host "Scheduling maintenance tasks..." -ForegroundColor Cyan
.\schedule-tasks.ps1

# 7. Output Access Information
Write-Host "`nDeployment Complete!" -ForegroundColor Green
Write-Host "`nAccess Information:" -ForegroundColor Cyan
Write-Host "Admin Credentials:"
Write-Host "  Username: admin"
Write-Host "  Password: $($secrets.admin_password)"
Write-Host "`nUser Credentials:"
Write-Host "  Username: user"
Write-Host "  Password: $($secrets.user_password)"
Write-Host "`nService URLs:"
Write-Host "  Authelia: https://auth.local"
Write-Host "  Radarr:   https://radarr.local"
Write-Host "  Sonarr:   https://sonarr.local"
Write-Host "  Lidarr:   https://lidarr.local"
Write-Host "  Prowlarr: https://prowlarr.local"
Write-Host "  Bazarr:   https://bazarr.local"
Write-Host "  Readarr:  https://readarr.local"
Write-Host "  Grafana:  https://grafana.local"

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "1. Configure your domain DNS settings"
Write-Host "2. Set up WireGuard clients using configs in ./docker/wireguard"
Write-Host "3. Configure email notifications in Authelia"
Write-Host "4. Set up indexers in Prowlarr"
Write-Host "5. Configure media paths in *arr services" 