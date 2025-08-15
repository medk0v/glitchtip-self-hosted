#!/bin/bash
set -euo pipefail

# =========================
# GlitchTip destroy script
# =========================
# Defaults
NETWORK_NAME="${NETWORK_NAME:-glitchtip_network}"
CONTAINERS=("glitchtip_beat" "glitchtip_worker" "glitchtip" "glitchtip-redis" "pgbouncer" "postgres")
VOLUMES=("pgdata" "redisdata")   # если использовал named volumes; иначе игнорируются
IMAGES=("glitchtip/glitchtip" "redis:alpine" "postgres:15")  # удалим только по флагу

PURGE_DATA=false
REMOVE_IMAGES=false
ASSUME_YES=false

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --purge-data        Remove named Docker volumes (WILL DELETE DB/REDIS DATA!)
  --remove-images     Remove stack images (glitchtip, redis, postgres)
  -y, --yes           Do not prompt for confirmation
  -h, --help          Show this help

Env overrides:
  NETWORK_NAME        Docker network name (default: glitchtip_network)

Example:
  $0 --purge-data -y
EOF
}

confirm() {
  $ASSUME_YES && return 0
  read -r -p "$1 [y/N]: " ans
  [[ "${ans:-N}" =~ ^[Yy]$ ]]
}

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

# ---- Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge-data)    PURGE_DATA=true; shift ;;
    --remove-images) REMOVE_IMAGES=true; shift ;;
    -y|--yes)        ASSUME_YES=true; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

echo "=== Destroying GlitchTip stack ==="
echo "Containers: ${CONTAINERS[*]}"
echo "Network:    ${NETWORK_NAME}"
$PURGE_DATA    && echo "Volumes:    ${VOLUMES[*]} (WILL BE DELETED)"
$REMOVE_IMAGES && echo "Images:     ${IMAGES[*]} (WILL BE REMOVED)"

if ! confirm "Proceed with destruction?"; then
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
docker image prune -f  >/dev/null 2>&1 || true

echo "✅ GlitchTip stack destroyed."
$PURGE_DATA && echo "⚠️  Data volumes removed."
$REMOVE_IMAGES && echo "🧹 Images removed."
