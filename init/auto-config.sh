#!/bin/bash
set -e

# Load env
source /.env

# Wait function
wait_for() {
  local url=$1
  local name=$2
  echo "⏳ Waiting for $name at $url..."
  until curl -s --fail "$url" >/dev/null; do
    sleep 3
  done
  echo "✅ $name is up!"
}

# API endpoints
SONARR_URL="http://sonarr:8989"
RADARR_URL="http://radarr:7878"
PROWLARR_URL="http://prowlarr:9696"
QBT_URL="http://qbittorrent:8080"

# Wait for services
wait_for "$SONARR_URL" "Sonarr"
wait_for "$RADARR_URL" "Radarr"
wait_for "$PROWLARR_URL" "Prowlarr"
wait_for "$QBT_URL" "qBittorrent"

# Get API keys (optional: fallback to env)
SONARR_API_KEY=${SONARR_API_KEY:-$(curl -s "$SONARR_URL/api/v3/system/status" | jq -r '.apiKey')}
RADARR_API_KEY=${RADARR_API_KEY:-$(curl -s "$RADARR_URL/api/v3/system/status" | jq -r '.apiKey')}
PROWLARR_API_KEY=${PROWLARR_API_KEY:-$(curl -s "$PROWLARR_URL/api/v1/system/status" | jq -r '.apiKey')}

# Add qBittorrent to Sonarr
echo "📡 Configuring Sonarr → qBittorrent..."
curl -s -X POST "$SONARR_URL/api/v3/downloadclient"   -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json"   -d '{
    "enable": true,
    "name": "qBittorrent",
    "protocol": "torrent",
    "implementation": "qBittorrent",
    "configContract": "qBittorrentSettings",
    "fields": [
      { "name": "host", "value": "qbittorrent" },
      { "name": "port", "value": 8080 },
      { "name": "username", "value": "'"$QBT_USER"'" },
      { "name": "password", "value": "'"$QBT_PASS"'" },
      { "name": "category", "value": "sonarr" },
      { "name": "recentTvPriority", "value": 1 },
      { "name": "olderTvPriority", "value": 1 }
    ]
  }'

# Add qBittorrent to Radarr
echo "📡 Configuring Radarr → qBittorrent..."
curl -s -X POST "$RADARR_URL/api/v3/downloadclient"   -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json"   -d '{
    "enable": true,
    "name": "qBittorrent",
    "protocol": "torrent",
    "implementation": "qBittorrent",
    "configContract": "qBittorrentSettings",
    "fields": [
      { "name": "host", "value": "qbittorrent" },
      { "name": "port", "value": 8080 },
      { "name": "username", "value": "'"$QBT_USER"'" },
      { "name": "password", "value": "'"$QBT_PASS"'" },
      { "name": "category", "value": "radarr" }
    ]
  }'

# Add Sonarr & Radarr to Prowlarr
echo "🔗 Linking Sonarr to Prowlarr..."
curl -s -X POST "$PROWLARR_URL/api/v1/applications"   -H "X-Api-Key: $PROWLARR_API_KEY" -H "Content-Type: application/json"   -d '{
    "name": "Sonarr",
    "implementation": "Sonarr",
    "enableRss": true,
    "enableAutomaticSearch": true,
    "enableInteractiveSearch": true,
    "syncLevel": 3,
    "configContract": "SonarrSettings",
    "fields": [
      { "name": "baseUrl", "value": "" },
      { "name": "apiKey", "value": "'"$SONARR_API_KEY"'" },
      { "name": "url", "value": "http://sonarr:8989" }
    ]
  }'

echo "🔗 Linking Radarr to Prowlarr..."
curl -s -X POST "$PROWLARR_URL/api/v1/applications"   -H "X-Api-Key: $PROWLARR_API_KEY" -H "Content-Type: application/json"   -d '{
    "name": "Radarr",
    "implementation": "Radarr",
    "enableRss": true,
    "enableAutomaticSearch": true,
    "enableInteractiveSearch": true,
    "syncLevel": 3,
    "configContract": "RadarrSettings",
    "fields": [
      { "name": "baseUrl", "value": "" },
      { "name": "apiKey", "value": "'"$RADARR_API_KEY"'" },
      { "name": "url", "value": "http://radarr:7878" }
    ]
  }'

echo "✅ All services connected!"
