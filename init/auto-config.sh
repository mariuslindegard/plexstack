#!/bin/bash
set -e

ENV_FILE="./.env"
source "$ENV_FILE"

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

# Automatically get API keys if not set
if [ -z "$SONARR_API_KEY" ]; then
  SONARR_API_KEY=$(curl -s "$SONARR_URL/api/v3/system/status" | jq -r '.apiKey')
  echo "🔑 SONARR_API_KEY: $SONARR_API_KEY"
fi

if [ -z "$RADARR_API_KEY" ]; then
  RADARR_API_KEY=$(curl -s "$RADARR_URL/api/v3/system/status" | jq -r '.apiKey')
  echo "🔑 RADARR_API_KEY: $RADARR_API_KEY"
fi

if [ -z "$PROWLARR_API_KEY" ]; then
  PROWLARR_API_KEY=$(curl -s "$PROWLARR_URL/api/v1/system/status" | jq -r '.apiKey')
  echo "🔑 PROWLARR_API_KEY: $PROWLARR_API_KEY"
fi

# ----------------------
# qBittorrent Integration
# ----------------------
echo "📡 Configuring Sonarr → qBittorrent..."
curl -s -X POST "$SONARR_URL/api/v3/downloadclient" \
  -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" \
  -d "{
    \"enable\": true,
    \"name\": \"qBittorrent\",
    \"protocol\": \"torrent\",
    \"implementation\": \"qBittorrent\",
    \"configContract\": \"qBittorrentSettings\",
    \"fields\": [
      { \"name\": \"host\", \"value\": \"qbittorrent\" },
      { \"name\": \"port\", \"value\": 8080 },
      { \"name\": \"username\", \"value\": \"$WEBUI_USERNAME\" },
      { \"name\": \"password\", \"value\": \"$WEBUI_PASSWORD\" },
      { \"name\": \"category\", \"value\": \"sonarr\" }
    ]
  }"

echo "📡 Configuring Radarr → qBittorrent..."
curl -s -X POST "$RADARR_URL/api/v3/downloadclient" \
  -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
  -d "{
    \"enable\": true,
    \"name\": \"qBittorrent\",
    \"protocol\": \"torrent\",
    \"implementation\": \"qBittorrent\",
    \"configContract\": \"qBittorrentSettings\",
    \"fields\": [
      { \"name\": \"host\", \"value\": \"qbittorrent\" },
      { \"name\": \"port\", \"value\": 8080 },
      { \"name\": \"username\", \"value\": \"$WEBUI_USERNAME\" },
      { \"name\": \"password\", \"value\": \"$WEBUI_PASSWORD\" },
      { \"name\": \"category\", \"value\": \"radarr\" },
      { \"name\": \"priority\", \"value\": 1 }
    ]
  }"

# ----------------------
# Root folders
# ----------------------
echo "📁 Ensuring root folders..."
curl -s -X POST "$SONARR_URL/api/v3/rootfolder" \
  -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" \
  -d "{
    \"path\": \"$TV_DIR\"
  }" || echo "📁 /tv already exists"

curl -s -X POST "$RADARR_URL/api/v3/rootfolder" \
  -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" \
  -d "{
    \"path\": \"$MOVIES_DIR\"
  }" || echo "📁 /movies already exists"

# ----------------------
# Skipping quality profile due to known API issue
# ----------------------
echo "🎞 Skipping quality profile for Sonarr due to known API issues."

# ----------------------
# Prowlarr integrations
# ----------------------
echo "🔗 Linking Sonarr to Prowlarr..."
curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
  -H "X-Api-Key: $PROWLARR_API_KEY" -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Sonarr\",
    \"implementation\": \"Sonarr\",
    \"enableRss\": true,
    \"enableAutomaticSearch\": true,
    \"enableInteractiveSearch\": true,
    \"syncLevel\": 3,
    \"configContract\": \"SonarrSettings\",
    \"fields\": [
      { \"name\": \"baseUrl\", \"value\": \"\" },
      { \"name\": \"apiKey\", \"value\": \"$SONARR_API_KEY\" },
      { \"name\": \"url\", \"value\": \"$SONARR_URL\" }
    ]
  }" || echo "🔗 Sonarr already linked"

echo "🔗 Linking Radarr to Prowlarr..."
curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
  -H "X-Api-Key: $PROWLARR_API_KEY" -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Radarr\",
    \"implementation\": \"Radarr\",
    \"enableRss\": true,
    \"enableAutomaticSearch\": true,
    \"enableInteractiveSearch\": true,
    \"syncLevel\": 3,
    \"configContract\": \"RadarrSettings\",
    \"fields\": [
      { \"name\": \"baseUrl\", \"value\": \"\" },
      { \"name\": \"apiKey\", \"value\": \"$RADARR_API_KEY\" },
      { \"name\": \"url\", \"value\": \"$RADARR_URL\" }
    ]
  }" || echo "🔗 Radarr already linked"

echo "✅ Autoconfiguration complete!"
