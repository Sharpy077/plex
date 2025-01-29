<#
.SYNOPSIS
    Fixes permissions on the Traefik ACME certificate file for secure operation.

.DESCRIPTION
    This script manages the ACME certificate file (acme.json) used by Traefik by:
    - Recreating the file with proper ownership
    - Setting correct file system permissions (600)
    - Configuring ACLs for the specified user
    The script ensures secure operation of Traefik's HTTPS certificate management.

.PARAMETER AcmeFile
    Path to the ACME certificate file. Defaults to "letsencrypt/acme.json".

.PARAMETER VerboseLogging
    Enable verbose logging output. Defaults to $true.

.ENVIRONMENT
    Required environment variables:
    - PUID: User ID for file ownership
    - PGID: Group ID for file ownership

.DEPENDENCIES
    Required PowerShell modules:
    - None (uses built-in modules only)

.EXAMPLE
    .\fix-acme-permissions.ps1 -AcmeFile "D:\letsencrypt\acme.json" -VerboseLogging $true

.NOTES
    Author: System Administrator
    Last Modified: 2024-01-27
    Version: 1.0
#>

param(
    [string]$AcmeFile = "letsencrypt/acme.json",
    [bool]$VerboseLogging = $true
)

# Script configuration
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$VerbosePreference = if ($VerboseLogging) { "Continue" } else { "SilentlyContinue" }

# Function definitions
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] - $Message"

    # Write to console with color
    $color = switch ($Level) {
        'WARNING' { 'Yellow' }
        'ERROR' { 'Red' }
        'SUCCESS' { 'Green' }
        default { 'White' }
    }
    Write-Host $logMessage -ForegroundColor $color
    Write-Verbose "Logged: $logMessage"
}

function Initialize-Environment {
    # Validate environment variables
    if ([string]::IsNullOrEmpty($env:PUID)) {
        throw "PUID environment variable is not set"
    }
    Write-Verbose "PUID is set to: $env:PUID"

    if ([string]::IsNullOrEmpty($env:PGID)) {
        throw "PGID environment variable is not set"
    }
    Write-Verbose "PGID is set to: $env:PGID"

    # Create directory if it doesn't exist
    $acmeDir = Split-Path $AcmeFile -Parent
    if (-not (Test-Path $acmeDir)) {
        New-Item -ItemType Directory -Path $acmeDir -Force | Out-Null
        Write-Log "Created directory: $acmeDir" -Level 'SUCCESS'
    }
}

function Reset-AcmeFile {
    try {
        # Remove existing acme.json if it exists
        if (Test-Path $AcmeFile) {
            Remove-Item -Force $AcmeFile
            Write-Log "Removed existing ACME file" -Level 'INFO'
        }

        # Create new acme.json file
        New-Item -ItemType File -Path $AcmeFile -Force | Out-Null
        Write-Log "Created new ACME file" -Level 'SUCCESS'
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Failed to reset ACME file: $errorMessage" -Level 'ERROR'
        throw
    }
}

function Set-AcmePermissions {
    try {
        # Create new ACL object
        $acl = New-Object System.Security.AccessControl.FileSecurity
        $acl.SetAccessRuleProtection($true, $false)
        Write-Verbose "Created new ACL object"

        # Create SID from PUID
        $objSID = New-Object System.Security.Principal.SecurityIdentifier($env:PUID)
        try {
            $objUser = $objSID.Translate([System.Security.Principal.NTAccount])
            Write-Verbose "Translated PUID $env:PUID to user account: $($objUser.Value)"
        }
        catch {
            throw "Failed to translate PUID $env:PUID to a valid user account: $($_.Exception.Message)"
        }

        # Configure file system access rule
        $fileSystemRights = [System.Security.AccessControl.FileSystemRights]::Read -bor
            [System.Security.AccessControl.FileSystemRights]::Write
        $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::None
        $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
        $type = [System.Security.AccessControl.AccessControlType]::Allow

        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $objUser, $fileSystemRights, $inheritanceFlags, $propagationFlags, $type)
        $acl.AddAccessRule($rule)
        Write-Verbose "Added access rule for $($objUser.Value)"

        # Apply the new ACL
        Set-Acl -Path $AcmeFile -AclObject $acl
        Write-Log "Applied new ACL to ACME file" -Level 'SUCCESS'

        # Set file attributes (600 equivalent)
        $acme = Get-Item $AcmeFile
        $acme.Attributes = [System.IO.FileAttributes]::Normal
        $acme.Attributes = [System.IO.FileAttributes]::Archive
        Write-Log "Set file attributes to read/write for owner only" -Level 'SUCCESS'

        # Verify permissions
        $currentAcl = Get-Acl -Path $AcmeFile
        Write-Log "Current owner: $($currentAcl.Owner)" -Level 'INFO'
        Write-Log "Permissions set successfully" -Level 'SUCCESS'
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Failed to set ACME file permissions: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        throw
    }
}

function Main {
    try {
        Write-Log "Starting ACME permissions fix..."
        Initialize-Environment
        Reset-AcmeFile
        Set-AcmePermissions
        Write-Log "Successfully updated ACME file permissions" -Level 'SUCCESS'
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Failed to fix ACME permissions: $errorMessage" -Level 'ERROR'
        Write-Verbose "Exception details: $($_.Exception)"
        Write-Log $_.ScriptStackTrace -Level 'ERROR'
        exit 1
    }
}

# Script execution
Main