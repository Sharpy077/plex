# Docker and System Cleanup Manager
# This script handles routine cleanup tasks for Docker and system maintenance

param (
    [switch]$Force,
    [int]$RetentionDays = 7,
    [int]$MinDiskSpaceGB = 10,
    [string]$LogPath = "../logs/maintenance"
)

# Import common functions
. "../common/logging.ps1"
. "../common/config-helper.ps1"

# Initialize logging
$LogFile = Join-Path $LogPath "cleanup-$(Get-Date -Format 'yyyyMMdd').log"
Initialize-Logging $LogFile

function Test-DiskSpace {
    param (
        [string]$Path = "/"
    )
    $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$Path'" | Select-Object Size, FreeSpace
    $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    $totalGB = [math]::Round($disk.Size / 1GB, 2)
    $freePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)

    Write-Log "Disk space check - Free: ${freeGB}GB / Total: ${totalGB}GB (${freePercent}%)"
    return $freeGB -lt $MinDiskSpaceGB
}

function Remove-OldImages {
    Write-Log "Removing unused Docker images older than $RetentionDays days..."
    try {
        # Get list of images with their creation date
        $images = docker images --format "{{.ID}}\t{{.CreatedAt}}" | ForEach-Object {
            $parts = $_ -split "\t"
            [PSCustomObject]@{
                ID      = $parts[0]
                Created = [DateTime]::Parse($parts[1])
            }
        }

        # Remove old images
        foreach ($image in $images) {
            if ((Get-Date).Subtract($image.Created).Days -gt $RetentionDays) {
                Write-Log "Removing image $($image.ID) - Created: $($image.Created)"
                docker rmi $image.ID -f
            }
        }
    }
    catch {
        Write-Log "Error removing old images: $_" -Level Error
    }
}

function Remove-UnusedVolumes {
    Write-Log "Removing unused Docker volumes..."
    try {
        docker volume prune -f
    }
    catch {
        Write-Log "Error removing unused volumes: $_" -Level Error
    }
}

function Remove-StoppedContainers {
    Write-Log "Removing stopped containers..."
    try {
        docker container prune -f
    }
    catch {
        Write-Log "Error removing stopped containers: $_" -Level Error
    }
}

function Clear-LogFiles {
    param (
        [string]$LogDirectory = "../logs"
    )
    Write-Log "Cleaning old log files..."
    try {
        Get-ChildItem -Path $LogDirectory -Recurse -File |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays) } |
        ForEach-Object {
            Write-Log "Removing old log file: $($_.FullName)"
            Remove-Item $_.FullName -Force
        }
    }
    catch {
        Write-Log "Error cleaning log files: $_" -Level Error
    }
}

function Clear-TempFiles {
    Write-Log "Cleaning temporary files..."
    try {
        $tempPaths = @(
            $env:TEMP,
            "../temp",
            "../downloads/temp"
        )

        foreach ($path in $tempPaths) {
            if (Test-Path $path) {
                Get-ChildItem -Path $path -Recurse -File |
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } |
                Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Log "Error cleaning temp files: $_" -Level Error
    }
}

function Optimize-DatabaseFiles {
    Write-Log "Optimizing database files..."
    try {
        # Add database optimization logic here
        # Example for SQLite databases
        Get-ChildItem -Path "../data" -Recurse -Filter "*.db" | ForEach-Object {
            Write-Log "Optimizing database: $($_.FullName)"
            sqlite3 $_.FullName "VACUUM;"
        }
    }
    catch {
        Write-Log "Error optimizing databases: $_" -Level Error
    }
}

# Main execution
try {
    Write-Log "Starting cleanup process..."

    # Check disk space
    if (Test-DiskSpace) {
        Write-Log "Low disk space detected. Forcing cleanup..." -Level Warning
        $Force = $true
    }

    # Execute cleanup tasks
    if ($Force) {
        Remove-OldImages
        Remove-UnusedVolumes
        Remove-StoppedContainers
        Clear-LogFiles
        Clear-TempFiles
        Optimize-DatabaseFiles
    }
    else {
        # Regular maintenance
        Remove-StoppedContainers
        Clear-TempFiles
        if ((Get-Date).DayOfWeek -eq "Sunday") {
            Remove-OldImages
            Remove-UnusedVolumes
            Clear-LogFiles
            Optimize-DatabaseFiles
        }
    }

    Write-Log "Cleanup process completed successfully."
}
catch {
    Write-Log "Error during cleanup process: $_" -Level Error
    exit 1
}