#!/usr/bin/env bash
set -euo pipefail

# =========================
# GlitchTip destroy script
# with optional full Docker wipe
# =========================

# Defaults (same as before)
NETWORK_NAME="${NETWORK_NAME:-glitchtip_network}"
CONTAINERS=("glitchtip_beat" "glitchtip_worker" "glitchtip" "glitchtip-redis" "pgbouncer" "postgres")
VOLUMES=("pgdata" "redisdata")   # named volumes; ignore if you used bind mounts
IMAGES=("glitchtip/glitchtip" "redis:alpine" "postgres:17")

PURGE_DATA=false
REMOVE_IMAGES=false
ASSUME_YES=false
NUKE_ALL=false

usage() {
  cat <<'EOF'
Usage: destroy-glitchtip.sh [options]

Options:
  --purge-data        Remove named Docker volumes (WILL DELETE DB/REDIS DATA!)
  --remove-images     Remove stack images (glitchtip, redis, postgres)
  --nuke              ⚠️ FULL WIPE: remove ALL containers, images, volumes, custom networks, build cache
  -y, --yes           Do not prompt for confirmation
  -h, --help          Show this help

Env overrides:
  NETWORK_NAME        Docker network name (default: glitchtip_network)

Examples:
  # Remove just the GlitchTip stack (keep named volumes/images)
  ./destroy-glitchtip.sh -y

  # Remove stack + named volumes
  ./destroy-glitchtip.sh --purge-data -y

  # Full, machine-wide Docker wipe (everything, not only GlitchTip)
  ./destroy-glitchtip.sh --nuke -y
EOF
}

confirm() {
  $ASSUME_YES && return 0
  read -r -p "$1 [y/N]: " ans
  [[ "${ans:-N}" =~ ^[Yy]$ ]]
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }

exists_container() { docker ps -a --format '{{.Names}}' | grep -Fxq "$1"; }
exists_network()   { docker network inspect "$1" &>/dev/null; }
exists_volume()    { docker volume inspect "$1" &>/dev/null; }

stop_rm_container() {
  local name="$1"
  if exists_container "$name"; then
    echo "Stopping $name..."
    docker stop "$name" >/dev/null 2>&1 || true
    echo "Removing $name..."
    docker rm "$name" >/dev/null 2>&1 || true
  else
    echo "$name does not exist, skipping..."
  fi
}

rm_network() {
  local net="$1"
  if exists_network "$net"; then
    echo "Removing network $net..."
    docker network rm "$net" >/dev/null 2>&1 || true
  else
    echo "Network $net does not exist, skipping..."
  fi
}

rm_volume() {
  local vol="$1"
  if exists_volume "$vol"; then
    echo "Removing volume $vol..."
    docker volume rm "$vol" >/dev/null 2>&1 || true
  else
    echo "Volume $vol does not exist, skipping..."
  fi
}

rm_images() {
  local images=("$@")
  for img in "${images[@]}"; do
    echo "Removing image $img (if present)..."
    docker image rm "$img" >/dev/null 2>&1 || true
  done
}

nuke_docker() {
  echo "=== FULL DOCKER WIPE START ==="

  # Stop & remove all containers
  if docker ps -aq >/dev/null; then
    ids=$(docker ps -aq)
    if [[ -n "${ids}" ]]; then
      echo "Stopping ALL containers..."
      docker stop ${ids} >/dev/null 2>&1 || true
      echo "Removing ALL containers..."
      docker rm -f ${ids} >/dev/null 2>&1 || true
    fi
  fi

  # Remove all images
  imgs=$(docker images -aq | sort -u || true)
  if [[ -n "${imgs:-}" ]]; then
    echo "Removing ALL images..."
    docker rmi -f ${imgs} >/dev/null 2>&1 || true
  fi

  # Remove all volumes
  vols=$(docker volume ls -q | sort -u || true)
  if [[ -n "${vols:-}" ]]; then
    echo "Removing ALL volumes..."
    docker volume rm -f ${vols} >/dev/null 2>&1 || true
  fi

  # Remove all custom networks (keep default: bridge, host, none)
  nets=$(docker network ls --filter type=custom -q | sort -u || true)
  if [[ -n "${nets:-}" ]]; then
    echo "Removing ALL custom networks..."
    docker network rm ${nets} >/dev/null 2>&1 || true
  fi

  # Prune builders and caches
  echo "Pruning build cache..."
  docker builder prune -af >/dev/null 2>&1 || true

  # Final safety prune to clear any dangling leftovers
  echo "Final system prune (dangling leftovers, volumes)..."
  docker system prune -af --volumes >/dev/null 2>&1 || true

  echo "✅ FULL Docker wipe complete."
  echo "   (If you use Docker Desktop or alternate contexts, data in other contexts may remain.)"
}

# ---- Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge-data)    PURGE_DATA=true; shift ;;
    --remove-images) REMOVE_IMAGES=true; shift ;;
    --nuke)          NUKE_ALL=true; shift ;;
    -y|--yes)        ASSUME_YES=true; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

need_cmd docker

if $NUKE_ALL; then
  echo "=== ⚠️  You requested a FULL Docker wipe (ALL containers/images/volumes/networks/cache) ==="
  if ! confirm "Proceed with COMPLETE removal of ALL Docker data on this machine?"; then
    echo "Aborted."
    exit 1
  fi
  nuke_docker
  exit 0
fi

# ---- Targeted GlitchTip teardown (default behavior)
echo "=== Destroying GlitchTip stack ==="
echo "Containers: ${CONTAINERS[*]}"
echo "Network:    ${NETWORK_NAME}"
$PURGE_DATA    && echo "Volumes:    ${VOLUMES[*]} (WILL BE DELETED)"
$REMOVE_IMAGES && echo "Images:     ${IMAGES[*]} (WILL BE REMOVED)"

if ! confirm "Proceed with destruction of the GlitchTip stack?"; then
  echo "Aborted."
  exit 1
fi

echo "Removing containers..."
for c in "${CONTAINERS[@]}"; do
  stop_rm_container "$c"
done

rm_network "$NETWORK_NAME"

if $PURGE_DATA; then
  echo "Removing data volumes..."
  for v in "${VOLUMES[@]}"; do
    rm_volume "$v"
  done
fi

if $REMOVE_IMAGES; then
  echo "Removing images..."
  rm_images "${IMAGES[@]}"
fi

echo "Pruning dangling resources (safe)..."
docker volume prune -f >/dev/null 2>&1 || true
docker image  prune -f >/dev/null 2>&1 || true

echo "✅ GlitchTip stack destroyed."
$PURGE_DATA    && echo "⚠️  Data volumes removed."
$REMOVE_IMAGES && echo "🧹 Images removed."
