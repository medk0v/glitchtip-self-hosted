#!/bin/bash
set -euo pipefail

# === Config ===
POSTGRES_PASSWORD="123456789"
SITE_URL="https://glitchtip.example.com"
GLITCHTIP_IMAGE="glitchtip/glitchtip:v5.1.0"

ADMIN_USERNAME="admin"
ADMIN_EMAIL="admin@example.com"
ADMIN_PASSWORD="ChangeMeStrong123!"

NETWORK_NAME="glitchtip_network"
POSTGRES_IMAGE="postgres:17"
REDIS_IMAGE="redis:8-alpine"

# Один и тот же ключ для всех процессов
SECRET_KEY="${SECRET_KEY:-$(openssl rand -base64 50)}"

# Общие переменные окружения для GlitchTip
GT_ENV=(
  -e DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres"
  -e CACHE_URL="redis://glitchtip-redis:6379/1"
  -e CELERY_BROKER_URL="redis://glitchtip-redis:6379/1"
  -e SITE_URL="${SITE_URL}"
  -e USE_X_FORWARDED_HOST=True
  -e SECURE_PROXY_SSL_HEADER="HTTP_X_FORWARDED_PROTO,https"
  -e SECRET_KEY="${SECRET_KEY}"
)

echo "[1/5] Network"
docker network create "$NETWORK_NAME" >/dev/null 2>&1 || true

echo "[2/5] PostgreSQL"
docker rm -f postgres >/dev/null 2>&1 || true
docker run -d \
  --name postgres \
  --network "$NETWORK_NAME" \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --restart unless-stopped \
  "$POSTGRES_IMAGE" \
  -c max_connections=300

echo "Waiting for PostgreSQL..."
until docker exec postgres pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done

echo "[3/5] Redis 8"
docker rm -f glitchtip-redis >/dev/null 2>&1 || true
docker run -d \
  --name glitchtip-redis \
  --network "$NETWORK_NAME" \
  --restart unless-stopped \
  "$REDIS_IMAGE"

echo "[4/5] Migrations + superuser (one-off)"
docker run --rm \
  --network "$NETWORK_NAME" \
  "${GT_ENV[@]}" \
  "$GLITCHTIP_IMAGE" ./manage.py migrate --noinput

docker run --rm \
  --network "$NETWORK_NAME" \
  -e DJANGO_SUPERUSER_USERNAME="$ADMIN_USERNAME" \
  -e DJANGO_SUPERUSER_EMAIL="$ADMIN_EMAIL" \
  -e DJANGO_SUPERUSER_PASSWORD="$ADMIN_PASSWORD" \
  "${GT_ENV[@]}" \
  "$GLITCHTIP_IMAGE" ./manage.py createsuperuser --noinput || true

echo "[5/5] Web, Worker, Beat"
docker rm -f glitchtip glitchtip_worker glitchtip_beat >/dev/null 2>&1 || true

# Web (оставил публикацию 8000 -> 8080; если есть reverse-proxy — порт можно убрать)
docker run -d \
  --name glitchtip \
  --network "$NETWORK_NAME" \
  -p 8000:8080 \
  --restart unless-stopped \
  "${GT_ENV[@]}" \
  "$GLITCHTIP_IMAGE"

# Celery worker
docker run -d \
  --name glitchtip_worker \
  --network "$NETWORK_NAME" \
  --restart unless-stopped \
  "${GT_ENV[@]}" \
  "$GLITCHTIP_IMAGE" celery -A glitchtip worker -l info

# Celery beat
docker run -d \
  --name glitchtip_beat \
  --network "$NETWORK_NAME" \
  --restart unless-stopped \
  "${GT_ENV[@]}" \
  "$GLITCHTIP_IMAGE" celery -A glitchtip beat -l info

echo "✅ Done. Open: ${SITE_URL}"
