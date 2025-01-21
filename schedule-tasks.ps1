# Schedule maintenance tasks

# 1. Security scan task
$action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File "security-test.ps1"'
$trigger = New-ScheduledTaskTrigger -Daily -At 3AM
Register-ScheduledTask -TaskName "SecurityScan" -Action $action -Trigger $trigger -Description "Daily security scan of services"

# 2. Backup task
$backupAction = New-ScheduledTaskAction -Execute 'docker' -Argument 'compose down && tar -czf backup-$(date +%Y%m%d).tar.gz ./docker && docker compose up -d'
$backupTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2AM
Register-ScheduledTask -TaskName "WeeklyBackup" -Action $backupAction -Trigger $backupTrigger -Description "Weekly backup of service data"

# 3. Certificate renewal check
$certAction = New-ScheduledTaskAction -Execute 'docker' -Argument 'compose restart traefik'
$certTrigger = New-ScheduledTaskTrigger -Daily -At 4AM
Register-ScheduledTask -TaskName "CertRenewal" -Action $certAction -Trigger $certTrigger -Description "Daily certificate renewal check"

Write-Host "Scheduled tasks created successfully" -ForegroundColor Green 