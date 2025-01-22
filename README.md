# Plex Media Server Stack

A comprehensive Docker-based media server stack with monitoring, security, and automation.

## Services

### Media Management
- Radarr - Movie management
- Sonarr - TV show management
- Lidarr - Music management
- Readarr - Book management
- Bazarr - Subtitle management
- Prowlarr - Indexer management
- qBittorrent - Download client

### Security & Access
- Traefik - Reverse proxy with SSL
- WireGuard - VPN server
- GitHub Authentication

### Monitoring & Metrics
- Prometheus - Metrics collection
- Alertmanager - Alert management
- Node Exporter - System metrics
- cAdvisor - Container metrics

## Features

- Automatic SSL certificate management
- GitHub-based authentication
- Email notifications for alerts
- Resource monitoring and alerts
- Network segmentation
- Automated backups
- Rate limiting and security headers

## Prerequisites

- Docker and Docker Compose
- PowerShell 7+
- Git
- Domain name with DNS configured

## Setup

1. Clone the repository:
```powershell
git clone https://github.com/yourusername/plex.git
cd plex
```

2. Create and update secrets.json with your credentials:
```json
{
  "github": {
    "client_id": "your-github-client-id",
    "client_secret": "your-github-client-secret"
  },
  "auth": {
    "secret": "random-secret-key",
    "cookie_domain": "your-domain.com",
    "auth_host": "auth.your-domain.com",
    "whitelist": ["your-github-username"]
  },
  "email": {
    "smtp_host": "smtp.gmail.com",
    "smtp_port": 587,
    "smtp_username": "your-email@gmail.com",
    "smtp_password": "your-app-password",
    "from_address": "your-email@gmail.com"
  },
  "notifications": {
    "admin_email": "your-admin@email.com"
  }
}
```

3. Generate environment variables:
```powershell
.\generate-env.ps1
```

4. Start the services:
```powershell
docker-compose up -d
```

5. Set up scheduled tasks (requires admin privileges):
```powershell
.\schedule-tasks.ps1
```

## Maintenance

### Backups
- Daily backups are scheduled at 2 AM
- Backups are stored in ./backups
- 7-day retention policy

### Monitoring
- Access Prometheus: https://prometheus.your-domain.com
- Access Alertmanager: https://alerts.your-domain.com
- SSL certificate monitoring runs weekly

### Updates
```powershell
git pull
docker-compose pull
docker-compose up -d
```

## Network Configuration

- Proxy Network: 172.18.0.0/16
- Media Network: 172.19.0.0/16
- Downloads Network: 172.20.0.0/16
- Monitoring Network: 172.21.0.0/16

## Security

- All services require authentication
- Rate limiting enabled
- Security headers configured
- Network segmentation implemented
- Regular security monitoring

## License

MIT License 