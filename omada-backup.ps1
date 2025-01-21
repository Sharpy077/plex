# Omada Controller Backup Script
$date = Get-Date -Format "yyyy-MM-dd"
$backupDir = ".\omada_backups\$date"
$omadaConfigDir = "C:\Program Files\TP-Link\OmadaController\data"
$omadaBackupFile = "omada_backup_$date.tar.gz"

# Create backup directory
New-Item -ItemType Directory -Force -Path $backupDir

# Backup Omada Configuration
Copy-Item -Path "$omadaConfigDir\*" -Destination $backupDir -Recurse -Force

# Backup VLAN Configuration
Get-Content ".\omada-vlan-config.txt" | Out-File "$backupDir\vlan_config_backup.txt"

# Backup Firewall Rules
Get-Content ".\omada-firewall-rules.txt" | Out-File "$backupDir\firewall_rules_backup.txt"

# Backup SSL Configuration
Get-Content ".\ssl-config.txt" | Out-File "$backupDir\ssl_config_backup.txt"

# Compress backup
Compress-Archive -Path "$backupDir\*" -DestinationPath "$backupDir\$omadaBackupFile"

# Clean up old backups (keep last 7 days)
Get-ChildItem ".\omada_backups" | Where-Object {
    $_.PSIsContainer -and 
    $_.CreationTime -lt (Get-Date).AddDays(-7)
} | Remove-Item -Recurse -Force

Write-Host "Backup completed to $backupDir\$omadaBackupFile"

# Optional: Upload to remote storage
# Add your remote storage upload commands here 