# init/auto-config.sh
#!/bin/bash
set -e

ENV_FILE="./.env"
[ -f "$ENV_FILE" ] || { echo "❌ $ENV_FILE not found"; exit 1; }
source "$ENV_FILE"

TV_DIR=${TV_DIR:-/media/tv}
MOVIES_DIR=${MOVIES_DIR:-/media/movies}

wait_for() {
  local url=$1 name=$2
  echo "⏳ Waiting for $name at $url..."
  until curl -s --fail "$url" >/dev/null; do sleep 3; done
  echo "✅ $name is up!"
}

SONARR_URL="http://sonarr:8989"
RADARR_URL="http://radarr:7878"
PROWLARR_URL="http://prowlarr:9696"
QBT_URL="http://qbittorrent:8080"

wait_for "$SONARR_URL"   "Sonarr"
wait_for "$RADARR_URL"   "Radarr"
wait_for "$PROWLARR_URL" "Prowlarr"
wait_for "$QBT_URL"      "qBittorrent"

[ -z "$SONARR_API_KEY" ]   && SONARR_API_KEY=$(curl -s "$SONARR_URL/api/v3/system/status"   | jq -r .apiKey)
[ -z "$RADARR_API_KEY" ]   && RADARR_API_KEY=$(curl -s "$RADARR_URL/api/v3/system/status"   | jq -r .apiKey)
[ -z "$PROWLARR_API_KEY" ] && PROWLARR_API_KEY=$(curl -s "$PROWLARR_URL/api/v1/system/status" | jq -r .apiKey)

echo "🔑 SONARR_API_KEY=$SONARR_API_KEY"
echo "🔑 RADARR_API_KEY=$RADARR_API_KEY"
echo "🔑 PROWLARR_API_KEY=$PROWLARR_API_KEY"

add_qbt_client() {
  local url=$1 key=$2 impl=$3 category=$4
  echo "📡 Ensuring $impl on $url..."
  local existing resp
  existing=$(curl -s -H "X-Api-Key: $key" "$url/api/v3/downloadclient")
  if echo "$existing" | jq -e ".[] | select(.implementation==\"$impl\")" >/dev/null; then
    echo "✅ $impl already configured"
  else
    resp=$(curl -s -X POST "$url/api/v3/downloadclient" \
      -H "X-Api-Key: $key" \
      -H "Content-Type: application/json" \
      -d '{
        "enable": true,
        "name": "qBittorrent",
        "protocol": "torrent",
        "implementation": "'"$impl"'",
        "configContract": "'"$impl"'Settings",
        "priority": 1,
        "fields":[
          {"name":"host","value":"qbittorrent"},
          {"name":"port","value":8080},
          {"name":"username","value":"'"$WEBUI_USERNAME"'"},
          {"name":"password","value":"'"$WEBUI_PASSWORD"'"},
          {"name":"category","value":"'"$category"'"}
        ]
      }')
    if echo "$resp" | jq -e '.name' >/dev/null; then
      echo "✅ $impl configured"
    else
      echo "❌ Failed to configure $impl. Response:"
      echo "$resp"
    fi
  fi
}

add_qbt_client "$SONARR_URL" "$SONARR_API_KEY" "qBittorrent" "sonarr"
add_qbt_client "$RADARR_URL" "$RADARR_API_KEY" "QBitTorrent" "radarr"

echo "📁 Ensuring Sonarr root folder at $TV_DIR..."
resp=$(curl -s -X POST "$SONARR_URL/api/v3/rootfolder" \
  -H "X-Api-Key: $SONARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"path\":\"$TV_DIR\"}")
if echo "$resp" | jq -e '.[] | select(.errorCode=="FolderWritableValidator")' >/dev/null; then
  echo "❌ Sonarr cannot write to $TV_DIR—check mount & permissions"
else
  echo "✅ Sonarr root folder OK"
fi

echo "📁 Ensuring Radarr root folder at $MOVIES_DIR..."
resp=$(curl -s -X POST "$RADARR_URL/api/v3/rootfolder" \
  -H "X-Api-Key: $RADARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"path\":\"$MOVIES_DIR\"}")
if echo "$resp" | jq -e '.[] | select(.errorCode=="FolderWritableValidator")' >/dev/null; then
  echo "❌ Radarr cannot write to $MOVIES_DIR—check mount & permissions"
else
  echo "✅ Radarr root folder OK"
fi

echo "🎞 Skipping Sonarr quality profile (known API issue)."

link_app() {
  local name=$1 url=$2 key=$3 impl=$4
  echo "🔗 Linking $name to Prowlarr..."
  local resp
  resp=$(curl -s -X POST "$PROWLARR_URL/api/v1/applications" \
    -H "X-Api-Key: $PROWLARR_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "name":"'"$name"'",
      "implementation":"'"$impl"'",
      "enableRss":true,
      "enableAutomaticSearch":true,
      "enableInteractiveSearch":true,
      "syncLevel":3,
      "configContract":"'"$impl"'Settings",
      "fields":[
        {"name":"baseUrl","value":""},
        {"name":"apiKey","value":"'"$key"'"},
        {"name":"url","value":"'"$url"'"}
      ]
    }')
  if echo "$resp" | jq -e '.id' >/dev/null; then
    echo "✅ $name linked to Prowlarr"
  else
    echo "🔗 $name already linked or error:"
    echo "$resp"
  fi
}

link_app "Sonarr" "$SONARR_URL" "$SONARR_API_KEY" "Sonarr"
link_app "Radarr" "$RADARR_URL" "$RADARR_API_KEY" "Radarr"

echo "✅ Autoconfiguration complete!"
