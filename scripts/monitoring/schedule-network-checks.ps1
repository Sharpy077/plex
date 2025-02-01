# Schedule Network Configuration Checks
#
# This script creates a scheduled task to regularly monitor
# network configuration compliance.

param (
    [switch]$Unregister
)

$taskName = "CursorAI-NetworkCompliance"
$taskPath = "\CursorAI\"
$scriptPath = Join-Path $PSScriptRoot "check-network-config.ps1"

if ($Unregister) {
    Write-Host "Unregistering existing network check task..."
    Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue
    exit 0
}

# Create the task action
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

# Create the task trigger (run every 15 minutes)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)

# Set task settings
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

# Set task principal (run with highest privileges)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Create or update the task
$existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue

if ($existingTask) {
    Write-Host "Updating existing network check task..."
    Set-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $action -Trigger $trigger -Settings $settings -Principal $principal
}
else {
    Write-Host "Creating new network check task..."
    Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $action -Trigger $trigger -Settings $settings -Principal $principal
}

Write-Host "Network check task scheduled successfully."
Write-Host "Task will run every 15 minutes and check:"
Write-Host "- VLAN configuration (VLAN 20)"
Write-Host "- IP addressing (10.10.20.0/24)"
Write-Host "- Network security settings"
Write-Host "- Monitoring configuration"
Write-Host "- Container network compliance"
Write-Host "Alerts will be sent to support@sharphorizons.tech for any non-compliant settings"