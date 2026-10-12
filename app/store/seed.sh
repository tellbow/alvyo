#!/usr/bin/env bash
# Makes the local account the App Store pictures show: «storeshots» with
# copies of official routes and a multi-day tour (Wanderland Schweiz, from
# the data import). Needs the dev stack, the API and the web dev server.
# Runs again without harm.
set -euo pipefail

web=http://localhost:5173
jar=$(mktemp)
trap 'rm -f "$jar"' EXIT
post() { curl -sf -b "$jar" -c "$jar" -H "Origin: $web" -H 'Content-Type: application/json' "$web/api/v1$1" -d "${2:-{\}}"; }
sql() { docker exec alvyo-db-1 psql -U alvyo -d alvyo -At -c "$1"; }

if ! post /auth/login '{"login":"storeshots","password":"store-shots-2026"}' >/dev/null; then
  post /auth/signup '{"email":"storeshots@example.ch","username":"storeshots","display_name":"Lena","password":"store-shots-2026","locale":"de"}' >/dev/null
  sleep 2 # the confirmation e-mail, in Mailpit
  id=$(curl -sf 'http://localhost:8025/api/v1/search?query=to:storeshots@example.ch' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["messages"][0]["ID"])')
  token=$(curl -sf "http://localhost:8025/api/v1/message/$id" | python3 -I -c 'import json,re,sys;print(re.search(r"token=([A-Za-z0-9_-]+)",json.load(sys.stdin)["Text"]).group(1))')
  post /auth/verify-email "{\"token\":\"$token\"}" >/dev/null
fi

# Copies what the account does not have yet, by title.
copy() { # kind (routes|journeys), title
  local have
  have=$(sql "select count(*) from $1 t join users u on u.id = t.owner_id where u.username = 'storeshots' and t.title = '$2'")
  [ "$have" != 0 ] && return
  local id
  id=$(sql "select t.id from $1 t join users u on u.id = t.owner_id where u.username = 'wanderland' and t.visibility = 'public' and t.title = '$2' limit 1")
  post "/$1/$id/copy" >/dev/null
  echo "copied $2"
}
copy routes 'Eiger Trail'
copy routes '5-Seenweg Zermatt'
copy journeys 'Aletsch Panoramaweg'
