# Remove existing acme.json if it exists
if (Test-Path "letsencrypt/acme.json") {
    Remove-Item -Force "letsencrypt/acme.json"
}

# Create new acme.json file
New-Item -ItemType File -Path "letsencrypt/acme.json" -Force

# Reset ACL
$acl = New-Object System.Security.AccessControl.FileSecurity
$acl.SetAccessRuleProtection($true, $false)

# Add rule for current user
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$fileSystemRights = [System.Security.AccessControl.FileSystemRights]::Read -bor [System.Security.AccessControl.FileSystemRights]::Write
$inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::None
$propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
$type = [System.Security.AccessControl.AccessControlType]::Allow

$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, $fileSystemRights, $inheritanceFlags, $propagationFlags, $type)
$acl.AddAccessRule($rule)

# Apply the new ACL
Set-Acl -Path "letsencrypt/acme.json" -AclObject $acl 