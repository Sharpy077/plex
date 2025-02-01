# Port Forwarding Verification Script
param (
    [string]$PublicIP = "202.128.124.242",
    [int[]]$Ports = @(80, 443, 8080, 8443)
)

Write-Host "=== Port Forwarding Verification ==="
Write-Host "Public IP: $PublicIP"
Write-Host ""

# Function to test port
function Test-Port {
    param(
        [string]$ComputerName,
        [int]$Port,
        [int]$Timeout = 1000
    )

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connect = $tcpClient.BeginConnect($ComputerName, $Port, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne($Timeout, $false)

        if (!$wait) {
            $tcpClient.Close()
            return $false
        }

        $tcpClient.EndConnect($connect)
        $tcpClient.Close()
        return $true
    }
    catch {
        return $false
    }
}

# Test local ports first
Write-Host "Testing local port bindings..."
Write-Host "-----------------------------"
foreach ($port in $Ports) {
    $localResult = Test-Port -ComputerName "localhost" -Port $port
    if ($localResult) {
        Write-Host "Port $port (Local): ✓ Open" -ForegroundColor Green
    } else {
        Write-Host "Port $port (Local): ✗ Closed" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Testing external port access..."
Write-Host "------------------------------"
foreach ($port in $Ports) {
    $externalResult = Test-Port -ComputerName $PublicIP -Port $port
    if ($externalResult) {
        Write-Host "Port $port (External): ✓ Open" -ForegroundColor Green
    } else {
        Write-Host "Port $port (External): ✗ Closed" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Port Forwarding Requirements:"
Write-Host "---------------------------"
Write-Host "The following ports need to be forwarded to your server:"
Write-Host "- Port 80: Required for Let's Encrypt HTTP challenge"
Write-Host "- Port 443: Required for HTTPS access"
Write-Host "- Port 8080: Required for Traefik dashboard (optional, can be restricted)"
Write-Host "- Port 8443: Required for HTTPS services"
Write-Host ""

Write-Host "Router Configuration Instructions:"
Write-Host "--------------------------------"
Write-Host "1. Access your router's admin interface"
Write-Host "2. Find the Port Forwarding section (might be under Advanced Settings)"
Write-Host "3. Add the following port forwards:"
Write-Host "   External Port -> Internal Port -> Internal IP"
Write-Host "   80    -> 80    -> Your Server IP"
Write-Host "   443   -> 443   -> Your Server IP"
Write-Host "   8080  -> 8080  -> Your Server IP (optional)"
Write-Host "   8443  -> 8443  -> Your Server IP"
Write-Host ""
Write-Host "Security Notes:"
Write-Host "---------------"
Write-Host "1. Only forward the ports you need"
Write-Host "2. Consider restricting access to port 8080 to local network only"
Write-Host "3. Ensure your firewall rules allow these ports"
Write-Host "4. Keep your router's firmware updated"
Write-Host ""

# Test HTTPS connectivity
Write-Host "Testing HTTPS connectivity..."
Write-Host "---------------------------"
$urls = @(
    "https://sonarr.$Domain",
    "https://prowlarr.$Domain",
    "https://traefik.$Domain"
)

foreach ($url in $urls) {
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -MaximumRedirection 0 -ErrorAction SilentlyContinue
        Write-Host "$url : ✓ Accessible (Status: $($response.StatusCode))" -ForegroundColor Green
    }
    catch [System.Net.WebException] {
        $statusCode = $_.Exception.Response.StatusCode.Value__
        if ($statusCode -eq 301 -or $statusCode -eq 302) {
            Write-Host "$url : ✓ Redirecting (Status: $statusCode)" -ForegroundColor Green
        } else {
            Write-Host "$url : ✗ Error (Status: $statusCode)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "$url : ✗ Not accessible" -ForegroundColor Red
    }
}