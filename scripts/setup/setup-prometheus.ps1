# Setup Prometheus with proper configuration
Write-Host "Setting up Prometheus..."

# Create Prometheus configuration
$prometheusConfig = @"
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'radarr'
    static_configs:
      - targets: ['radarr:7878']
    metrics_path: '/metrics'

  - job_name: 'sonarr'
    static_configs:
      - targets: ['sonarr:8989']
    metrics_path: '/metrics'

  - job_name: 'lidarr'
    static_configs:
      - targets: ['lidarr:8686']
    metrics_path: '/metrics'

  - job_name: 'readarr'
    static_configs:
      - targets: ['readarr:8787']
    metrics_path: '/metrics'

  - job_name: 'prowlarr'
    static_configs:
      - targets: ['prowlarr:9696']
    metrics_path: '/metrics'

  - job_name: 'qbittorrent'
    static_configs:
      - targets: ['qbittorrent:8080']
    metrics_path: '/metrics'
"@

# Write Prometheus configuration
Write-Host "Writing Prometheus configuration..."
$prometheusConfig | Out-File -FilePath "prometheus/prometheus.yml" -Encoding utf8 -Force

# Create Prometheus rules
$prometheusRules = @"
groups:
  - name: service_alerts
    rules:
      - alert: ServiceDown
        expr: up == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ \$labels.job }} is down"
          description: "{{ \$labels.job }} has been down for more than 5 minutes."

      - alert: HighCPUUsage
        expr: rate(process_cpu_seconds_total[5m]) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ \$labels.job }}"
          description: "{{ \$labels.job }} has high CPU usage (> 80%) for more than 5 minutes."

      - alert: HighMemoryUsage
        expr: process_resident_memory_bytes / process_virtual_memory_bytes * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ \$labels.job }}"
          description: "{{ \$labels.job }} has high memory usage (> 80%) for more than 5 minutes."

      - alert: DiskSpaceLow
        expr: node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100 < 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space on {{ \$labels.instance }}"
          description: "Disk space is below 10% on {{ \$labels.instance }}."
"@

# Write Prometheus rules
Write-Host "Writing Prometheus rules..."
$prometheusRules | Out-File -FilePath "prometheus/rules.yml" -Encoding utf8 -Force

Write-Host "Setup complete! Prometheus configuration and rules have been created." 