#!/bin/bash
set -e

echo "🔧 Starting autoconfig..."
source "/.env"

# Helper: wait until service is ready
await() { local url=$1 name=$2; echo "⏳ Waiting for $name ($url)..."; until curl -s --fail "$url" >/dev/null; do sleep 3; done; echo "✅ $name is up!"; }

SONARR="http://sonarr:8989"
RADARR="http://radarr:7878"
PROWLARR="http://prowlarr:9696"
QB="http://qbittorrent:8080"
await "$SONARR" Sonarr
await "$RADARR" Radarr
await "$PROWLARR" Prowlarr
await "$QB" qBittorrent

echo
QBT_USER="${QBT_USER:-admin}"
QBT_PASS="${QBT_PASS:-adminadmin}"

# Manage download client: delete existing then create new
manage_client() {
  local base=$1 api_key=$2 name=$3 category=$4
  local url="$base/api/v3/downloadclient"
  echo "📡 Ensuring $name client (delete old then create new)..."
  local id=$(curl -s -H "X-Api-Key: $api_key" "$url" | jq -r ".[] | select(.name==\"$name\") | .id")
  if [[ -n "$id" && "$id" != "null" ]]; then
    curl -s -X DELETE "$url/$id" -H "X-Api-Key: $api_key"
    echo "🗑 Deleted existing client (ID=$id)."
  fi
  # Create new
  curl -s -X POST "$url" -H "X-Api-Key: $api_key" -H "Content-Type: application/json" -d '{
    "enable": true,
    "name": "'"$name"'",
    "protocol": "torrent",
    "implementation": "qBittorrent",
    "configContract": "qBittorrentSettings",
    "fields": [
      {"name":"host","value":"qbittorrent"},
      {"name":"port","value":8080},
      {"name":"username","value":"'"$QBT_USER"'"},
      {"name":"password","value":"'"$QBT_PASS"'"},
      {"name":"category","value":"'"$category"'"},
      {"name":"priority","value":1}
    ]
  }'
  echo "✅ Created $name client with priority=1."
}

# Manage Prowlarr app link: delete existing then create
manage_app() {
  local api_key=$1 app=$2 impl=$3 urlval=$4
  local endpoint="${PROWLARR}/api/v1/applications"
  echo "🔗 Ensuring Prowlarr link for $app..."
  local id=$(curl -s -H "X-Api-Key: $api_key" "$endpoint" | jq -r ".[] | select(.name==\"$app\") | .id")
  if [[ -n "$id" && "$id" != "null" ]]; then
    curl -s -X DELETE "$endpoint/$id" -H "X-Api-Key: $api_key"
    echo "🗑 Deleted existing Prowlarr link (ID=$id)."
  fi
  curl -s -X POST "$endpoint" -H "X-Api-Key: $api_key" -H "Content-Type: application/json" -d '{
    "name": "'"$app"'",
    "implementation": "'"$impl"'",
    "enableRss": true,
    "enableAutomaticSearch": true,
    "enableInteractiveSearch": true,
    "syncLevel": 3,
    "configContract": "'"$impl"'Settings",
    "fields": [
      {"name":"baseUrl","value":""},
      {"name":"apiKey","value":"'"${!api_key}"'"},
      {"name":"url","value":"'"$urlval"'"}
    ]
  }'
  echo "✅ Linked $app in Prowlarr."
}

# Execute
manage_client "$SONARR" "$SONARR_API_KEY" "qBittorrent" "sonarr"
manage_client "$RADARR" "$RADARR_API_KEY" "qBittorrent" "radarr"
manage_app "${PROWLARR_API_KEY}" "Sonarr" "Sonarr" "$SONARR"
manage_app "${PROWLARR_API_KEY}" "Radarr" "Radarr" "$RADARR"

echo "✅ Autoconfig complete."
