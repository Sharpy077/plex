# Configure Windows Firewall Rules for required ports
param (
    [string]$RuleName = "Plex Stack Services",
    [int[]]$Ports = @(80, 443, 8080, 8443),
    [string]$Description = "Allow incoming traffic for Plex and related services"
)

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "⚠️ This script requires administrator privileges. Please run as administrator." -ForegroundColor Yellow
    exit 1
}

Write-Host "=== Configuring Windows Firewall Rules ==="
Write-Host "Configuring rules for ports: $($Ports -join ', ')"
Write-Host ""

# Function to create or update firewall rules
function Set-FirewallRule {
    param (
        [string]$Name,
        [int]$Port,
        [string]$Protocol = "TCP",
        [string]$Description
    )

    $ruleName = "$Name-$Port-$Protocol"
    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

    if ($existing) {
        Write-Host "Updating existing rule: $ruleName"
        $existing | Set-NetFirewallRule -Enabled True
        $existing | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -Protocol $Protocol -LocalPort $Port
    }
    else {
        Write-Host "Creating new rule: $ruleName"
        New-NetFirewallRule -DisplayName $ruleName `
            -Direction Inbound `
            -Protocol $Protocol `
            -LocalPort $Port `
            -Action Allow `
            -Description $Description
    }
}

# Create/update rules for each port
foreach ($port in $Ports) {
    Write-Host ""
    Write-Host "Configuring port $port..."
    Write-Host "-------------------------"

    # TCP Rule
    Set-FirewallRule -Name $RuleName -Port $port -Protocol "TCP" -Description $Description

    # UDP Rule (for specific ports that need it)
    if ($port -in @(80, 443)) {
        Set-FirewallRule -Name $RuleName -Port $port -Protocol "UDP" -Description $Description
    }
}

# Verify rules
Write-Host ""
Write-Host "Verifying Firewall Rules..."
Write-Host "-------------------------"
foreach ($port in $Ports) {
    $tcpRule = Get-NetFirewallRule -DisplayName "$RuleName-$port-TCP" -ErrorAction SilentlyContinue
    $udpRule = Get-NetFirewallRule -DisplayName "$RuleName-$port-UDP" -ErrorAction SilentlyContinue

    Write-Host "Port $($port):"
    if ($tcpRule) {
        Write-Host "  ✓ TCP Rule: Enabled=$($tcpRule.Enabled)" -ForegroundColor Green
    }
    if ($udpRule) {
        Write-Host "  ✓ UDP Rule: Enabled=$($udpRule.Enabled)" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Recommendations:"
Write-Host "---------------"
Write-Host "1. Verify these ports are forwarded in your router"
Write-Host "2. Ensure your ISP is not blocking these ports"
Write-Host "3. Consider using a port tester tool to verify external access"
Write-Host "4. For additional security:"
Write-Host "   - Limit incoming connections to specific IP ranges"
Write-Host "   - Enable logging for these rules"
Write-Host "   - Regularly review firewall logs"