#!/bin/bash
set -e

source /.env

# Ensure qBittorrent config folder exists and is owned correctly
echo "📁 Ensuring qBittorrent config directory is ready..."

mkdir -p /config/qbittorrent
chown -R "$PUID:$PGID" /config/qbittorrent

# Wait until config file is created by qBittorrent
until [ -f /config/qbittorrent/qBittorrent/qBittorrent.conf ]; do
  echo "⏳ Waiting for qBittorrent config to be created..."
  sleep 2
done

echo "✅ qBittorrent config file found."

SONARR_URL="http://sonarr:8989"
RADARR_URL="http://radarr:7878"
PROWLARR_URL="http://prowlarr:9696"
QBT_URL="http://qbittorrent:8080"
QBIT_CONFIG="/config/qbittorrent/qBittorrent/qBittorrent.conf"


wait_for() {
  local url=$1
  local name=$2
  echo "⏳ Waiting for $name at $url..."
  until curl -s --fail "$url" >/dev/null; do
    sleep 3
  done
  echo "✅ $name is up!"
}

wait_for "$SONARR_URL" "Sonarr"
wait_for "$RADARR_URL" "Radarr"
wait_for "$PROWLARR_URL" "Prowlarr"
wait_for "$QBT_URL" "qBittorrent"

echo "⚙ Checking qBittorrent credentials..."
echo "⏳ Waiting for qBittorrent config to be created at $QBIT_CONFIG..."
for i in {1..30}; do
  if [ -f "$QBIT_CONFIG" ]; then
    echo "✅ Found qBittorrent config file."
    break
  fi
  sleep 2
  if [ "$i" -eq 30 ]; then
    echo "❌ Timed out waiting for qBittorrent config. Exiting."
    exit 1
  fi

done

echo "🔧 Setting qBittorrent credentials..."
sed -i "s/WebUI\sUsername=.*/WebUI\sUsername=$QBT_USER/" "$QBIT_CONFIG"
sed -i "s/WebUI\sPassword_PBKDF2=.*/WebUI\sPassword_PBKDF2=""/" "$QBIT_CONFIG"
echo "🔁 Restarting qBittorrent to apply credentials..."
curl -X POST "$QBT_URL/api/v2/app/shutdown" >/dev/null 2>&1 || true
sleep 5

# Wait again for qBittorrent
wait_for "$QBT_URL" "qBittorrent"

# Retrieve API keys if not set
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

if [ -z "$SONARR_API_KEY" ] || [ -z "$RADARR_API_KEY" ] || [ -z "$PROWLARR_API_KEY" ]; then
  echo "❌ Missing one or more API keys."
  exit 1
fi

# ----------------------
# Configure download clients
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
      { "name": "recentTvPriority", "value": 1 },
      { "name": "olderTvPriority", "value": 1 }
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
# Link Sonarr/Radarr to Prowlarr
# ----------------------
echo "🔗 Linking Sonarr to Prowlarr..."
curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
  -H "X-Api-Key: $PROWLARR_API_KEY" -H "Content-Type: application/json" \
  -d ' {
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
curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
  -H "X-Api-Key: $PROWLARR_API_KEY" -H "Content-Type: application/json" \
  -d ' {
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
