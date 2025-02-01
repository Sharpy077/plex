# Network Configuration Validation
#
# This script performs comprehensive validation of network configuration
# according to the defined topology and security requirements.

param (
    [switch]$Verbose,
    [switch]$Fix,
    [hashtable]$VLANConfig = @{
        # Default VLAN configurations
        "10" = @{
            Subnet    = "10.10.10.0/24"
            Gateway   = "10.10.10.1"
            Purpose   = "Current Devices"
            Reserved  = @{
                System  = "10.10.10.1-10.10.10.10"      # Network infrastructure
                DHCP    = "10.10.10.11-10.10.10.50"     # DHCP pool
                Static  = "10.10.10.51-10.10.10.150"    # Static assignments
                Dynamic = "10.10.10.151-10.10.10.254"   # Dynamic allocations
            }
            AllowedTo = @("20")  # VLANs this VLAN can communicate with
            Ports     = @{
                Inbound  = @("53", "123")  # DNS and NTP
                Outbound = @("80", "443")  # HTTP/HTTPS
            }
        }
        "20" = @{
            Subnet    = "10.10.20.0/24"
            Gateway   = "10.10.20.1"
            Purpose   = "Docker Containers"
            Reserved  = @{
                System     = "10.10.20.1-10.10.20.10"     # Network infrastructure
                Services   = "10.10.20.11-10.10.20.50"    # Core services
                Containers = "10.10.20.51-10.10.20.200"   # Container assignments
                Reserved   = "10.10.20.201-10.10.20.254"  # Future expansion
            }
            AllowedTo = @("10")  # VLANs this VLAN can communicate with
            Ports     = @{
                Inbound  = @("80", "443")  # HTTP/HTTPS
                Outbound = @("53", "123")  # DNS and NTP
            }
        }
    }
)

# Import common functions
. "$PSScriptRoot\..\common\logging.ps1"

function Test-VLANConfiguration {
    param (
        [hashtable]$VLANConfig
    )
    Write-Log "Checking VLAN configuration..."
    $results = @{
        Success = $true
        Issues  = @()
    }

    # Validate all VLANs are within 10.10.0.0/16
    foreach ($vlan in $VLANConfig.Keys) {
        $vlanConfig = $VLANConfig[$vlan]
        $subnet = $vlanConfig.Subnet

        # Basic subnet validation
        if ($subnet -notmatch "^10\.10\.\d{1,3}\.0/24$") {
            $results.Success = $false
            $results.Issues += "VLAN $vlan subnet $subnet is not within 10.10.0.0/16 range"
        }

        # Validate VLAN ID matches subnet
        $subnetThirdOctet = ($subnet -split '\.')[2]
        if ($subnetThirdOctet -ne $vlan) {
            $results.Success = $false
            $results.Issues += "VLAN $vlan subnet third octet ($subnetThirdOctet) does not match VLAN ID"
        }

        # Validate gateway is first IP in subnet
        $expectedGateway = ($subnet -replace "0/24$", "1")
        if ($vlanConfig.Gateway -ne $expectedGateway) {
            $results.Success = $false
            $results.Issues += "VLAN $vlan gateway should be $expectedGateway"
        }

        # Validate allowed VLAN communication
        foreach ($allowedVlan in $vlanConfig.AllowedTo) {
            if (-not $VLANConfig.ContainsKey($allowedVlan)) {
                $results.Success = $false
                $results.Issues += "VLAN $vlan references non-existent VLAN $allowedVlan in AllowedTo"
            }
        }

        # Validate port configurations
        foreach ($direction in @("Inbound", "Outbound")) {
            foreach ($port in $vlanConfig.Ports.$direction) {
                if ($port -notmatch "^\d+$" -or [int]$port -lt 1 -or [int]$port -gt 65535) {
                    $results.Success = $false
                    $results.Issues += "VLAN $vlan has invalid $direction port: $port"
                }
            }
        }

        # Add IP range validation
        $usedRanges = @()
        foreach ($rangeType in $vlanConfig.Reserved.Keys) {
            $range = $vlanConfig.Reserved[$rangeType]
            $start, $end = $range -split '-'

            # Validate range format
            if (-not ($start -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' -and
                    $end -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')) {
                $results.Success = $false
                $results.Issues += "Invalid IP range format in VLAN ${vlan} for ${rangeType}: ${range}"
                continue
            }

            # Convert IPs to integers for comparison
            $startInt = [int64]([ipaddress]$start).Address
            $endInt = [int64]([ipaddress]$end).Address

            # Validate range order
            if ($startInt -gt $endInt) {
                $results.Success = $false
                $results.Issues += "Invalid IP range in VLAN ${vlan} for ${rangeType}: start IP greater than end IP"
                continue
            }

            # Check for overlap with existing ranges
            foreach ($usedRange in $usedRanges) {
                $usedStart, $usedEnd = $usedRange -split '-'
                $usedStartInt = [int64]([ipaddress]$usedStart).Address
                $usedEndInt = [int64]([ipaddress]$usedEnd).Address

                if (-not ($startInt -gt $usedEndInt -or $endInt -lt $usedStartInt)) {
                    $results.Success = $false
                    $results.Issues += "IP range overlap detected in VLAN ${vlan}: ${range} overlaps with ${usedRange}"
                }
            }

            # Validate range is within VLAN subnet
            $subnet = $vlanConfig.Subnet
            $networkID = ($subnet -split '/')[0]
            $networkIDInt = [int64]([ipaddress]$networkID).Address
            $networkEndInt = $networkIDInt + [Math]::Pow(2, 24) - 1  # /24 subnet

            if ($startInt -lt $networkIDInt -or $endInt -gt $networkEndInt) {
                $results.Success = $false
                $results.Issues += "IP range ${range} in VLAN ${vlan} is outside subnet ${subnet}"
            }

            $usedRanges += $range
        }

        # Validate gateway is in system range
        $gatewayIP = $vlanConfig.Gateway
        $systemRange = $vlanConfig.Reserved.System
        $systemStart, $systemEnd = $systemRange -split '-'
        $gatewayInt = [int64]([ipaddress]$gatewayIP).Address
        $systemStartInt = [int64]([ipaddress]$systemStart).Address
        $systemEndInt = [int64]([ipaddress]$systemEnd).Address

        if ($gatewayInt -lt $systemStartInt -or $gatewayInt -gt $systemEndInt) {
            $results.Success = $false
            $results.Issues += "Gateway IP ${gatewayIP} in VLAN ${vlan} is outside system range ${systemRange}"
        }
    }

    # Check for subnet overlap
    $subnets = @{}
    foreach ($vlan in $VLANConfig.Keys) {
        $subnet = ($VLANConfig[$vlan].Subnet -split "/")[0]
        if ($subnets.ContainsKey($subnet)) {
            $results.Success = $false
            $results.Issues += "VLAN $vlan subnet overlaps with VLAN $($subnets[$subnet])"
        }
        $subnets[$subnet] = $vlan
    }

    # Check Docker containers are in correct VLAN
    $networks = docker network ls --format "{{.Name}}" | Where-Object { $_ -ne "proxy" -and $_ -ne "bridge" -and $_ -ne "host" -and $_ -ne "none" }
    foreach ($network in $networks) {
        $config = docker network inspect $network | ConvertFrom-Json
        $subnet = $config.IPAM.Config.Subnet
        if ($subnet -notmatch "^10\.10\.\d{1,3}\.0/24$") {
            $results.Success = $false
            $results.Issues += "Network '$network' using non-compliant subnet: $subnet"
        }
        # Verify Docker networks are in VLAN 20
        if ($subnet -ne $VLANConfig["20"].Subnet) {
            $results.Success = $false
            $results.Issues += "Docker network '$network' must use VLAN 20 subnet: $($VLANConfig['20'].Subnet)"
        }
    }

    return $results
}

function Test-IPAddressing {
    param (
        [hashtable]$VLANConfig
    )
    Write-Log "Checking IP addressing..."
    $results = @{
        Success = $true
        Issues  = @()
    }

    # Check IP assignments against VLAN configurations
    $containers = docker ps -q
    foreach ($container in $containers) {
        $inspect = docker inspect $container | ConvertFrom-Json
        $networks = $inspect.NetworkSettings.Networks
        foreach ($network in $networks.PSObject.Properties) {
            $ip = $network.Value.IPAddress
            foreach ($vlan in $VLANConfig.Keys) {
                $subnet = $VLANConfig[$vlan].Subnet -replace "/24$", ""
                if ($ip -match "^$($subnet -replace '\.0$', '\.')" -and $vlan -ne "20") {
                    $results.Success = $false
                    $results.Issues += "Container ${$inspect.Name} using IP from VLAN ${vlan}: ${ip}"
                }
            }
        }
    }

    return $results
}

function Test-NetworkSecurity {
    param (
        [hashtable]$VLANConfig
    )
    Write-Log "Checking network security configuration..."
    $results = @{
        Success = $true
        Issues  = @()
    }

    # Check inter-VLAN communication rules
    Write-Log "Checking inter-VLAN security..."
    foreach ($sourceVlan in $VLANConfig.Keys) {
        $sourceConfig = $VLANConfig[$sourceVlan]

        # Check allowed VLAN communication
        foreach ($targetVlan in $VLANConfig.Keys) {
            if ($sourceVlan -eq $targetVlan) { continue }

            $ruleName = "VLAN-$sourceVlan-to-$targetVlan"
            $isAllowed = $sourceConfig.AllowedTo -contains $targetVlan

            # Check firewall rules match allowed communication
            $rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
            if ($isAllowed -and -not $rule) {
                $results.Success = $false
                $results.Issues += "Missing firewall rule for allowed communication: VLAN $sourceVlan to VLAN $targetVlan"
            }
            elseif (-not $isAllowed -and $rule) {
                $results.Success = $false
                $results.Issues += "Unexpected firewall rule exists: VLAN $sourceVlan to VLAN $targetVlan should be blocked"
            }

            # Verify port configurations
            if ($isAllowed) {
                $filterProps = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule
                $allowedPorts = $sourceConfig.Ports.Outbound
                if (-not (Compare-Object $filterProps.RemotePort $allowedPorts -SyncWindow 0)) {
                    $results.Success = $false
                    $results.Issues += "Firewall rule ports don't match configuration for VLAN $sourceVlan to $targetVlan"
                }
            }
        }
    }

    # Check for unauthorized cross-VLAN traffic
    Write-Log "Checking for unauthorized cross-VLAN traffic..."
    $netstatOutput = docker exec proxy netstat -an 2>$null
    foreach ($sourceVlan in $VLANConfig.Keys) {
        $sourceSubnet = ($VLANConfig[$sourceVlan].Subnet -split "/")[0]
        foreach ($targetVlan in $VLANConfig.Keys) {
            if ($sourceVlan -eq $targetVlan) { continue }

            $targetSubnet = ($VLANConfig[$targetVlan].Subnet -split "/")[0]
            $connections = $netstatOutput | Select-String -Pattern "$sourceSubnet.*$targetSubnet"

            if ($connections -and -not ($VLANConfig[$sourceVlan].AllowedTo -contains $targetVlan)) {
                $results.Success = $false
                $results.Issues += "Detected unauthorized traffic from VLAN $sourceVlan to VLAN $targetVlan"
            }
        }
    }

    # Check rate limiting per VLAN
    Write-Log "Checking VLAN-specific rate limiting..."
    foreach ($vlan in $VLANConfig.Keys) {
        $rateLimitRule = "RateLimit-VLAN-$vlan"
        $rule = Get-NetQosPolicy -Name $rateLimitRule -ErrorAction SilentlyContinue
        if (-not $rule) {
            $results.Success = $false
            $results.Issues += "Missing rate limiting policy for VLAN $vlan"
        }
    }

    # Check MAC address binding
    Write-Log "Checking MAC address binding..."
    $containers = docker ps -q
    foreach ($container in $containers) {
        $inspect = docker inspect $container | ConvertFrom-Json
        $networks = $inspect.NetworkSettings.Networks
        foreach ($network in $networks.PSObject.Properties) {
            if (-not $network.Value.MacAddress) {
                $results.Success = $false
                $results.Issues += "Container $($inspect.Name) missing MAC address binding"
            }
            # Verify MAC address format
            elseif ($network.Value.MacAddress -notmatch '^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$') {
                $results.Success = $false
                $results.Issues += "Container $($inspect.Name) has invalid MAC address format"
            }
        }
    }

    # Additional security checks from original function...
    // ... existing code ...

    return $results
}

function Test-NetworkMonitoring {
    Write-Log "Checking network monitoring configuration..."
    $results = @{
        Success = $true
        Issues  = @()
    }

    # Check Prometheus metrics
    $prometheusConfig = Get-Content "prometheus/prometheus.yml" -Raw
    if (-not ($prometheusConfig -match "job_name: 'node-exporter'")) {
        $results.Success = $false
        $results.Issues += "Node exporter metrics not configured"
    }
    if (-not ($prometheusConfig -match "job_name: 'cadvisor'")) {
        $results.Success = $false
        $results.Issues += "cAdvisor metrics not configured"
    }

    # Check logging configuration
    if (-not (Test-Path "traefik/config/dynamic/middlewares.yml")) {
        $results.Success = $false
        $results.Issues += "Traefik access logs not configured"
    }

    return $results
}

function Send-NetworkAlert {
    param (
        [string]$Subject,
        [string]$Body
    )

    $emailParams = @{
        From       = $env:FROM_ADDRESS
        To         = $env:ADMIN_EMAIL
        Subject    = $Subject
        Body       = $Body
        SmtpServer = $env:SMTP_HOST
        Port       = $env:SMTP_PORT
        UseSSL     = $true
        Credential = New-Object System.Management.Automation.PSCredential(
            $env:SMTP_USERNAME,
            (ConvertTo-SecureString $env:SMTP_PASSWORD -AsPlainText -Force)
        )
    }

    try {
        Send-MailMessage @emailParams
        Write-Log "Sent network alert: $Subject"
    }
    catch {
        Write-Log "Failed to send network alert: $_" -Level Error
    }
}

# Main execution
try {
    Write-Log "Starting network configuration validation..."

    $allResults = @{
        VLAN         = Test-VLANConfiguration -VLANConfig $VLANConfig
        IPAddressing = Test-IPAddressing -VLANConfig $VLANConfig
        Security     = Test-NetworkSecurity -VLANConfig $VLANConfig
        Monitoring   = Test-NetworkMonitoring
    }

    $networkIssues = @()
    $overallSuccess = $true

    foreach ($category in $allResults.Keys) {
        $result = $allResults[$category]
        if (-not $result.Success) {
            $overallSuccess = $false
            $networkIssues += "== $category Issues =="
            $networkIssues += $result.Issues
            $networkIssues += ""
        }
    }

    if (-not $overallSuccess) {
        $body = "The following network configuration issues were detected:`n`n"
        $body += $networkIssues | ForEach-Object { "$_`n" }

        Send-NetworkAlert -Subject "[NETWORK] Configuration Issues Detected" -Body $body
        Write-Log "Network configuration issues detected. Alert sent." -Level Warning
    }
    else {
        Write-Log "All network configurations are compliant." -Level Success
    }

    # Generate network status report
    $report = @"
Network Status Report
====================
Generated: $(Get-Date)

VLAN Configuration: $($allResults.VLAN.Success)
IP Addressing: $($allResults.IPAddressing.Success)
Security Configuration: $($allResults.Security.Success)
Monitoring Status: $($allResults.Monitoring.Success)

Active Containers:
$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}")

Network Details:
$(docker network inspect proxy | ConvertFrom-Json | ConvertTo-Json -Depth 3)
"@

    $report | Out-File -FilePath "logs/network-status.log"
    Write-Log "Network status report generated: logs/network-status.log"
}
catch {
    $errorMsg = "Error during network validation: $_"
    Write-Log $errorMsg -Level Error
    Send-NetworkAlert -Subject "[NETWORK] Validation Failed" -Body $errorMsg
    exit 1
}