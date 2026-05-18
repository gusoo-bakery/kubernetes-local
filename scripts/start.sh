#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== Build de l'image Django ==="
docker build -t gestion-rh:latest /Users/augustinpeyridieux/Desktop/projets/gestion-rh

log "=== Démarrage de PostgreSQL et de l'application ==="
docker compose up -d

log "=== Attente de l'application ==="
sleep 5

log "=== Tunnel HTTPS (Serveo - URL fixe) ==="
nohup ssh -i ~/.ssh/serveo_key \
  -o StrictHostKeyChecking=no \
  -o ServerAliveInterval=60 \
  -R gestionpresences:80:localhost:8000 serveo.net \
  &>/tmp/serveo.log &
SERVEO_PID=$!

sleep 5

echo ""
echo "============================================"
echo " Application en ligne !"
echo " URL fixe : https://gestionpresences.serveousercontent.com"
echo " Local     : http://localhost:8000"
echo " Admin     : admin / 0UGtvTgZvSuQQ8ZZeWaF"
echo " Tunnel PID: $SERVEO_PID"
echo "============================================"
