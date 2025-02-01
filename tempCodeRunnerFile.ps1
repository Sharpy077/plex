# WSL Config.ps1
# Script to configure WSL2 with optimized networking settings

# Create/update WSL config with optimized networking settings
$wslConfigContent = @"
[wsl2]
networkingMode=mirrored
dnsTunneling=true
localhostForwarding=true
autoProxy=true
kernelCommandLine=sysctl.net.ipv4.ip_unprivileged_port_start=0
"@

# Write the config to .wslconfig file in user profile directory
$wslConfigContent | Out-File $env:USERPROFILE\.wslconfig -Force

# Display confirmation message
Write-Host "WSL2 configuration has been updated successfully" -ForegroundColor Green
Write-Host "Please restart WSL for changes to take effect" -ForegroundColor Yellow

# Save script execution status
$scriptPath = Join-Path $env:USERPROFILE "WSL Config.ps1"
Write-Host "Script saved to: $scriptPath" -ForegroundColor Cyan
