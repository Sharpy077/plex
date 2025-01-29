<#
.SYNOPSIS
    Monitors SSL certificate expiration for all configured domains and sends alerts.

.DESCRIPTION
    This script performs comprehensive SSL certificate monitoring including:
    - Checking certificate expiration dates for all configured domains
    - Validating certificate chains
    - Sending email alerts for certificates expiring soon
    - Logging all monitoring activities
    - Reporting any errors in certificate validation

.PARAMETER WarningDays
    Number of days before expiration to start sending warnings. Defaults to 30.

.PARAMETER LogFile
    Path to the log file. Defaults to ".\logs\cert-monitor.log".

.ENVIRONMENT
    Required environment variables:
    - AUTH_HOST, RADARR_HOST, SONARR_HOST, etc.: Domain names to monitor
    - FROM_ADDRESS: Email address to send alerts from
    - ADMIN_EMAIL: Email address to send alerts to
    - SMTP_HOST: SMTP server hostname
    - SMTP_PORT: SMTP server port
    - SMTP_USERNAME: SMTP authentication username
    - SMTP_PASSWORD: SMTP authentication password

.DEPENDENCIES
    Required PowerShell modules:
    - None (uses built-in modules only)

.EXAMPLE
    .\monitor-certs.ps1 -WarningDays 45 -LogFile "C:\logs\cert-monitor.log"

.NOTES
    Author: System Administrator
    Last Modified: 2024-01-27
    Version: 1.0
#>

param (
    [int]$WarningDays = 30,
    [string]$LogFile = ".\logs\cert-monitor.log"
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
    $logMessage | Tee-Object -FilePath $LogFile -Append

    # Also write to console with color
    switch ($Level) {
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'ERROR' { Write-Host $logMessage -ForegroundColor Red }
        default { Write-Host $logMessage }
    }
}

function Initialize-Environment {
    # Verify required environment variables
    $requiredVars = @(
        'FROM_ADDRESS',
        'ADMIN_EMAIL',
        'SMTP_HOST',
        'SMTP_PORT',
        'SMTP_USERNAME',
        'SMTP_PASSWORD'
    )

    foreach ($var in $requiredVars) {
        if (-not (Get-Item "env:$var" -ErrorAction SilentlyContinue)) {
            throw "Required environment variable $var is not set"
        }
    }

    # Ensure log directory exists
    $logDir = Split-Path $LogFile
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        Write-Log "Created log directory: $logDir"
    }
}

function Get-DomainCertificate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    try {
        $req = [System.Net.HttpWebRequest]::Create("https://$domain")
        $req.Timeout = 10000
        $req.ServerCertificateValidationCallback = {
            param($sender, $certificate, $chain, $errors)
            $script:certToAnalyze = $certificate
            return $true
        }

        try {
            $resp = $req.GetResponse()
            $resp.Close()
        }
        catch [System.Net.WebException] {
            if ($script:certToAnalyze) {
                return $script:certToAnalyze
            }
            throw
        }

        return $script:certToAnalyze
    }
    finally {
        $script:certToAnalyze = $null
    }
}

function Test-CertificateValidity {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    # Validate certificate chain
    $chain = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Chain
    $chain.ChainPolicy.RevocationFlag = [System.Security.Cryptography.X509Certificates.X509RevocationFlag]::EntireChain
    $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::Online
    $chain.ChainPolicy.UrlRetrievalTimeout = New-TimeSpan -Seconds 10

    $chainValid = $chain.Build($Certificate)
    if (-not $chainValid) {
        throw "Certificate chain validation failed for $Domain"
    }

    # Check expiration
    $expirationDate = [DateTime]::Parse($Certificate.GetExpirationDateString())
    $daysUntilExpiration = ($expirationDate - (Get-Date)).Days

    return @{
        ExpirationDate = $expirationDate
        DaysLeft = $daysUntilExpiration
    }
}

function Send-AlertEmail {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Subject,
        [Parameter(Mandatory = $true)]
        [string]$Body
    )

    $emailParams = @{
        From = $env:FROM_ADDRESS
        To = $env:ADMIN_EMAIL
        Subject = $Subject
        Body = $Body
        SmtpServer = $env:SMTP_HOST
        Port = $env:SMTP_PORT
        UseSsl = $true
        Credential = New-Object System.Management.Automation.PSCredential(
            $env:SMTP_USERNAME,
            (ConvertTo-SecureString $env:SMTP_PASSWORD -AsPlainText -Force)
        )
    }

    Send-MailMessage @emailParams
    Write-Log "Sent email: $Subject"
}

function Main {
    try {
        Initialize-Environment
        Write-Log "Starting certificate monitoring..."

        # Get domains to monitor
        $domains = @(
            $env:AUTH_HOST,
            $env:RADARR_HOST,
            $env:SONARR_HOST,
            $env:LIDARR_HOST,
            $env:PROWLARR_HOST,
            $env:BAZARR_HOST,
            $env:READARR_HOST,
            $env:QBIT_HOST
        ) | Where-Object { $_ }  # Filter out empty values

        if ($domains.Count -eq 0) {
            throw "No domains configured for monitoring"
        }

        $expiringSoon = @()
        $errors = @()

        foreach ($domain in $domains) {
            try {
                Write-Log "Checking certificate for $domain"
                $cert = Get-DomainCertificate -Domain $domain

                if ($cert) {
                    $validity = Test-CertificateValidity -Certificate $cert -Domain $domain

                    if ($validity.DaysLeft -lt $WarningDays) {
                        $expiringSoon += @{
                            Domain = $domain
                            ExpirationDate = $validity.ExpirationDate
                            DaysLeft = $validity.DaysLeft
                        }
                        Write-Log "Certificate for $domain expires in $($validity.DaysLeft) days" -Level 'WARNING'
                    }
                    else {
                        Write-Log "Certificate for $domain is valid for $($validity.DaysLeft) days"
                    }
                }
                else {
                    throw "No certificate retrieved"
                }
            }
            catch {
                $errors += @{
                    Domain = $domain
                    Error = $_.Exception.Message
                }
                Write-Log "Error checking $domain : $_" -Level 'ERROR'
            }
        }

        # Send notifications if there are issues
        if ($expiringSoon.Count -gt 0 -or $errors.Count -gt 0) {
            $body = "Certificate Monitoring Report`n`n"

            if ($expiringSoon.Count -gt 0) {
                $body += "Certificates Expiring Soon:`n"
                foreach ($cert in $expiringSoon) {
                    $body += "- $($cert.Domain): Expires in $($cert.DaysLeft) days ($($cert.ExpirationDate))`n"
                }
                $body += "`n"
            }

            if ($errors.Count -gt 0) {
                $body += "Errors:`n"
                foreach ($error in $errors) {
                    $body += "- $($error.Domain): $($error.Error)`n"
                }
            }

            Send-AlertEmail -Subject "[CERT] Certificate Monitor Alert - $(Get-Date -Format 'yyyy-MM-dd')" -Body $body
        }
        else {
            Write-Log "All certificates are valid and not expiring soon"
        }
    }
    catch {
        $errorMessage = "Certificate monitoring failed: $_"
        Write-Log $errorMessage -Level 'ERROR'

        Send-AlertEmail -Subject "[CERT] Monitoring FAILED - $(Get-Date -Format 'yyyy-MM-dd')" -Body $errorMessage
        throw
    }
}

# Script execution
Main