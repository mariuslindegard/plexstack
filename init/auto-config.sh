#!/bin/bash
set -e

echo "🔧 Starting autoconfig..."
source "/.env"

# Wait helper
await() { local url=$1 name=$2; echo "⏳ Waiting for $name ($url)..."; until curl -s --fail "$url" >/dev/null; do sleep 3; done; echo "✅ $name is up!"; }

# Endpoints
SONARR="http://sonarr:8989"
RADARR="http://radarr:7878"
PROWLARR="http://prowlarr:9696"
QBITTORRENT="http://qbittorrent:8080"
await "$SONARR" Sonarr
await "$RADARR" Radarr
await "$PROWLARR" Prowlarr
await "$QBITTORRENT" qBittorrent

echo
QBT_USER="${QBT_USER:-admin}"
QBT_PASS="${QBT_PASS:-adminadmin}"

# Upsert Sonarr/Radarr download client
upsert_client() {
  local base_url=$1 api_key=$2 name=$3 category=$4
  echo "📡 $name → qBittorrent"
  local endpoint="$base_url/api/v3/downloadclient"
  local existing_id=$(curl -s -H "X-Api-Key: $api_key" "$endpoint" | jq -r ".[] | select(.name==\"$name\") | .id")

  # Prepare payload
  local payload=$(cat <<EOF
{
  "enable": true,
  "name": "$name",
  "protocol": "torrent",
  "implementation": "qBittorrent",
  "configContract": "qBittorrentSettings",
  "fields": [
    {"name":"host","value":"qbittorrent"},
    {"name":"port","value":8080},
    {"name":"username","value":"$QBT_USER"},
    {"name":"password","value":"$QBT_PASS"},
    {"name":"category","value":"$category"},
    {"name":"priority","value":1}
  ]
}
EOF
)

  if [[ -n "$existing_id" && "$existing_id" != "null" ]]; then
    echo "🔄 Updating $name client (ID=$existing_id)..."
    curl -s -X PUT "$endpoint/$existing_id" -H "X-Api-Key: $api_key" -H "Content-Type: application/json" -d "$payload"
  else
    echo "➕ Creating $name client..."
    curl -s -X POST "$endpoint" -H "X-Api-Key: $api_key" -H "Content-Type: application/json" -d "$payload"
  fi
}

# Upsert Prowlarr application link
upsert_app() {
  local api_key=$1 app_name=$2 impl=$3 url_val=$4
  echo "🔗 $app_name ↔ Prowlarr"
  local endpoint="${PROWLARR}/api/v1/applications"
  local existing_id=$(curl -s -H "X-Api-Key: $api_key" "$endpoint" | jq -r ".[] | select(.name==\"$app_name\") | .id")

  local data=$(cat <<EOF
{
  "name": "$app_name",
  "implementation": "$impl",
  "enableRss": true,
  "enableAutomaticSearch": true,
  "enableInteractiveSearch": true,
  "syncLevel": 3,
  "configContract": "${impl}Settings",
  "fields": [
    {"name":"baseUrl","value":""},
    {"name":"apiKey","value":"\${${app_name^^}_API_KEY}"},
    {"name":"url","value":"$url_val"}
  ]
}
EOF
)

  if [[ -n "$existing_id" && "$existing_id" != "null" ]]; then
    echo "🔄 Updating Prowlarr for $app_name (ID=$existing_id)..."
    curl -s -X PUT "$endpoint/$existing_id" -H "X-Api-Key: $api_key" -H "Content-Type: application/json" -d "$data"
  else
    echo "➕ Linking $app_name in Prowlarr..."
    curl -s -X POST "$endpoint" -H "X-Api-Key: $api_key" -H "Content-Type: application/json" -d "$data"
  fi
}

# Execute upserts
echo "-- Configuring Download Clients --"
upsert_client "$SONARR" "$SONARR_API_KEY" "qBittorrent" "sonarr"
upsert_client "$RADARR" "$RADARR_API_KEY" "qBittorrent" "radarr"

echo "-- Configuring Prowlarr Links --"
upsert_app "$PROWLARR_API_KEY" "Sonarr" "Sonarr" "$SONARR"
upsert_app "$PROWLARR_API_KEY" "Radarr" "Radarr" "$RADARR"

echo "✅ Autoconfig complete."
