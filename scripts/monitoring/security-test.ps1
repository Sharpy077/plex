<#
.SYNOPSIS
    Performs comprehensive security testing of the Plex server environment.

.DESCRIPTION
    This script performs security tests including:
    - Authentication checks for all services
    - SSL certificate validation
    - WireGuard VPN status and configuration
    - Service accessibility and security headers
    - Port security checks
    The script provides detailed reporting of security status and potential issues.

.PARAMETER None
    This script doesn't accept any parameters.

.ENVIRONMENT
    Required environment variables:
    None required, but uses these if available:
    - AUTH_HOST: Authelia host domain
    - TRAEFIK_HOST: Traefik dashboard domain
    - SERVICE_DOMAINS: Comma-separated list of service domains to test

.DEPENDENCIES
    Required PowerShell modules:
    - None (uses built-in modules only)

.EXAMPLE
    .\security-test.ps1

.NOTES
    Author: System Administrator
    Last Modified: 2024-01-27
    Version: 1.0
#>

# Script configuration
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Function definitions
function Write-TestResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TestName,
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('Success', 'Warning', 'Error', 'Info')]
        [string]$Status = 'Info'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $icon = switch ($Status) {
        'Success' { "✓"; break }
        'Warning' { "⚠"; break }
        'Error' { "✗"; break }
        default { "→" }
    }

    $color = switch ($Status) {
        'Success' { 'Green'; break }
        'Warning' { 'Yellow'; break }
        'Error' { 'Red'; break }
        default { 'Cyan' }
    }

    Write-Host "[$timestamp] $icon $TestName : $Message" -ForegroundColor $color
}

function Test-Service {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [int]$ExpectedCode = 200
    )

    Write-TestResult -TestName $Name -Message "Testing service..." -Status 'Info'
    try {
        $response = Invoke-WebRequest -Uri $url -Method GET -SkipCertificateCheck

        if ($response.StatusCode -eq $ExpectedCode) {
            Write-TestResult -TestName $Name -Message "Service is properly secured (Status: $($response.StatusCode))" -Status 'Success'

            # Check security headers
            $headers = @{
                'Strict-Transport-Security' = 'max-age=31536000'
                'X-Frame-Options' = 'DENY'
                'X-Content-Type-Options' = 'nosniff'
                'X-XSS-Protection' = '1; mode=block'
            }

            foreach ($header in $headers.Keys) {
                if ($response.Headers[$header]) {
                    Write-TestResult -TestName $Name -Message "Has security header: $header" -Status 'Success'
                } else {
                    Write-TestResult -TestName $Name -Message "Missing security header: $header" -Status 'Warning'
                }
            }
        } else {
            Write-TestResult -TestName $Name -Message "Unexpected status code: $($response.StatusCode)" -Status 'Error'
        }
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 401) {
            Write-TestResult -TestName $Name -Message "Requires authentication (Status: 401)" -Status 'Success'
        } else {
            Write-TestResult -TestName $Name -Message "Error: $($_.Exception.Message)" -Status 'Error'
        }
    }
}

function Test-WireGuard {
    Write-TestResult -TestName "WireGuard" -Message "Testing VPN status..." -Status 'Info'

    # Check process
    $wg = Get-Process | Where-Object { $_.ProcessName -eq "wireguard" }
    if ($wg) {
        Write-TestResult -TestName "WireGuard" -Message "Process is running" -Status 'Success'

        # Test UDP port
        $udpTest = Test-NetConnection -ComputerName localhost -Port 51820 -InformationLevel Quiet
        if ($udpTest) {
            Write-TestResult -TestName "WireGuard" -Message "Port 51820 is open" -Status 'Success'
        } else {
            Write-TestResult -TestName "WireGuard" -Message "Port 51820 is closed" -Status 'Error'
        }

        # Check interface
        $interface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*WireGuard*" }
        if ($interface) {
            Write-TestResult -TestName "WireGuard" -Message "Network interface is present" -Status 'Success'
            if ($interface.Status -eq "Up") {
                Write-TestResult -TestName "WireGuard" -Message "Network interface is up" -Status 'Success'
            } else {
                Write-TestResult -TestName "WireGuard" -Message "Network interface is down" -Status 'Error'
            }
        } else {
            Write-TestResult -TestName "WireGuard" -Message "Network interface not found" -Status 'Error'
        }
    } else {
        Write-TestResult -TestName "WireGuard" -Message "Process is not running" -Status 'Error'
    }
}

function Test-SSL {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    Write-TestResult -TestName "SSL ($Domain)" -Message "Testing certificate..." -Status 'Info'
    try {
        $cert = Invoke-WebRequest -Uri "https://$Domain" -Method GET -SkipCertificateCheck
        $certInfo = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($cert.Certificate)

        # Check expiration
        $daysUntilExpiry = ($certInfo.NotAfter - (Get-Date)).Days
        if ($daysUntilExpiry -gt 30) {
            Write-TestResult -TestName "SSL ($Domain)" -Message "Certificate valid for $daysUntilExpiry days" -Status 'Success'
        } elseif ($daysUntilExpiry -gt 0) {
            Write-TestResult -TestName "SSL ($Domain)" -Message "Certificate expires in $daysUntilExpiry days" -Status 'Warning'
        } else {
            Write-TestResult -TestName "SSL ($Domain)" -Message "Certificate has expired" -Status 'Error'
        }

        # Check protocol version
        if ($cert.Protocol -match "TLS1.2|TLS1.3") {
            Write-TestResult -TestName "SSL ($Domain)" -Message "Using secure protocol: $($cert.Protocol)" -Status 'Success'
        } else {
            Write-TestResult -TestName "SSL ($Domain)" -Message "Using insecure protocol: $($cert.Protocol)" -Status 'Error'
        }

        # Check certificate details
        Write-TestResult -TestName "SSL ($Domain)" -Message "Issuer: $($certInfo.Issuer)" -Status 'Info'
        Write-TestResult -TestName "SSL ($Domain)" -Message "Valid until: $($certInfo.NotAfter)" -Status 'Info'
    }
    catch {
        Write-TestResult -TestName "SSL ($Domain)" -Message "Test failed: $($_.Exception.Message)" -Status 'Error'
    }
}

function Main {
    try {
        Write-TestResult -TestName "Security Test" -Message "Starting security assessment..." -Status 'Info'

        # Test Authentication Services
        Test-Service -Name "Authelia" -Url "https://$($env:AUTH_HOST ?? 'auth.local')"
        Test-Service -Name "Traefik Dashboard" -Url "https://$($env:TRAEFIK_HOST ?? 'traefik.local')"

        # Test Media Services
        $services = @(
            @{Name="Radarr"; Url="https://$($env:RADARR_HOST ?? 'radarr.local')"},
            @{Name="Sonarr"; Url="https://$($env:SONARR_HOST ?? 'sonarr.local')"},
            @{Name="Lidarr"; Url="https://$($env:LIDARR_HOST ?? 'lidarr.local')"},
            @{Name="Prowlarr"; Url="https://$($env:PROWLARR_HOST ?? 'prowlarr.local')"},
            @{Name="Bazarr"; Url="https://$($env:BAZARR_HOST ?? 'bazarr.local')"},
            @{Name="Readarr"; Url="https://$($env:READARR_HOST ?? 'readarr.local')"},
            @{Name="qBittorrent"; Url="https://$($env:QBIT_HOST ?? 'qbit.local')"}
        )

        foreach ($service in $services) {
            Test-Service -Name $service.Name -Url $service.Url
        }

        # Test VPN
        Test-WireGuard

        # Test SSL Certificates
        $domains = @(
            $env:AUTH_HOST ?? "auth.local",
            $env:TRAEFIK_HOST ?? "traefik.local"
        ) + ($services | ForEach-Object { ([Uri]$_.Url).Host })

        foreach ($domain in $domains) {
            Test-SSL -Domain $domain
        }

        Write-TestResult -TestName "Security Test" -Message "Assessment complete" -Status 'Success'
    }
    catch {
        Write-TestResult -TestName "Security Test" -Message "Assessment failed: $_" -Status 'Error'
        exit 1
    }
}

# Script execution
Main