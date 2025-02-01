# Configuration Helper Module
# Provides common configuration management functionality

# Configuration cache
$script:ConfigCache = @{}

function Initialize-Config {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        [switch]$Force
    )

    if ($script:ConfigCache.ContainsKey($ConfigPath) -and -not $Force) {
        return $script:ConfigCache[$ConfigPath]
    }

    try {
        # Load and parse configuration file
        if (Test-Path $ConfigPath) {
            $content = Get-Content $ConfigPath -Raw
            $config = $content | ConvertFrom-Json -AsHashtable
            $script:ConfigCache[$ConfigPath] = $config
            return $config
        }
        else {
            throw "Configuration file not found: $ConfigPath"
        }
    }
    catch {
        Write-Error "Failed to initialize configuration: $_"
        throw
    }
}

function Get-ConfigValue {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        $DefaultValue = $null
    )

    try {
        $config = Initialize-Config -ConfigPath $Path
        $value = Invoke-Expression "`$config.$Key"
        if ($null -eq $value) {
            return $DefaultValue
        }
        return $value
    }
    catch {
        Write-Warning "Failed to get configuration value for $Key. Using default value."
        return $DefaultValue
    }
}

function Set-ConfigValue {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        $Value
    )

    try {
        $config = Initialize-Config -ConfigPath $Path
        Invoke-Expression "`$config.$Key = `$Value"
        $json = $config | ConvertTo-Json -Depth 10
        Set-Content -Path $Path -Value $json
        $script:ConfigCache[$Path] = $config
    }
    catch {
        Write-Error "Failed to set configuration value: $_"
        throw
    }
}

function Test-ConfigValue {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [scriptblock]$Validation
    )

    try {
        $value = Get-ConfigValue -Path $Path -Key $Key
        if ($null -eq $value) {
            return $false
        }
        if ($Validation) {
            return Invoke-Command -ScriptBlock $Validation -ArgumentList $value
        }
        return $true
    }
    catch {
        Write-Warning "Failed to validate configuration value: $_"
        return $false
    }
}

function Merge-Configurations {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PrimaryPath,
        [Parameter(Mandatory = $true)]
        [string]$SecondaryPath,
        [switch]$Force
    )

    try {
        $primary = Initialize-Config -ConfigPath $PrimaryPath
        $secondary = Initialize-Config -ConfigPath $SecondaryPath

        function Merge-Hashtables {
            param($Primary, $Secondary)

            foreach ($key in $Secondary.Keys) {
                if (-not $Primary.ContainsKey($key) -or $Force) {
                    $Primary[$key] = $Secondary[$key]
                }
                elseif ($Primary[$key] -is [hashtable] -and $Secondary[$key] -is [hashtable]) {
                    $Primary[$key] = Merge-Hashtables $Primary[$key] $Secondary[$key]
                }
            }
            return $Primary
        }

        $merged = Merge-Hashtables $primary $secondary
        return $merged
    }
    catch {
        Write-Error "Failed to merge configurations: $_"
        throw
    }
}

function Export-Configuration {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$OutputPath,
        [switch]$IncludeSecrets
    )

    try {
        $config = Initialize-Config -ConfigPath $Path

        if (-not $IncludeSecrets) {
            # Remove sensitive information
            $config = $config | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
            $sensitiveKeys = @('password', 'secret', 'key', 'token', 'credential')

            function Remove-SensitiveData {
                param($Object)

                if ($Object -is [System.Collections.IDictionary]) {
                    $Object.Keys | ForEach-Object {
                        if ($sensitiveKeys -contains $_.ToLower()) {
                            $Object[$_] = '***REDACTED***'
                        }
                        elseif ($Object[$_] -is [System.Collections.IDictionary] -or $Object[$_] -is [Array]) {
                            Remove-SensitiveData $Object[$_]
                        }
                    }
                }
                elseif ($Object -is [Array]) {
                    $Object | ForEach-Object { Remove-SensitiveData $_ }
                }
            }

            Remove-SensitiveData $config
        }

        if ($OutputPath) {
            $config | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath
        }
        else {
            return $config
        }
    }
    catch {
        Write-Error "Failed to export configuration: $_"
        throw
    }
}

function Import-EnvironmentVariables {
    param (
        [Parameter(Mandatory = $true)]
        [string]$EnvFile
    )

    try {
        if (Test-Path $EnvFile) {
            Get-Content $EnvFile | ForEach-Object {
                if ($_ -match '^([^=]+)=(.*)$') {
                    $key = $matches[1]
                    $value = $matches[2]
                    [Environment]::SetEnvironmentVariable($key, $value, 'Process')
                }
            }
            return $true
        }
        return $false
    }
    catch {
        Write-Error "Failed to import environment variables: $_"
        return $false
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-Config',
    'Get-ConfigValue',
    'Set-ConfigValue',
    'Test-ConfigValue',
    'Merge-Configurations',
    'Export-Configuration',
    'Import-EnvironmentVariables'
)