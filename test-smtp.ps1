$SmtpServer = "smtp.office365.com"
$SmtpPort = 587
$Username = "support@sharphorizons.tech"
$Password = Get-Content "docker/secrets/secrets/smtp_password.secret"
$From = "support@sharphorizons.tech"
$To = "msharp@sharphorizons.tech"
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
} Catch {
    Write-Host "Error sending email:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "`nStack Trace:" -ForegroundColor Yellow
    Write-Host $_.Exception.StackTrace
    
    if ($_.Exception.InnerException) {
        Write-Host "`nInner Exception:" -ForegroundColor Yellow
        Write-Host $_.Exception.InnerException.Message
    }
} 