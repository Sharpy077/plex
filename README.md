# Arrs-Compose

Docker Compose configuration for running various *arr services (Sonarr, Radarr, etc.) along with supporting services.

## Services

- Authelia: Authentication service
- Other services (to be documented)

## Configuration

The configuration files are stored in the `config` directory for each service.

## Getting Started

1. Clone this repository
2. Configure the services in their respective config directories
3. Run `docker compose up -d` to start all services

## Notes

- The `version` attribute in docker-compose.yml is obsolete and will be removed in a future update 