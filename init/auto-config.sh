#!/bin/bash
set -e

source /.env

# Service URLs
SONARR_URL="http://sonarr:8989"
RADARR_URL="http://radarr:7878"
PROWLARR_URL="http://prowlarr:9696"
QBT_URL="http://qbittorrent:8080"

wait_for() {
  local url=$1
  local name=$2
  echo "⏳ Waiting for $name at $url..."
  until curl -s --fail "$url" >/dev/null; do
    sleep 3
  done
  echo "✅ $name is up!"
}

# Wait for services to be ready
wait_for "$SONARR_URL" "Sonarr"
wait_for "$RADARR_URL" "Radarr"
wait_for "$PROWLARR_URL" "Prowlarr"
wait_for "$QBT_URL" "qBittorrent"

# Validate and show API keys
for SERVICE in SONARR RADARR PROWLARR; do
  VAR_NAME="${SERVICE}_API_KEY"
  VAR_VALUE="${!VAR_NAME}"
  if [ -z "$VAR_VALUE" ]; then
    echo "❌ $VAR_NAME is missing in .env"
    exit 1
  else
    echo "🔑 $VAR_NAME = $VAR_VALUE"
  fi
done

# Configure Sonarr → qBittorrent
echo "📡 Configuring Sonarr → qBittorrent..."
curl -s -X POST "$SONARR_URL/api/v3/downloadclient" \
  -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" \
  -d '{
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
      { "name": "priority", "value": 1 }
    ]
  }'

# Configure Radarr → qBittorrent
echo "📡 Configuring Radarr → qBittorrent..."
curl -s -X POST "$RADARR_URL/api/v3/downloadclient" \
  -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
  -d '{
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
      { "name": "category", "value": "radarr" },
      { "name": "priority", "value": 1 }
    ]
  }'

# Add root folders (ignores errors if they already exist)
echo "📁 Adding root folders..."
curl -s -X POST "$SONARR_URL/api/v3/rootfolder" \
  -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" \
  -d '{ "path": "/tv" }' || echo "⚠️ Sonarr root folder /tv may already exist."

curl -s -X POST "$RADARR_URL/api/v3/rootfolder" \
  -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
  -d '{ "path": "/movies" }' || echo "⚠️ Radarr root folder /movies may already exist."

# Skip quality profiles due to Sonarr API issue
echo "🎞 Skipping quality profile for Sonarr due to known API issues."

# Link Sonarr → Prowlarr
echo "🔗 Linking Sonarr to Prowlarr..."
curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
  -H "X-Api-Key: $PROWLARR_API_KEY" -H "Content-Type: application/json" \
  -d '{
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
  }' || echo "⚠️ Sonarr already linked to Prowlarr."

# Link Radarr → Prowlarr
echo "🔗 Linking Radarr to Prowlarr..."
curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
  -H "X-Api-Key: $PROWLARR_API_KEY" -H "Content-Type: application/json" \
  -d '{
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
  }' || echo "⚠️ Radarr already linked to Prowlarr."

echo "✅ Autoconfig complete!"
