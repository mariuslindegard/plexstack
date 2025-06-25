#!/bin/bash
set -e

echo "🔧 Starting autoconfig..."

ENV_FILE="/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ .env file not found. Make sure it's mounted correctly."
  exit 1
fi

source "$ENV_FILE"

# Wait until services are reachable
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

# Fetch and write API keys if needed
update_env_if_missing() {
  local key=$1
  local value=$2
  if ! grep -q "^$key=" "$ENV_FILE"; then
    echo "$key=$value" >> "$ENV_FILE"
    echo "💾 Appended $key to .env"
  fi
}

if [ -z "$SONARR_API_KEY" ]; then
  SONARR_API_KEY=$(curl -s "$SONARR_URL/api/v3/system/status" | jq -r '.apiKey')
  echo "🔑 SONARR_API_KEY=$SONARR_API_KEY"
  update_env_if_missing "SONARR_API_KEY" "$SONARR_API_KEY"
fi

if [ -z "$RADARR_API_KEY" ]; then
  RADARR_API_KEY=$(curl -s "$RADARR_URL/api/v3/system/status" | jq -r '.apiKey')
  echo "🔑 RADARR_API_KEY=$RADARR_API_KEY"
  update_env_if_missing "RADARR_API_KEY" "$RADARR_API_KEY"
fi

if [ -z "$PROWLARR_API_KEY" ]; then
  PROWLARR_API_KEY=$(curl -s "$PROWLARR_URL/api/v1/system/status" | jq -r '.apiKey')
  echo "🔑 PROWLARR_API_KEY=$PROWLARR_API_KEY"
  update_env_if_missing "PROWLARR_API_KEY" "$PROWLARR_API_KEY"
fi

# Link Sonarr/Radarr to qBittorrent (assumes user has set credentials manually)
echo "📡 Configuring Sonarr → qBittorrent..."
curl -s -X POST "$SONARR_URL/api/v3/downloadclient" \
  -H "X-Api-Key: $SONARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"enable\": true,
    \"name\": \"qBittorrent\",
    \"protocol\": \"torrent\",
    \"implementation\": \"qBittorrent\",
    \"configContract\": \"qBittorrentSettings\",
    \"fields\": [
      { \"name\": \"host\", \"value\": \"qbittorrent\" },
      { \"name\": \"port\", \"value\": 8080 },
      { \"name\": \"username\", \"value\": \"${QBT_USER:-admin}\" },
      { \"name\": \"password\", \"value\": \"${QBT_PASS:-adminadmin}\" },
      { \"name\": \"category\", \"value\": \"sonarr\" },
      { \"name\": \"priority\", \"value\": 1 }
    ]
  }"

echo "📡 Configuring Radarr → qBittorrent..."
curl -s -X POST "$RADARR_URL/api/v3/downloadclient" \
  -H "X-Api-Key: $RADARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"enable\": true,
    \"name\": \"qBittorrent\",
    \"protocol\": \"torrent\",
    \"implementation\": \"qBittorrent\",
    \"configContract\": \"qBittorrentSettings\",
    \"fields\": [
      { \"name\": \"host\", \"value\": \"qbittorrent\" },
      { \"name\": \"port\", \"value\": 8080 },
      { \"name\": \"username\", \"value\": \"${QBT_USER:-admin}\" },
      { \"name\": \"password\", \"value\": \"${QBT_PASS:-adminadmin}\" },
      { \"name\": \"category\", \"value\": \"radarr\" },
      { \"name\": \"priority\", \"value\": 1 }
    ]
  }"

# Add root folders
echo "📁 Adding root folders..."
curl -s -X POST "$SONARR_URL/api/v3/rootfolder" \
  -H "X-Api-Key: $SONARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "path": "/tv" }'

curl -s -X POST "$RADARR_URL/api/v3/rootfolder" \
  -H "X-Api-Key: $RADARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "path": "/movies" }'

# Link to Prowlarr
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
      { \"name\": \"apiKey\", \"value\": \"$SONARR_API_KEY\" },
      { \"name\": \"url\", \"value\": \"http://sonarr:8989\" }
    ]
  }"

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
      { \"name\": \"apiKey\", \"value\": \"$RADARR_API_KEY\" },
      { \"name\": \"url\", \"value\": \"http://radarr:7878\" }
    ]
  }"

echo "✅ Autoconfig completed successfully."
echo "📋 If any API keys were added to .env, please restart the stack to apply changes."
