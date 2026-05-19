# Kubernetes Local

Environnement de développement local avec Docker Compose et k3d.

## Services

| Service | Rôle | Accès |
|---------|------|-------|
| `postgresql` | Base de données PostgreSQL 16 | `localhost:5432` |
| `web` | Application Django (gestion-rh) | `localhost:8000` |
| `cluster-manager` | Cluster k3d + Dashboard K8s (profil `k8s`) | `localhost:8080` / `localhost:9443` |

## Utilisation

### Application uniquement

```bash
docker compose up -d
```

→ [http://localhost:8000](http://localhost:8000) — `admin` / `0UGtvTgZvSuQQ8ZZeWaF`

### Application + cluster Kubernetes

```bash
docker compose --profile k8s up -d --build
```

→ App : [http://localhost:8080](http://localhost:8080)  
→ Dashboard K8s : [https://localhost:9443](https://localhost:9443)

### Token du Dashboard

```bash
docker exec k3d-manager kubectl -n kubernetes-dashboard create token admin-user
```

Coller le token dans la page de connexion (choisir "Token").

### Tout en une commande (via gestion-rh)

```bash
cd ~/Desktop/projets/gestion-rh
bash scripts/up.sh
```

Build l'image Django, démarre les services, le cluster k3d, le Dashboard, et le tunnel HTTPS.

### Arrêter

```bash
docker compose down
docker compose --profile k8s down        # si le cluster était actif
pkill -f "serveo.net"                     # tuer le tunnel SSH
```

## Tunnel HTTPS (Serveo)

```bash
ssh -i ~/.ssh/serveo_key \
  -R gestionpresences:80:localhost:8000 serveo.net
```

→ [https://gestionpresences.serveousercontent.com](https://gestionpresences.serveousercontent.com)

## Kubernetes (k3d)

Le `cluster-manager` (profil `k8s`) crée un cluster k3d nommé `web-cluster` avec :

- 1 serveur + 2 agents
- Port `8080` → port-forward vers l'application
- Port `9443` → port-forward vers le Dashboard K8s
- Déploie automatiquement les manifests de `gestion-rh/k8s/`
- Installe le Dashboard via Helm (kubernetes-dashboard 7.14.0)

### Dashboard Kubernetes

Installé automatiquement par `setup.sh` via Helm avec :

- **nginx** désactivé (pas besoin de ingress)
- **cert-manager** désactivé
- **Kong** comme proxy API (auto-configuré)
- Port-forward `9443` → `kubernetes-dashboard-kong-proxy:443`

Accès : `https://localhost:9443` (certificat auto-signé → accepter le risque)

### Commandes k3d

```bash
# Lister les clusters
k3d cluster list

# Supprimer le cluster
k3d cluster delete web-cluster

# Voir les logs du setup
docker compose --profile k8s logs -f cluster-manager

# Simuler un crash (Kubernetes recrée le pod)
docker exec k3d-manager kubectl delete pod -l app=gestion-rh --force
```

## Persistance des données

PostgreSQL stocke ses données dans `./data/postgresql/` (bind mount sur l'hôte). Les données survivent aux redémarrages.

```bash
# Tout effacer
docker compose down
rm -rf data/postgresql
```

## Structure

```
kubernetes-local/
├── docker-compose.yml     # PostgreSQL + web + cluster-manager (port 9443)
├── Dockerfile              # Image k3d + kubectl + helm
├── scripts/
│   ├── setup.sh           # Entrypoint du cluster-manager
│   └── start.sh           # Build + start + tunnel
├── k8s/                   # Anciens manifests (non utilisés)
└── data/postgresql/       # Données PostgreSQL (.gitignored)
```

## Dépendances

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [gestion-rh](https://github.com/gusoo-bakery/gestion-rh) — application Django (build local)
