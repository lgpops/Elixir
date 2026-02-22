# Quick Start Guide

## Start the Application

```bash
cd /Users/rblren/Elixir/log_app
mix phx.server
```

The server will start on `http://localhost:4000`

## Access the Logs Dashboard

Open your browser and navigate to:
```
http://localhost:4000/logs
```

## Log a Message from Elixir

Open an IEx shell while the server is running in another terminal:

```bash
iex -S mix phx.server
```

Then in the IEx console:

```elixir
# Simple info log
LogApp.TemporalHelper.log_info(
  "550e8400-e29b-41d4-a716-446655440000",
  %{"message" => "Hello from Temporal"}
)

# Error log
LogApp.TemporalHelper.log_error(
  "550e8400-e29b-41d4-a716-446655440000",
  %{"error" => "Something went wrong"}
)

# Raw Oban job
LogApp.LogWorker.new(%{
  "level" => "info",
  "job_id" => "550e8400-e29b-41d4-a716-446655440000",
  "detail" => %{"custom_field" => "value"}
})
|> Oban.insert!()
```

Watch the logs table update in real-time on the dashboard!

## Project Layout

```
lib/log_app/
  ├── log.ex              # Database schema
  ├── logs.ex             # Business logic
  ├── log_worker.ex       # Oban job processor
  ├── temporal_helper.ex  # Easy logging API
  └── examples.ex         # Usage examples

lib/log_app_web/
  └── live/log_live/
      └── index.ex        # Real-time dashboard

priv/repo/migrations/
  ├── 20260220074336_create_logs.exs
  └── 20260220075000_add_oban.exs
```

## Key Features

✅ Real-time log updates via Phoenix LiveView  
✅ PostgreSQL JSONB detail field for flexible data  
✅ Job ID UUID indexing for fast lookup  
✅ Oban integration for reliable job processing  
✅ Helper functions for easy Temporal integration  

## Documentation

See [SETUP_SUMMARY.md](./SETUP_SUMMARY.md) for complete information.  
See [LOG_GUIDE.md](./LOG_GUIDE.md) for detailed usage patterns.

---

That's it! Your logging application is ready to use! 🚀
