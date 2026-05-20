#!/bin/bash
set -e

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# Check if cluster already exists
if k3d cluster list 2>/dev/null | grep -q web-cluster; then
  log "=== Cluster existant détecté, skip création ==="
else
  log "=== Création du cluster Kubernetes (k3d) ==="
  k3d cluster create web-cluster \
    --servers 1 \
    --agents 2 \
    --wait

  log "=== Import de l'image locale dans k3d ==="
  k3d image import gestion-rh:latest -c web-cluster || true

  log "=== Déploiement des manifests k8s ==="
  kubectl apply --validate=false -k /k8s/

  log "=== Attente de PostgreSQL ==="
  kubectl wait --for=condition=ready --timeout=120s pod -l app=postgresql

  log "=== Attente du PVC media ==="
  kubectl wait --for=condition=bound --timeout=30s pvc/gestion-rh-media 2>/dev/null || true

  log "=== Attente de l'application ==="
  kubectl wait --for=condition=available --timeout=180s deployment/gestion-rh
  kubectl wait --for=condition=ready --timeout=180s pod -l app=gestion-rh
  kubectl rollout status deployment/gestion-rh --timeout=60s

  log "=== Installation du Dashboard Kubernetes ==="
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
  kubectl wait --for=condition=available --timeout=120s deployment/kubernetes-dashboard -n kubernetes-dashboard

  log "=== Création du token d'accès ==="
  kubectl apply -f - <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: admin-user
    namespace: kubernetes-dashboard
YAML

  sleep 5
  TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user)
  echo "Token Dashboard: $TOKEN" > /tmp/dashboard-token.txt
fi

# Configure kubectl with server node's kubeconfig (avoids port conflicts with k3d kubeconfig merge)
log "=== Configuration kubectl ==="
KUBECONFIG_SRC=""
# Try k3d kubeconfig get first (most reliable from inside Docker)
k3d kubeconfig get web-cluster > /tmp/k3s-kubeconfig 2>/dev/null || true
# Fix server address to use internal Docker hostname
if [ -f /tmp/k3s-kubeconfig ] && [ -s /tmp/k3s-kubeconfig ]; then
  sed -i 's|server: https://0.0.0.0:[0-9]*|server: https://k3d-web-cluster-serverlb:6443|' /tmp/k3s-kubeconfig
  mkdir -p /root/.kube
  cp /tmp/k3s-kubeconfig /root/.kube/config
  log "  kubeconfig depuis k3d (serveur: k3d-web-cluster-serverlb:6443)"
elif k3d kubeconfig merge web-cluster -s &>/dev/null; then
  log "  kubeconfig via merge (fallback)"
else
  log "  WARN: échec récupération kubeconfig"
fi

log "=== Suppression des anciens port-forwards ==="
pkill -f "port-forward" 2>/dev/null || true
sleep 1

log "=== Exposition du Dashboard via port-forward ==="
nohup kubectl port-forward svc/kubernetes-dashboard -n kubernetes-dashboard 9443:443 --address 0.0.0.0 &>/tmp/dashboard-pf.log &

log "=== Exposition de l'application via port-forward ==="
nohup kubectl port-forward svc/gestion-rh 8080:80 --address 0.0.0.0 &>/tmp/port-forward.log &

# Wait for port-forwards to be ready
sleep 2

# Regenerate token if missing
if [ ! -f /tmp/dashboard-token.txt ]; then
  sleep 3
  TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user 2>/dev/null || true)
  [ -n "$TOKEN" ] && echo "Token Dashboard: $TOKEN" > /tmp/dashboard-token.txt
fi

log "============================================"
log " Cluster prêt !"
log " Application : http://localhost:8080"
log " PostgreSQL  : postgresql:5432 (interne)"
log " Dashboard   : https://localhost:9443 (token dans /tmp/dashboard-token.txt)"
log "============================================"

exec tail -f /dev/null
