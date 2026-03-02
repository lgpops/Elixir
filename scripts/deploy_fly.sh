#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-log-app-lgpops}"
FLY_REGION="${FLY_REGION:-syd}"
PHX_HOST="${PHX_HOST:-${APP_NAME}.fly.dev}"

if ! command -v flyctl >/dev/null 2>&1; then
  echo "Error: flyctl is not installed. Install with: brew install flyctl"
  exit 1
fi

if ! flyctl auth whoami >/dev/null 2>&1; then
  echo "You are not logged in to Fly. Running: flyctl auth login"
  flyctl auth login
fi

echo "Using app: ${APP_NAME}"
echo "Using region: ${FLY_REGION}"
echo "Using host: ${PHX_HOST}"

if ! flyctl apps list --json | grep -q "\"Name\":\"${APP_NAME}\""; then
  echo "Creating Fly app ${APP_NAME}..."
  flyctl apps create "${APP_NAME}"
else
  echo "Fly app ${APP_NAME} already exists"
fi

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "Error: DATABASE_URL is required in your shell env"
  echo "Example: export DATABASE_URL=ecto://USER:PASS@HOST:5432/DB"
  exit 1
fi

if [[ -z "${SECRET_KEY_BASE:-}" ]]; then
  echo "SECRET_KEY_BASE not set; generating one via mix"
  SECRET_KEY_BASE="$(mix phx.gen.secret)"
fi

echo "Setting Fly secrets..."
flyctl secrets set \
  DATABASE_URL="${DATABASE_URL}" \
  SECRET_KEY_BASE="${SECRET_KEY_BASE}" \
  PHX_HOST="${PHX_HOST}" \
  --app "${APP_NAME}"

echo "Deploying release..."
flyctl deploy --remote-only --app "${APP_NAME}" --region "${FLY_REGION}"

echo "Running DB migrations..."
flyctl ssh console -C "/app/bin/log_app eval 'LogApp.Release.migrate'" --app "${APP_NAME}"

echo "Done. App URL: https://${PHX_HOST}"
echo "Smoke test command:"
echo "curl -X POST https://${PHX_HOST}/logs -H 'content-type: application/json' -d '{\"level\":\"info\",\"workflow_id\":\"550e8400-e29b-41d4-a716-446655440000\",\"message\":{\"message\":\"hello from fly\"}}'"
