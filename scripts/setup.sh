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

log "=== Exposition du Dashboard via port-forward ==="
kubectl port-forward svc/kubernetes-dashboard -n kubernetes-dashboard 9443:443 --address 0.0.0.0 &>/tmp/dashboard-pf.log &

log "=== Exposition de l'application via port-forward ==="
kubectl delete svc gestion-rh 2>/dev/null || true
kubectl expose deployment gestion-rh --type=ClusterIP --port=80 --target-port=8000 --name=gestion-rh
kubectl port-forward svc/gestion-rh 8080:80 --address 0.0.0.0 &>/tmp/port-forward.log &

log "============================================"
log " Cluster prêt !"
log " Application : http://localhost:8080"
log " PostgreSQL  : postgresql:5432 (interne)"
log " Dashboard   : https://localhost:9443 (token dans /tmp/dashboard-token.txt)"
log "============================================"

exec tail -f /dev/null
