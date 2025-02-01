# DNS Record Verification Script
param (
    [string]$Domain = "sharphorizons.tech",
    [string]$ExpectedIP = "202.128.124.242"
)

$subdomains = @(
    "sonarr",
    "radarr",
    "prowlarr",
    "lidarr",
    "readarr",
    "plex",
    "traefik",
    "auth"
)

Write-Host "=== DNS Record Verification ==="
Write-Host "Domain: $Domain"
Write-Host "Expected IP: $ExpectedIP"
Write-Host ""

Write-Host "Required DNS Records:"
Write-Host "-------------------"
foreach ($subdomain in $subdomains) {
    Write-Host "Type: A"
    Write-Host "Name: $subdomain"
    Write-Host "Value: $ExpectedIP"
    Write-Host "TTL: 3600"
    Write-Host ""
}

Write-Host "Verifying current DNS records..."
Write-Host "--------------------------------"
foreach ($subdomain in $subdomains) {
    $fqdn = "$subdomain.$Domain"
    try {
        $dnsResult = Resolve-DnsName -Name $fqdn -ErrorAction Stop
        $actualIP = $dnsResult | Where-Object { $_.Type -eq 'A' } | Select-Object -ExpandProperty IPAddress

        Write-Host "$fqdn -> $actualIP"
        if ($actualIP -eq $ExpectedIP) {
            Write-Host "✓ Correct" -ForegroundColor Green
        } else {
            Write-Host "✗ Incorrect (should be $ExpectedIP)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "$fqdn -> Not found" -ForegroundColor Yellow
        Write-Host "✗ DNS record needs to be created" -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "DNS Setup Instructions:"
Write-Host "----------------------"
Write-Host "1. Log into your DNS provider's control panel"
Write-Host "2. Add an A record for each subdomain listed above"
Write-Host "3. Set each record to point to: $ExpectedIP"
Write-Host "4. Set TTL to 3600 seconds (1 hour) or lower"
Write-Host "5. Wait for DNS propagation (can take up to 24 hours)"
Write-Host ""
Write-Host "Common DNS Providers:"
Write-Host "- Cloudflare: https://dash.cloudflare.com"
Write-Host "- Google Domains: https://domains.google.com"
Write-Host "- Namecheap: https://www.namecheap.com/domains/domain-name-search/"
Write-Host ""
Write-Host "Note: If using Cloudflare, ensure SSL/TLS is set to 'Full' or 'Full (Strict)'"
Write-Host "      and disable the Cloudflare proxy (orange cloud) for these records."