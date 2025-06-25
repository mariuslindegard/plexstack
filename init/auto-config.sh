#!/bin/bash
set -e

CONFIG_PATH="/config/qbittorrent/qBittorrent/config/qBittorrent.conf"
QBT_CONTAINER="qbittorrent"

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

# -------- qBittorrent config injection --------
echo "⚙ Checking qBittorrent credentials..."

if [ ! -f "$CONFIG_PATH" ]; then
  echo "⏳ Waiting for qBittorrent config to be created..."
  until [ -f "$CONFIG_PATH" ]; do
    sleep 2
  done
  sleep 2
fi

if ! grep -q "WebUI\\.Password_ha1" "$CONFIG_PATH"; then
  echo "➕ Injecting WebUI credentials into qBittorrent.conf"
  echo "WebUI\\.Username=$QBT_USER" >> "$CONFIG_PATH"
  echo "WebUI\\.Password_ha1=@ByteArray(\"$(echo -n "$QBT_USER:$QBT_PASS" | md5sum | cut -d' ' -f1)\")" >> "$CONFIG_PATH"
  echo "WebUI\\.CSRFProtection=false" >> "$CONFIG_PATH"
  docker restart $QBT_CONTAINER
  wait_for "$QBT_URL" "qBittorrent (post-restart)"
fi

# -------- Get API keys if needed --------
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

# -------- Connect qBittorrent --------
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

# -------- Root folders --------
echo "📁 Ensuring root folders exist..."
curl -s -X POST "$SONARR_URL/api/v3/rootfolder" -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" -d '{ "path": "/tv" }' || true
curl -s -X POST "$RADARR_URL/api/v3/rootfolder" -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" -d '{ "path": "/movies" }' || true

# -------- Prowlarr Integration --------
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
      { "name": "apiKey", "value": "'"$SONARR_API_KEY"'" },
      { "name": "url", "value": "http://sonarr:8989" }
    ]
  }' || true

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
      { "name": "apiKey", "value": "'"$RADARR_API_KEY"'" },
      { "name": "url", "value": "http://radarr:7878" }
    ]
  }' || true

echo "✅ All services connected and configured!"
