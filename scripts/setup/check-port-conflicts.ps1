# Check for services blocking required ports
param (
    [int[]]$PortsToCheck = @(80, 443, 8080, 8443)
)

Write-Host "=== Port Conflict Check ==="
Write-Host "Checking for services using required ports..."
Write-Host ""

# Function to get process using a port
function Get-ProcessUsingPort {
    param (
        [int]$Port
    )

    try {
        $connections = netstat -ano | findstr ":$Port "
        if ($connections) {
            $processIds = $connections | ForEach-Object {
                $parts = $_ -split '\s+'
                $processId = $parts[-1]
                return $processId
            } | Select-Object -Unique

            foreach ($processId in $processIds) {
                $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
                if ($process) {
                    [PSCustomObject]@{
                        Port = $Port
                        ProcessId = $processId
                        ProcessName = $process.ProcessName
                        Path = $process.Path
                    }
                }
            }
        }
    }
    catch {
        Write-Warning "Error checking port $Port : $_"
    }
}

# Check Windows features that might be using ports
Write-Host "Checking Windows Features..."
Write-Host "-------------------------"
$iisInstalled = Get-WindowsOptionalFeature -Online -FeatureName IIS-WebServer | Where-Object { $_.State -eq "Enabled" }
if ($iisInstalled) {
    Write-Host "⚠️ IIS is installed and might be using port 80/443" -ForegroundColor Yellow
    Write-Host "   To disable IIS:"
    Write-Host "   > Disable-WindowsOptionalFeature -Online -FeatureName IIS-WebServer"
} else {
    Write-Host "✓ IIS is not installed" -ForegroundColor Green
}

$wsmanRunning = Get-Service WinRM | Where-Object { $_.Status -eq "Running" }
if ($wsmanRunning) {
    Write-Host "⚠️ WinRM is running and might be using port 5985/5986" -ForegroundColor Yellow
} else {
    Write-Host "✓ WinRM is not using conflicting ports" -ForegroundColor Green
}

Write-Host ""
Write-Host "Checking Port Usage..."
Write-Host "--------------------"
foreach ($port in $PortsToCheck) {
    Write-Host "Port $port :"
    $processInfo = Get-ProcessUsingPort -Port $port
    if ($processInfo) {
        Write-Host "⚠️ Port $port is in use by:" -ForegroundColor Yellow
        foreach ($proc in $processInfo) {
            Write-Host "   - Process: $($proc.ProcessName) (PID: $($proc.ProcessId))"
            Write-Host "     Path: $($proc.Path)"
        }
        Write-Host "   To free this port, you can:"
        Write-Host "   1. Stop the process: Stop-Process -Id $($processInfo[0].ProcessId)"
        Write-Host "   2. Configure the application to use a different port"
        Write-Host "   3. Uninstall the application if not needed"
    } else {
        Write-Host "✓ Port $port is available" -ForegroundColor Green
    }
    Write-Host ""
}

# Check Docker port mappings
Write-Host "Checking Docker Port Mappings..."
Write-Host "---------------------------"
try {
    $dockerContainers = docker ps --format "{{.Names}}: {{.Ports}}"
    if ($dockerContainers) {
        Write-Host "Docker containers with port mappings:"
        $dockerContainers | ForEach-Object {
            Write-Host "   $_"
        }
    } else {
        Write-Host "No Docker containers with port mappings found"
    }
} catch {
    Write-Warning "Could not check Docker containers: $_"
}

Write-Host ""
Write-Host "Recommendations:"
Write-Host "---------------"
Write-Host "1. For any conflicting services:"
Write-Host "   - Stop the service if not needed"
Write-Host "   - Reconfigure to use different ports"
Write-Host "   - Uninstall if not required"
Write-Host ""
Write-Host "2. For Docker containers:"
Write-Host "   - Check docker-compose.yml for port conflicts"
Write-Host "   - Update port mappings if needed"
Write-Host ""
Write-Host "3. For system services:"
Write-Host "   - Use Services.msc to disable conflicting services"
Write-Host "   - Configure services to use alternative ports"