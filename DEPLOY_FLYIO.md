# Fly.io deployment (minimal)

This repo is now scaffolded for a simple Fly.io deployment path.

## 1) Prerequisites

- Install Fly CLI: `brew install flyctl`
- Login: `fly auth login`

## 2) Create app (first time)

If app does not exist yet:

```bash
fly apps create log-app
```

If app name is different, update `app` and `PHX_HOST` in `fly.toml`.

## 3) Create Postgres and attach URL

Use any managed Postgres provider and set `DATABASE_URL` on Fly:

```bash
fly secrets set DATABASE_URL="ecto://USER:PASS@HOST:5432/DB"
```

## 4) Set required Phoenix secrets

```bash
fly secrets set SECRET_KEY_BASE="$(mix phx.gen.secret)"
fly secrets set PHX_HOST="log-app.fly.dev"
```

## 5) Deploy

```bash
fly deploy
```

## 6) Run migrations

After first deploy:

```bash
fly ssh console -C "/app/bin/log_app eval 'LogApp.Release.migrate'"
```

## 7) Test log ingest endpoint

```bash
curl -X POST "https://log-app.fly.dev/logs" \
  -H "content-type: application/json" \
  -d '{"level":"info","workflow_id":"550e8400-e29b-41d4-a716-446655440000","message":{"message":"hello from fly"}}'
```

## Notes

- Keep one public app URL and call `POST /logs` from clients.
- The in-app helper remains available: `LogApp.send_info/2` and `LogApp.send_log/3`.
