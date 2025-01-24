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

# Function to get file hashes recursively
function Get-FileHashes {
    param([string]$Path)
    
    Get-ChildItem $Path -Recurse -File | ForEach-Object {
        $relativePath = $_.FullName.Substring($Path.Length + 1)
        $hash = Get-FileHash $_.FullName -Algorithm SHA256
        [PSCustomObject]@{
            RelativePath = $relativePath
            Hash = $hash.Hash
            Size = $_.Length
        }
    }
}

# Function to verify backup integrity
function Test-BackupIntegrity {
    param(
        [string]$SourceDir,
        [string]$BackupDir,
        [string]$Service
    )
    
    $sourceHashes = Get-FileHashes $SourceDir
    $backupHashes = Get-FileHashes $BackupDir
    
    # Compare file counts
    if ($sourceHashes.Count -ne $backupHashes.Count) {
        throw ("File count mismatch for " + $Service + ". Source: " + $sourceHashes.Count + ", Backup: " + $backupHashes.Count)
    }
    
    # Compare each file
    foreach ($sourceFile in $sourceHashes) {
        $backupFile = $backupHashes | Where-Object { $_.RelativePath -eq $sourceFile.RelativePath }
        
        if (-not $backupFile) {
            throw ("Missing file in backup: " + $sourceFile.RelativePath)
        }
        
        if ($sourceFile.Hash -ne $backupFile.Hash) {
            throw ("Hash mismatch for file: " + $sourceFile.RelativePath)
        }
        
        if ($sourceFile.Size -ne $backupFile.Size) {
            throw ("Size mismatch for file: " + $sourceFile.RelativePath)
        }
    }
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
                Test-BackupIntegrity -SourceDir $sourceDir -BackupDir "$verificationDir\$service" -Service $service
                Write-Log "Verified $service backup integrity"
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