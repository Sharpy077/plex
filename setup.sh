#!/bin/bash

# Create Docker network
docker network create proxy

# Create directories
mkdir -p docker/secrets
mkdir -p config/{plex,qbittorrent,prowlarr,radarr,sonarr,lidarr,readarr,bazarr}
mkdir -p {tv,movies,music,downloads}
mkdir -p traefik/config
mkdir -p letsencrypt

# Set permissions
chmod 600 docker/secrets
chmod 755 config/{plex,qbittorrent,prowlarr,radarr,sonarr,lidarr,readarr,bazarr}
chmod 755 {tv,movies,music,downloads}
chmod 755 traefik/config
chmod 755 letsencrypt

# Create example .env file
cat > .env.example << EOL
COOKIE_SECRET=generate_a_secure_random_string
GITHUB_CLIENT_ID=your_github_oauth_app_client_id
GITHUB_CLIENT_SECRET=your_github_oauth_app_client_secret
TZ=Australia/Sydney
PUID=1000
PGID=1000
EOL

echo "Setup complete. Please:"
echo "1. Copy .env.example to .env and fill in the values"
echo "2. Create secret files in docker/secrets/"
echo "3. Configure your GitHub OAuth application"
echo "4. Update DNS records for your domain"