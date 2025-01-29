# Setup Scripts

This directory contains scripts for setting up and configuring various services in the Plex environment.

## Script Documentation

### Service Setup Scripts
- `setup-radarr.ps1`: Configures Radarr for movie management
- `setup-sonarr.ps1`: Configures Sonarr for TV show management
- `setup-lidarr.ps1`: Configures Lidarr for music management
- `setup-bazarr.ps1`: Configures Bazarr for subtitle management
- `setup-prowlarr.ps1`: Configures Prowlarr for indexer management
- `setup-qbittorrent.ps1`: Configures qBittorrent for download management

### Configuration Scripts
- `generate-env.ps1`: Generates environment configuration files
- `generate-secrets.ps1`: Generates secure secrets and API keys
- `configure-services.ps1`: Performs post-installation service configuration

## Usage Guidelines

1. Run scripts in the following order:
   - Generate environment files first (`generate-env.ps1`)
   - Generate secrets (`generate-secrets.ps1`)
   - Setup individual services
   - Run post-configuration (`configure-services.ps1`)

2. All scripts use the template format defined in `../SCRIPT_TEMPLATE.ps1`

3. Before running any script:
   - Ensure all prerequisites are met
   - Review the script's documentation header
   - Backup any existing configurations

## Maintenance

When adding new setup scripts:
1. Follow the script template format
2. Update this README
3. Test the script in isolation
4. Document any dependencies
5. Update the main documentation in `/docs`