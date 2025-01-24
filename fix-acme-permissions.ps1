# Validate environment variables
if ([string]::IsNullOrEmpty($env:PUID)) {
    throw "PUID environment variable is not set"
}

if ([string]::IsNullOrEmpty($env:PGID)) {
    throw "PGID environment variable is not set"
}

# Remove existing acme.json if it exists
if (Test-Path "letsencrypt/acme.json") {
    Remove-Item -Force "letsencrypt/acme.json"
}

# Create new acme.json file
New-Item -ItemType File -Path "letsencrypt/acme.json" -Force

# Reset ACL
$acl = New-Object System.Security.AccessControl.FileSecurity
$acl.SetAccessRuleProtection($true, $false)

# Create SID from PUID
$objSID = New-Object System.Security.Principal.SecurityIdentifier($env:PUID)
try {
    $objUser = $objSID.Translate([System.Security.Principal.NTAccount])
}
catch {
    Write-Error "Failed to translate PUID $env:PUID to a valid user account"
    throw
}

# Add rule for the specified user
$fileSystemRights = [System.Security.AccessControl.FileSystemRights]::Read -bor [System.Security.AccessControl.FileSystemRights]::Write
$inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::None
$propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
$type = [System.Security.AccessControl.AccessControlType]::Allow

$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($objUser, $fileSystemRights, $inheritanceFlags, $propagationFlags, $type)
$acl.AddAccessRule($rule)

# Apply the new ACL
Set-Acl -Path "letsencrypt/acme.json" -AclObject $acl

# Set file permissions to 600 (owner read/write only)
$acme = Get-Item "letsencrypt/acme.json"
$acme.Attributes = [System.IO.FileAttributes]::Normal
$acme.Attributes = [System.IO.FileAttributes]::Archive

Write-Host "Successfully updated permissions for acme.json"
Write-Host "Owner: $($objUser.Value)"
Write-Host "Permissions: Read/Write for owner only" 