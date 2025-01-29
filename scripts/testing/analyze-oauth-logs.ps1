# OAuth and Traefik Log Analysis Script
# This script helps analyze OAuth authentication flows and Traefik logs

param (
    [Parameter(Mandatory = $false)]
    [string]$TraefikLogPath = "C:\var\log\traefik\traefik.log",

    [Parameter(Mandatory = $false)]
    [string]$AccessLogPath = "C:\var\log\traefik\access.log",

    [Parameter(Mandatory = $false)]
    [int]$LastMinutes = 10,

    [Parameter(Mandatory = $false)]
    [string]$UserEmail = "",

    [Parameter(Mandatory = $false)]
    [switch]$LiveMonitoring,

    [Parameter(Mandatory = $false)]
    [switch]$ShowErrors,

    [Parameter(Mandatory = $false)]
    [switch]$ShowMetrics,

    [Parameter(Mandatory = $false)]
    [switch]$AnalyzeTokens,

    [Parameter(Mandatory = $false)]
    [switch]$CheckRateLimits,

    [Parameter(Mandatory = $false)]
    [switch]$AnalyzeRedirects,

    [Parameter(Mandatory = $false)]
    [switch]$AnalyzeSessions,

    [Parameter(Mandatory = $false)]
    [switch]$SecurityCheck,

    [Parameter(Mandatory = $false)]
    [switch]$PerformanceMetrics,

    [Parameter(Mandatory = $false)]
    [switch]$ComplianceCheck,

    [Parameter(Mandatory = $false)]
    [int]$AlertThreshold = 5
)

# Color configuration for output
$script:Colors = @{
    Success = 'Green'
    Error   = 'Red'
    Warning = 'Yellow'
    Info    = 'Cyan'
}

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = $Colors.Info
    )
    Write-Host $Message -ForegroundColor $Color
}

function Test-LogPaths {
    if (-not (Test-Path $TraefikLogPath)) {
        Write-ColorOutput "Traefik log file not found at: $TraefikLogPath" $Colors.Error
        return $false
    }
    if (-not (Test-Path $AccessLogPath)) {
        Write-ColorOutput "Access log file not found at: $AccessLogPath" $Colors.Error
        return $false
    }
    return $true
}

function Get-RecentLogs {
    param (
        [string]$LogPath,
        [int]$Minutes
    )

    $cutoffTime = (Get-Date).AddMinutes(-$Minutes)
    Get-Content $LogPath | ForEach-Object {
        try {
            $logEntry = $_ | ConvertFrom-Json
            if ($logEntry.time) {
                $logTime = [DateTime]::Parse($logEntry.time)
                if ($logTime -gt $cutoffTime) {
                    $_
                }
            }
        }
        catch {
            Write-ColorOutput "Error parsing log entry: $_" $Colors.Warning
        }
    }
}

function Get-OAuthFlowAnalysis {
    param(
        [string[]]$LogEntries
    )

    Write-ColorOutput "`n=== OAuth Flow Analysis ===" $Colors.Info

    $flows = @{}
    $LogEntries | ForEach-Object {
        $entry = $_ | ConvertFrom-Json
        if ($entry.RequestHeaders.'X-OAuth-Debug' -eq 'true') {
            $key = "$($entry.ClientIP)-$($entry.StartUTC)"
            if (-not $flows.ContainsKey($key)) {
                $flows[$key] = @()
            }
            $flows[$key] += $entry
        }
    }

    foreach ($flow in $flows.GetEnumerator()) {
        Write-ColorOutput "`nFlow for Client IP: $($flow.Value[0].ClientIP)" $Colors.Info
        $flow.Value | ForEach-Object {
            $status = switch ($_.StatusCode) {
                200 { "Success" }
                302 { "Redirect" }
                { $_ -in 401, 403 } { "Auth Failed" }
                default { "Unknown" }
            }
            Write-ColorOutput "  $($_.StartUTC) - Status: $($_.StatusCode) ($status) - Path: $($_.RequestPath)" $(if ($status -eq "Auth Failed") { $Colors.Error } else { $Colors.Success })
        }
    }
}

function Get-AuthenticationErrors {
    param(
        [string[]]$LogEntries
    )

    Write-ColorOutput "`n=== Authentication Errors ===" $Colors.Info

    $LogEntries | ForEach-Object {
        $entry = $_ | ConvertFrom-Json
        if ($entry.StatusCode -in 401, 403) {
            Write-ColorOutput "Time: $($entry.StartUTC)" $Colors.Error
            Write-ColorOutput "Status: $($entry.StatusCode)" $Colors.Error
            Write-ColorOutput "Path: $($entry.RequestPath)" $Colors.Error
            Write-ColorOutput "Client IP: $($entry.ClientIP)" $Colors.Error
            if ($entry.RequestHeaders.'X-Auth-Request-Email') {
                Write-ColorOutput "User Email: $($entry.RequestHeaders.'X-Auth-Request-Email')" $Colors.Error
            }
            Write-ColorOutput "---" $Colors.Error
        }
    }
}

function Get-UserActivity {
    param(
        [string[]]$LogEntries,
        [string]$Email
    )

    Write-ColorOutput "`n=== User Activity Analysis ===" $Colors.Info

    $LogEntries | ForEach-Object {
        $entry = $_ | ConvertFrom-Json
        if ($entry.RequestHeaders.'X-Auth-Request-Email' -eq $Email) {
            Write-ColorOutput "Time: $($entry.StartUTC)" $Colors.Info
            Write-ColorOutput "Status: $($entry.StatusCode)" $(if ($entry.StatusCode -ge 400) { $Colors.Error } else { $Colors.Success })
            Write-ColorOutput "Path: $($entry.RequestPath)" $Colors.Info
            Write-ColorOutput "---"
        }
    }
}

function Start-LiveMonitoring {
    Write-ColorOutput "`n=== Starting Live OAuth Monitoring ===" $Colors.Info
    Write-ColorOutput "Press Ctrl+C to stop monitoring`n" $Colors.Warning

    try {
        Get-Content $AccessLogPath -Wait | ForEach-Object {
            try {
                $entry = $_ | ConvertFrom-Json
                if ($entry.RequestHeaders.'X-OAuth-Debug' -eq 'true' -or $entry.StatusCode -in 401, 403) {
                    $color = switch ($entry.StatusCode) {
                        200 { $Colors.Success }
                        302 { $Colors.Info }
                        { $_ -in 401, 403 } { $Colors.Error }
                        default { $Colors.Warning }
                    }

                    Write-ColorOutput "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" $color
                    Write-ColorOutput "Status: $($entry.StatusCode)" $color
                    Write-ColorOutput "Path: $($entry.RequestPath)" $color
                    if ($entry.RequestHeaders.'X-Auth-Request-Email') {
                        Write-ColorOutput "User: $($entry.RequestHeaders.'X-Auth-Request-Email')" $color
                    }
                    Write-ColorOutput "---`n"
                }
            }
            catch {
                Write-ColorOutput "Error parsing log entry: $_" $Colors.Warning
            }
        }
    }
    catch {
        Write-ColorOutput "Error in live monitoring: $_" $Colors.Error
    }
}

function Get-OAuthMetrics {
    param(
        [string[]]$LogEntries
    )

    Write-ColorOutput "`n=== OAuth Authentication Metrics ===" $Colors.Info

    $metrics = @{
        TotalRequests = 0
        SuccessfulAuths = 0
        FailedAuths = 0
        UniqueUsers = @{}
        UniqueIPs = @{}
        ResponseTimes = @()
        CommonPaths = @{}
        ErrorPaths = @{}
    }

    $LogEntries | ForEach-Object {
        $entry = $_ | ConvertFrom-Json
        if ($entry.RequestHeaders.'X-OAuth-Debug' -eq 'true') {
            $metrics.TotalRequests++

            # Track success/failure
            if ($entry.StatusCode -eq 200) { $metrics.SuccessfulAuths++ }
            elseif ($entry.StatusCode -in 401, 403) { $metrics.FailedAuths++ }

            # Track unique users
            if ($entry.RequestHeaders.'X-Auth-Request-Email') {
                $metrics.UniqueUsers[$entry.RequestHeaders.'X-Auth-Request-Email'] = $true
            }

            # Track IPs
            $metrics.UniqueIPs[$entry.ClientIP] = $true

            # Track response times
            if ($entry.Duration) {
                $metrics.ResponseTimes += $entry.Duration
            }

            # Track paths
            if ($entry.RequestPath) {
                if ($entry.StatusCode -ge 400) {
                    $metrics.ErrorPaths[$entry.RequestPath] = ($metrics.ErrorPaths[$entry.RequestPath] ?? 0) + 1
                }
                $metrics.CommonPaths[$entry.RequestPath] = ($metrics.CommonPaths[$entry.RequestPath] ?? 0) + 1
            }
        }
    }

    # Output metrics
    Write-ColorOutput "Total Requests: $($metrics.TotalRequests)" $Colors.Info
    Write-ColorOutput "Successful Authentications: $($metrics.SuccessfulAuths)" $Colors.Success
    Write-ColorOutput "Failed Authentications: $($metrics.FailedAuths)" $Colors.Error
    Write-ColorOutput "Unique Users: $($metrics.UniqueUsers.Count)" $Colors.Info
    Write-ColorOutput "Unique IPs: $($metrics.UniqueIPs.Count)" $Colors.Info

    if ($metrics.ResponseTimes.Count -gt 0) {
        $avgTime = ($metrics.ResponseTimes | Measure-Object -Average).Average
        Write-ColorOutput "Average Response Time: $($avgTime.ToString('0.00'))ms" $Colors.Info
    }

    Write-ColorOutput "`nTop Error Paths:" $Colors.Warning
    $metrics.ErrorPaths.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object {
        Write-ColorOutput "  $($_.Key): $($_.Value) errors" $Colors.Warning
    }
}

function Get-TokenAnalysis {
    param(
        [string[]]$LogEntries
    )

    Write-ColorOutput "`n=== Token Analysis ===" $Colors.Info

    $tokenIssues = @{
        Expired = 0
        Invalid = 0
        Missing = 0
    }

    $LogEntries | ForEach-Object {
        $entry = $_ | ConvertFrom-Json
        if ($entry.StatusCode -in 401, 403) {
            if ($entry.RequestHeaders.'Authorization') {
                if ($entry.ResponseBody -match "token.*expired") {
                    $tokenIssues.Expired++
                }
                elseif ($entry.ResponseBody -match "invalid.*token") {
                    $tokenIssues.Invalid++
                }
            }
            else {
                $tokenIssues.Missing++
            }
        }
    }

    Write-ColorOutput "Token Issues Found:" $Colors.Info
    Write-ColorOutput "  Expired Tokens: $($tokenIssues.Expired)" $Colors.Warning
    Write-ColorOutput "  Invalid Tokens: $($tokenIssues.Invalid)" $Colors.Error
    Write-ColorOutput "  Missing Tokens: $($tokenIssues.Missing)" $Colors.Warning
}

function Get-RateLimitAnalysis {
    param(
        [string[]]$LogEntries
    )

    Write-ColorOutput "`n=== Rate Limit Analysis ===" $Colors.Info

    $rateLimits = @{}

    $LogEntries | ForEach-Object {
        $entry = $_ | ConvertFrom-Json
        if ($entry.StatusCode -eq 429) {
            $key = "$($entry.ClientIP)"
            if (-not $rateLimits.ContainsKey($key)) {
                $rateLimits[$key] = @{
                    Count = 0
                    FirstSeen = $entry.StartUTC
                    LastSeen = $entry.StartUTC
                    Paths = @{}
                }
            }

            $rateLimits[$key].Count++
            $rateLimits[$key].LastSeen = $entry.StartUTC
            $rateLimits[$key].Paths[$entry.RequestPath] = ($rateLimits[$key].Paths[$entry.RequestPath] ?? 0) + 1
        }
    }

    if ($rateLimits.Count -gt 0) {
        foreach ($ip in $rateLimits.Keys) {
            Write-ColorOutput "`nRate Limited IP: $ip" $Colors.Warning
            Write-ColorOutput "  Total Hits: $($rateLimits[$ip].Count)" $Colors.Warning
            Write-ColorOutput "  First Seen: $($rateLimits[$ip].FirstSeen)" $Colors.Info
            Write-ColorOutput "  Last Seen: $($rateLimits[$ip].LastSeen)" $Colors.Info
            Write-ColorOutput "  Top Paths:" $Colors.Info
            $rateLimits[$ip].Paths.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3 | ForEach-Object {
                Write-ColorOutput "    $($_.Key): $($_.Value) hits" $Colors.Warning
            }
        }
    }
    else {
        Write-ColorOutput "No rate limit issues found" $Colors.Success
    }
}

function Get-RedirectAnalysis {
    param(
        [string[]]$LogEntries
    )

    Write-ColorOutput "`n=== OAuth Redirect Analysis ===" $Colors.Info

    $redirects = @{}

    $LogEntries | ForEach-Object {
        $entry = $_ | ConvertFrom-Json
        if ($entry.StatusCode -eq 302 -and $entry.RequestHeaders.'X-OAuth-Debug' -eq 'true') {
            $source = $entry.RequestPath
            $destination = $entry.ResponseHeaders.Location

            $key = "$source -> $destination"
            $redirects[$key] = ($redirects[$key] ?? 0) + 1
        }
    }

    if ($redirects.Count -gt 0) {
        Write-ColorOutput "OAuth Redirect Patterns:" $Colors.Info
        $redirects.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
            Write-ColorOutput "  $($_.Key)" $Colors.Info
            Write-ColorOutput "    Count: $($_.Value)" $Colors.Success
        }
    }
    else {
        Write-ColorOutput "No OAuth redirects found in the analyzed period" $Colors.Warning
    }
}

function Get-SessionAnalysis {
    param(
        [string[]]$LogEntries
    )

    Write-ColorOutput "`n=== Session Analysis ===" $Colors.Info

    $sessions = @{}
    $refreshPatterns = @{}
    $terminationReasons = @{
        Timeout = 0
        Logout = 0
        Error = 0
    }

    $LogEntries | ForEach-Object {
        $entry = $_ | ConvertFrom-Json
        if ($entry.RequestHeaders.'X-OAuth-Debug' -eq 'true') {
            $userEmail = $entry.RequestHeaders.'X-Auth-Request-Email'
            if ($userEmail) {
                if (-not $sessions.ContainsKey($userEmail)) {
                    $sessions[$userEmail] = @{
                        FirstSeen = $entry.StartUTC
                        LastSeen = $entry.StartUTC
                        RefreshCount = 0
                        Endpoints = @{}
                        ActiveDuration = 0
                    }
                }

                $sessions[$userEmail].LastSeen = $entry.StartUTC
                $sessions[$userEmail].Endpoints[$entry.RequestPath] = ($sessions[$userEmail].Endpoints[$entry.RequestPath] ?? 0) + 1

                # Track token refreshes
                if ($entry.RequestPath -match "token/refresh") {
                    $sessions[$userEmail].RefreshCount++
                    $timeSinceLastRefresh = [math]::Round(([DateTime]::Parse($entry.StartUTC) - [DateTime]::Parse($sessions[$userEmail].LastSeen)).TotalMinutes)
                    $refreshPatterns[$timeSinceLastRefresh] = ($refreshPatterns[$timeSinceLastRefresh] ?? 0) + 1
                }

                # Track session terminations
                if ($entry.StatusCode -eq 401) {
                    if ($entry.ResponseBody -match "session.*expired") {
                        $terminationReasons.Timeout++
                    }
                    elseif ($entry.RequestPath -match "logout") {
                        $terminationReasons.Logout++
                    }
                    else {
                        $terminationReasons.Error++
                    }
                }

                # Calculate active duration
                $sessions[$userEmail].ActiveDuration = [math]::Round(([DateTime]::Parse($sessions[$userEmail].LastSeen) - [DateTime]::Parse($sessions[$userEmail].FirstSeen)).TotalMinutes)
            }
        }
    }

    # Output session statistics
    Write-ColorOutput "Active Sessions Found: $($sessions.Count)" $Colors.Info
    foreach ($user in $sessions.Keys) {
        Write-ColorOutput "`nUser: $user" $Colors.Info
        Write-ColorOutput "  Session Duration: $($sessions[$user].ActiveDuration) minutes" $Colors.Info
        Write-ColorOutput "  Token Refreshes: $($sessions[$user].RefreshCount)" $Colors.Info
        Write-ColorOutput "  Most Accessed Endpoints:" $Colors.Info
        $sessions[$user].Endpoints.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3 | ForEach-Object {
            Write-ColorOutput "    $($_.Key): $($_.Value) hits" $Colors.Success
        }
    }

    Write-ColorOutput "`nSession Termination Analysis:" $Colors.Info
    Write-ColorOutput "  Timeouts: $($terminationReasons.Timeout)" $Colors.Warning
    Write-ColorOutput "  User Logouts: $($terminationReasons.Logout)" $Colors.Success
    Write-ColorOutput "  Errors: $($terminationReasons.Error)" $Colors.Error
}

function Get-SecurityAnalysis {
    param(
        [string[]]$LogEntries,
        [int]$AlertThreshold
    )

    Write-ColorOutput "`n=== Security Pattern Analysis ===" $Colors.Info

    $securityMetrics = @{
        FailedLogins = @{}
        SuspiciousIPs = @{}
        UnauthorizedAttempts = @{}
        BruteForceAttempts = @{}
        SSLIssues = 0
        InsecureProtocols = 0
    }

    $LogEntries | ForEach-Object {
        $entry = $_ | ConvertFrom-Json

        # Track failed logins by IP
        if ($entry.StatusCode -in 401, 403) {
            $securityMetrics.FailedLogins[$entry.ClientIP] = ($securityMetrics.FailedLogins[$entry.ClientIP] ?? 0) + 1

            # Check for potential brute force
            if ($securityMetrics.FailedLogins[$entry.ClientIP] -gt $AlertThreshold) {
                $securityMetrics.BruteForceAttempts[$entry.ClientIP] = $true
            }
        }

        # Track unauthorized access attempts
        if ($entry.StatusCode -eq 403) {
            $key = "$($entry.ClientIP):$($entry.RequestPath)"
            $securityMetrics.UnauthorizedAttempts[$key] = ($securityMetrics.UnauthorizedAttempts[$key] ?? 0) + 1
        }

        # Check for SSL/TLS issues
        if ($entry.RequestHeaders.'X-Forwarded-Proto' -ne 'https') {
            $securityMetrics.InsecureProtocols++
        }

        if ($entry.ResponseBody -match "ssl|tls|certificate") {
            $securityMetrics.SSLIssues++
        }

        # Identify suspicious patterns
        if ($entry.RequestHeaders.'User-Agent' -match "curl|wget|postman" -or
            $entry.RequestPath -match "/admin|/config|/internal" -or
            $entry.RequestMethod -notin @('GET', 'POST', 'HEAD')) {
            $securityMetrics.SuspiciousIPs[$entry.ClientIP] = ($securityMetrics.SuspiciousIPs[$entry.ClientIP] ?? 0) + 1
        }
    }

    # Output security findings
    if ($securityMetrics.BruteForceAttempts.Count -gt 0) {
        Write-ColorOutput "`nPotential Brute Force Attempts Detected!" $Colors.Error
        foreach ($ip in $securityMetrics.BruteForceAttempts.Keys) {
            Write-ColorOutput "  IP: $ip (Failed Attempts: $($securityMetrics.FailedLogins[$ip]))" $Colors.Error
        }
    }

    Write-ColorOutput "`nSuspicious Activity:" $Colors.Warning
    $securityMetrics.SuspiciousIPs.GetEnumerator() | Where-Object { $_.Value -gt $AlertThreshold } | ForEach-Object {
        Write-ColorOutput "  IP: $($_.Key) (Suspicious Actions: $($_.Value))" $Colors.Warning
    }

    Write-ColorOutput "`nUnauthorized Access Attempts:" $Colors.Warning
    $securityMetrics.UnauthorizedAttempts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object {
        Write-ColorOutput "  $($_.Key): $($_.Value) attempts" $Colors.Warning
    }

    if ($securityMetrics.InsecureProtocols -gt 0) {
        Write-ColorOutput "`nInsecure Protocol Usage: $($securityMetrics.InsecureProtocols) requests" $Colors.Error
    }

    if ($securityMetrics.SSLIssues -gt 0) {
        Write-ColorOutput "SSL/TLS Issues Detected: $($securityMetrics.SSLIssues) occurrences" $Colors.Error
    }
}

function Get-PerformanceMetrics {
    param(
        [string[]]$LogEntries
    )

    Write-ColorOutput "`n=== Performance Analysis ===" $Colors.Info

    $performance = @{
        EndpointTiming = @{}
        SlowRequests = @()
        CacheStats = @{
            Hits = 0
            Misses = 0
        }
        TokenRefreshTiming = @()
        AverageLatency = 0
        P95Latency = 0
        P99Latency = 0
    }

    $allDurations = @()

    $LogEntries | ForEach-Object {
        $entry = $_ | ConvertFrom-Json

        if ($entry.Duration) {
            $duration = [double]$entry.Duration
            $allDurations += $duration

            # Track endpoint timing
            $key = "$($entry.RequestMethod) $($entry.RequestPath)"
            if (-not $performance.EndpointTiming.ContainsKey($key)) {
                $performance.EndpointTiming[$key] = @{
                    Count = 0
                    TotalTime = 0
                    MaxTime = 0
                    MinTime = [double]::MaxValue
                }
            }

            $performance.EndpointTiming[$key].Count++
            $performance.EndpointTiming[$key].TotalTime += $duration
            $performance.EndpointTiming[$key].MaxTime = [math]::Max($performance.EndpointTiming[$key].MaxTime, $duration)
            $performance.EndpointTiming[$key].MinTime = [math]::Min($performance.EndpointTiming[$key].MinTime, $duration)

            # Track slow requests (> 1000ms)
            if ($duration -gt 1000) {
                $performance.SlowRequests += @{
                    Path = $entry.RequestPath
                    Duration = $duration
                    Timestamp = $entry.StartUTC
                }
            }
        }

        # Track cache performance
        if ($entry.ResponseHeaders.'X-Cache') {
            if ($entry.ResponseHeaders.'X-Cache' -eq 'HIT') {
                $performance.CacheStats.Hits++
            }
            else {
                $performance.CacheStats.Misses++
            }
        }

        # Track token refresh performance
        if ($entry.RequestPath -match "token/refresh" -and $entry.Duration) {
            $performance.TokenRefreshTiming += $entry.Duration
        }
    }

    # Calculate statistics
    if ($allDurations.Count -gt 0) {
        $performance.AverageLatency = ($allDurations | Measure-Object -Average).Average
        $sortedDurations = $allDurations | Sort-Object
        $p95Index = [math]::Floor($sortedDurations.Count * 0.95)
        $p99Index = [math]::Floor($sortedDurations.Count * 0.99)
        $performance.P95Latency = $sortedDurations[$p95Index]
        $performance.P99Latency = $sortedDurations[$p99Index]
    }

    # Output performance metrics
    Write-ColorOutput "Overall Latency Metrics:" $Colors.Info
    Write-ColorOutput "  Average: $([math]::Round($performance.AverageLatency, 2))ms" $Colors.Info
    Write-ColorOutput "  95th Percentile: $([math]::Round($performance.P95Latency, 2))ms" $Colors.Info
    Write-ColorOutput "  99th Percentile: $([math]::Round($performance.P99Latency, 2))ms" $Colors.Info

    Write-ColorOutput "`nEndpoint Performance:" $Colors.Info
    $performance.EndpointTiming.GetEnumerator() | Sort-Object { $_.Value.TotalTime / $_.Value.Count } -Descending | Select-Object -First 5 | ForEach-Object {
        $avgTime = [math]::Round($_.Value.TotalTime / $_.Value.Count, 2)
        Write-ColorOutput "  $($_.Key):" $Colors.Info
        Write-ColorOutput "    Avg: ${avgTime}ms, Min: $([math]::Round($_.Value.MinTime, 2))ms, Max: $([math]::Round($_.Value.MaxTime, 2))ms" $(if ($avgTime -gt 1000) { $Colors.Warning } else { $Colors.Success })
    }

    if ($performance.SlowRequests.Count -gt 0) {
        Write-ColorOutput "`nSlow Requests (>1000ms):" $Colors.Warning
        $performance.SlowRequests | Sort-Object Duration -Descending | Select-Object -First 5 | ForEach-Object {
            Write-ColorOutput "  $($_.Path): $([math]::Round($_.Duration, 2))ms at $($_.Timestamp)" $Colors.Warning
        }
    }

    if ($performance.CacheStats.Hits + $performance.CacheStats.Misses -gt 0) {
        $cacheHitRate = [math]::Round(($performance.CacheStats.Hits / ($performance.CacheStats.Hits + $performance.CacheStats.Misses)) * 100, 2)
        Write-ColorOutput "`nCache Performance:" $Colors.Info
        Write-ColorOutput "  Hit Rate: ${cacheHitRate}%" $(if ($cacheHitRate -lt 50) { $Colors.Warning } else { $Colors.Success })
    }

    if ($performance.TokenRefreshTiming.Count -gt 0) {
        $avgRefreshTime = ($performance.TokenRefreshTiming | Measure-Object -Average).Average
        Write-ColorOutput "`nToken Refresh Performance:" $Colors.Info
        Write-ColorOutput "  Average Time: $([math]::Round($avgRefreshTime, 2))ms" $(if ($avgRefreshTime -gt 500) { $Colors.Warning } else { $Colors.Success })
    }
}

function Get-ComplianceCheck {
    param(
        [string[]]$LogEntries
    )

    Write-ColorOutput "`n=== Compliance Analysis ===" $Colors.Info

    $compliance = @{
        RequiredHeaders = @{
            'Strict-Transport-Security' = 0
            'X-Content-Type-Options' = 0
            'X-Frame-Options' = 0
            'Content-Security-Policy' = 0
        }
        SSLVersion = @{}
        ConsentTracking = @{
            Granted = 0
            Denied = 0
            Missing = 0
        }
        TokenExpiration = @{
            Valid = 0
            Expired = 0
            NoExpiry = 0
        }
        DataPrivacy = @{
            PII = 0
            Encrypted = 0
            Unencrypted = 0
        }
    }

    $LogEntries | ForEach-Object {
        $entry = $_ | ConvertFrom-Json

        # Check security headers
        foreach ($header in $compliance.RequiredHeaders.Keys) {
            if ($entry.ResponseHeaders.$header) {
                $compliance.RequiredHeaders[$header]++
            }
        }

        # Check SSL/TLS version
        if ($entry.RequestHeaders.'SSL-Protocol') {
            $compliance.SSLVersion[$entry.RequestHeaders.'SSL-Protocol'] = ($compliance.SSLVersion[$entry.RequestHeaders.'SSL-Protocol'] ?? 0) + 1
        }

        # Track consent
        if ($entry.RequestPath -match "consent") {
            if ($entry.StatusCode -eq 200) {
                $compliance.ConsentTracking.Granted++
            }
            elseif ($entry.StatusCode -eq 403) {
                $compliance.ConsentTracking.Denied++
            }
            else {
                $compliance.ConsentTracking.Missing++
            }
        }

        # Check token expiration
        if ($entry.ResponseHeaders.'Authorization') {
            if ($entry.ResponseBody -match "exp") {
                if ($entry.ResponseBody -match "token.*expired") {
                    $compliance.TokenExpiration.Expired++
                }
                else {
                    $compliance.TokenExpiration.Valid++
                }
            }
            else {
                $compliance.TokenExpiration.NoExpiry++
            }
        }

        # Check PII handling
        if ($entry.RequestHeaders.'X-Auth-Request-Email' -or
            $entry.RequestPath -match "profile|personal|account") {
            $compliance.DataPrivacy.PII++
            if ($entry.RequestHeaders.'X-Forwarded-Proto' -eq 'https') {
                $compliance.DataPrivacy.Encrypted++
            }
            else {
                $compliance.DataPrivacy.Unencrypted++
            }
        }
    }

    # Output compliance findings
    Write-ColorOutput "Security Headers Coverage:" $Colors.Info
    foreach ($header in $compliance.RequiredHeaders.Keys) {
        $percentage = if ($LogEntries.Count -gt 0) {
            [math]::Round(($compliance.RequiredHeaders[$header] / $LogEntries.Count) * 100, 2)
        } else { 0 }
        Write-ColorOutput "  $header`: ${percentage}%" $(if ($percentage -lt 98) { $Colors.Warning } else { $Colors.Success })
    }

    Write-ColorOutput "`nSSL/TLS Versions:" $Colors.Info
    $compliance.SSLVersion.GetEnumerator() | ForEach-Object {
        Write-ColorOutput "  $($_.Key): $($_.Value) requests" $(if ($_.Key -notmatch "TLSv1.2|TLSv1.3") { $Colors.Error } else { $Colors.Success })
    }

    Write-ColorOutput "`nConsent Tracking:" $Colors.Info
    Write-ColorOutput "  Granted: $($compliance.ConsentTracking.Granted)" $Colors.Success
    Write-ColorOutput "  Denied: $($compliance.ConsentTracking.Denied)" $Colors.Warning
    Write-ColorOutput "  Missing: $($compliance.ConsentTracking.Missing)" $Colors.Error

    Write-ColorOutput "`nToken Management:" $Colors.Info
    Write-ColorOutput "  Valid Tokens: $($compliance.TokenExpiration.Valid)" $Colors.Success
    Write-ColorOutput "  Expired Tokens: $($compliance.TokenExpiration.Expired)" $Colors.Warning
    Write-ColorOutput "  Missing Expiry: $($compliance.TokenExpiration.NoExpiry)" $Colors.Error

    Write-ColorOutput "`nPII Handling:" $Colors.Info
    Write-ColorOutput "  Total PII Requests: $($compliance.DataPrivacy.PII)" $Colors.Info
    Write-ColorOutput "  Encrypted: $($compliance.DataPrivacy.Encrypted)" $Colors.Success
    Write-ColorOutput "  Unencrypted: $($compliance.DataPrivacy.Unencrypted)" $Colors.Error
}

# Main execution
if (-not (Test-LogPaths)) {
    exit 1
}

if ($LiveMonitoring) {
    Start-LiveMonitoring
    exit 0
}

Write-ColorOutput "Analyzing logs for the last $LastMinutes minutes..." $Colors.Info

$recentLogs = Get-RecentLogs -LogPath $AccessLogPath -Minutes $LastMinutes

if ($ShowErrors) {
    Get-AuthenticationErrors -LogEntries $recentLogs
}
else {
    Get-OAuthFlowAnalysis -LogEntries $recentLogs
}

if ($UserEmail) {
    Get-UserActivity -LogEntries $recentLogs -Email $UserEmail
}

if ($ShowMetrics) {
    Get-OAuthMetrics -LogEntries $recentLogs
}

if ($AnalyzeTokens) {
    Get-TokenAnalysis -LogEntries $recentLogs
}

if ($CheckRateLimits) {
    Get-RateLimitAnalysis -LogEntries $recentLogs
}

if ($AnalyzeRedirects) {
    Get-RedirectAnalysis -LogEntries $recentLogs
}

if ($AnalyzeSessions) {
    Get-SessionAnalysis -LogEntries $recentLogs
}

if ($SecurityCheck) {
    Get-SecurityAnalysis -LogEntries $recentLogs -AlertThreshold $AlertThreshold
}

if ($PerformanceMetrics) {
    Get-PerformanceMetrics -LogEntries $recentLogs
}

if ($ComplianceCheck) {
    Get-ComplianceCheck -LogEntries $recentLogs
}

Write-ColorOutput "`nAnalysis complete!" $Colors.Success