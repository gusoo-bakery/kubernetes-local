#!/bin/bash
set -e

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== Création du cluster Kubernetes (k3d) ==="
k3d cluster create web-cluster \
  --servers 1 \
  --agents 2 \
  --port "8080:80@loadbalancer" \
  --wait 2>/dev/null || k3d cluster start web-cluster

log "=== Configuration de kubectl ==="
k3d kubeconfig merge web-cluster --switch-context

log "=== Import de l'image locale dans k3d ==="
k3d image import gestion-rh:latest -c web-cluster || true

log "=== Déploiement des manifests k8s ==="
kubectl apply -k /k8s/

log "=== Attente de PostgreSQL ==="
kubectl wait --for=condition=ready --timeout=120s pod -l app=postgresql

log "=== Attente de l'application ==="
kubectl wait --for=condition=available --timeout=120s deployment/gestion-rh
kubectl wait --for=condition=ready --timeout=120s pod -l app=gestion-rh

log "============================================"
log " Cluster prêt !"
log " Application : http://localhost:8080"
log " PostgreSQL  : postgresql:5432 (interne)"
log " Dashboard   : kubectl get all"
log "============================================"

exec tail -f /dev/null
