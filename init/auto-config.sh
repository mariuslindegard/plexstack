#!/bin/bash
set -e

source /.env

wait_for() {
  local url=$1
  local name=$2
  echo "⏳ Waiting for $name at $url..."
  until curl -s --fail "$url" >/dev/null; do
    sleep 3
  done
  echo "✅ $name is up!"
}

SONARR_URL="http://sonarr:8989"
RADARR_URL="http://radarr:7878"
PROWLARR_URL="http://prowlarr:9696"
QBT_URL="http://qbittorrent:8080"

wait_for "$SONARR_URL" "Sonarr"
wait_for "$RADARR_URL" "Radarr"
wait_for "$PROWLARR_URL" "Prowlarr"
wait_for "$QBT_URL" "qBittorrent"

# Retrieve API keys if not set
if [ -z "$SONARR_API_KEY" ]; then
  SONARR_API_KEY=$(curl -s "$SONARR_URL/api/v3/system/status" | jq -r '.apiKey')
  echo "🔑 SONARR_API_KEY (not set in .env): $SONARR_API_KEY"
fi
if [ -z "$RADARR_API_KEY" ]; then
  RADARR_API_KEY=$(curl -s "$RADARR_URL/api/v3/system/status" | jq -r '.apiKey')
  echo "🔑 RADARR_API_KEY (not set in .env): $RADARR_API_KEY"
fi
if [ -z "$PROWLARR_API_KEY" ]; then
  PROWLARR_API_KEY=$(curl -s "$PROWLARR_URL/api/v1/system/status" | jq -r '.apiKey')
  echo "🔑 PROWLARR_API_KEY (not set in .env): $PROWLARR_API_KEY"
fi

if [ -z "$SONARR_API_KEY" ] || [ -z "$RADARR_API_KEY" ] || [ -z "$PROWLARR_API_KEY" ]; then
  echo "❌ Please add the above API keys to your .env file and restart the autoconfig container."
  exit 1
fi

# ----------------------
# qBittorrent Integration
# ----------------------
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

# ----------------------
# Root folders
# ----------------------
echo "📁 Adding root folders..."

curl -s -X POST "$SONARR_URL/api/v3/rootfolder" \
  -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" \
  -d '{ "path": "/tv" }'

curl -s -X POST "$RADARR_URL/api/v3/rootfolder" \
  -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
  -d '{ "path": "/movies" }'

# ----------------------
# Skip Sonarr Quality Profile if causing errors
# ----------------------
echo "🎞 Skipping quality profile for Sonarr due to known API issues."

# ----------------------
# Link Sonarr/Radarr to Prowlarr if not already added
# ----------------------
link_app() {
  local appname=$1
  local url=$2
  local apikey=$3
  local config=$4

  if curl -s -H "X-Api-Key: $PROWLARR_API_KEY" "$PROWLARR_URL/api/v1/applications" | jq -e ".[] | select(.name == \"$appname\")" >/dev/null; then
    echo "🔗 $appname already linked to Prowlarr."
  else
    echo "🔗 Linking $appname to Prowlarr..."
    curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
      -H "X-Api-Key: $PROWLARR_API_KEY" -H "Content-Type: application/json" \
      -d '{
        "name": "'"$appname"'",
        "implementation": "'"$appname"'",
        "enableRss": true,
        "enableAutomaticSearch": true,
        "enableInteractiveSearch": true,
        "syncLevel": 3,
        "configContract": "'"$config"'",
        "fields": [
          { "name": "baseUrl", "value": "" },
          { "name": "apiKey", "value": "'"$apikey"'" },
          { "name": "url", "value": "'"$url"'" }
        ]
      }'
  fi
}

link_app "Sonarr" "$SONARR_URL" "$SONARR_API_KEY" "SonarrSettings"
link_app "Radarr" "$RADARR_URL" "$RADARR_API_KEY" "RadarrSettings"

echo "✅ All services connected!"
