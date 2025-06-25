#!/bin/bash
set -e

echo "📁 Ensuring config folders exist..."
mkdir -p ./config/qbittorrent
mkdir -p ./config/sonarr
mkdir -p ./config/radarr
mkdir -p ./config/prowlarr
mkdir -p ./config/plex
mkdir -p ./config/proxy-manager
mkdir -p ./downloads
mkdir -p ./media/movies
mkdir -p ./media/shows

echo "🔐 Setting permissions for config folders..."
sudo chown -R 1000:1000 ./config
sudo chown -R 1000:1000 ./downloads
sudo chown -R 1000:1000 ./media

echo "🐳 Bringing containers up..."
docker compose up -d --build

echo "✅ All services started successfully!"
echo ""
echo "📌 NOTE: On first run, manually set qBittorrent credentials to:"
echo "   Username: admin"
echo "   Password: adminadmin"
echo "Then restart autoconfig container with:"
echo "   docker restart autoconfig"
