#!/usr/bin/env bash
# Railway entrypoint for Marzban panel.
# 1. Bind host/port from Railway's $PORT.
# 2. Run database migrations (falls back to create_all if alembic has no history).
# 3. Create the sudo admin from env vars, if provided (idempotent).
# 4. Start uvicorn.
set -euo pipefail

cd /code

export HOST="0.0.0.0"
export PORT="${PORT:-8000}"
export UVICORN_HOST="$HOST"
export UVICORN_PORT="$PORT"
export SQLALCHEMY_DATABASE_URL="${SQLALCHEMY_DATABASE_URL:-sqlite:////code/db.sqlite3}"

echo "==> [railway] Marzban panel starting on ${HOST}:${PORT}"

echo "==> [railway] Running database migrations (alembic upgrade head)..."
alembic upgrade head || {
    echo "!! [railway] alembic upgrade failed; falling back to create_all()..."
    python - <<'PY'
import app.db.base as b
try:
    b.Base.metadata.create_all(bind=b.engine)
    print("create_all() succeeded")
except Exception as e:
    print("create_all() also failed:", e)
PY
}

if [ -n "${SUDO_USERNAME:-}" ] && [ -n "${SUDO_PASSWORD:-}" ]; then
    echo "==> [railway] Ensuring sudo admin '${SUDO_USERNAME}' exists..."
    python create_admin.py --username "$SUDO_USERNAME" --password "$SUDO_PASSWORD" --sudo \
        || echo "!! [railway] admin creation reported an issue (it may already exist) - continuing"
else
    echo "==> [railway] SUDO_USERNAME / SUDO_PASSWORD not set."
    echo "    Create an admin later from the Railway console with:"
    echo "    marzban-cli admin create --sudo"
fi

echo "==> [railway] Launching uvicorn..."
exec uvicorn main:app \
    --host "$HOST" \
    --port "$PORT" \
    --workers 1 \
    --proxy-headers \
    --forwarded-allow-ips '*' \
    --log-level info
