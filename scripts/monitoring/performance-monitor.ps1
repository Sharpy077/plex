# Performance Monitoring Script
# Monitors system and service performance metrics

param (
    [int]$MonitoringInterval = 60,
    [int]$AlertThresholdCPU = 80,
    [int]$AlertThresholdMemory = 85,
    [int]$AlertThresholdDisk = 90,
    [int]$AlertThresholdLatency = 1000,
    [string]$LogPath = "../logs/monitoring"
)

# Import common functions
. "../common/logging.ps1"
. "../common/config-helper.ps1"

# Initialize logging
$LogFile = Join-Path $LogPath "performance-$(Get-Date -Format 'yyyyMMdd').log"
Initialize-Logging $LogFile

# Configuration
$config = @{
    PrometheusEndpoint   = "http://localhost:9090"
    AlertmanagerEndpoint = "http://localhost:9093"
    ServicesToMonitor    = @(
        "plex",
        "radarr",
        "sonarr",
        "lidarr",
        "traefik"
    )
    Ports                = @{
        plex    = "32400"
        radarr  = "7878"
        sonarr  = "8989"
        lidarr  = "8686"
        traefik = "8080"
    }
}

function Get-SystemMetrics {
    Write-Log "Collecting system metrics..."
    try {
        # CPU Usage
        $cpu = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue
        $cpuUsage = [math]::Round($cpu.CounterSamples.CookedValue)

        # Memory Usage
        $os = Get-Ciminstance Win32_OperatingSystem
        $memoryUsage = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) * 100 / $os.TotalVisibleMemorySize)

        # Disk Usage
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" |
        Select-Object Size, FreeSpace
        $diskUsage = [math]::Round(($disk.Size - $disk.FreeSpace) * 100 / $disk.Size)

        return @{
            CPU    = $cpuUsage
            Memory = $memoryUsage
            Disk   = $diskUsage
        }
    }
    catch {
        Write-Log "Error collecting system metrics: $_" -Level Error
        return $null
    }
}

function Get-NetworkLatency {
    param (
        [string]$Target
    )
    try {
        $ping = Test-Connection -ComputerName $Target -Count 1 -ErrorAction Stop
        return $ping.ResponseTime
    }
    catch {
        Write-Log "Error testing network latency to $Target: $_" -Level Error
        return -1
    }
}

function Get-DockerMetrics {
    param (
        [string]$ServiceName
    )
    Write-Log "Collecting Docker metrics for $ServiceName..."
    try {
        $stats = docker stats ${ServiceName} --no-stream --format "{{.CPUPerc}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"
        $metrics = $stats -split "\t"

        return @{
            CPU       = [decimal]($metrics[0] -replace '%', '')
            Memory    = [decimal]($metrics[1] -replace '%', '')
            NetworkIO = $metrics[2]
            DiskIO    = $metrics[3]
        }
    }
    catch {
        Write-Log "Error collecting Docker metrics for $ServiceName: $_" -Level Error
        return $null
    }
}

function Test-ServiceEndpoint {
    param (
        [string]$ServiceName,
        [string]$Endpoint
    )
    try {
        $startTime = Get-Date
        $response = Invoke-WebRequest -Uri $Endpoint -Method Get -TimeoutSec 5
        $endTime = Get-Date
        $latency = ($endTime - $startTime).TotalMilliseconds

        return @{
            Status  = $response.StatusCode
            Latency = $latency
            Success = $true
        }
    }
    catch {
        Write-Log "Error testing endpoint for $ServiceName: $_" -Level Error
        return @{
            Status  = 0
            Latency = 0
            Success = $false
        }
    }
}

function Send-Alert {
    param (
        [string]$Title,
        [string]$Message,
        [string]$Severity = "warning"
    )
    Write-Log "Sending alert: $Title" -Level Warning
    try {
        $alert = @{
            labels      = @{
                alertname = $Title
                severity  = $Severity
            }
            annotations = @{
                description = $Message
            }
        }

        $body = ConvertTo-Json @($alert)
        Invoke-RestMethod -Uri "$($config.AlertmanagerEndpoint)/api/v1/alerts" -Method Post -Body $body -ContentType "application/json"
    }
    catch {
        Write-Log "Error sending alert: $_" -Level Error
    }
}

function Export-MetricsToPrometheus {
    param (
        [hashtable]$Metrics,
        [string]$ServiceName
    )
    try {
        $timestamp = [int64](Get-Date -UFormat %s)
        $metricsData = @"
# HELP service_cpu_usage CPU usage percentage
# TYPE service_cpu_usage gauge
service_cpu_usage{service="$ServiceName"} $($Metrics.CPU) $timestamp
# HELP service_memory_usage Memory usage percentage
# TYPE service_memory_usage gauge
service_memory_usage{service="$ServiceName"} $($Metrics.Memory) $timestamp
"@
        $metricsFile = Join-Path $LogPath "metrics/$ServiceName.prom"
        $metricsData | Set-Content $metricsFile
    }
    catch {
        Write-Log "Error exporting metrics: $_" -Level Error
    }
}

function Start-PerformanceMonitoring {
    Write-Log "Starting performance monitoring..."

    while ($true) {
        try {
            # System metrics
            $systemMetrics = Get-SystemMetrics
            if ($systemMetrics) {
                if ($systemMetrics.CPU -gt $AlertThresholdCPU) {
                    Send-Alert -Title "High CPU Usage" -Message "System CPU usage is at $($systemMetrics.CPU)%" -Severity "warning"
                }
                if ($systemMetrics.Memory -gt $AlertThresholdMemory) {
                    Send-Alert -Title "High Memory Usage" -Message "System memory usage is at $($systemMetrics.Memory)%" -Severity "warning"
                }
                if ($systemMetrics.Disk -gt $AlertThresholdDisk) {
                    Send-Alert -Title "High Disk Usage" -Message "System disk usage is at $($systemMetrics.Disk)%" -Severity "warning"
                }
            }

            # Service metrics
            foreach ($service in $config.ServicesToMonitor) {
                $dockerMetrics = Get-DockerMetrics -ServiceName $service
                if ($dockerMetrics) {
                    Export-MetricsToPrometheus -Metrics $dockerMetrics -ServiceName $service

                    if ($dockerMetrics.CPU -gt $AlertThresholdCPU) {
                        Send-Alert -Title "High Service CPU Usage" -Message "$service CPU usage is at $($dockerMetrics.CPU)%" -Severity "warning"
                    }
                }

                # Service health and latency
                $endpoint = "http://localhost:$($config.Ports.${service})/health"
                $health = Test-ServiceEndpoint -ServiceName $service -Endpoint $endpoint
                if (-not $health.Success) {
                    Send-Alert -Title "Service Unreachable" -Message "$service is not responding" -Severity "critical"
                }
                elseif ($health.Latency -gt $AlertThresholdLatency) {
                    Send-Alert -Title "High Service Latency" -Message "$service response time is $($health.Latency)ms" -Severity "warning"
                }
            }

            # Network latency
            $latency = Get-NetworkLatency -Target "8.8.8.8"
            if ($latency -gt $AlertThresholdLatency) {
                Send-Alert -Title "High Network Latency" -Message "Network latency is ${latency}ms" -Severity "warning"
            }

            Write-Log "Performance check completed"
            Start-Sleep -Seconds $MonitoringInterval
        }
        catch {
            Write-Log "Error in monitoring loop: $_" -Level Error
            Start-Sleep -Seconds 30  # Shorter interval on error
        }
    }
}

# Main execution
try {
    # Create metrics directory if it doesn't exist
    New-Item -ItemType Directory -Path (Join-Path $LogPath "metrics") -Force | Out-Null

    # Start monitoring
    Start-PerformanceMonitoring
}
catch {
    Write-Log "Critical error in performance monitoring: $_" -Level Error
    exit 1
}