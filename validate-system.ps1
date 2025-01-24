# Comprehensive system validation script
param(
    [Parameter(Mandatory=$false)]
    [string]$LogFile = ".\logs\system-validation.log"
)

function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$Level] - $Message" | Tee-Object -FilePath $LogFile -Append
}

function Test-DockerService {
    param($ServiceName)
    try {
        $container = docker ps -q -f name=^/${ServiceName}$
        if ($container) {
            $status = docker inspect --format='{{.State.Status}}' $container
            $health = docker inspect --format='{{.State.Health.Status}}' $container 2>$null
            
            if ($status -eq "running") {
                if ($health -and $health -ne "healthy") {
                    Write-Log ("$ServiceName is running but health check shows: " + $health) "WARNING"
                    return $false
                }
                Write-Log "$ServiceName is running properly" "SUCCESS"
                return $true
            }
        }
        Write-Log "$ServiceName is not running" "ERROR"
        return $false
    }
    catch {
        Write-Log ("Error checking " + $ServiceName + ": " + $_) "ERROR"
        return $false
    }
}

function Test-NetworkConnectivity {
    param($Container, $Target, $Port)
    try {
        $result = docker exec $Container timeout 5 nc -zv $Target $Port 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log ("Network connectivity from " + $Container + " to " + $Target + ":" + $Port + " successful") "SUCCESS"
            return $true
        }
        Write-Log ("Network connectivity from " + $Container + " to " + $Target + ":" + $Port + " failed") "ERROR"
        return $false
    }
    catch {
        Write-Log ("Error testing network connectivity from " + $Container + " to " + $Target + ":" + $Port + ": " + $_) "ERROR"
        return $false
    }
}

function Test-MountPoints {
    param($Container)
    try {
        $mounts = docker inspect --format='{{range .Mounts}}{{.Source}}:{{.Destination}}{{println}}{{end}}' $Container
        if ($mounts) {
            Write-Log ("Mount points for " + $Container + ":") "INFO"
            $mounts | ForEach-Object {
                $source, $dest = $_.Split(":")
                if (Test-Path $source) {
                    Write-Log ("  " + $_ + " (Source exists)") "SUCCESS"
                } else {
                    Write-Log ("  " + $_ + " (Source missing)") "ERROR"
                    return $false
                }
            }
            return $true
        }
        Write-Log ("No mount points found for " + $Container) "WARNING"
        return $false
    }
    catch {
        Write-Log ("Error checking mount points for " + $Container + ": " + $_) "ERROR"
        return $false
    }
}

function Test-TraefikConfig {
    try {
        # Check Traefik dynamic configuration
        if (-not (Test-Path "traefik/config")) {
            Write-Log "Traefik config directory missing" "ERROR"
            return $false
        }

        # Validate middleware configuration
        $middlewareConfig = Get-Content "traefik/config/middleware.yml" -Raw
        if ($middlewareConfig -notmatch "chain-secure") {
            Write-Log "Secure middleware chain not configured" "ERROR"
            return $false
        }

        Write-Log "Traefik configuration valid" "SUCCESS"
        return $true
    }
    catch {
        Write-Log ("Error checking Traefik configuration: " + $_) "ERROR"
        return $false
    }
}

function Test-Secrets {
    try {
        $requiredSecrets = @(
            "github_client_id.secret",
            "github_client_secret.secret",
            "auth_secret.secret",
            "prowlarr_api_key.secret",
            "radarr_api_key.secret",
            "sonarr_api_key.secret",
            "lidarr_api_key.secret",
            "readarr_api_key.secret"
        )

        $allValid = $true
        foreach ($secret in $requiredSecrets) {
            $path = Join-Path "docker/secrets" $secret
            if (-not (Test-Path $path)) {
                Write-Log ("Missing required secret: " + $secret) "ERROR"
                $allValid = $false
                continue
            }
            
            $content = Get-Content $path -Raw
            if ([string]::IsNullOrWhiteSpace($content)) {
                Write-Log ("Empty secret file: " + $secret) "ERROR"
                $allValid = $false
            }
        }

        if ($allValid) {
            Write-Log "All required secrets present and populated" "SUCCESS"
        }
        return $allValid
    }
    catch {
        Write-Log ("Error checking secrets: " + $_) "ERROR"
        return $false
    }
}

# Create log directory
New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null

Write-Log "Starting system validation..." "INFO"

# Track overall status
$systemValid = $true

# 1. Check all services
$services = @(
    "traefik", "plex", "sonarr", "radarr", "lidarr",
    "prowlarr", "bazarr", "readarr", "qbittorrent",
    "oauth2-proxy", "prometheus", "alertmanager"
)

foreach ($service in $services) {
    $serviceValid = Test-DockerService $service
    $systemValid = $systemValid -and $serviceValid
}

# 2. Check network connectivity
$networkTests = @(
    @{ Container = "prowlarr"; Target = "qbittorrent"; Port = 8080 },
    @{ Container = "radarr"; Target = "qbittorrent"; Port = 8080 },
    @{ Container = "sonarr"; Target = "qbittorrent"; Port = 8080 },
    @{ Container = "lidarr"; Target = "qbittorrent"; Port = 8080 }
)

foreach ($test in $networkTests) {
    $networkValid = Test-NetworkConnectivity $test.Container $test.Target $test.Port
    $systemValid = $systemValid -and $networkValid
}

# 3. Check mount points
foreach ($service in $services) {
    $mountsValid = Test-MountPoints $service
    $systemValid = $systemValid -and $mountsValid
}

# 4. Check Traefik configuration
$traefikValid = Test-TraefikConfig
$systemValid = $systemValid -and $traefikValid

# 5. Check secrets
$secretsValid = Test-Secrets
$systemValid = $systemValid -and $secretsValid

# Final status
if ($systemValid) {
    Write-Log "System validation completed successfully!" "SUCCESS"
    exit 0
} else {
    Write-Log "System validation failed. Check the log for details." "ERROR"
    exit 1
} 