#!/bin/bash
set -e

# ┌────────────────────────────────────────────────────────────────────────────┐
# │                         Load environment                                   │
# └────────────────────────────────────────────────────────────────────────────┘
ENV_FILE="./.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Cannot find $ENV_FILE"
  exit 1
fi
source "$ENV_FILE"

# Default media dirs inside the containers (override in .env if needed)
TV_DIR=${TV_DIR:-/media/tv}
MOVIES_DIR=${MOVIES_DIR:-/media/movies}

# ┌────────────────────────────────────────────────────────────────────────────┐
# │                         Helper: wait_for                                    │
# └────────────────────────────────────────────────────────────────────────────┘
wait_for() {
  local url=$1; local name=$2
  echo "⏳ Waiting for $name at $url..."
  until curl -s --fail "$url" >/dev/null; do sleep 3; done
  echo "✅ $name is up!"
}

# ┌────────────────────────────────────────────────────────────────────────────┐
# │                            Service URLs                                     │
# └────────────────────────────────────────────────────────────────────────────┘
SONARR_URL="http://sonarr:8989"
RADARR_URL="http://radarr:7878"
PROWLARR_URL="http://prowlarr:9696"
QBT_URL="http://qbittorrent:8080"

# ┌────────────────────────────────────────────────────────────────────────────┐
# │                        Wait for all services                                │
# └────────────────────────────────────────────────────────────────────────────┘
wait_for "$SONARR_URL"   "Sonarr"
wait_for "$RADARR_URL"   "Radarr"
wait_for "$PROWLARR_URL" "Prowlarr"
wait_for "$QBT_URL"      "qBittorrent"


# ┌────────────────────────────────────────────────────────────────────────────┐
# │                      Sonarr → qBittorrent                                  │
# └────────────────────────────────────────────────────────────────────────────┘
echo "📡 Ensuring Sonarr → qBittorrent..."
existing_sonarr=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_URL/api/v3/downloadclient")
if echo "$existing_sonarr" | jq -e '.[] | select(.implementation=="qBittorrent")' >/dev/null; then
  echo "✅ Sonarr already has qBittorrent client"
else
  curl --fail -s -X POST "$SONARR_URL/api/v3/downloadclient" \
    -H "X-Api-Key: $SONARR_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "enable": true,
      "name": "qBittorrent",
      "protocol": "torrent",
      "implementation": "qBittorrent",
      "configContract": "qBittorrentSettings",
      "fields": [
        {"name":"host",    "value":"qbittorrent"},
        {"name":"port",    "value":8080},
        {"name":"username","value":"'"$WEBUI_USERNAME"'"},
        {"name":"password","value":"'"$WEBUI_PASSWORD"'"},
        {"name":"category","value":"sonarr"}
      ]
    }' \
    && echo "✅ Sonarr → qBittorrent configured" \
    || echo "❌ Failed to configure Sonarr → qBittorrent"
fi

# ┌────────────────────────────────────────────────────────────────────────────┐
# │                      Radarr → qBittorrent                                  │
# └────────────────────────────────────────────────────────────────────────────┘
echo "📡 Ensuring Radarr → qBittorrent..."
existing_radarr=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_URL/api/v3/downloadclient")
if echo "$existing_radarr" | jq -e '.[] | select(.implementation=="QBitTorrent")' >/dev/null; then
  echo "✅ Radarr already has qBittorrent client"
else
  # Attempt to add Radarr's qBittorrent client and capture response for debugging
  resp=$(curl -s -X POST "$RADARR_URL/api/v3/downloadclient" \
    -H "X-Api-Key: $RADARR_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "enable": true,
      "name": "qBittorrent",
      "protocol": "torrent",
      "implementation": "QBitTorrent",
      "configContract": "QBitTorrentSettings",
      "priority": 1,
      "fields": [
        {"name":"host",    "value":"qbittorrent"},
        {"name":"port",    "value":8080},
        {"name":"username","value":"'"$WEBUI_USERNAME"'"},
        {"name":"password","value":"'"$WEBUI_PASSWORD"'"},
        {"name":"category","value":"radarr"}
      ]
    }')
  if echo "$resp" | grep -q '"name"'; then
    echo "✅ Radarr → qBittorrent configured"
  else
    echo "❌ Failed to configure Radarr → qBittorrent. Response was:"
    echo "$resp"
  fi
fi

# ┌────────────────────────────────────────────────────────────────────────────┐
# │                         Root folder setup                                   │
# └────────────────────────────────────────────────────────────────────────────┘
echo "📁 Ensuring Sonarr root folder at $TV_DIR..."
curl -s -X POST "$SONARR_URL/api/v3/rootfolder" \
  -H "X-Api-Key: $SONARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"path\":\"$TV_DIR\"}" \
  && echo "✅ Sonarr root folder set: $TV_DIR" \
  || echo "⚠️ Sonarr already has root folder $TV_DIR"

echo "📁 Ensuring Radarr root folder at $MOVIES_DIR..."
curl -s -X POST "$RADARR_URL/api/v3/rootfolder" \
  -H "X-Api-Key: $RADARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"path\":\"$MOVIES_DIR\"}" \
  && echo "✅ Radarr root folder set: $MOVIES_DIR" \
  || echo "⚠️ Radarr already has root folder $MOVIES_DIR"

# ┌────────────────────────────────────────────────────────────────────────────┐
# │                  Skipping Sonarr quality profile                           │
# └────────────────────────────────────────────────────────────────────────────┘
echo "🎞 Skipping Sonarr quality profile (known API issue)."

# ┌────────────────────────────────────────────────────────────────────────────┐
# │                      Prowlarr integrations                                 │
# └────────────────────────────────────────────────────────────────────────────┘
echo "🔗 Linking Sonarr to Prowlarr (Apps sync)..."
curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
  -H "X-Api-Key: $PROWLARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Sonarr",
    "implementation": "Sonarr",
    "enableRss": true,
    "enableAutomaticSearch": true,
    "enableInteractiveSearch": true,
    "syncLevel": "full-sync,
    "configContract": "SonarrSettings",
    "fields": [
      {"name":"baseUrl","value":"http://sonarr:8989"},
      {"name":"apiKey","value":"'"$SONARR_API_KEY"'"},
      {"name":"prowlarrUrl","value":"'"$PROWLARR_URL"'"}
    ]
  }' \
  && echo "✅ Sonarr linked to Prowlarr" \
  || echo "🔗 Sonarr already linked to Prowlarr"

echo "🔗 Linking Radarr to Prowlarr (Apps sync)..."
curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
  -H "X-Api-Key: $PROWLARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Radarr",
    "implementation": "Radarr",
    "enableRss": true,
    "enableAutomaticSearch": true,
    "enableInteractiveSearch": true,
    "syncLevel": "full-sync,
    "configContract": "RadarrSettings",
    "fields": [
      {"name":"baseUrl","value":"http://radarr:7878"},
      {"name":"apiKey","value":"'"$RADARR_API_KEY"'"},
      {"name":"prowlarrUrl","value":"'"$PROWLARR_URL"'"}
    ]
  }' \
  && echo "✅ Radarr linked to Prowlarr" \
  || echo "🔗 Radarr already linked to Prowlarr"

# Add qBittorrent as a download client in Prowlarr
echo "📡 Ensuring Prowlarr → qBittorrent download client..."
existing_prowlarr=$(curl -s -H "X-Api-Key: $PROWLARR_API_KEY" "$PROWLARR_URL/api/v1/downloadclient")
if echo "$existing_prowlarr" | jq -e '.[] | select(.name=="qBittorrent")' >/dev/null; then
  echo "✅ Prowlarr already has qBittorrent client"
else
  resp=$(curl -s -X POST "$PROWLARR_URL/api/v1/downloadclient" \
    -H "X-Api-Key: $PROWLARR_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "enable": true,
      "protocol": "torrent",
      "priority": 1,
      "categories": [],
      "supportsCategories": true,
      "name": "qBittorrent",
      "fields": [
        {"name":"host",          "value":"qbittorrent"},
        {"name":"port",          "value":8080},
        {"name":"useSsl",        "value":false},
        {"name":"urlBase",       "value":""},
        {"name":"username",      "value":"'"$WEBUI_USERNAME"'"},
        {"name":"password",      "value":"'"$WEBUI_PASSWORD"'"},
        {"name":"category",      "value":"prowlarr"},
        {"name":"priority",      "value":0},
        {"name":"initialState",  "value":0},
        {"name":"sequentialOrder","value":false},
        {"name":"firstAndLast",  "value":false},
        {"name":"contentLayout", "value":0}
      ],
      "implementationName": "qBittorrent",
      "implementation": "QBittorrent",
      "configContract": "QBittorrentSettings",
      "infoLink": "https://wiki.servarr.com/prowlarr/supported#qbittorrent",
      "tags": []
    }')
  if echo "$resp" | grep -q '"name"'; then
    echo "✅ Prowlarr → qBittorrent configured"
  else
    echo "❌ Failed to configure Prowlarr → qBittorrent. Response was:"
    echo "$resp"
  fi
fi

echo "✅ Autoconfiguration complete!"
