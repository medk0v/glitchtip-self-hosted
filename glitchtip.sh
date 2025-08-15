#!/bin/bash
set -e

# Configuration variables
POSTGRES_PASSWORD="123456789"
SITE_URL="https://glitchtip.example.com"   # Change this to your domain
GLITCHTIP_IMAGE="glitchtip/glitchtip:v5.1.0"

ADMIN_USERNAME="admin"                      # Change if needed
ADMIN_EMAIL="admin@example.com"             # Change if needed
ADMIN_PASSWORD="ChangeMeStrong123!"         # Change to a strong password

echo "[1/6] Creating network..."
docker network create glitchtip_network || true

echo "[2/6] Starting PostgreSQL..."
docker run -d \
  --name postgres \
  --network glitchtip_network \
  --memory="8g" \
  --memory-swap="8g" \
  -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  -p 5432:5432 \
  --restart unless-stopped \
  postgres

echo "Waiting for PostgreSQL (10s)..."
sleep 10

echo "[3/6] Starting Redis..."
docker run -d \
  --name glitchtip-redis \
  --network glitchtip_network \
  --memory="8g" \
  --memory-swap="8g" \
  -p 6380:6379 \
  --restart unless-stopped \
  redis:alpine

echo "Waiting for Redis (5s)..."
sleep 5

echo "[4/6] Starting GlitchTip main web service..."
docker run -d \
  --name glitchtip \
  --network glitchtip_network \
  --memory="8g" \
  --memory-swap="8g" \
  -e DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres" \
  -e CACHE_URL="redis://glitchtip-redis:6379/1" \
  -e CELERY_BROKER_URL="redis://glitchtip-redis:6379/1" \
  -e SITE_URL="${SITE_URL}" \
  -e USE_X_FORWARDED_HOST=True \
  -e SECURE_PROXY_SSL_HEADER="('HTTP_X_FORWARDED_PROTO', 'https')" \
  -e UWSGI_LISTEN=1024 \
  -e UWSGI_WORKERS=32 \
  -e UWSGI_THREADS=4 \
  -e UWSGI_BUFFER_SIZE=32768 \
  -e UWSGI_HARAKIRI=60 \
  -e UWSGI_MAX_REQUESTS=5000 \
  -p 8000:8080 \
  ${GLITCHTIP_IMAGE}

echo "Waiting for GlitchTip to start (10s)..."
sleep 10

# Extract SECRET_KEY from the main container
SECRET_KEY=$(docker exec glitchtip env | grep -m1 '^SECRET_KEY=' | cut -d= -f2)

echo "[5/6] Starting Celery Worker..."
docker run -d \
  --name glitchtip_worker \
  --network glitchtip_network \
  -e DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres" \
  -e CELERY_BROKER_URL="redis://glitchtip-redis:6379/1" \
  -e CACHE_URL="redis://glitchtip-redis:6379/1" \
  -e SITE_URL="${SITE_URL}" \
  -e USE_X_FORWARDED_HOST=True \
  -e SECURE_PROXY_SSL_HEADER="HTTP_X_FORWARDED_PROTO,https" \
  -e SECRET_KEY="${SECRET_KEY}" \
  ${GLITCHTIP_IMAGE} \
  celery -A glitchtip worker -l info

echo "[6/6] Starting Celery Beat..."
docker run -d \
  --name glitchtip_beat \
  --network glitchtip_network \
  -e DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres" \
  -e CELERY_BROKER_URL="redis://glitchtip-redis:6379/1" \
  -e CACHE_URL="redis://glitchtip-redis:6379/1" \
  -e SITE_URL="${SITE_URL}" \
  -e USE_X_FORWARDED_HOST=True \
  -e SECURE_PROXY_SSL_HEADER="HTTP_X_FORWARDED_PROTO,https" \
  -e SECRET_KEY="${SECRET_KEY}" \
  ${GLITCHTIP_IMAGE} \
  celery -A glitchtip beat -l info

echo "✅ GlitchTip deployment complete!"
echo "Access it at: ${SITE_URL}"
