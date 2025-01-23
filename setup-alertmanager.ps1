# Setup Alertmanager with proper configuration
Write-Host "Setting up Alertmanager..."

# Create Alertmanager configuration
$alertmanagerConfig = @"
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'email-notifications'

receivers:
- name: 'email-notifications'
  email_configs:
  - to: 'your.email@example.com'
    from: 'alertmanager@localhost'
    smarthost: 'smtp.gmail.com:587'
    auth_username: 'your.email@gmail.com'
    auth_identity: 'your.email@gmail.com'
    auth_password: 'your-app-specific-password'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
"@

# Write Alertmanager configuration
Write-Host "Writing Alertmanager configuration..."
$alertmanagerConfig | Out-File -FilePath "alertmanager/alertmanager.yml" -Encoding utf8 -Force

Write-Host "Setup complete! Alertmanager configuration has been created."
Write-Host "Please update the email settings in alertmanager/alertmanager.yml with your actual email configuration." 