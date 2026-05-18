# Kubernetes Local

Environnement de développement local avec Docker Compose et k3d.

## Services

| Service | Rôle | Accès |
|---------|------|-------|
| `postgresql` | Base de données PostgreSQL 16 | `localhost:5432` |
| `web` | Application Django (gestion-rh) | `localhost:8000` |
| `cluster-manager` | Cluster k3d (profil `k8s`) | `localhost:8080` |

## Utilisation

### Application uniquement

```bash
docker compose up -d
```

→ [http://localhost:8000](http://localhost:8000) — `admin` / `0UGtvTgZvSuQQ8ZZeWaF`

### Application + cluster Kubernetes

```bash
docker compose --profile k8s up -d
```

→ App : [http://localhost:8000](http://localhost:8000)
→ Cluster : [http://localhost:8080](http://localhost:8080)

### Tout en une commande

```bash
bash scripts/start.sh
```

Build l'image Django, démarre les services et lance le tunnel HTTPS.

### Arrêter

```bash
docker compose down
docker compose --profile k8s down        # si le cluster était actif
pkill -f "serveo.net|localhost.run"      # tuer les tunnels SSH
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
- Port `8080` → loadbalancer `80`
- Déploie automatiquement les manifests de `gestion-rh/k8s/`

### Commandes k3d

```bash
# Lister les clusters
k3d cluster list

# Supprimer le cluster
k3d cluster delete web-cluster

# Voir les logs
docker compose --profile k8s logs -f cluster-manager
```

## Structure

```
kubernetes-local/
├── docker-compose.yml     # PostgreSQL + web + cluster-manager
├── Dockerfile              # Image k3d + kubectl
├── scripts/
│   ├── setup.sh           # Entrypoint du cluster-manager
│   └── start.sh           # Build + start + tunnel
└── k8s/                   # Manifests (non utilisés directement)
```

## Dépendances

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [gestion-rh](https://github.com/gusoo-bakery/gestion-rh) — application Django (build local)
