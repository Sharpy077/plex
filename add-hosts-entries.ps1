# Requires -RunAsAdministrator

$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
$entries = @(
    "127.0.0.1 auth.sharphorizons.tech",
    "127.0.0.1 sonarr.sharphorizons.tech",
    "127.0.0.1 radarr.sharphorizons.tech",
    "127.0.0.1 lidarr.sharphorizons.tech",
    "127.0.0.1 readarr.sharphorizons.tech",
    "127.0.0.1 bazarr.sharphorizons.tech",
    "127.0.0.1 prowlarr.sharphorizons.tech",
    "127.0.0.1 qbit.sharphorizons.tech",
    "127.0.0.1 plex.sharphorizons.tech",
    "127.0.0.1 prometheus.sharphorizons.tech",
    "127.0.0.1 alerts.sharphorizons.tech",
    "127.0.0.1 traefik.sharphorizons.tech"
)

# Check if entries already exist
$currentHosts = Get-Content $hostsFile
$entriesToAdd = $entries | Where-Object { $currentHosts -notcontains $_ }

if ($entriesToAdd.Count -eq 0) {
    Write-Host "All entries already exist in hosts file."
    exit 0
}

# Add new entries
$entriesToAdd | Add-Content -Path $hostsFile
Write-Host "Added the following entries to hosts file:"
$entriesToAdd | ForEach-Object { Write-Host $_ } 