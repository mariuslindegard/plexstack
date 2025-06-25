#!/bin/bash
set -e

echo "🔧 Starting autoconfig..."

# Load environment variables including QBT_USER and QBT_PASS
# Ensure .env is mounted read-write if you want to auto-update it
# Otherwise, export env vars beforehand
source "/.env"

# Helper: wait until a service is reachable
wait_for() {
  local url=$1
  local name=$2
  echo "⏳ Waiting for $name at $url..."
  until curl -s --fail "$url" >/dev/null; do
    sleep 3
  done
  echo "✅ $name is up!"
}

# Service URLs
SONARR_URL="http://sonarr:8989"
RADARR_URL="http://radarr:7878"
PROWLARR_URL="http://prowlarr:9696"
QBITTORRENT_URL="http://qbittorrent:8080"

# Wait for all services
wait_for "$SONARR_URL" "Sonarr"
wait_for "$RADARR_URL" "Radarr"
wait_for "$PROWLARR_URL" "Prowlarr"
wait_for "$QBITTORRENT_URL" "qBittorrent"

# Retrieve API keys (echo to user)
echo "🔑 Sonarr API Key:" 
curl -s "$SONARR_URL/api/v3/system/status" | jq -r '.apiKey'
echo "🔑 Radarr API Key:" 
curl -s "$RADARR_URL/api/v3/system/status" | jq -r '.apiKey'
echo "🔑 Prowlarr API Key:" 
curl -s "$PROWLARR_URL/api/v1/system/status" | jq -r '.apiKey'

echo
# Default qBittorrent credentials
QBT_USER=${QBT_USER:-admin}
QBT_PASS=${QBT_PASS:-adminadmin}

echo "📡 Configuring Sonarr → qBittorrent..."
curl -s -X POST "$SONARR_URL/api/v3/downloadclient" \
  -H "X-Api-Key: $SONARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"enable\":true,\"name\":\"qBittorrent\",\"protocol\":\"torrent\",\"implementation\":\"qBittorrent\",\"configContract\":\"qBittorrentSettings\",\"fields\":[{\"name\":\"host\",\"value\":\"qbittorrent\"},{\"name\":\"port\",\"value\":8080},{\"name\":\"username\",\"value\":\"$QBT_USER\"},{\"name\":\"password\",\"value\":\"$QBT_PASS\"},{\"name\":\"category\",\"value\":\"sonarr\"},{\"name\":\"priority\",\"value\":1}]}"

echo "📡 Configuring Radarr → qBittorrent..."
curl -s -X POST "$RADARR_URL/api/v3/downloadclient" \
  -H "X-Api-Key: $RADARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"enable\":true,\"name\":\"qBittorrent\",\"protocol\":\"torrent\",\"implementation\":\"qBittorrent\",\"configContract\":\"qBittorrentSettings\",\"fields\":[{\"name\":\"host\",\"value\":\"qbittorrent\"},{\"name\":\"port\",\"value\":8080},{\"name\":\"username\",\"value\":\"$QBT_USER\"},{\"name\":\"password\",\"value\":\"$QBT_PASS\"},{\"name\":\"category\",\"value\":\"radarr\"},{\"name\":\"priority\",\"value\":1}]}"

echo "🔗 Linking Sonarr to Prowlarr..."
curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
  -H "X-Api-Key: $PROWLARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"Sonarr\",\"implementation\":\"Sonarr\",\"enableRss\":true,\"enableAutomaticSearch\":true,\"enableInteractiveSearch\":true,\"syncLevel\":3,\"configContract\":\"SonarrSettings\",\"fields\":[{\"name\":\"baseUrl\",\"value\":\"\"},{\"name\":\"apiKey\",\"value\":\"$SONARR_API_KEY\"},{\"name\":\"url\",\"value\":\"http://sonarr:8989\"}]}"

echo "🔗 Linking Radarr to Prowlarr..."
curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
  -H "X-Api-Key: $PROWLARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"Radarr\",\"implementation\":\"Radarr\",\"enableRss\":true,\"enableAutomaticSearch\":true,\"enableInteractiveSearch\":true,\"syncLevel\":3,\"configContract\":\"RadarrSettings\",\"fields\":[{\"name\":\"baseUrl\",\"value\":\"\"},{\"name\":\"apiKey\",\"value\":\"$RADARR_API_KEY\"},{\"name\":\"url\",\"value\":\"http://radarr:7878\"}]}"

echo "✅ Autoconfig completed. Please verify the above API keys and update your .env if needed."
