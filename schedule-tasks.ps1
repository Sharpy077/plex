# Script to schedule monitoring and backup tasks
param (
    [string]$TaskPath = "\Plex\"
)

# Ensure we're running with admin privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

# Get the current script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Create task path if it doesn't exist
if (-not (Get-ScheduledTask -TaskPath $TaskPath -ErrorAction SilentlyContinue)) {
    Write-Host "Creating task folder: $TaskPath"
}

# Schedule backup task (daily at 2 AM)
$backupAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptDir\backup-script.ps1`""
$backupTrigger = New-ScheduledTaskTrigger -Daily -At 2am
$backupSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 3

Register-ScheduledTask -TaskName "PlexBackup" `
                      -TaskPath $TaskPath `
                      -Action $backupAction `
                      -Trigger $backupTrigger `
                      -Settings $backupSettings `
                      -Description "Daily backup of Plex services" `
                      -Force

Write-Host "Scheduled backup task"

# Schedule certificate monitoring (weekly on Sunday at 3 AM)
$certAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptDir\monitor-certs.ps1`""
$certTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
$certSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 3

Register-ScheduledTask -TaskName "PlexCertMonitor" `
                      -TaskPath $TaskPath `
                      -Action $certAction `
                      -Trigger $certTrigger `
                      -Settings $certSettings `
                      -Description "Weekly SSL certificate monitoring" `
                      -Force

Write-Host "Scheduled certificate monitoring task"

# Schedule Prometheus alert rules check (daily at 1 AM)
$alertAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"docker exec prometheus promtool check rules /etc/prometheus/rules/*.yml`""
$alertTrigger = New-ScheduledTaskTrigger -Daily -At 1am
$alertSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd

Register-ScheduledTask -TaskName "PlexAlertCheck" `
                      -TaskPath $TaskPath `
                      -Action $alertAction `
                      -Trigger $alertTrigger `
                      -Settings $alertSettings `
                      -Description "Daily Prometheus alert rules validation" `
                      -Force

Write-Host "Scheduled alert rules check task"

Write-Host "All tasks scheduled successfully" 