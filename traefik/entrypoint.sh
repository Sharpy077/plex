#!/bin/sh

# Create acme.json if it doesn't exist
if [ ! -f /letsencrypt/acme.json ]; then
    touch /letsencrypt/acme.json
fi

# Set correct permissions
chmod 600 /letsencrypt/acme.json

# Start Traefik with the provided command
exec /entrypoint.sh "$@" 