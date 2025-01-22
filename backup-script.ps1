# Backup script for services with compression, rotation, and verification
param (
    [int]$RetentionDays = 7,
    [string]$BackupRoot = ".\backups",
    [string]$LogFile = ".\backups\backup.log"
)

# Function to write to log
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Tee-Object -FilePath $LogFile -Append
}

# Create backup directory structure
$date = Get-Date -Format "yyyy-MM-dd-HHmmss"
$backupDir = Join-Path $BackupRoot $date
$verificationDir = Join-Path $backupDir "verification"

try {
    Write-Log "Starting backup process..."
    
    # Create directories
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    New-Item -ItemType Directory -Force -Path $verificationDir | Out-Null

    # Backup docker compose file
    Copy-Item "docker-compose.yml" -Destination "$backupDir\docker-compose.yml"
    Write-Log "Backed up docker-compose.yml"

    # Backup config directories
    $services = @("radarr", "sonarr", "lidarr", "prowlarr", "bazarr", "readarr", "qbittorrent")
    foreach ($service in $services) {
        $sourceDir = ".\docker\$service"
        if (Test-Path $sourceDir) {
            $archivePath = "$backupDir\$service.zip"
            
            # Create compressed backup
            Compress-Archive -Path "$sourceDir\*" -DestinationPath $archivePath -Force
            Write-Log "Backed up $service configuration"

            # Verify backup
            try {
                Expand-Archive -Path $archivePath -DestinationPath "$verificationDir\$service" -Force
                if (Compare-Object -ReferenceObject (Get-ChildItem $sourceDir -Recurse) -DifferenceObject (Get-ChildItem "$verificationDir\$service" -Recurse)) {
                    throw "Verification failed for $service"
                }
                Write-Log "Verified $service backup"
            }
            catch {
                Write-Log "ERROR: Backup verification failed for $service: $_"
                throw
            }
        }
    }

    # Cleanup old backups
    Get-ChildItem -Path $BackupRoot -Directory | Where-Object {
        $_.LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays)
    } | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force
        Write-Log "Cleaned up old backup: $($_.Name)"
    }

    # Calculate total backup size
    $backupSize = (Get-ChildItem $backupDir -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
    Write-Log "Backup completed successfully. Total size: $([math]::Round($backupSize, 2)) MB"

    # Send email notification
    $emailParams = @{
        From = $env:FROM_ADDRESS
        To = $env:ADMIN_EMAIL
        Subject = "[BACKUP] Success - $(Get-Date -Format 'yyyy-MM-dd')"
        Body = "Backup completed successfully.`nLocation: $backupDir`nSize: $([math]::Round($backupSize, 2)) MB"
        SmtpServer = $env:SMTP_HOST
        Port = $env:SMTP_PORT
        UseSsl = $true
        Credential = New-Object System.Management.Automation.PSCredential($env:SMTP_USERNAME, (ConvertTo-SecureString $env:SMTP_PASSWORD -AsPlainText -Force))
    }
    Send-MailMessage @emailParams
    Write-Log "Sent backup notification email"
}
catch {
    $errorMessage = "Backup failed: $_"
    Write-Log "ERROR: $errorMessage"
    
    # Send error notification
    $emailParams = @{
        From = $env:FROM_ADDRESS
        To = $env:ADMIN_EMAIL
        Subject = "[BACKUP] FAILED - $(Get-Date -Format 'yyyy-MM-dd')"
        Body = $errorMessage
        SmtpServer = $env:SMTP_HOST
        Port = $env:SMTP_PORT
        UseSsl = $true
        Credential = New-Object System.Management.Automation.PSCredential($env:SMTP_USERNAME, (ConvertTo-SecureString $env:SMTP_PASSWORD -AsPlainText -Force))
    }
    Send-MailMessage @emailParams
    Write-Log "Sent backup failure notification email"
    throw
} 