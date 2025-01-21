# Schedule daily backup task
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -File `"$PWD\backup-script.ps1`""
$Trigger = New-ScheduledTaskTrigger -Daily -At 3AM
$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U
$Settings = New-ScheduledTaskSettingsSet -DontStopOnIdleEnd -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 3

# Create the scheduled task
Register-ScheduledTask -TaskName "ArrsMediaBackup" `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Settings $Settings `
    -Description "Daily backup of Arrs Media Project configurations"

Write-Host "Backup task scheduled successfully for 3 AM daily" 