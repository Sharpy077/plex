# Get SMTP configuration from environment variables
$SmtpServer = $env:SMTP_HOST
$SmtpPort = $env:SMTP_PORT
$Username = $env:SMTP_USERNAME
$Password = $env:SMTP_PASSWORD
$From = $env:FROM_ADDRESS
$To = $env:ADMIN_EMAIL

# Validate required environment variables
$requiredVars = @{
    "SMTP_HOST" = $SmtpServer
    "SMTP_PORT" = $SmtpPort
    "SMTP_USERNAME" = $Username
    "SMTP_PASSWORD" = $Password
    "FROM_ADDRESS" = $From
    "ADMIN_EMAIL" = $To
}

foreach ($var in $requiredVars.GetEnumerator()) {
    if ([string]::IsNullOrEmpty($var.Value)) {
        throw "Required environment variable '$($var.Key)' is not set"
    }
}

$Subject = "SMTP Test from Plex Server"
$Body = "This is a test email from your Plex server's SMTP configuration. If you receive this, SMTP is working correctly."

Write-Host "Using credentials:"
Write-Host "Server: $SmtpServer"
Write-Host "Port: $SmtpPort"
Write-Host "Username: $Username"
Write-Host "From: $From"
Write-Host "To: $To"

$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$Credentials = New-Object System.Management.Automation.PSCredential($Username, $SecurePassword)

Write-Host "`nTesting SMTP connection..."
Try {
    # Create SmtpClient object
    $SmtpClient = New-Object Net.Mail.SmtpClient($SmtpServer, $SmtpPort)
    $SmtpClient.EnableSsl = $true
    $SmtpClient.Credentials = $Credentials
    
    # Create MailMessage object
    $Message = New-Object System.Net.Mail.MailMessage($From, $To, $Subject, $Body)
    
    Write-Host "Attempting to send email..."
    $SmtpClient.Send($Message)
    Write-Host "Email sent successfully!" -ForegroundColor Green
    
    # Clean up
    $Message.Dispose()
    $SmtpClient.Dispose()
} Catch {
    Write-Host "Error sending email:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "`nStack Trace:" -ForegroundColor Yellow
    Write-Host $_.Exception.StackTrace
    
    if ($_.Exception.InnerException) {
        Write-Host "`nInner Exception:" -ForegroundColor Yellow
        Write-Host $_.Exception.InnerException.Message
    }
    throw
} Finally {
    if ($Message) { $Message.Dispose() }
    if ($SmtpClient) { $SmtpClient.Dispose() }
} 