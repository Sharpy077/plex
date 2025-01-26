#!/bin/bash

echo "🔍 Starting setup verification..."

# Test 1: Check Docker network
echo -n "Testing Docker network 'proxy'... "
if docker network inspect proxy >/dev/null 2>&1; then
    echo "✅ OK"
else
    echo "❌ FAILED - Network not found"
    docker network create proxy
    echo "🔧 Created proxy network"
fi

# Test 2: Check required directories
echo -n "Checking required directories... "
DIRS=(
    "docker/secrets"
    "config/plex"
    "config/qbittorrent"
    "config/prowlarr"
    "config/radarr"
    "config/sonarr"
    "config/lidarr"
    "config/readarr"
    "config/bazarr"
    "tv"
    "movies"
    "music"
    "downloads"
    "traefik/config"
    "letsencrypt"
)

FAILED=0
for dir in "${DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "❌ Missing: $dir"
        FAILED=1
    fi
done
[ $FAILED -eq 0 ] && echo "✅ OK"

# Test 3: Check permissions
echo -n "Checking directory permissions... "
FAILED=0
if [ "$(stat -c %a docker/secrets)" != "600" ]; then
    echo "❌ Wrong permissions on docker/secrets"
    FAILED=1
fi

for dir in config/* tv movies music downloads traefik/config letsencrypt; do
    if [ -d "$dir" ] && [ "$(stat -c %a $dir)" != "755" ]; then
        echo "❌ Wrong permissions on $dir"
        FAILED=1
    fi
done
[ $FAILED -eq 0 ] && echo "✅ OK"

# Test 4: Check configuration files
echo -n "Checking configuration files... "
FAILED=0
CONFIG_FILES=(
    "traefik/config/middlewares.yml"
    ".env"
)

for file in "${CONFIG_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ Missing: $file"
        FAILED=1
    fi
done
[ $FAILED -eq 0 ] && echo "✅ OK"

# Test 5: Check environment variables
echo -n "Checking environment variables... "
if [ -f ".env" ]; then
    REQUIRED_VARS=(
        "COOKIE_SECRET"
        "GITHUB_CLIENT_ID"
        "GITHUB_CLIENT_SECRET"
        "TZ"
        "PUID"
        "PGID"
    )

    FAILED=0
    for var in "${REQUIRED_VARS[@]}"; do
        if ! grep -q "^${var}=" .env; then
            echo "❌ Missing: $var in .env"
            FAILED=1
        fi
    done
    [ $FAILED -eq 0 ] && echo "✅ OK"
else
    echo "❌ FAILED - .env file not found"
fi

# Test 6: Check Docker Compose file
echo -n "Validating docker-compose.yml... "
if docker-compose config >/dev/null 2>&1; then
    echo "✅ OK"
else
    echo "❌ FAILED - Invalid docker-compose.yml"
fi

echo "🏁 Setup verification complete"