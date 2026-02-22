# Phoenix Log Application - Complete Setup Summary

A real-time logging application built with Phoenix, Ecto, PostgreSQL, Oban, and Phoenix LiveView. This application is designed to capture logs from Temporal workflows and display them in real-time through a web-based dashboard.

## Project Overview

This application provides:
- ✅ PostgreSQL database schema with logs table (ID, level, job_id UUID, JSONB detail)
- ✅ Oban job queue for processing log messages from Temporal workflows
- ✅ LogWorker that transforms queue messages into database entries
- ✅ Real-time LiveView dashboard at `/logs`
- ✅ PubSub broadcasting for instant updates across connected clients
- ✅ Helper modules for easy integration with Temporal workflows
- ✅ Complete examples and documentation

## Quick Start

### 1. Prerequisites
- Elixir 1.15+ installed
- PostgreSQL 14+ running locally
- Current user (rblren) with PostgreSQL database creation privileges

### 2. Start the Application

```bash
# Navigate to the project
cd /Users/rblren/Elixir/log_app

# Start the Phoenix server
mix phx.server

# Server will be available at http://localhost:4000
```

### 3. View the Logs Dashboard

Open your browser and go to: **http://localhost:4000/logs**

You'll see a table with headers:
- ID
- Level
- Job ID
- Detail
- Created At

## Core Modules Created

### Data Models

#### LogApp.Log
Ecto schema for the logs database table.
- Validates required fields: `level`, `job_id`
- Accepts optional `detail` map

#### LogApp.Logs (Context)
Business logic module providing functions:
- `list_logs()` - Get all logs (newest first)
- `get_log!(id)` - Get a single log by ID
- `create_log(attrs)` - Create a new log entry
- `create_log_notification(log)` - Broadcast to LiveView clients

### Workers & Integration

#### LogApp.LogWorker (Oban Worker)
Processes incoming job queue messages:
- Queue: `default`
- Expected args: `%{"level" => "...", "job_id" => "...", "detail" => %{...}}`
- Automatically creates log entries and broadcasts updates

#### LogApp.TemporalHelper
Convenience module for Temporal workflow integration:
- `log_workflow(job_id, level, detail)` - Generic logging
- `log_info(job_id, detail)` - Info level
- `log_error(job_id, detail)` - Error level
- `log_warning(job_id, detail)` - Warning level
- `log_debug(job_id, detail)` - Debug level

### UI Components

#### LogAppWeb.LogLive.Index
Real-time LiveView dashboard:
- Displays logs in a responsive table
- Subscribes to `logs:updates` PubSub channel
- Auto-refreshes when new logs are broadcast
- Handles empty state messaging

## Database Schema

### logs table
```sql
CREATE TABLE logs (
  id BIGSERIAL PRIMARY KEY,
  level VARCHAR NOT NULL,
  job_id UUID NOT NULL,
  detail JSONB,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX logs_job_id_index ON logs(job_id);
```

### oban_jobs table (Managed by Oban)
Stores background job queue information.

## Usage Examples

### Example 1: Simple Log from Workflow

```elixir
alias LogApp.TemporalHelper

# In your Temporal workflow
TemporalHelper.log_info(
  "550e8400-e29b-41d4-a716-446655440000",
  %{"message" => "Workflow step 1 completed"}
)
```

### Example 2: Error Logging

```elixir
TemporalHelper.log_error(
  workflow_id,
  %{
    "error" => "Connection timeout",
    "retry_count" => 3,
    "timestamp" => DateTime.utc_now()
  }
)
```

### Example 3: Raw Oban Job Submission

```elixir
LogApp.LogWorker.new(%{
  "level" => "info",
  "job_id" => "550e8400-e29b-41d4-a716-446655440000",
  "detail" => %{
    "step" => "data_processing",
    "duration_ms" => 1234,
    "records_processed" => 5000
  }
})
|> Oban.insert!()
```

## Configuration

### Database (config/dev.exs)
```elixir
config :log_app, LogApp.Repo,
  username: "rblren",
  password: "",
  hostname: "localhost",
  database: "log_app_dev",
  pool_size: 10
```

### Oban (config/config.exs)
```elixir
config :log_app, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10],
  repo: LogApp.Repo
```

## Project Structure

```
/Users/rblren/Elixir/log_app/
├── lib/
│   ├── log_app/
│   │   ├── log.ex              # Ecto schema
│   │   ├── logs.ex             # Context with business logic
│   │   ├── log_worker.ex       # Oban worker
│   │   ├── temporal_helper.ex  # Helper for Temporal integration
│   │   ├── examples.ex         # Usage examples
│   │   ├── application.ex      # App supervision tree
│   │   └── repo.ex             # Ecto repository
│   └── log_app_web/
│       ├── live/
│       │   └── log_live/
│       │       └── index.ex    # LiveView dashboard
│       ├── router.ex           # Route definitions
│       └── endpoint.ex         # Phoenix endpoint
├── priv/
│   └── repo/
│       └── migrations/
│           ├── 20260220074336_create_logs.exs
│           └── 20260220075000_add_oban.exs
├── config/
│   ├── config.exs             # Main configuration
│   ├── dev.exs                # Development configuration
│   └── test.exs               # Test configuration
├── mix.exs                     # Project dependencies
└── LOG_GUIDE.md               # Detailed user guide
```

## Available Commands

```bash
# Start the server
mix phx.server

# Run tests
mix test

# Create and migrate database
mix ecto.create && mix ecto.migrate

# Reset database
mix ecto.reset

# Compile project
mix compile

# Get dependencies
mix deps.get

# Format code
mix format

# Run with live reload
mix phx.server    # Auto-reloads on file changes
```

## Features

- **Real-time Dashboard**: See logs update instantly using LiveView
- **Job Tracking**: Link logs to specific Temporal workflow IDs
- **Rich Data**: Store complex data in JSONB detail field
- **Fast Retrieval**: Indexed job_id for quick filtering
- **Scalable**: Oban handles async processing
- **Type-Safe**: Compiled Elixir with pattern matching

## Integration Points

### For Temporal Workflow Projects

In your Temporal workflow code:

```elixir
defmodule MyWorkflow do
  def run(input) do
    workflow_id = "your-temporal-workflow-uuid"
    
    # Log workflow start
    LogApp.TemporalHelper.log_info(workflow_id, %{"event" => "started"})
    
    # Do your work...
    
    # Log workflow completion
    LogApp.TemporalHelper.log_info(workflow_id, %{"event" => "completed"})
  end
end
```

## Routes

- **GET** `/` - Home page
- **GET** `/logs` - Real-time logs dashboard (LiveView)
- **GET** `/dev/dashboard` - Phoenix LiveDashboard (development only)
- **GET** `/dev/mailbox` - Swoosh Mailbox Preview (development only)

## Troubleshooting

### Database Connection Error
```
role "postgres" does not exist
```

**Solution**: Use your current username (rblren) in database config. ✓ Already configured.

### Port 4000 Already in Use
```bash
# Run on a different port
mix phx.server --port 4001
```

### Oban Jobs Not Processing
Ensure PostgreSQL is running and Oban is properly configured:
```bash
mix phx.server
# Check browser console for any errors
```

## Files Modified/Created

- ✅ mix.exs - Added Oban and Igniter dependencies
- ✅ config/config.exs - Added Oban configuration
- ✅ config/dev.exs - Updated database credentials
- ✅ config/test.exs - Added Oban test config
- ✅ lib/log_app/application.ex - Added Oban supervisor
- ✅ lib/log_app/log.ex - Created schema
- ✅ lib/log_app/logs.ex - Created context
- ✅ lib/log_app/log_worker.ex - Created Oban worker
- ✅ lib/log_app/temporal_helper.ex - Created helper
- ✅ lib/log_app/examples.ex - Created examples
- ✅ lib/log_app_web/live/log_live/index.ex - Created LiveView
- ✅ lib/log_app_web/router.ex - Added /logs route
- ✅ priv/repo/migrations/20260220074336_create_logs.exs - Logs table migration
- ✅ priv/repo/migrations/20260220075000_add_oban.exs - Oban migration
- ✅ LOG_GUIDE.md - Detailed user guide

## Next Steps

1. **Access the Dashboard**: Visit `http://localhost:4000/logs` after starting the server
2. **Test Logging**: Run example log creation from IEx console
3. **Integrate with Temporal**: Add logging calls to your workflow code
4. **Extend**: Add filtering, search, and export features as needed

## Support Resources

- [Phoenix Framework](https://www.phoenixframework.org/)
- [Ecto Documentation](https://hexdocs.pm/ecto/)
- [Oban Documentation](https://hexdocs.pm/oban/)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

---

✨ **Your Phoenix logging application is ready!** ✨
