# Common Logging Module
# Provides consistent logging functionality across scripts

# Log levels
$script:LogLevels = @{
    Info     = 0
    Warning  = 1
    Error    = 2
    Critical = 3
}

# Log colors
$script:LogColors = @{
    Info     = "White"
    Warning  = "Yellow"
    Error    = "Red"
    Critical = "DarkRed"
}

# Initialize logging
function Initialize-Logging {
    param (
        [Parameter(Mandatory = $true)]
        [string]$LogFile,
        [string]$LogLevel = "Info"
    )

    # Create log directory if it doesn't exist
    $logDir = Split-Path $LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    # Set global log file
    $script:LogFilePath = $LogFile
    $script:CurrentLogLevel = $LogLevels[$LogLevel]

    Write-Log "Logging initialized. Log file: $LogFile" -Level Info
}

function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = "Info",
        [string]$Component = "",
        [switch]$NoConsole
    )

    # Check if logging is initialized
    if (-not $script:LogFilePath) {
        throw "Logging not initialized. Call Initialize-Logging first."
    }

    # Get timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Format component if provided
    $componentStr = if ($Component) { "[$Component] " } else { "" }

    # Format log message
    $logMessage = "${timestamp} ${Level}: ${componentStr}${Message}"

    # Write to file
    try {
        Add-Content -Path $script:LogFilePath -Value $logMessage
    }
    catch {
        Write-Error "Failed to write to log file: $_"
    }

    # Write to console with color if not suppressed
    if (-not $NoConsole) {
        $color = $LogColors[$Level]
        Write-Host $logMessage -ForegroundColor $color
    }
}

function Write-MetricLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$MetricName,
        [Parameter(Mandatory = $true)]
        [decimal]$Value,
        [hashtable]$Labels = @{},
        [string]$Component = ""
    )

    # Format labels
    $labelStr = $Labels.GetEnumerator() | ForEach-Object { "${$_.Key}=""$($_.Value)""" }
    $labelStr = $labelStr -join ","

    # Format metric message
    $metricMessage = "${MetricName}{${labelStr}} ${Value}"

    Write-Log -Message $metricMessage -Component $Component -Level "Info" -NoConsole
}

function Write-ErrorLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$Component = ""
    )

    $errorMessage = $Message
    if ($ErrorRecord) {
        $errorMessage += "`nError Details:"
        $errorMessage += "`n  Type: $($ErrorRecord.Exception.GetType().FullName)"
        $errorMessage += "`n  Message: $($ErrorRecord.Exception.Message)"
        $errorMessage += "`n  Script: $($ErrorRecord.InvocationInfo.ScriptName)"
        $errorMessage += "`n  Line: $($ErrorRecord.InvocationInfo.ScriptLineNumber)"
    }

    Write-Log -Message $errorMessage -Level "Error" -Component $Component
}

function Start-LogRotation {
    param (
        [int]$RetentionDays = 7,
        [string]$LogDirectory
    )

    if (-not $LogDirectory) {
        $LogDirectory = Split-Path $script:LogFilePath -Parent
    }

    Write-Log "Starting log rotation..." -Level Info

    try {
        # Get all log files older than retention period
        $oldLogs = Get-ChildItem -Path $LogDirectory -Filter "*.log" |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays) }

        foreach ($log in $oldLogs) {
            Write-Log "Removing old log file: $($log.FullName)" -Level Info
            Remove-Item $log.FullName -Force
        }

        Write-Log "Log rotation completed. Removed $($oldLogs.Count) old log files." -Level Info
    }
    catch {
        Write-ErrorLog -Message "Error during log rotation" -ErrorRecord $_
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-Logging',
    'Write-Log',
    'Write-MetricLog',
    'Write-ErrorLog',
    'Start-LogRotation'
)