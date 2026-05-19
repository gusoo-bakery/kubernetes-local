#!/bin/bash
set -e

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== Création du cluster Kubernetes (k3d) ==="
k3d cluster delete web-cluster 2>/dev/null || true
k3d cluster create web-cluster \
  --servers 1 \
  --agents 2 \
  --wait

log "=== Configuration de kubectl ==="
k3d kubeconfig merge web-cluster -s

log "=== Import de l'image locale dans k3d ==="
k3d image import gestion-rh:latest -c web-cluster || true

log "=== Déploiement des manifests k8s ==="
kubectl apply --validate=false -k /k8s/

log "=== Attente de PostgreSQL ==="
kubectl wait --for=condition=ready --timeout=120s pod -l app=postgresql

log "=== Attente de l'application ==="
kubectl wait --for=condition=available --timeout=120s deployment/gestion-rh
kubectl wait --for=condition=ready --timeout=120s pod -l app=gestion-rh

log "=== Exposition de l'application via port-forward ==="
kubectl delete svc gestion-rh 2>/dev/null || true
kubectl expose deployment gestion-rh --type=ClusterIP --port=80 --target-port=8000 --name=gestion-rh
kubectl port-forward svc/gestion-rh 8080:80 --address 0.0.0.0 &>/tmp/port-forward.log &

log "============================================"
log " Cluster prêt !"
log " Application : http://localhost:8080"
log " PostgreSQL  : postgresql:5432 (interne)"
log " Dashboard   : kubectl get all"
log "============================================"

exec tail -f /dev/null
