# Read the secrets.json file
$secrets = Get-Content -Path "secrets.json" | ConvertFrom-Json

# Create .env content
$envContent = @"
# GitHub Authentication
GITHUB_CLIENT_ID=$($secrets.github.client_id)
GITHUB_CLIENT_SECRET=$($secrets.github.client_secret)

# Auth Configuration
AUTH_SECRET=$($secrets.auth.secret)
COOKIE_DOMAIN=$($secrets.auth.cookie_domain)
AUTH_HOST=$($secrets.auth.auth_host)
AUTH_WHITELIST=$($secrets.auth.whitelist -join ',')

# Email Configuration
SMTP_HOST=$($secrets.email.smtp_host)
SMTP_PORT=$($secrets.email.smtp_port)
SMTP_USERNAME=$($secrets.email.smtp_username)
SMTP_PASSWORD=$($secrets.email.smtp_password)
FROM_ADDRESS=$($secrets.email.from_address)

# Admin Configuration
ADMIN_EMAIL=$($secrets.notifications.admin_email)

# Service Hostnames
RADARR_HOST=radarr.$($secrets.auth.cookie_domain)
SONARR_HOST=sonarr.$($secrets.auth.cookie_domain)
LIDARR_HOST=lidarr.$($secrets.auth.cookie_domain)
PROWLARR_HOST=prowlarr.$($secrets.auth.cookie_domain)
BAZARR_HOST=bazarr.$($secrets.auth.cookie_domain)
READARR_HOST=readarr.$($secrets.auth.cookie_domain)
QBIT_HOST=qbit.$($secrets.auth.cookie_domain)

# System Configuration
PUID=1000
PGID=1000
TZ=America/New_York

# Monitoring Hostnames
PROMETHEUS_HOST=prometheus.$($secrets.auth.cookie_domain)
ALERTMANAGER_HOST=alerts.$($secrets.auth.cookie_domain)
TRAEFIK_HOST=traefik.$($secrets.auth.cookie_domain)
"@

# Write to .env file
$envContent | Out-File -FilePath ".env" -Encoding UTF8 -NoNewline

Write-Host "Environment variables generated successfully!" 