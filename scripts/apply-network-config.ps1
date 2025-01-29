# Apply Network Configuration Script
param(
    [switch]$SkipOmada,
    [switch]$SkipTraefik,
    [switch]$SkipRestart
)

$ErrorActionPreference = "Stop"

Write-Host "Starting network configuration..." -ForegroundColor Cyan

# 1. Configure Omada Controller
if (-not $SkipOmada) {
    Write-Host "`nConfiguring Omada Controller..." -ForegroundColor Green
    try {
        & "$PSScriptRoot\configure-omada.ps1"
    }
    catch {
        Write-Host "Error configuring Omada Controller: $_" -ForegroundColor Red
        exit 1
    }
}

# 2. Clear existing certificates and logs
if (-not $SkipTraefik) {
    Write-Host "`nClearing existing certificates and logs..." -ForegroundColor Green
    Remove-Item -Path "..\letsencrypt\*" -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item -Path "..\logs\traefik\*" -Force -Recurse -ErrorAction SilentlyContinue
}

# 3. Restart services
if (-not $SkipRestart) {
    Write-Host "`nRestarting Docker services..." -ForegroundColor Green
    try {
        docker-compose down
        Start-Sleep -Seconds 5
        docker-compose up -d
    }
    catch {
        Write-Host "Error restarting services: $_" -ForegroundColor Red
        exit 1
    }
}

# 4. Monitor certificate generation
Write-Host "`nMonitoring certificate generation..." -ForegroundColor Green
Write-Host "Waiting 30 seconds for services to initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

Write-Host "`nChecking Traefik logs for certificate status..." -ForegroundColor Cyan
docker-compose logs -f traefik | Select-String -Pattern "obtained|success|certificate issued|error|challenge|acme"

Write-Host "`nNetwork configuration completed!" -ForegroundColor Green
Write-Host @"
Next steps:
1. Verify Traefik dashboard at https://traefik.sharphorizons.tech
2. Check certificate status in the Traefik dashboard
3. Test accessing services through their domains
4. Monitor Traefik logs for any issues
"@ -ForegroundColor Yellow