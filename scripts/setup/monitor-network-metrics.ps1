# Enhanced Network Monitoring Script with Prometheus Integration
param (
    [Parameter(Mandatory=$false)]
    [string[]]$VlanRanges = @(
        "10.10.10.0/24", # Main network
        "10.10.20.0/24"  # Docker network
    ),
    [int]$MonitorDuration = 300, # 5 minutes
    [string]$MetricsPath = ".\metrics\network",
    [string]$PrometheusPort = 9091,
    [string]$TraefikMetricsEndpoint = "http://localhost:8082/metrics"
)

# Function for structured logging
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Metric')]
        [string]$Level = 'Info'
    )
    $Colors = @{
        'Info' = 'Cyan'
        'Warning' = 'Yellow'
        'Error' = 'Red'
        'Success' = 'Green'
        'Metric' = 'Magenta'
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $Colors[$Level]
}

# Function to format metrics for Prometheus
function Format-PrometheusMetric {
    param(
        [string]$Name,
        [string]$Value,
        [hashtable]$Labels = @{},
        [string]$Help = ""
    )

    $labelStr = if ($Labels.Count -gt 0) {
        "{" + ($Labels.GetEnumerator() | ForEach-Object { "$($_.Key)=`"$($_.Value)`"" }) -join "," + "}"
    } else { "" }

    if ($Help) {
        "# HELP $Name $Help`n"
    }
    "$Name$labelStr $Value"
}

# Create metrics directory
if (-not (Test-Path $MetricsPath)) {
    New-Item -ItemType Directory -Path $MetricsPath -Force | Out-Null
}

Write-Log "Starting enhanced network monitoring..." -Level Info
Write-Log "Monitoring VLANs: $($VlanRanges -join ', ')" -Level Info

# Initialize metrics storage
$metrics = @{
    vlan_traffic = @{}
    container_metrics = @{}
    network_latency = @{}
    error_counts = @{}
    traefik_metrics = @{}
    container_health = @{}
}

foreach ($vlan in $VlanRanges) {
    $metrics.vlan_traffic[$vlan] = @{
        bytes_in = 0
        bytes_out = 0
        packets_in = 0
        packets_out = 0
        active_connections = 0
    }
}

try {
    # Start monitoring loop
    $startTime = Get-Date
    $endTime = $startTime.AddSeconds($MonitorDuration)

    while ((Get-Date) -lt $endTime) {
        # Monitor VLAN traffic
        foreach ($vlan in $VlanRanges) {
            $vlanPrefix = ($vlan -split "/")[0] -replace "\.\d+$", ""

            # Get network adapter statistics
            $adapters = Get-NetAdapter | Where-Object { $_.Name -like "*$vlanPrefix*" }
            foreach ($adapter in $adapters) {
                $stats = $adapter | Get-NetAdapterStatistics
                $metrics.vlan_traffic[$vlan].bytes_in += $stats.ReceivedBytes
                $metrics.vlan_traffic[$vlan].bytes_out += $stats.SentBytes
                $metrics.vlan_traffic[$vlan].packets_in += $stats.ReceivedPackets
                $metrics.vlan_traffic[$vlan].packets_out += $stats.SentPackets
            }

            # Monitor active connections
            $connections = Get-NetTCPConnection | Where-Object {
                $_.LocalAddress -match $vlanPrefix -or $_.RemoteAddress -match $vlanPrefix
            }
            $metrics.vlan_traffic[$vlan].active_connections = $connections.Count

            # Test network latency
            $gateway = ($vlan -split "/")[0] -replace "\.\d+$", ".1"
            $pingResult = Test-Connection -ComputerName $gateway -Count 1 -ErrorAction SilentlyContinue
            if ($pingResult) {
                $metrics.network_latency[$vlan] = $pingResult.ResponseTime
            }
        }

        # Monitor Traefik metrics
        try {
            $traefikMetrics = Invoke-RestMethod -Uri $TraefikMetricsEndpoint -ErrorAction Stop
            $metrics.traefik_metrics = @{
                total_requests = ($traefikMetrics | Where-Object { $_ -match 'traefik_entrypoint_requests_total' }).Count
                response_time = ($traefikMetrics | Where-Object { $_ -match 'traefik_entrypoint_request_duration_seconds' } |
                    Measure-Object -Average).Average
                error_requests = ($traefikMetrics | Where-Object { $_ -match 'traefik_entrypoint_requests_total.*code="[45]' }).Count
            }
        } catch {
            Write-Log "Failed to collect Traefik metrics: $_" -Level Warning
        }

        # Enhanced Docker container monitoring
        $containers = docker ps --format "{{.Names}}"
        foreach ($container in $containers) {
            # Get detailed container stats
            $stats = docker stats $container --no-stream --format "{{.NetIO}}|{{.CPUPerc}}|{{.MemUsage}}|{{.BlockIO}}"
            $statsParts = $stats -split '\|'

            if ($statsParts.Count -eq 4) {
                $metrics.container_metrics[$container] = @{
                    net_io = if ($statsParts[0] -match "(\d+\.?\d*)") { [double]$matches[1] } else { 0 }
                    cpu_percent = if ($statsParts[1] -match "(\d+\.?\d*)") { [double]$matches[1] } else { 0 }
                    memory_usage = if ($statsParts[2] -match "(\d+\.?\d*)") { [double]$matches[1] } else { 0 }
                    block_io = if ($statsParts[3] -match "(\d+\.?\d*)") { [double]$matches[1] } else { 0 }
                }
            }

            # Check container health status
            $health = docker inspect --format "{{.State.Health.Status}}" $container 2>$null
            $metrics.container_health[$container] = if ($health) { $health } else { "none" }

            # Enhanced error logging with context
            $errors = docker logs $container --since 1m 2>&1 | Select-String -Pattern "error|failed|warning" -CaseSensitive:$false
            $metrics.error_counts[$container] = @{
                count = $errors.Count
                context = if ($errors.Count -gt 0) {
                    $errors | Select-Object -First 3 | ForEach-Object { $_.Line.Trim() }
                } else { @() }
            }
        }

        # Export enhanced metrics in Prometheus format
        $prometheusMetrics = @()

        # VLAN traffic metrics
        foreach ($vlan in $VlanRanges) {
            $labels = @{ vlan = $vlan }
            $prometheusMetrics += Format-PrometheusMetric -Name "vlan_bytes_in" -Value $metrics.vlan_traffic[$vlan].bytes_in -Labels $labels
            $prometheusMetrics += Format-PrometheusMetric -Name "vlan_bytes_out" -Value $metrics.vlan_traffic[$vlan].bytes_out -Labels $labels
            $prometheusMetrics += Format-PrometheusMetric -Name "vlan_packets_in" -Value $metrics.vlan_traffic[$vlan].packets_in -Labels $labels
            $prometheusMetrics += Format-PrometheusMetric -Name "vlan_packets_out" -Value $metrics.vlan_traffic[$vlan].packets_out -Labels $labels
            $prometheusMetrics += Format-PrometheusMetric -Name "vlan_active_connections" -Value $metrics.vlan_traffic[$vlan].active_connections -Labels $labels
        }

        # Enhanced container metrics
        foreach ($container in $metrics.container_metrics.Keys) {
            $labels = @{ container = $container }
            $containerMetrics = $metrics.container_metrics[$container]
            $prometheusMetrics += Format-PrometheusMetric -Name "container_net_io" -Value $containerMetrics.net_io -Labels $labels
            $prometheusMetrics += Format-PrometheusMetric -Name "container_cpu_percent" -Value $containerMetrics.cpu_percent -Labels $labels
            $prometheusMetrics += Format-PrometheusMetric -Name "container_memory_usage" -Value $containerMetrics.memory_usage -Labels $labels
            $prometheusMetrics += Format-PrometheusMetric -Name "container_block_io" -Value $containerMetrics.block_io -Labels $labels
            $prometheusMetrics += Format-PrometheusMetric -Name "container_error_count" -Value $metrics.error_counts[$container].count -Labels $labels
            $prometheusMetrics += Format-PrometheusMetric -Name "container_health_status" -Value $(switch($metrics.container_health[$container]) {
                "healthy" { 1 }
                "unhealthy" { 0 }
                default { -1 }
            }) -Labels $labels
        }

        # Traefik metrics
        if ($metrics.traefik_metrics.Count -gt 0) {
            $prometheusMetrics += Format-PrometheusMetric -Name "traefik_total_requests" -Value $metrics.traefik_metrics.total_requests
            $prometheusMetrics += Format-PrometheusMetric -Name "traefik_average_response_time" -Value $metrics.traefik_metrics.response_time
            $prometheusMetrics += Format-PrometheusMetric -Name "traefik_error_requests" -Value $metrics.traefik_metrics.error_requests
        }

        # Network latency metrics
        foreach ($vlan in $metrics.network_latency.Keys) {
            $labels = @{ vlan = $vlan }
            $prometheusMetrics += Format-PrometheusMetric -Name "network_latency_ms" -Value $metrics.network_latency[$vlan] -Labels $labels
        }

        # Save metrics to file
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $metricsFile = Join-Path $MetricsPath "metrics_$timestamp.prom"
        $prometheusMetrics | Set-Content -Path $metricsFile

        # Log summary
        Write-Log "Metrics collected at $timestamp" -Level Metric
        Write-Log "Active containers: $($containers.Count)" -Level Metric
        Write-Log "Total VLANs monitored: $($VlanRanges.Count)" -Level Metric

        Start-Sleep -Seconds 10
    }

} catch {
    Write-Log "Error monitoring network: $_" -Level Error
} finally {
    Write-Log "Monitoring completed. Metrics saved to: $MetricsPath" -Level Success

    # Enhanced summary report
    $summaryFile = Join-Path $MetricsPath "summary_$(Get-Date -Format 'yyyyMMdd_HHmmss').md"
    @"
# Network Monitoring Summary
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## VLAN Statistics
$(foreach ($vlan in $VlanRanges) {
"### $vlan
- Bytes In: $([math]::Round($metrics.vlan_traffic[$vlan].bytes_in / 1MB, 2)) MB
- Bytes Out: $([math]::Round($metrics.vlan_traffic[$vlan].bytes_out / 1MB, 2)) MB
- Active Connections: $($metrics.vlan_traffic[$vlan].active_connections)
- Average Latency: $($metrics.network_latency[$vlan]) ms
"})

## Container Statistics
$(foreach ($container in $metrics.container_metrics.Keys) {
    $containerMetrics = $metrics.container_metrics[$container]
"### $container
- Network I/O: $($containerMetrics.net_io) MB
- CPU Usage: $($containerMetrics.cpu_percent)%
- Memory Usage: $($containerMetrics.memory_usage) MB
- Block I/O: $($containerMetrics.block_io) MB
- Health Status: $($metrics.container_health[$container])
- Error Count: $($metrics.error_counts[$container].count)
$(if ($metrics.error_counts[$container].count -gt 0) {
"Recent Errors:
$(($metrics.error_counts[$container].context | ForEach-Object { "  - $_" }) -join "`n")
"})
"})

## Traefik Statistics
- Total Requests: $($metrics.traefik_metrics.total_requests)
- Average Response Time: $([math]::Round($metrics.traefik_metrics.response_time, 2)) seconds
- Error Requests: $($metrics.traefik_metrics.error_requests)

## Recommendations
1. Monitor containers with high error counts or unhealthy status
2. Check VLANs with high latency (>100ms)
3. Review containers with high resource usage
4. Investigate services with high error rates
5. Monitor Traefik performance metrics
"@ | Set-Content -Path $summaryFile

    Write-Log "Summary report saved to: $summaryFile" -Level Success
}