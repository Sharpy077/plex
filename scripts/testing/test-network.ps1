$ErrorActionPreference = "Stop"

function Test-NetworkSegmentation {
    $services = @(
        @{Name = "Traefik"; Network = "frontend" },
        @{Name = "Radarr"; Network = "backend" },
        @{Name = "Prometheus"; Network = "monitoring" }
    )

    foreach ($service in $services) {
        $network = docker inspect $service.Name.ToLower() --format '{{range $net, $settings := .NetworkSettings.Networks}}{{$net}} {{end}}'
        if (-not $network.Contains($service.Network)) {
            throw "$($service.Name) not on $($service.Network) network"
        }
    }
}

function Test-ServiceCommunication {
    # Frontend services should not reach backend
    docker exec traefik curl -s -o /dev/null -w "%{http_code}" http://radarr.internal:7878 | Should -Be 403

    # Backend services should communicate internally
    docker exec radarr curl -s -o /dev/null -w "%{http_code}" http://sonarr.internal:8989 | Should -Be 401  # Auth required

    # Monitoring should access backend metrics
    docker exec prometheus curl -s -o /dev/null -w "%{http_code}" http://node-exporter:9100/metrics | Should -Be 200
}

function Test-FirewallRules {
    # Test IP whitelisting
    $externalIP = (Invoke-RestMethod ipinfo.io/ip).Trim()
    $response = Invoke-WebRequest -Uri "https://radarr.your.domain" -UseBasicParsing -SkipCertificateCheck
    if ($response.Headers["X-Real-IP"] -ne $externalIP) {
        throw "IP whitelisting failed"
    }
}

# Run all tests
Test-NetworkSegmentation
Test-ServiceCommunication
Test-FirewallRules

Write-Host "All network tests passed successfully" -ForegroundColor Green