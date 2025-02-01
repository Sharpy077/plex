# Check Global Configuration Compliance
#
# This script monitors and validates that global CursorAI configurations
# are being followed across all projects.

param (
    [switch]$Verbose
)

# Import common functions
. "$PSScriptRoot\..\common\logging.ps1"

function Test-EmailConfiguration {
    Write-Log "Checking email configuration..."
    $results = @{
        Success = $true
        Issues  = @()
    }

    # Check for correct email domain
    if ($env:FROM_ADDRESS -ne "support@sharphorizons.tech") {
        $results.Success = $false
        $results.Issues += "FROM_ADDRESS must be support@sharphorizons.tech"
    }

    # Verify M365 SMTP settings
    if ($env:SMTP_HOST -ne "smtp.office365.com") {
        $results.Success = $false
        $results.Issues += "SMTP_HOST must be smtp.office365.com"
    }

    if ($env:SMTP_PORT -ne "587") {
        $results.Success = $false
        $results.Issues += "SMTP_PORT must be 587"
    }

    # Check for any Gmail references
    $files = Get-ChildItem -Path $env:GITHUB_REPOS_PATH -Recurse -File -Include "*.yml", "*.yaml", "*.json", "*.ps1", "*.env*"
    foreach ($file in $files) {
        $content = Get-Content $file -Raw
        if ($content -match "gmail\.com") {
            $results.Success = $false
            $results.Issues += "Found Gmail reference in $($file.FullName)"
        }
    }

    return $results
}

function Test-RepositoryLocation {
    Write-Log "Checking repository location..."
    $results = @{
        Success = $true
        Issues  = @()
    }

    # Verify repository path
    $expectedPath = "D:\Github Repositories"
    $actualPath = $env:GITHUB_REPOS_PATH

    if ($actualPath -ne $expectedPath) {
        $results.Success = $false
        $results.Issues += "Repository path must be $expectedPath"
    }

    # Check if path exists and is accessible
    if (-not (Test-Path $expectedPath)) {
        $results.Success = $false
        $results.Issues += "Repository path does not exist: $expectedPath"
    }

    return $results
}

function Test-NetworkConfiguration {
    Write-Log "Checking network configuration..."
    $results = @{
        Success = $true
        Issues  = @()
    }

    # Verify VLAN ID
    if ($env:VLAN_ID -ne "20") {
        $results.Success = $false
        $results.Issues += "VLAN_ID must be 20"
    }

    # Verify Docker subnet
    if ($env:DOCKER_SUBNET -ne "10.10.20.0/24") {
        $results.Success = $false
        $results.Issues += "Docker subnet must be 10.10.20.0/24"
    }

    # Verify Docker gateway
    if ($env:DOCKER_GATEWAY -ne "10.10.20.1") {
        $results.Success = $false
        $results.Issues += "Docker gateway must be 10.10.20.1"
    }

    # Check for any 172.x.x.x addresses in Docker configurations
    $dockerFiles = Get-ChildItem -Path $env:GITHUB_REPOS_PATH -Recurse -File -Include "docker-compose*.yml", "*.dockerfile", "Dockerfile*"
    foreach ($file in $dockerFiles) {
        $content = Get-Content $file -Raw
        if ($content -match "172\.[0-9]+\.[0-9]+\.[0-9]+") {
            $results.Success = $false
            $results.Issues += "Found 172.x.x.x IP address in $($file.FullName)"
        }
    }

    # Verify IP whitelist
    $expectedIPs = "10.10.0.0/16,202.128.124.242/32"
    if ($env:ALLOWED_IPS -ne $expectedIPs) {
        $results.Success = $false
        $results.Issues += "IP whitelist must be: $expectedIPs"
    }

    return $results
}

function Send-ComplianceAlert {
    param (
        [string]$Subject,
        [string]$Body
    )

    $emailParams = @{
        From       = $env:FROM_ADDRESS
        To         = $env:ADMIN_EMAIL
        Subject    = $Subject
        Body       = $Body
        SmtpServer = $env:SMTP_HOST
        Port       = $env:SMTP_PORT
        UseSSL     = $true
        Credential = New-Object System.Management.Automation.PSCredential(
            $env:SMTP_USERNAME,
            (ConvertTo-SecureString $env:SMTP_PASSWORD -AsPlainText -Force)
        )
    }

    try {
        Send-MailMessage @emailParams
        Write-Log "Sent compliance alert: $Subject"
    }
    catch {
        Write-Log "Failed to send compliance alert: $_" -Level Error
    }
}

# Main execution
try {
    Write-Log "Starting global configuration compliance check..."

    $allResults = @{
        Email      = Test-EmailConfiguration
        Repository = Test-RepositoryLocation
        Network    = Test-NetworkConfiguration
    }

    $complianceIssues = @()
    $overallSuccess = $true

    foreach ($category in $allResults.Keys) {
        $result = $allResults[$category]
        if (-not $result.Success) {
            $overallSuccess = $false
            $complianceIssues += "== $category Issues =="
            $complianceIssues += $result.Issues
            $complianceIssues += ""
        }
    }

    if (-not $overallSuccess) {
        $body = "The following compliance issues were detected:`n`n"
        $body += $complianceIssues | ForEach-Object { "$_`n" }

        Send-ComplianceAlert -Subject "[COMPLIANCE] Configuration Issues Detected" -Body $body
        Write-Log "Compliance issues detected. Alert sent." -Level Warning
    }
    else {
        Write-Log "All configurations are compliant." -Level Success
    }
}
catch {
    $errorMsg = "Error during compliance check: $_"
    Write-Log $errorMsg -Level Error
    Send-ComplianceAlert -Subject "[COMPLIANCE] Check Failed" -Body $errorMsg
    exit 1
}