# Omada Controller Configuration Script
param(
    [string]$ControllerIP = "10.10.10.250", # Updated for OC200
    [string]$Username = $(Read-Host -Prompt "Enter Omada Controller username"),
    [SecureString]$Password = $(Read-Host -Prompt "Enter Omada Controller password" -AsSecureString),
    [string]$CertPath = "$PSScriptRoot\..\certs\omada",
    [switch]$SetupHTTPS
)

Write-Host "`nConfiguring Omada Controller at $ControllerIP..." -ForegroundColor Cyan

# Convert SecureString to plain text for API auth
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
$PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

# API endpoints for OC200 (starting with HTTP)
$BaseUrl = "http://$ControllerIP`:8088"
$ApiUrl = "$BaseUrl/api/v2"
$LoginUrl = "$ApiUrl/login"
$ServiceGroupUrl = "$ApiUrl/sites/default/setting/service/groups"
$PortForwardUrl = "$ApiUrl/sites/default/setting/portforward"
$ACLUrl = "$ApiUrl/sites/default/setting/firewall/acl"
$SettingsUrl = "$ApiUrl/sites/default/setting/controller"

Write-Host "`nTesting connection to Omada Controller..." -ForegroundColor Cyan
try {
    # Disable certificate validation
    if (-not ([System.Management.Automation.PSTypeName]'ServerCertificateValidationCallback').Type) {
        $certCallback = @"
            using System;
            using System.Net;
            using System.Net.Security;
            using System.Security.Cryptography.X509Certificates;
            public class ServerCertificateValidationCallback
            {
                public static void Ignore()
                {
                    ServicePointManager.ServerCertificateValidationCallback +=
                        delegate
                        (
                            Object obj,
                            X509Certificate certificate,
                            X509Chain chain,
                            SslPolicyErrors errors
                        )
                        {
                            return true;
                        };
                }
            }
"@
        Add-Type $certCallback
    }
    [ServerCertificateValidationCallback]::Ignore()
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    Write-Host "Testing basic connection..." -ForegroundColor Cyan
    $testResponse = Invoke-WebRequest -Uri $BaseUrl -UseBasicParsing -Method Get
    Write-Host "Successfully connected to Omada Controller" -ForegroundColor Green

    # Attempt login
    Write-Host "`nAttempting to log in as $Username..." -ForegroundColor Cyan
    $LoginBody = @{
        username = $Username
        password = $PlainPassword
    } | ConvertTo-Json

    Write-Host "Sending login request to $LoginUrl" -ForegroundColor Cyan
    $loginResponse = Invoke-RestMethod -Uri $LoginUrl -Method Post -Body $LoginBody -ContentType "application/json"

    if ($loginResponse.errorCode -ne 0) {
        throw "Login failed: $($loginResponse.msg)"
    }

    $token = $loginResponse.result.token
    if (-not $token) {
        throw "Failed to get authentication token"
    }
    Write-Host "Successfully logged into Omada Controller" -ForegroundColor Green

} catch {
    Write-Host "`nError connecting to Omada Controller: $_" -ForegroundColor Red
    Write-Host "Please verify:" -ForegroundColor Yellow
    Write-Host "1. Controller is accessible at $BaseUrl" -ForegroundColor Yellow
    Write-Host "2. Username ($Username) and password are correct" -ForegroundColor Yellow
    Write-Host "3. Controller is fully initialized" -ForegroundColor Yellow
    Write-Host "`nDebug Information:" -ForegroundColor Cyan
    Write-Host "Response: $($_.Exception.Response)" -ForegroundColor Cyan
    Write-Host "Status Code: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Cyan
    Write-Host "Status Description: $($_.Exception.Response.StatusDescription)" -ForegroundColor Cyan
    exit 1
}

# HTTPS Certificate Setup
if ($SetupHTTPS) {
    Write-Host "`nSetting up HTTPS for Omada Controller..." -ForegroundColor Green

    # Create certificate directory if it doesn't exist
    if (-not (Test-Path $CertPath)) {
        New-Item -ItemType Directory -Path $CertPath -Force | Out-Null
        Write-Host "Created certificate directory at: $CertPath" -ForegroundColor Green
    }

    # Generate self-signed certificate for initial setup
    Write-Host "Generating self-signed certificate..." -ForegroundColor Cyan
    $cert = New-SelfSignedCertificate -DnsName "omada.sharphorizons.tech" `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -NotAfter (Get-Date).AddYears(1) `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -KeyExportPolicy Exportable `
        -KeyUsage DigitalSignature, KeyEncipherment `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1")

    # Export certificate and private key
    $certPassword = ConvertTo-SecureString -String "omada-temp-pass" -Force -AsPlainText
    $certPath = Join-Path $CertPath "omada.pfx"
    Export-PfxCertificate -Cert $cert -FilePath $certPath -Password $certPassword | Out-Null

    Write-Host "Certificate generated successfully:" -ForegroundColor Green
    Write-Host "- Location: $certPath" -ForegroundColor Green
    Write-Host "- Password: omada-temp-pass" -ForegroundColor Yellow
}

# Headers for subsequent requests
$Headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

try {
    # Create Docker Services group
    Write-Host "`nConfiguring network services..." -ForegroundColor Cyan
    $ServiceGroup = @{
        name = "Docker Services"
        services = @(
            @{
                protocol = "TCP"
                port = "80"
                description = "HTTP"
            },
            @{
                protocol = "TCP"
                port = "443"
                description = "HTTPS"
            },
            @{
                protocol = "TCP"
                port = "8082"
                description = "Metrics"
            }
        )
    } | ConvertTo-Json

    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("Authorization", "Bearer $token")
    $ServiceGroupResponse = $webClient.UploadString($ServiceGroupUrl, $ServiceGroup)
    $serviceGroupId = ($ServiceGroupResponse | ConvertFrom-Json).id
    Write-Host "Created Service Group: Docker Services" -ForegroundColor Green

    # Create Port Forwarding rules for entire network
    $PortForward = @{
        name = "Docker Services"
        status = "enabled"
        protocol = "TCP"
        sourcePort = "80,443"
        internalPort = "80,443"
        sourceIp = "0.0.0.0/0"
        internalIp = "10.10.10.0/24"
        serviceGroup = $serviceGroupId
    } | ConvertTo-Json

    $PortForwardResponse = $webClient.UploadString($PortForwardUrl, $PortForward)
    Write-Host "Created Port Forwarding rules" -ForegroundColor Green

    # Create ACL rules
    $ACLRules = @(
        @{
            name = "Allow Internal Docker Access"
            status = "enabled"
            policy = "allow"
            protocol = "TCP"
            sourceIp = "10.10.10.0/24"
            destinationPort = "80,443,8082"
            direction = "in"
        },
        @{
            name = "Allow External HTTPS"
            status = "enabled"
            policy = "allow"
            protocol = "TCP"
            sourceIp = "0.0.0.0/0"
            destinationPort = "443"
            direction = "in"
        },
        @{
            name = "Allow External HTTP for ACME"
            status = "enabled"
            policy = "allow"
            protocol = "TCP"
            sourceIp = "0.0.0.0/0"
            destinationPort = "80"
            direction = "in"
        }
    )

    foreach ($Rule in $ACLRules) {
        $RuleJson = $Rule | ConvertTo-Json
        $RuleResponse = $webClient.UploadString($ACLUrl, $RuleJson)
        Write-Host "Created ACL rule: $($Rule.name)" -ForegroundColor Green
    }

    Write-Host "`nOmada Controller configuration completed!" -ForegroundColor Green
    Write-Host @"
Next steps:
1. Access Omada Controller at http://$ControllerIP:8088
2. Go to Settings > Controller Settings > Security
3. Import the certificate from $certPath using password: omada-temp-pass
4. Enable HTTPS (port 8043) after importing the certificate
5. Verify port forwarding rules are active
6. Test internal network access
7. Monitor EAP783 adoption when installed
"@ -ForegroundColor Yellow

} catch {
    Write-Host "`nError configuring network services: $_" -ForegroundColor Red
    exit 1
}