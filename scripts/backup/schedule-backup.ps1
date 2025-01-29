<#
.SYNOPSIS
    Schedules daily backup tasks for the Plex server environment.

.DESCRIPTION
    This script creates a Windows Scheduled Task to run the backup script daily.
    It configures the task with proper credentials, retry settings, and logging.
    The task is set to run at 3 AM daily with automatic retry on failure.

.PARAMETER TaskName
    Name of the scheduled task. Defaults to "PlexServerBackup".

.PARAMETER BackupTime
    Time to run the backup. Defaults to "3AM".

.PARAMETER RetryCount
    Number of times to retry on failure. Defaults to 3.

.PARAMETER RetryInterval
    Interval between retries in minutes. Defaults to 1.

.DEPENDENCIES
    Required PowerShell modules:
    - ScheduledTasks (built-in)

.EXAMPLE
    .\schedule-backup.ps1 -TaskName "CustomBackupTask" -BackupTime "2AM"

.NOTES
    Author: System Administrator
    Last Modified: 2024-01-27
    Version: 1.0
#>

param (
    [string]$TaskName = "PlexServerBackup",
    [string]$BackupTime = "3AM",
    [int]$RetryCount = 3,
    [int]$RetryInterval = 1
)

# Script configuration
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Function definitions
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(
        switch ($Level) {
            'WARNING' { 'Yellow' }
            'ERROR' { 'Red' }
            default { 'White' }
        }
    )
}

function Test-AdminPrivileges {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script requires administrative privileges to create scheduled tasks"
    }
}

function New-BackupTask {
    try {
        # Create the action to run the backup script
        $scriptPath = Join-Path $PWD "backup-script.ps1"
        if (-not (Test-Path $scriptPath)) {
            throw "Backup script not found at: $scriptPath"
        }

        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
            -Argument "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`""
        Write-Log "Created scheduled task action"

        # Create the daily trigger
        $trigger = New-ScheduledTaskTrigger -Daily -At $BackupTime
        Write-Log "Created daily trigger for $BackupTime"

        # Configure the principal (run whether user is logged in or not)
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
            -LogonType S4U -RunLevel Highest
        Write-Log "Configured task principal"

        # Configure task settings
        $settings = New-ScheduledTaskSettingsSet `
            -DontStopOnIdleEnd `
            -RestartInterval (New-TimeSpan -Minutes $RetryInterval) `
            -RestartCount $RetryCount `
            -StartWhenAvailable
        Write-Log "Configured task settings"

        # Register the task
        Register-ScheduledTask -TaskName $TaskName `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Description "Daily backup of Plex server configurations and data" `
            -Force

        Write-Log "Successfully scheduled backup task '$TaskName' for $BackupTime daily"
    }
    catch {
        Write-Log "Failed to create scheduled task: $_" -Level 'ERROR'
        throw
    }
}

function Main {
    try {
        Write-Log "Starting backup task scheduler..."
        Test-AdminPrivileges
        New-BackupTask
    }
    catch {
        Write-Log "Failed to schedule backup task: $_" -Level 'ERROR'
        throw
    }
}

# Script execution
Main