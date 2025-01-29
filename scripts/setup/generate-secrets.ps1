# Generate secure secrets and passwords
function Generate-SecureSecret {
    $length = 32
    $characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{}|;:,.<>?'
    $bytes = [byte[]]::new($length)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    
    $result = -join ($bytes | ForEach-Object { 
        $characters[$_ % $characters.Length] 
    })
    
    # Ensure at least one special character
    if ($result -notmatch '[^a-zA-Z0-9]') {
        $result = $result.Substring(0, $result.Length - 1) + "!"
    }
    
    $rng.Dispose()
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

$secrets | ConvertTo-Json | Out-File -FilePath ".\secrets.json" -Force

Write-Host "Secrets generated and saved to secrets.json" 