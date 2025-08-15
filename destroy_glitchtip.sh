#!/bin/bash
set -e

NETWORK_NAME="glitchtip_network"

stop_rm () {
  local name="$1"
  if docker ps -a --format '{{.Names}}' | grep -Fxq "$name"; then
    echo "Stopping $name..."
    docker stop "$name" >/dev/null 2>&1 || true
    echo "Removing $name..."
    docker rm "$name" >/dev/null 2>&1 || true
  else
    echo "$name does not exist, skipping..."
  fi
}

echo "Removing GlitchTip containers..."
stop_rm glitchtip_beat
stop_rm glitchtip_worker
stop_rm glitchtip
stop_rm glitchtip-redis
stop_rm postgres

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "Removing network $NETWORK_NAME..."
  docker network rm "$NETWORK_NAME" >/dev/null 2>&1 || true
else
  echo "Network $NETWORK_NAME does not exist, skipping..."
fi

echo "✅ GlitchTip stack destroyed."
