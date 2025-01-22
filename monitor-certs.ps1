# Script to monitor SSL certificate expiration
param (
    [int]$WarningDays = 30,
    [string]$LogFile = ".\logs\cert-monitor.log"
)

# Function to write to log
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Tee-Object -FilePath $LogFile -Append
}

# Ensure log directory exists
New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null

try {
    Write-Log "Starting certificate monitoring..."
    
    # Read domains from environment
    $domains = @(
        $env:AUTH_HOST,
        $env:RADARR_HOST,
        $env:SONARR_HOST,
        $env:LIDARR_HOST,
        $env:PROWLARR_HOST,
        $env:BAZARR_HOST,
        $env:READARR_HOST,
        $env:QBIT_HOST
    )

    $expiringSoon = @()
    $errors = @()

    foreach ($domain in $domains) {
        try {
            Write-Log "Checking certificate for $domain"
            
            # Get certificate information
            $cert = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
            $req = [System.Net.HttpWebRequest]::Create("https://$domain")
            $req.Timeout = 10000
            try {
                $resp = $req.GetResponse()
                $cert = $req.ServicePoint.Certificate
                $resp.Close()
            }
            catch {
                throw "Failed to connect to $domain"
            }

            # Check expiration
            $expirationDate = [DateTime]::Parse($cert.GetExpirationDateString())
            $daysUntilExpiration = ($expirationDate - (Get-Date)).Days

            if ($daysUntilExpiration -lt $WarningDays) {
                $expiringSoon += @{
                    Domain = $domain
                    ExpirationDate = $expirationDate
                    DaysLeft = $daysUntilExpiration
                }
                Write-Log "WARNING: Certificate for $domain expires in $daysUntilExpiration days"
            }
            else {
                Write-Log "Certificate for $domain is valid for $daysUntilExpiration days"
            }
        }
        catch {
            $errors += @{
                Domain = $domain
                Error = $_.Exception.Message
            }
            Write-Log "ERROR checking $domain : $_"
        }
    }

    # Send notification if there are issues
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

        $emailParams = @{
            From = $env:FROM_ADDRESS
            To = $env:ADMIN_EMAIL
            Subject = "[CERT] Certificate Monitor Alert - $(Get-Date -Format 'yyyy-MM-dd')"
            Body = $body
            SmtpServer = $env:SMTP_HOST
            Port = $env:SMTP_PORT
            UseSsl = $true
            Credential = New-Object System.Management.Automation.PSCredential($env:SMTP_USERNAME, (ConvertTo-SecureString $env:SMTP_PASSWORD -AsPlainText -Force))
        }
        Send-MailMessage @emailParams
        Write-Log "Sent certificate monitoring alert email"
    }
    else {
        Write-Log "All certificates are valid and not expiring soon"
    }
}
catch {
    $errorMessage = "Certificate monitoring failed: $_"
    Write-Log "ERROR: $errorMessage"
    
    # Send error notification
    $emailParams = @{
        From = $env:FROM_ADDRESS
        To = $env:ADMIN_EMAIL
        Subject = "[CERT] Monitoring FAILED - $(Get-Date -Format 'yyyy-MM-dd')"
        Body = $errorMessage
        SmtpServer = $env:SMTP_HOST
        Port = $env:SMTP_PORT
        UseSsl = $true
        Credential = New-Object System.Management.Automation.PSCredential($env:SMTP_USERNAME, (ConvertTo-SecureString $env:SMTP_PASSWORD -AsPlainText -Force))
    }
    Send-MailMessage @emailParams
    Write-Log "Sent monitoring failure notification email"
    throw
} 