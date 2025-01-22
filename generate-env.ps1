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
"@

# Write to .env file
$envContent | Out-File -FilePath ".env" -Encoding UTF8 -NoNewline

Write-Host "Environment variables generated successfully!" 