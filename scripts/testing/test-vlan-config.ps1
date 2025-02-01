# Automated VLAN Configuration Testing
param (
    [Parameter(Mandatory = $false)]
    [string]$TestVLANConfig = "test-vlan-config.json",
    [switch]$GenerateReport
)

# Import required modules
. "$PSScriptRoot\..\common\logging.ps1"
. "$PSScriptRoot\..\monitoring\check-network-config.ps1"

function Test-VLANConnectivity {
    param (
        [string]$SourceVLAN,
        [string]$TargetVLAN,
        [array]$AllowedPorts
    )

    Write-Log "Testing connectivity from VLAN $SourceVLAN to VLAN $TargetVLAN..."
    $results = @{
        Success = $true
        Issues  = @()
    }

    foreach ($port in $AllowedPorts) {
        $sourceIP = "10.10.$SourceVLAN.100"
        $targetIP = "10.10.$TargetVLAN.100"

        # Test TCP connectivity
        $tcpTest = Test-NetConnection -ComputerName $targetIP -Port $port -WarningAction SilentlyContinue
        if (-not $tcpTest.TcpTestSucceeded) {
            $results.Success = $false
            $results.Issues += "Failed to connect from $sourceIP to $targetIP on port $port"
        }
    }

    return $results
}

function Test-VLANIsolation {
    param (
        [string]$SourceVLAN,
        [string]$TargetVLAN,
        [array]$BlockedPorts
    )

    Write-Log "Testing isolation between VLAN $SourceVLAN and VLAN $TargetVLAN..."
    $results = @{
        Success = $true
        Issues  = @()
    }

    foreach ($port in $BlockedPorts) {
        $sourceIP = "10.10.$SourceVLAN.100"
        $targetIP = "10.10.$TargetVLAN.100"

        # Test TCP connectivity (should fail)
        $tcpTest = Test-NetConnection -ComputerName $targetIP -Port $port -WarningAction SilentlyContinue
        if ($tcpTest.TcpTestSucceeded) {
            $results.Success = $false
            $results.Issues += "Unexpected connectivity from $sourceIP to $targetIP on port $port"
        }
    }

    return $results
}

function Test-VLANLatency {
    param (
        [string]$VLAN,
        [int]$WarningThreshold = 50, # ms
        [int]$CriticalThreshold = 100 # ms
    )

    Write-Log "Testing VLAN $VLAN latency..."
    $results = @{
        Success = $true
        Issues  = @()
        Metrics = @{}
    }

    $gateway = "10.10.$VLAN.1"
    $pingResults = Test-Connection -ComputerName $gateway -Count 10 -ErrorAction SilentlyContinue

    if ($pingResults) {
        $avgLatency = ($pingResults | Measure-Object -Property ResponseTime -Average).Average
        $results.Metrics.AverageLatency = $avgLatency

        if ($avgLatency -gt $CriticalThreshold) {
            $results.Success = $false
            $results.Issues += "Critical latency ($avgLatency ms) on VLAN $VLAN"
        }
        elseif ($avgLatency -gt $WarningThreshold) {
            $results.Issues += "Warning: High latency ($avgLatency ms) on VLAN $VLAN"
        }
    }
    else {
        $results.Success = $false
        $results.Issues += "Unable to measure latency for VLAN $VLAN"
    }

    return $results
}

function Test-VLANBandwidth {
    param (
        [string]$VLAN,
        [int]$MinimumBandwidth = 100  # Mbps
    )

    Write-Log "Testing VLAN $VLAN bandwidth..."
    $results = @{
        Success = $true
        Issues  = @()
        Metrics = @{}
    }

    $target = "10.10.$VLAN.1"
    $testFile = "bandwidth-test.tmp"

    try {
        # Create test file
        $null = New-Item -Path $testFile -ItemType File -Value ("X" * 1MB)

        # Measure upload speed
        $startTime = Get-Date
        Copy-Item -Path $testFile -Destination "\\$target\temp\" -ErrorAction Stop
        $endTime = Get-Date

        $duration = ($endTime - $startTime).TotalSeconds
        $bandwidthMbps = (1 * 8) / $duration  # Convert MB to Mbps

        $results.Metrics.Bandwidth = $bandwidthMbps

        if ($bandwidthMbps -lt $MinimumBandwidth) {
            $results.Success = $false
            $results.Issues += "VLAN $VLAN bandwidth ($bandwidthMbps Mbps) below minimum requirement"
        }
    }
    catch {
        $results.Success = $false
        $results.Issues += "Failed to test bandwidth on VLAN $VLAN: $_"
    }
    finally {
        Remove-Item -Path $testFile -ErrorAction SilentlyContinue
    }

    return $results
}

function Test-VLANSecurity {
    param (
        [hashtable]$VLANConfig
    )

    Write-Log "Testing VLAN security configuration..."
    $results = @{
        Success = $true
        Issues  = @()
    }

    # Test firewall rules
    foreach ($vlan in $VLANConfig.Keys) {
        $config = $VLANConfig[$vlan]

        # Check inbound rules
        foreach ($port in $config.Ports.Inbound) {
            $rule = Get-NetFirewallRule -DisplayName "Allow-VLAN$vlan-Inbound-$port" -ErrorAction SilentlyContinue
            if (-not $rule) {
                $results.Success = $false
                $results.Issues += "Missing inbound firewall rule for VLAN $vlan port $port"
            }
        }

        # Check outbound rules
        foreach ($port in $config.Ports.Outbound) {
            $rule = Get-NetFirewallRule -DisplayName "Allow-VLAN$vlan-Outbound-$port" -ErrorAction SilentlyContinue
            if (-not $rule) {
                $results.Success = $false
                $results.Issues += "Missing outbound firewall rule for VLAN $vlan port $port"
            }
        }
    }

    return $results
}

function Test-VLANRangeAllocation {
    param (
        [hashtable]$VLANConfig,
        [string]$VLAN
    )

    Write-Log "Testing VLAN $VLAN IP range allocation..."
    $results = @{
        Success = $true
        Issues  = @()
        Metrics = @{
            UsedIPs               = 0
            AvailableIPs          = 0
            UtilizationPercentage = 0
        }
    }

    $config = $VLANConfig[$VLAN]
    $totalIPs = 254  # Total usable IPs in a /24 network

    # Validate range allocations
    $usedRanges = @()
    $totalUsed = 0

    foreach ($rangeType in $config.Reserved.Keys) {
        $range = $config.Reserved[$rangeType]
        $start, $end = $range -split '-'
        $startIP = [System.Net.IPAddress]::Parse($start)
        $endIP = [System.Net.IPAddress]::Parse($end)

        # Calculate IPs in range
        $rangeSize = ([System.Net.IPAddress]::Parse($end)).Address - ([System.Net.IPAddress]::Parse($start)).Address + 1
        $totalUsed += $rangeSize

        # Check range size against purpose
        switch ($rangeType) {
            'System' {
                if ($rangeSize -gt 10) {
                    $results.Success = $false
                    $results.Issues += "System range for VLAN $VLAN exceeds recommended size (max 10 IPs)"
                }
            }
            'DHCP' {
                if ($rangeSize -lt 40) {
                    $results.Success = $false
                    $results.Issues += "DHCP range for VLAN $VLAN too small (min 40 IPs recommended)"
                }
            }
            'Static' {
                if ($rangeSize -lt 50) {
                    $results.Success = $false
                    $results.Issues += "Static range for VLAN $VLAN too small (min 50 IPs recommended)"
                }
            }
            'Services' {
                if ($VLAN -eq "20" -and $rangeSize -lt 40) {
                    $results.Success = $false
                    $results.Issues += "Services range for VLAN 20 too small (min 40 IPs recommended)"
                }
            }
            'Containers' {
                if ($VLAN -eq "20" -and $rangeSize -lt 150) {
                    $results.Success = $false
                    $results.Issues += "Containers range for VLAN 20 too small (min 150 IPs recommended)"
                }
            }
        }

        # Check for gaps between ranges
        if ($usedRanges.Count -gt 0) {
            $lastEndIP = [System.Net.IPAddress]::Parse(($usedRanges[-1] -split '-')[1])
            $currentStartIP = [System.Net.IPAddress]::Parse($start)

            if (($currentStartIP.Address - $lastEndIP.Address) -gt 1) {
                $results.Issues += "Gap detected between IP ranges in VLAN $VLAN: $($lastEndIP.ToString()) to $($currentStartIP.ToString())"
            }
        }

        $usedRanges += $range
    }

    # Calculate metrics
    $results.Metrics.UsedIPs = $totalUsed
    $results.Metrics.AvailableIPs = $totalIPs - $totalUsed
    $results.Metrics.UtilizationPercentage = [math]::Round(($totalUsed / $totalIPs) * 100, 2)

    # Check overall utilization
    if ($results.Metrics.UtilizationPercentage -gt 90) {
        $results.Issues += "VLAN $VLAN IP utilization above 90% ($($results.Metrics.UtilizationPercentage)%)"
    }

    return $results
}

# Main execution
try {
    Write-Log "Starting automated VLAN configuration testing..."

    # Load test configuration
    $testConfig = Get-Content $TestVLANConfig | ConvertFrom-Json -AsHashtable

    $testResults = @{
        Timestamp      = Get-Date
        VLANTests      = @{}
        SecurityTests  = $null
        OverallSuccess = $true
    }

    # Test each VLAN configuration
    foreach ($vlan in $testConfig.Keys) {
        $vlanResults = @{
            Connectivity    = @()
            Isolation       = @()
            Performance     = @{}
            RangeAllocation = @()
        }

        # Test connectivity to allowed VLANs
        foreach ($targetVlan in $testConfig[$vlan].AllowedTo) {
            $connectivityTest = Test-VLANConnectivity -SourceVLAN $vlan -TargetVLAN $targetVlan -AllowedPorts $testConfig[$vlan].Ports.Outbound
            $vlanResults.Connectivity += @{
                TargetVLAN = $targetVlan
                Results    = $connectivityTest
            }
            if (-not $connectivityTest.Success) {
                $testResults.OverallSuccess = $false
            }
        }

        # Test isolation from non-allowed VLANs
        $nonAllowedVLANs = $testConfig.Keys | Where-Object { $_ -ne $vlan -and $testConfig[$vlan].AllowedTo -notcontains $_ }
        foreach ($targetVlan in $nonAllowedVLANs) {
            $isolationTest = Test-VLANIsolation -SourceVLAN $vlan -TargetVLAN $targetVlan -BlockedPorts @(80, 443, 53, 123)
            $vlanResults.Isolation += @{
                TargetVLAN = $targetVlan
                Results    = $isolationTest
            }
            if (-not $isolationTest.Success) {
                $testResults.OverallSuccess = $false
            }
        }

        # Test performance
        $latencyTest = Test-VLANLatency -VLAN $vlan
        $bandwidthTest = Test-VLANBandwidth -VLAN $vlan
        $vlanResults.Performance = @{
            Latency   = $latencyTest
            Bandwidth = $bandwidthTest
        }
        if (-not ($latencyTest.Success -and $bandwidthTest.Success)) {
            $testResults.OverallSuccess = $false
        }

        # Add range allocation test
        $rangeTest = Test-VLANRangeAllocation -VLANConfig $testConfig -VLAN $vlan
        $vlanResults.RangeAllocation = $rangeTest
        if (-not $rangeTest.Success) {
            $testResults.OverallSuccess = $false
        }

        $testResults.VLANTests[$vlan] = $vlanResults
    }

    # Test security configuration
    $securityTest = Test-VLANSecurity -VLANConfig $testConfig
    $testResults.SecurityTests = $securityTest
    if (-not $securityTest.Success) {
        $testResults.OverallSuccess = $false
    }

    # Generate report if requested
    if ($GenerateReport) {
        $reportPath = "reports/vlan-test-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $testResults | ConvertTo-Json -Depth 10 | Out-File $reportPath
        Write-Log "Test report generated: $reportPath"
    }

    # Return results
    return $testResults
}
catch {
    Write-Log "Error during VLAN configuration testing: $_" -Level Error
    throw
}