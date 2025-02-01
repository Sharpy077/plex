# Docker Media Server Stack

A comprehensive media server stack using Docker, featuring Plex and various automation tools for managing your media library.

## Features

- **Media Management**
  - Radarr: Movie collection manager
  - Sonarr: TV series collection manager
  - Lidarr: Music collection manager
  - Readarr: Book collection manager
  - Bazarr: Subtitle management
  - Prowlarr: Indexer aggregator

- **Network & Security**
  - Traefik: Reverse proxy with automatic SSL
  - OAuth2 authentication via GitHub
  - WireGuard VPN for secure remote access
  - VLAN support for network segregation

- **Monitoring**
  - Prometheus: Metrics collection
  - Node Exporter: System metrics
  - cAdvisor: Container metrics
  - Alertmanager: Alert handling

## Prerequisites

- Docker and Docker Compose
- Git
- A GitHub account (for OAuth authentication)
- Port 80, 443 available (or configured differently)
- Sufficient storage for media files

## Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/plex.git
   cd plex
   ```

2. Create required directories:
   ```bash
   mkdir -p docker media/{movies,tv,music,books,downloads} backups prometheus alertmanager letsencrypt
   ```

3. Copy and configure environment variables:
   ```bash
   cp .env.example .env
   # Edit .env with your settings
   ```

4. Start the stack:
   ```bash
   docker-compose up -d
   ```

## Configuration

### Environment Variables

Create a `.env` file with the following variables:

```env
# GitHub OAuth
GITHUB_CLIENT_ID=your_client_id
GITHUB_CLIENT_SECRET=your_client_secret
AUTH_SECRET=random_secret_string
COOKIE_DOMAIN=your.domain.com
AUTH_WHITELIST=github_username1,github_username2

# Email Configuration
ADMIN_EMAIL=your@email.com

# System
PUID=1000
PGID=1000
TZ=Your/Timezone

# Service Hostnames
RADARR_HOST=radarr.your.domain
SONARR_HOST=sonarr.your.domain
LIDARR_HOST=lidarr.your.domain
READARR_HOST=readarr.your.domain
PROWLARR_HOST=prowlarr.your.domain
BAZARR_HOST=bazarr.your.domain
QBIT_HOST=qbit.your.domain
```

### Network Configuration

The stack uses several Docker networks:
- `proxy`: For Traefik reverse proxy
- `vlan20`: For container traffic (external network)
- `media`: For media access
- `downloads`: For download clients
- `monitoring`: For metrics collection

### Security

- All web interfaces are protected by GitHub OAuth authentication
- Services are accessible only through Traefik's secure endpoints
- Rate limiting and security headers are configured
- IP whitelisting for internal networks

## Maintenance

### Backup

Regular backups of the following directories are recommended:
- `./docker/`: Service configurations
- `./letsencrypt/`: SSL certificates
- Application-specific databases

### Monitoring

Access monitoring interfaces at:
- Traefik Dashboard: `traefik.your.domain`
- Prometheus: `prometheus.your.domain`
- Alertmanager: `alerts.your.domain`

## Troubleshooting

Common issues and solutions:

1. **Permission Issues**
   - Ensure PUID/PGID match your user
   - Check directory permissions

2. **Network Access**
   - Verify port forwarding
   - Check VLAN configuration
   - Confirm DNS resolution

3. **Service Health**
   ```bash
   docker-compose ps
   docker-compose logs [service]
   ```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

# Missing:
- Detailed security audit process
- Incident response plan
- Compliance documentation (GDPR, CCPA)
- Data retention policies