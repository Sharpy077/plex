<#
.SYNOPSIS
    Tests SMTP email configuration by sending a test email.

.DESCRIPTION
    This script validates and tests the SMTP configuration by:
    - Validating all required environment variables
    - Testing SMTP server connection
    - Sending a test email
    - Providing detailed error information if the test fails
    The script is useful for verifying email notifications will work correctly.

.PARAMETER None
    This script doesn't accept any parameters.

.ENVIRONMENT
    Required environment variables:
    - SMTP_HOST: SMTP server hostname
    - SMTP_PORT: SMTP server port
    - SMTP_USERNAME: SMTP authentication username
    - SMTP_PASSWORD: SMTP authentication password
    - FROM_ADDRESS: Email address to send from
    - ADMIN_EMAIL: Email address to send to

.DEPENDENCIES
    Required PowerShell modules:
    - None (uses built-in modules only)

.EXAMPLE
    .\test-smtp.ps1

.NOTES
    Author: System Administrator
    Last Modified: 2024-01-27
    Version: 1.0
#>

# Script configuration
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Function definitions
function Initialize-Environment {
    # Get SMTP configuration from environment variables
    $script:SmtpConfig = @{
        Server = $env:SMTP_HOST
        Port = $env:SMTP_PORT
        Username = $env:SMTP_USERNAME
        Password = $env:SMTP_PASSWORD
        FromAddress = $env:FROM_ADDRESS
        ToAddress = $env:ADMIN_EMAIL
    }

    # Validate required environment variables
    foreach ($key in $script:SmtpConfig.Keys) {
        if ([string]::IsNullOrEmpty($script:SmtpConfig[$key])) {
            throw "Required environment variable for '$key' is not set"
        }
    }

    # Validate port number
    if (-not [int]::TryParse($script:SmtpConfig.Port, [ref]$null)) {
        throw "SMTP_PORT must be a valid number"
    }

    # Display configuration (excluding password)
    Write-Host "SMTP Configuration:"
    Write-Host "Server: $($script:SmtpConfig.Server)"
    Write-Host "Port: $($script:SmtpConfig.Port)"
    Write-Host "Username: $($script:SmtpConfig.Username)"
    Write-Host "From: $($script:SmtpConfig.FromAddress)"
    Write-Host "To: $($script:SmtpConfig.ToAddress)"
}

function Send-TestEmail {
    $Subject = "SMTP Test from Plex Server"
    $Body = @"
This is a test email from your Plex server's SMTP configuration.
If you receive this, SMTP is working correctly.

Configuration Details:
- Server: $($script:SmtpConfig.Server)
- Port: $($script:SmtpConfig.Port)
- From: $($script:SmtpConfig.FromAddress)
- SSL: Enabled
- Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@

    try {
        Write-Host "`nTesting SMTP connection..."

        # Create credentials
        $SecurePassword = ConvertTo-SecureString $script:SmtpConfig.Password -AsPlainText -Force
        $Credentials = New-Object System.Management.Automation.PSCredential($script:SmtpConfig.Username, $SecurePassword)

        # Create SmtpClient object
        $SmtpClient = New-Object Net.Mail.SmtpClient($script:SmtpConfig.Server, $script:SmtpConfig.Port)
        $SmtpClient.EnableSsl = $true
        $SmtpClient.Credentials = $Credentials

        # Create MailMessage object
        $Message = New-Object System.Net.Mail.MailMessage(
            $script:SmtpConfig.FromAddress,
            $script:SmtpConfig.ToAddress,
            $Subject,
            $Body
        )

        Write-Host "Attempting to send email..."
        $SmtpClient.Send($Message)
        Write-Host "Email sent successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "Error sending email:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        Write-Host "`nStack Trace:" -ForegroundColor Yellow
        Write-Host $_.Exception.StackTrace

        if ($_.Exception.InnerException) {
            Write-Host "`nInner Exception:" -ForegroundColor Yellow
            Write-Host $_.Exception.InnerException.Message
        }
        throw
    }
    finally {
        if ($Message) { $Message.Dispose() }
        if ($SmtpClient) { $SmtpClient.Dispose() }
    }
}

function Main {
    try {
        Initialize-Environment
        Send-TestEmail
    }
    catch {
        Write-Error "SMTP test failed: $_"
        exit 1
    }
}

# Script execution
Main