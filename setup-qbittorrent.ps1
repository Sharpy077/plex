# Setup qBittorrent with proper authentication and configuration
Write-Host "Setting up qBittorrent..."

# Function to make authenticated requests
function Invoke-QBitRequest {
    param (
        [string]$Endpoint,
        [string]$Method = "GET",
        [string]$Data,
        [string]$Cookie
    )
    
    $cmd = "curl -s"
    if ($Method -eq "POST") {
        $cmd += " -X POST"
    }
    
    if ($Data) {
        $cmd += " --data `"$Data`""
    }
    
    if ($Cookie) {
        $cmd += " -b `"$Cookie`""
    }
    
    $cmd += " http://localhost:8080$Endpoint"
    
    Write-Host "Executing: $cmd"
    $result = docker exec qbittorrent bash -c $cmd
    return $result
}

# Step 1: Get initial cookie using temporary password
Write-Host "Authenticating with temporary password..."
$auth = docker exec qbittorrent curl -s -i -X POST --data "username=admin&password=CtJKzU4SN" http://localhost:8080/api/v2/auth/login
Write-Host "Auth response: $auth"

# Extract the cookie from the response
$cookie = ($auth -split "`n" | Select-String "SID=") -replace "Set-Cookie: ", "" -replace ";.*", ""
Write-Host "Extracted cookie: $cookie"

if ($cookie) {
    # Step 2: Configure settings
    Write-Host "Successfully authenticated. Configuring qBittorrent settings..."
    
    $settings = @{
        "save_path" = "/downloads/complete"
        "temp_path" = "/downloads/incomplete"
        "temp_path_enabled" = "true"
        "preallocate_all" = "true"
        "incomplete_files_ext" = "true"
        "create_subfolder_enabled" = "true"
        "start_paused_enabled" = "false"
        "auto_delete_mode" = "0"
        "web_ui_username" = "admin"
        "web_ui_password" = "adminadmin"
    }

    # Convert settings to proper JSON
    $jsonSettings = $settings | ConvertTo-Json -Compress
    $jsonSettings = $jsonSettings.Replace('"', '\"')
    $data = "json=$jsonSettings"
    
    Write-Host "Applying settings..."
    Start-Sleep -Seconds 1
    $result = Invoke-QBitRequest -Endpoint "/api/v2/app/setPreferences" -Method "POST" -Data $data -Cookie $cookie
    Write-Host "Result: $result"
    
    Write-Host "Setup complete!"
} else {
    Write-Host "Failed to authenticate. Please check qBittorrent logs and try again."
    exit 1
} 