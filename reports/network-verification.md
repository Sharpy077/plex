# Network Configuration Verification Report
Generated: 2025-01-31 21:29:28

## Configuration Parameters
- Main VLAN: 10.10.10.0/24
- Docker VLAN: 10.10.20.0/24
- Public IP: 202.128.124.242
[2025-01-31 21:29:28] [Info] Starting network configuration verification...
[2025-01-31 21:29:28] [Check] 
## IP Range Validation
[2025-01-31 21:29:28] [Success] Main VLAN format is valid: 10.10.10.0/24
[2025-01-31 21:29:28] [Success] Docker VLAN format is valid: 10.10.20.0/24
[2025-01-31 21:29:28] [Check] 
## Docker Network Configuration
[2025-01-31 21:29:28] [Info] Available Docker networks:
[2025-01-31 21:29:28] [Info] bridge: bridge
[2025-01-31 21:29:28] [Info] docker_services: bridge
[2025-01-31 21:29:28] [Info] host: host
[2025-01-31 21:29:28] [Info] none: null
[2025-01-31 21:29:28] [Info] plex_proxy: bridge
[2025-01-31 21:29:28] [Error] Proxy network not found
[2025-01-31 21:29:28] [Check] 
## Traefik Configuration
[2025-01-31 21:29:28] [Success] Traefik configuration file found
[2025-01-31 21:29:28] [Error] No trusted IPs configuration found
[2025-01-31 21:29:28] [Check] 
## Middleware Configuration
[2025-01-31 21:29:28] [Success] Middlewares configuration file found
[2025-01-31 21:29:28] [Success] IP whitelist configuration found
[2025-01-31 21:29:28] [Warning] Missing VLANs in whitelist configuration
[2025-01-31 21:29:28] [Check] 
## Network Connectivity
[2025-01-31 21:29:28] [Info] Testing connectivity to Main VLAN gateway (10.10.10.1)...
[2025-01-31 21:29:28] [Success] Main VLAN gateway is accessible
[2025-01-31 21:29:28] [Info] Testing connectivity to Docker VLAN gateway (10.10.20.1)...
[2025-01-31 21:29:28] [Success] Docker VLAN gateway is accessible
[2025-01-31 21:29:28] [Check] 
## Container Network Assignment
[2025-01-31 21:29:28] [Info] Container: prowlarr
[2025-01-31 21:29:28] [Info] - Network Mode: docker_services
[2025-01-31 21:29:28] [Info] - Networks: docker_services
[2025-01-31 21:29:28] [Info] Container: oauth2-proxy
[2025-01-31 21:29:28] [Info] - Network Mode: docker_services
[2025-01-31 21:29:28] [Info] - Networks: docker_services
[2025-01-31 21:29:28] [Info] Container: alertmanager
[2025-01-31 21:29:28] [Info] - Network Mode: docker_services
[2025-01-31 21:29:28] [Info] - Networks: docker_services
[2025-01-31 21:29:28] [Info] Container: qbittorrent
[2025-01-31 21:29:28] [Info] - Network Mode: docker_services
[2025-01-31 21:29:28] [Info] - Networks: docker_services
[2025-01-31 21:29:28] [Info] Container: prometheus
[2025-01-31 21:29:28] [Info] - Network Mode: docker_services
[2025-01-31 21:29:28] [Info] - Networks: docker_services
[2025-01-31 21:29:28] [Info] Container: radarr
[2025-01-31 21:29:28] [Info] - Network Mode: docker_services
[2025-01-31 21:29:28] [Info] - Networks: docker_services
[2025-01-31 21:29:29] [Info] Container: node-exporter
[2025-01-31 21:29:29] [Info] - Network Mode: docker_services
[2025-01-31 21:29:29] [Info] - Networks: docker_services
[2025-01-31 21:29:29] [Info] Container: sonarr
[2025-01-31 21:29:29] [Info] - Network Mode: docker_services
[2025-01-31 21:29:29] [Info] - Networks: docker_services
[2025-01-31 21:29:29] [Info] Container: lidarr
[2025-01-31 21:29:29] [Info] - Network Mode: docker_services
[2025-01-31 21:29:29] [Info] - Networks: docker_services
[2025-01-31 21:29:29] [Info] Container: readarr
[2025-01-31 21:29:29] [Info] - Network Mode: docker_services
[2025-01-31 21:29:29] [Info] - Networks: docker_services
[2025-01-31 21:29:29] [Info] Container: bazarr
[2025-01-31 21:29:29] [Info] - Network Mode: docker_services
[2025-01-31 21:29:29] [Info] - Networks: docker_services
[2025-01-31 21:29:29] [Info] Container: traefik
[2025-01-31 21:29:29] [Info] - Network Mode: docker_services
[2025-01-31 21:29:29] [Info] - Networks: docker_services
[2025-01-31 21:29:29] [Info] Container: plex
[2025-01-31 21:29:29] [Info] - Network Mode: docker_services
[2025-01-31 21:29:29] [Info] - Networks: docker_services
[2025-01-31 21:29:29] [Info] Container: cadvisor
[2025-01-31 21:29:29] [Info] - Network Mode: docker_services
[2025-01-31 21:29:29] [Info] - Networks: docker_services

