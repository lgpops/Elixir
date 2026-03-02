# Fly.io deployment (simple path)

This repo is configured for a minimal Phoenix deployment on Fly.

## Defaults in this branch

- App name: `log-app-lgpops`
- Region: `syd`
- Host: `log-app-lgpops.fly.dev`

If you change app name, also change `app` and `PHX_HOST` in `fly.toml`.

## 1) Install and login

```bash
brew install flyctl
flyctl auth login
```

## 1.1) One-command deploy (recommended)

You can run the helper script from this branch:

```bash
export DATABASE_URL="ecto://USER:PASS@HOST:5432/DB"
./scripts/deploy_fly.sh
```

Optional overrides:

```bash
APP_NAME="log-app-lgpops" FLY_REGION="syd" PHX_HOST="log-app-lgpops.fly.dev" ./scripts/deploy_fly.sh
```

## 2) Create app (first run only)

```bash
flyctl apps create log-app-lgpops
```

## 3) Set required secrets

```bash
flyctl secrets set \
  DATABASE_URL="ecto://USER:PASS@HOST:5432/DB" \
  SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  PHX_HOST="log-app-lgpops.fly.dev"
```

## 4) Deploy

```bash
flyctl deploy --remote-only
```

## 5) Run migrations

```bash
flyctl ssh console -C "/app/bin/log_app eval 'LogApp.Release.migrate'"
```

## 6) Smoke test ingest endpoint

```bash
curl -X POST "https://log-app-lgpops.fly.dev/logs" \
  -H "content-type: application/json" \
  -d '{"level":"info","workflow_id":"550e8400-e29b-41d4-a716-446655440000","message":{"message":"hello from fly"}}'
```

## Client calls

- Elixir helper: `LogApp.send_info/2`, `LogApp.send_log/3`
- External clients: send `POST /logs` to `https://log-app-lgpops.fly.dev`
