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
fi

# Import image on ALL nodes every restart (handles image updates + new nodes)
log "=== Import de l'image locale sur tous les nœuds ==="
docker save gestion-rh:latest | gzip > /tmp/gestion-rh.tar.gz
for node in $(k3d node list -c web-cluster -o json 2>/dev/null | python3 -c "import sys,json; nodes=json.load(sys.stdin); [print(n['name']) for n in nodes]" 2>/dev/null || k3d node list 2>/dev/null | awk 'NR>1{print $1}'); do
  [ -z "$node" ] && continue
  log "  Import sur $node..."
  docker cp /tmp/gestion-rh.tar.gz "$node:/tmp/gestion-rh.tar.gz" 2>/dev/null
  docker exec "$node" sh -c "gunzip -c /tmp/gestion-rh.tar.gz | ctr -n k8s.io images import -" 2>/dev/null || true
  docker exec "$node" rm -f /tmp/gestion-rh.tar.gz 2>/dev/null || true
done
rm -f /tmp/gestion-rh.tar.gz
log "  Import terminé"

# Configure kubectl before any kubectl commands
log "=== Configuration kubectl ==="
k3d kubeconfig get web-cluster > /tmp/k3s-kubeconfig 2>/dev/null || true
if [ -f /tmp/k3s-kubeconfig ] && [ -s /tmp/k3s-kubeconfig ]; then
  sed -i 's|server: https://0.0.0.0:[0-9]*|server: https://k3d-web-cluster-serverlb:6443|' /tmp/k3s-kubeconfig
  mkdir -p /root/.kube
  cp /tmp/k3s-kubeconfig /root/.kube/config
  log "  kubeconfig ok (serveur: k3d-web-cluster-serverlb:6443)"
elif k3d kubeconfig merge web-cluster -s &>/dev/null; then
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  log "  kubeconfig via merge"
else
  log "  WARN: échec récupération kubeconfig"
fi

# Clean old prometheus/grafana resources (wrong labels from previous setup)
kubectl delete deployment prometheus grafana 2>/dev/null || true
kubectl delete service prometheus grafana 2>/dev/null || true

# Generate secret.yaml if missing (gitignored)
if [ ! -f /k8s/secret.yaml ]; then
  log "=== Génération de secret.yaml ==="
  cat > /k8s/secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: gestion-rh-secret
type: Opaque
stringData:
  db-password: "${DB_PASSWORD:-CHANGE_ME_DB_PASSWORD}"
  django-secret-key: "${DJANGO_SECRET_KEY:-CHANGE_ME_DJANGO_SECRET_KEY}"
  admin-password: "${ADMIN_PASSWORD:-CHANGE_ME_ADMIN_PASSWORD}"
  grafana-password: "${GRAFANA_PASSWORD:-CHANGE_ME_GRAFANA_PASSWORD}"
EOF
fi

log "=== Déploiement des manifests k8s ==="
kubectl apply --validate=false -k /k8s/

log "=== Attente de PostgreSQL (rollout 30-60s) ==="
kubectl wait --for=condition=ready --timeout=180s pod -l app=postgresql 2>/dev/null || log "  WARN: timeout pg"

log "=== Attente du PVC media ==="
kubectl wait --for=condition=bound --timeout=30s pvc/gestion-rh-media 2>/dev/null || true

log "=== Attente de l'application ==="
kubectl wait --for=condition=available --timeout=300s deployment/gestion-rh 2>/dev/null || log "  WARN: timeout app"

log "=== Attente de Prometheus ==="
kubectl wait --for=condition=available --timeout=120s deployment/prometheus 2>/dev/null || true

log "=== Attente de Grafana ==="
kubectl wait --for=condition=available --timeout=120s deployment/grafana 2>/dev/null || true

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
TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user 2>/dev/null || true)
[ -n "$TOKEN" ] && echo "Token Dashboard: $TOKEN" > /tmp/dashboard-token.txt

# Regenerate token if missing
if [ ! -f /tmp/dashboard-token.txt ]; then
  sleep 3
  TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user 2>/dev/null || true)
  [ -n "$TOKEN" ] && echo "Token Dashboard: $TOKEN" > /tmp/dashboard-token.txt
fi

log "=== Démarrage des port-forwards (auto-restart) ==="
pkill -f "port-forward" 2>/dev/null || true
sleep 1

pf_keepalive() {
  local label=$1; shift
  local logfile="/tmp/${label}.log"
  while true; do
    kubectl port-forward "$@" --address 0.0.0.0 &>"$logfile"
    log "  [pf:$label] redémarrage dans 2s..."
    sleep 2
  done
}

pf_keepalive "app" svc/gestion-rh 8080:80 &
pf_keepalive "dashboard" svc/kubernetes-dashboard -n kubernetes-dashboard 9443:443 &
pf_keepalive "prometheus" svc/prometheus 9090:9090 &
pf_keepalive "grafana" svc/grafana 3000:3000 &
sleep 3

# Vérification initiale
for f in /tmp/app.log /tmp/dashboard.log /tmp/prometheus.log /tmp/grafana.log; do
  if grep -q "Forwarding from" "$f" 2>/dev/null; then
    log "  $(basename $f .log) OK"
  fi
done

log "============================================"
log " Cluster prêt !"
log " Application   : http://localhost:8080"
log " Prometheus    : http://localhost:9090"
log " Grafana       : http://localhost:3000 (admin/admin)"
log " PostgreSQL    : postgresql:5432 (interne)"
log " Dashboard K8s : https://localhost:9443 (token dans /tmp/dashboard-token.txt)"
log "============================================"

# Garder le container vivant et surveiller les port-forwards
while true; do
  for pid in $(pgrep -f "kubectl port-forward" 2>/dev/null); do
    if ! kill -0 "$pid" 2>/dev/null; then
      log "  WARN: port-forward manquant, pf_keepalive va le relancer"
    fi
  done
  for name in app dashboard prometheus grafana; do
    logfile="/tmp/${name}.log"
    if [ -f "$logfile" ] && grep -q "error" "$logfile" 2>/dev/null; then
      log "  [pf:$name] erreur detectée, attente du restart auto..."
    fi
  done
  sleep 10
done
