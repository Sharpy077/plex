# Generate secure secrets and passwords
function Generate-SecureSecret {
    $length = 32
    $nonAlphanumeric = $true
    $characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{}|;:,.<>?'
    $bytes = New-Object "System.Byte[]" $length
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $rng.GetBytes($bytes)
    
    $result = ""
    for ($i = 0; $i -lt $length; $i++) {
        $result += $characters[$bytes[$i] % $characters.Length]
    }
    
    if ($nonAlphanumeric -and ($result -notmatch '[^a-zA-Z0-9]')) {
        $result = $result.Remove(0, 1) + "!"
    }
    
    return $result
}

# Generate secrets
$jwt_secret = Generate-SecureSecret
$session_secret = Generate-SecureSecret
$admin_password = Generate-SecureSecret
$user_password = Generate-SecureSecret

# Output to secure file
$secrets = @{
    jwt_secret = $jwt_secret
    session_secret = $session_secret
    admin_password = $admin_password
    user_password = $user_password
}

$secrets | ConvertTo-Json | Out-File -FilePath ".\secrets.json"

Write-Host "Secrets generated and saved to secrets.json" 