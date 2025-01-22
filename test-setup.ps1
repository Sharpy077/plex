# Test script for verifying setup and configuration
param (
    [string]$LogFile = ".\logs\test-setup.log"
)

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Tee-Object -FilePath $LogFile -Append
}

function Test-Port {
    param($HostName, $Port)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.ConnectAsync($HostName, $Port).Wait(1000) | Out-Null
        $tcp.Close()
        return $true
    }
    catch {
        return $false
    }
}

# Ensure log directory exists
New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null
Write-Log "Starting setup verification..."

# Check required files
$requiredFiles = @(
    "docker-compose.yml",
    "secrets.json",
    "generate-env.ps1",
    "schedule-tasks.ps1",
    "backup-script.ps1",
    "monitor-certs.ps1"
)

$missingFiles = @()
foreach ($file in $requiredFiles) {
    if (-not (Test-Path $file)) {
        $missingFiles += $file
        Write-Log "ERROR: Missing required file: $file"
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Log "ERROR: Missing required files. Please ensure all files are present."
    exit 1
}

# Verify secrets.json structure
try {
    $secrets = Get-Content -Path "secrets.json" | ConvertFrom-Json
    $requiredFields = @(
        @{Path="github.client_id"; Name="GitHub Client ID"},
        @{Path="github.client_secret"; Name="GitHub Client Secret"},
        @{Path="auth.secret"; Name="Auth Secret"},
        @{Path="auth.cookie_domain"; Name="Cookie Domain"},
        @{Path="auth.auth_host"; Name="Auth Host"},
        @{Path="auth.whitelist"; Name="Auth Whitelist"},
        @{Path="email.smtp_host"; Name="SMTP Host"},
        @{Path="email.smtp_port"; Name="SMTP Port"},
        @{Path="email.smtp_username"; Name="SMTP Username"},
        @{Path="email.smtp_password"; Name="SMTP Password"},
        @{Path="notifications.admin_email"; Name="Admin Email"}
    )

    foreach ($field in $requiredFields) {
        $value = Invoke-Expression "`$secrets.$($field.Path)"
        if ([string]::IsNullOrEmpty($value)) {
            Write-Log "ERROR: Missing or empty $($field.Name) in secrets.json"
            exit 1
        }
    }
    Write-Log "Verified secrets.json structure"
}
catch {
    Write-Log "ERROR: Failed to parse secrets.json: $_"
    exit 1
}

# Check Docker and Docker Compose
try {
    $dockerVersion = docker --version
    $composeVersion = docker-compose --version
    Write-Log "Docker version: $dockerVersion"
    Write-Log "Docker Compose version: $composeVersion"
}
catch {
    Write-Log "ERROR: Docker or Docker Compose not installed"
    exit 1
}

# Check required ports
$ports = @(
    @{Port=80; Service="HTTP"},
    @{Port=443; Service="HTTPS"},
    @{Port=51820; Service="WireGuard"}
)

foreach ($portInfo in $ports) {
    if (Test-Port -HostName "localhost" -Port $portInfo.Port) {
        Write-Log "WARNING: Port $($portInfo.Port) ($($portInfo.Service)) is already in use"
    }
    else {
        Write-Log "Port $($portInfo.Port) ($($portInfo.Service)) is available"
    }
}

# Check required directories
$directories = @(
    @{Path="./docker"; Purpose="Service Configurations"},
    @{Path="./media"; Purpose="Media Storage"},
    @{Path="./backups"; Purpose="Backup Storage"},
    @{Path="./prometheus"; Purpose="Prometheus Configuration"},
    @{Path="./alertmanager"; Purpose="Alertmanager Configuration"},
    @{Path="./letsencrypt"; Purpose="SSL Certificates"}
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir.Path)) {
        New-Item -ItemType Directory -Force -Path $dir.Path | Out-Null
        Write-Log "Created directory: $($dir.Path) for $($dir.Purpose)"
    }
    else {
        Write-Log "Directory exists: $($dir.Path) for $($dir.Purpose)"
    }
}

# Generate environment variables
try {
    Write-Log "Generating environment variables..."
    & .\generate-env.ps1
    if (Test-Path .env) {
        Write-Log "Successfully generated .env file"
    }
    else {
        Write-Log "ERROR: Failed to generate .env file"
        exit 1
    }
}
catch {
    Write-Log "ERROR: Failed to generate environment variables: $_"
    exit 1
}

# Verify network configuration
$networks = docker network ls --format "{{.Name}}"
$requiredNetworks = @("proxy", "media", "downloads", "monitoring")
foreach ($network in $requiredNetworks) {
    if ($networks -notcontains $network) {
        Write-Log "Network '$network' will be created by docker-compose"
    }
    else {
        Write-Log "Network '$network' already exists"
    }
}

Write-Log "Setup verification completed. Please review the log for any warnings or errors." 