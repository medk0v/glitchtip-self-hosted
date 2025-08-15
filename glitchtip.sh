#!/bin/bash
set -e

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

# === 1. Network ===
echo "[1/6] Ensuring network..."
docker network create "$NETWORK_NAME" || true

# === 2. PostgreSQL ===
echo "[2/6] Starting PostgreSQL..."
docker run -d \
  --name postgres \
  --network "$NETWORK_NAME" \
  --memory="8g" \
  --memory-swap="8g" \
  -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  -p 5432:5432 \
  --restart unless-stopped \
  $POSTGRES_IMAGE \
  -c max_connections=1000 \
  -c shared_buffers=2GB \
  -c work_mem=64MB \
  -c maintenance_work_mem=512MB \
  -c effective_cache_size=4GB \
  -c wal_buffers=16MB \
  -c default_statistics_target=500

echo "Waiting for PostgreSQL..."
until docker exec postgres pg_isready -U postgres >/dev/null 2>&1; do
  sleep 1
done
echo "PostgreSQL is ready."

# === 3. Redis ===
echo "[3/6] Starting Redis..."
docker run -d \
  --name glitchtip-redis \
  --network "$NETWORK_NAME" \
  --memory="8g" \
  --memory-swap="8g" \
  -p 6380:6379 \
  --restart unless-stopped \
  $REDIS_IMAGE
sleep 5

# === 4. GlitchTip Web (initial for migrations) ===
echo "[4/6] Starting GlitchTip web for migrations..."
docker run -d \
  --name glitchtip \
  --network "$NETWORK_NAME" \
  --memory="8g" \
  --memory-swap="8g" \
  -e DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres" \
  -e CACHE_URL="redis://glitchtip-redis:6379/1" \
  -e CELERY_BROKER_URL="redis://glitchtip-redis:6379/1" \
  -e SITE_URL="${SITE_URL}" \
  -e USE_X_FORWARDED_HOST=True \
  -e SECURE_PROXY_SSL_HEADER="('HTTP_X_FORWARDED_PROTO', 'https')" \
  -e UWSGI_LISTEN=1024 \
  -e UWSGI_WORKERS=64 \
  -e UWSGI_THREADS=4 \
  -e UWSGI_BUFFER_SIZE=32768 \
  -e UWSGI_HARAKIRI=60 \
  -e UWSGI_MAX_REQUESTS=10000 \
  -p 8000:8080 \
  $GLITCHTIP_IMAGE
sleep 10

# === Migrations ===
echo "[*] Running database migrations..."
docker exec glitchtip ./manage.py migrate --noinput

# === Create superuser ===
echo "[*] Creating superuser..."
docker exec -e DJANGO_SUPERUSER_USERNAME="$ADMIN_USERNAME" \
            -e DJANGO_SUPERUSER_EMAIL="$ADMIN_EMAIL" \
            -e DJANGO_SUPERUSER_PASSWORD="$ADMIN_PASSWORD" \
            glitchtip ./manage.py createsuperuser --noinput || true

# === Get SECRET_KEY ===
SECRET_KEY=$(docker exec glitchtip env | grep -m1 '^SECRET_KEY=' | cut -d= -f2)

# === 5. Celery Worker ===
echo "[5/6] Starting Celery Worker..."
docker run -d \
  --name glitchtip_worker \
  --network "$NETWORK_NAME" \
  --memory="8g" \
  --memory-swap="8g" \
  -e DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres" \
  -e CELERY_BROKER_URL="redis://glitchtip-redis:6379/1" \
  -e CACHE_URL="redis://glitchtip-redis:6379/1" \
  -e SITE_URL="${SITE_URL}" \
  -e USE_X_FORWARDED_HOST=True \
  -e SECURE_PROXY_SSL_HEADER="HTTP_X_FORWARDED_PROTO,https" \
  -e SECRET_KEY="${SECRET_KEY}" \
  $GLITCHTIP_IMAGE \
  celery -A glitchtip worker -l info

# === 6. Celery Beat ===
echo "[6/6] Starting Celery Beat..."
docker run -d \
  --name glitchtip_beat \
  --network "$NETWORK_NAME" \
  --memory="8g" \
  --memory-swap="8g" \
  -e DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres" \
  -e CELERY_BROKER_URL="redis://glitchtip-redis:6379/1" \
  -e CACHE_URL="redis://glitchtip-redis:6379/1" \
  -e SITE_URL="${SITE_URL}" \
  -e USE_X_FORWARDED_HOST=True \
  -e SECURE_PROXY_SSL_HEADER="HTTP_X_FORWARDED_PROTO,https" \
  -e SECRET_KEY="${SECRET_KEY}" \
  $GLITCHTIP_IMAGE \
  celery -A glitchtip beat -l info

echo "✅ GlitchTip deployment complete!"
echo "Access it at: ${SITE_URL}"
