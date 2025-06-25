#!/bin/bash
set -e

# Load environment
ENV_FILE="./.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Cannot find $ENV_FILE"
  exit 1
fi
source "$ENV_FILE"

# Default media dirs inside the containers
TV_DIR=${TV_DIR:-/media/tv}
MOVIES_DIR=${MOVIES_DIR:-/media/movies}

wait_for() {
  local url=$1
  local name=$2
  echo "⏳ Waiting for $name at $url..."
  until curl -s --fail "$url" >/dev/null; do
    sleep 3
  done
  echo "✅ $name is up!"
}

# URLs for each service
SONARR_URL="http://sonarr:8989"
RADARR_URL="http://radarr:7878"
PROWLARR_URL="http://prowlarr:9696"
QBT_URL="http://qbittorrent:8080"

# Wait for all services
wait_for "$SONARR_URL" "Sonarr"
wait_for "$RADARR_URL" "Radarr"
wait_for "$PROWLARR_URL" "Prowlarr"
wait_for "$QBT_URL" "qBittorrent"

# Fetch API keys if not provided
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
      { \"name\": \"host\",     \"value\": \"qbittorrent\" },
      { \"name\": \"port\",     \"value\": 8080 },
      { \"name\": \"username\", \"value\": \"$WEBUI_USERNAME\" },
      { \"name\": \"password\", \"value\": \"$WEBUI_PASSWORD\" },
      { \"name\": \"category\", \"value\": \"sonarr\" }
    ]
  }" \
  && echo "✅ Sonarr → qBittorrent configured" \
  || echo "⚠️ Sonarr already had qBittorrent client"

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
      { \"name\": \"host\",     \"value\": \"qbittorrent\" },
      { \"name\": \"port\",     \"value\": 8080 },
      { \"name\": \"username\", \"value\": \"$WEBUI_USERNAME\" },
      { \"name\": \"password\", \"value\": \"$WEBUI_PASSWORD\" },
      { \"name\": \"category\", \"value\": \"radarr\" },
      { \"name\": \"priority\", \"value\": 1 }
    ]
  }" \
  && echo "✅ Radarr → qBittorrent configured" \
  || echo "⚠️ Radarr already had qBittorrent client"

# ----------------------
# Root folders
# ----------------------
echo "📁 Ensuring Sonarr root folder at $TV_DIR..."
curl -s -X POST "$SONARR_URL/api/v3/rootfolder" \
  -H "X-Api-Key: $SONARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"path\": \"$TV_DIR\"
  }" \
  && echo "✅ Sonarr root folder set: $TV_DIR" \
  || echo "⚠️ Sonarr already has root folder $TV_DIR"

echo "📁 Ensuring Radarr root folder at $MOVIES_DIR..."
curl -s -X POST "$RADARR_URL/api/v3/rootfolder" \
  -H "X-Api-Key: $RADARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"path\": \"$MOVIES_DIR\"
  }" \
  && echo "✅ Radarr root folder set: $MOVIES_DIR" \
  || echo "⚠️ Radarr already has root folder $MOVIES_DIR"

# ----------------------
# Skipping quality profile due to known API issue
# ----------------------
echo "🎞 Skipping Sonarr quality profile (known API issue)."

# ----------------------
# Prowlarr integrations
# ----------------------
echo "🔗 Linking Sonarr to Prowlarr..."
curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
  -H "X-Api-Key: $PROWLARR_API_KEY" \
  -H "Content-Type: application/json" \
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
      { \"name\": \"apiKey\",  \"value\": \"$SONARR_API_KEY\" },
      { \"name\": \"url\",     \"value\": \"$SONARR_URL\" }
    ]
  }" \
  && echo "✅ Sonarr linked to Prowlarr" \
  || echo "🔗 Sonarr already linked to Prowlarr"

echo "🔗 Linking Radarr to Prowlarr..."
curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
  -H "X-Api-Key: $PROWLARR_API_KEY" \
  -H "Content-Type: application/json" \
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
      { \"name\": \"apiKey\",  \"value\": \"$RADARR_API_KEY\" },
      { \"name\": \"url\",     \"value\": \"$RADARR_URL\" }
    ]
  }" \
  && echo "✅ Radarr linked to Prowlarr" \
  || echo "🔗 Radarr already linked to Prowlarr"

echo "✅ Autoconfiguration complete!"
