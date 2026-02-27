# Quick Start Guide

## Start the Application

```bash
cd /Users/rblren/Elixir
mix phx.server
```

The server will start on `http://localhost:4000`

## Access the Logs Dashboard

Open your browser and navigate to:
```
http://localhost:4000/logs
```

## Send a Log via Ingress

```bash
curl -X POST http://localhost:4001/logs \
  -H "Content-Type: application/json" \
  -d '{
    "level": "info",
    "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
    "message": {"message": "Hello from ingress"}
  }'
```

Watch the logs table update in real-time on the dashboard!

## Project Layout

```
lib/log_app/
  ├── log.ex              # Database schema
  ├── logs.ex             # Business logic
  ├── ingress.ex          # Cowboy ingress router + server
  └── log_queue.ex        # Ordered GenServer queue (persist + broadcast)

lib/log_app_web/
  └── live/log_live/
      └── index.ex        # Real-time dashboard

priv/repo/migrations/
  ├── 20260220074336_create_logs.exs
  └── 20260222000000_rebuild_logs_for_ingress.exs
```

## Key Features

✅ Real-time log updates via Phoenix LiveView  
✅ PostgreSQL JSONB message field for flexible data  
✅ Workflow UUID indexing for fast lookup  
✅ Ordered GenServer queue for deterministic processing  
✅ Cowboy ingress separated from web UI routes  

## Documentation

See [SETUP_SUMMARY.md](./SETUP_SUMMARY.md) for complete information.  
See [LOG_GUIDE.md](./LOG_GUIDE.md) for detailed usage patterns.

---

That's it! Your logging application is ready to use! 🚀
