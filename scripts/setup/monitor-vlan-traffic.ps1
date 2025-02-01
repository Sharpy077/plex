# Monitor Inter-VLAN Traffic
param (
    [Parameter(Mandatory=$false)]
    [string[]]$VlanRanges = @(
        "10.10.10.0/24", # Main network
        "10.10.20.0/24"  # Docker network
    ),
    [int]$MonitorDuration = 300, # 5 minutes
    [string]$LogPath = ".\logs\vlan-traffic.log"
)

# Function for structured logging
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Traffic')]
        [string]$Level = 'Info'
    )
    $Colors = @{
        'Info' = 'Cyan'
        'Warning' = 'Yellow'
        'Error' = 'Red'
        'Success' = 'Green'
        'Traffic' = 'Magenta'
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $Colors[$Level]
    Add-Content -Path $LogPath -Value $logMessage
}

# Create log directory if it doesn't exist
$logDir = Split-Path $LogPath -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

Write-Log "Starting VLAN traffic monitoring..." -Level Info
Write-Log "Monitoring VLANs: $($VlanRanges -join ', ')" -Level Info
Write-Log "Duration: $MonitorDuration seconds" -Level Info
Write-Log "Log file: $LogPath" -Level Info

# Initialize counters for each VLAN
$trafficStats = @{}
foreach ($vlan in $VlanRanges) {
    $trafficStats[$vlan] = @{
        BytesIn = 0
        BytesOut = 0
        PacketsIn = 0
        PacketsOut = 0
        Connections = @{}
    }
}

$startTime = Get-Date
$endTime = $startTime.AddSeconds($MonitorDuration)

try {
    Write-Log "Starting packet capture..." -Level Info

    # Create ETW session for network monitoring
    New-NetEventSession -Name "VLANMonitor" -CaptureMode SaveToFile -LocalFilePath "$logDir\capture.etl" | Out-Null
    Add-NetEventPacketCaptureProvider -SessionName "VLANMonitor" -TruncationLength 128 | Out-Null
    Start-NetEventSession -Name "VLANMonitor"

    while ((Get-Date) -lt $endTime) {
        $connections = Get-NetTCPConnection | Where-Object {
            $localVlan = $VlanRanges | Where-Object { $_.StartsWith($_.LocalAddress) }
            $remoteVlan = $VlanRanges | Where-Object { $_.StartsWith($_.RemoteAddress) }
            $localVlan -and $remoteVlan -and ($localVlan -ne $remoteVlan)
        }

        foreach ($conn in $connections) {
            $sourceVlan = $VlanRanges | Where-Object { $conn.LocalAddress.StartsWith($_) }
            $destVlan = $VlanRanges | Where-Object { $conn.RemoteAddress.StartsWith($_) }

            if ($sourceVlan -and $destVlan) {
                $key = "$($conn.LocalAddress):$($conn.LocalPort) -> $($conn.RemoteAddress):$($conn.RemotePort)"

                if (-not $trafficStats[$sourceVlan].Connections.ContainsKey($key)) {
                    $trafficStats[$sourceVlan].Connections[$key] = @{
                        StartTime = Get-Date
                        State = $conn.State
                        ProcessId = $conn.OwningProcess
                        ProcessName = (Get-Process -Id $conn.OwningProcess).ProcessName
                    }

                    Write-Log "New connection detected: $key (Process: $((Get-Process -Id $conn.OwningProcess).ProcessName))" -Level Traffic
                }
            }
        }

        # Update statistics
        foreach ($vlan in $VlanRanges) {
            $stats = Get-NetAdapterStatistics | Where-Object { $_.Name -like "*VLAN*" }
            if ($stats) {
                $trafficStats[$vlan].BytesIn += $stats.ReceivedBytes
                $trafficStats[$vlan].BytesOut += $stats.SentBytes
                $trafficStats[$vlan].PacketsIn += $stats.ReceivedPackets
                $trafficStats[$vlan].PacketsOut += $stats.SentPackets
            }
        }

        Start-Sleep -Seconds 1
    }

} catch {
    Write-Log "Error monitoring traffic: $_" -Level Error
} finally {
    # Stop packet capture
    Stop-NetEventSession -Name "VLANMonitor"
    Remove-NetEventSession -Name "VLANMonitor"
}

# Generate summary report
Write-Log "`nTraffic Monitoring Summary" -Level Success
Write-Log "=========================" -Level Success

foreach ($vlan in $VlanRanges) {
    Write-Log "`nVLAN: $vlan" -Level Info
    Write-Log "Bytes In: $([math]::Round($trafficStats[$vlan].BytesIn / 1MB, 2)) MB" -Level Traffic
    Write-Log "Bytes Out: $([math]::Round($trafficStats[$vlan].BytesOut / 1MB, 2)) MB" -Level Traffic
    Write-Log "Packets In: $($trafficStats[$vlan].PacketsIn)" -Level Traffic
    Write-Log "Packets Out: $($trafficStats[$vlan].PacketsOut)" -Level Traffic
    Write-Log "Active Connections: $($trafficStats[$vlan].Connections.Count)" -Level Traffic

    if ($trafficStats[$vlan].Connections.Count -gt 0) {
        Write-Log "`nDetailed Connections:" -Level Info
        foreach ($conn in $trafficStats[$vlan].Connections.GetEnumerator()) {
            Write-Log "- $($conn.Key)" -Level Traffic
            Write-Log "  Process: $($conn.Value.ProcessName) (PID: $($conn.Value.ProcessId))" -Level Traffic
            Write-Log "  State: $($conn.Value.State)" -Level Traffic
            Write-Log "  Duration: $([math]::Round(((Get-Date) - $conn.Value.StartTime).TotalSeconds, 2)) seconds" -Level Traffic
        }
    }
}

Write-Log "`nMonitoring completed! Full logs available at: $LogPath" -Level Success