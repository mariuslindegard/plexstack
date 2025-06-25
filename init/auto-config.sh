#!/bin/bash
set -e

echo "🔧 Starting autoconfig..."
source "/.env"

# Helper: wait until a service is reachable
await() { local url=$1 name=$2; echo "⏳ Waiting for $name..."; until curl -s --fail "$url" >/dev/null; do sleep 3; done; echo "✅ $name is up!"; }

SONARR="http://sonarr:8989"
RADARR="http://radarr:7878"
PROWLARR="http://prowlarr:9696"
QBIT="http://qbittorrent:8080"
await "$SONARR" Sonarr
await "$RADARR" Radarr
await "$PROWLARR" Prowlarr
await "$QBIT" qBittorrent

echo
QBT_USER="${QBT_USER:-admin}"
QBT_PASS="${QBT_PASS:-adminadmin}"

# Function to upsert Sonarr/Radarr download client
upsert_client() {
  local base=$1 api_key=$2 client_name=$3 category=$4
  local url="$base/api/v3/downloadclient"
  # fetch existing
  local existing_id=$(curl -s -H "X-Api-Key: $api_key" "$url" | jq -r ".[] | select(.name==\"$client_name\") | .id")
  # payload
  read -r -d '' payload <<EOF
{
  "enable": true,
  "name": "$client_name",
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
  if [[ -n "$existing_id" ]]; then
    echo "🔄 Updating $client_name client (ID $existing_id)..."
    curl -s -X PUT "$url/$existing_id" -H "X-Api-Key: $api_key" -H "Content-Type: application/json" -d "$payload"
  else
    echo "➕ Creating $client_name client..."
    curl -s -X POST "$url" -H "X-Api-Key: $api_key" -H "Content-Type: application/json" -d "$payload"
  fi
}

# Upsert Sonarr & Radarr clients
echo "📡 Sonarr → qBittorrent"
upsert_client "$SONARR" "$SONARR_API_KEY" qBittorrent sonarr
echo "📡 Radarr → qBittorrent"
upsert_client "$RADARR" "$RADARR_API_KEY" qBittorrent radarr

# Function to upsert Prowlarr application link
upsert_app() {
  local base=$1 api_key=$2 name=$3 impl=$4 url_field=$5
  local endpoint="$base/api/v1/applications"
  local id=$(curl -s -H "X-Api-Key: $api_key" "$endpoint" | jq -r ".[] | select(.name==\"$name\") | .id")
  read -r -d '' data <<EOF
{
  "name": "$name",
  "implementation": "$impl",
  "enableRss": true,
  "enableAutomaticSearch": true,
  "enableInteractiveSearch": true,
  "syncLevel": 3,
  "configContract": "${impl}Settings",
  "fields": [
    {"name":"baseUrl","value":""},
    {"name":"apiKey","value":"${!api_key}"},
    {"name":"url","value":"$url_field"}
  ]
}
EOF
  if [[ -n "$id" ]]; then
    echo "🔄 Updating Prowlarr link for $name (ID $id)..."
    curl -s -X PUT "$endpoint/$id" -H "X-Api-Key: $api_key" -H "Content-Type: application/json" -d "$data"
  else
    echo "➕ Linking $name in Prowlarr"
    curl -s -X POST "$endpoint" -H "X-Api-Key: $api_key" -H "Content-Type: application/json" -d "$data"
  fi
}

echo "🔗 Sonarr ↔ Prowlarr"
upsert_app "$PROWLARR" PROWLARR_API_KEY Sonarr Sonarr http://sonarr:8989

echo "🔗 Radarr ↔ Prowlarr"
upsert_app "$PROWLARR" PROWLARR_API_KEY Radarr Radarr http://radarr:7878

echo "✅ Autoconfig complete."
