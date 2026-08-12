#!/usr/bin/env bash
# Diagnose fuer die Naudit-Instanz auf dem VPS. Auf dem Server ausfuehren.
#
#   ./check.sh                       # nur lokale Container-Pruefungen
#   ./check.sh naudit.example.de     # zusaetzlich von aussen pruefen
set -euo pipefail

DOMAIN="${1:-}"

cid=$(docker ps -qf name=naudit | head -1)
if [ -z "$cid" ]; then
  echo "FEHLER: kein laufender Naudit-Container."
  echo "Gestoppte Container:"
  docker ps -a --filter name=naudit --format '  {{.Names}}  {{.Status}}'
  exit 1
fi

echo "== Container =="
docker ps --filter "id=$cid" --format '  {{.Names}}  {{.Status}}'

echo "== Netze =="
# Traefik erreicht den Container nur, wenn beide im dokploy-network haengen.
docker inspect "$cid" --format '  {{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'

echo "== Image =="
# git fehlt im offiziellen Image; ohne git faellt jeder Review auf "nur Diff" zurueck.
docker exec "$cid" git --version 2>/dev/null | sed 's/^/  /' || echo "  WARNUNG: kein git im Image"
docker exec "$cid" id | sed 's/^/  /'

echo "== Health von innen =="
docker exec "$cid" bash -c \
  'exec 3<>/dev/tcp/127.0.0.1/8080
   printf "GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" >&3
   head -1 <&3' | sed 's/^/  /'

echo "== Startup-Report =="
docker logs "$cid" 2>&1 | grep -E "Modus:|Plattform:|AI:|Zugang:" | tail -4 | sed 's/^/  /'

if [ -n "$DOMAIN" ]; then
  echo "== Von aussen =="
  curl -sS -o /dev/null -w '  HTTP %{http_code}  TLS-Pruefung %{ssl_verify_result}\n' \
    "https://$DOMAIN/health"
fi
