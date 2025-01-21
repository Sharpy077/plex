# Backup script for *arr services
$date = Get-Date -Format "yyyy-MM-dd"
$backupDir = ".\backups\$date"

# Create backup directory
New-Item -ItemType Directory -Force -Path $backupDir

# Backup docker compose file
Copy-Item "docker-compose.yml" -Destination "$backupDir\docker-compose.yml"

# Backup config directories
$services = @("radarr", "sonarr", "lidarr", "prowlarr", "bazarr", "readarr", "qbittorrent")
foreach ($service in $services) {
    $sourceDir = ".\docker\$service"
    if (Test-Path $sourceDir) {
        $destDir = "$backupDir\$service"
        New-Item -ItemType Directory -Force -Path $destDir
        Copy-Item "$sourceDir\*" -Destination $destDir -Recurse -Force
    }
}

Write-Host "Backup completed to $backupDir" 