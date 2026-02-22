# Log Application - User Guide

This is a Phoenix application that logs information to a PostgreSQL database and displays logs in real-time using Phoenix LiveView and Oban job processing.

## Architecture

### Core Components

1. **Logs Table**: PostgreSQL table with the following structure:
   - `id`: Auto-incrementing primary key
   - `level`: String field for the log level (e.g., "info", "error", "warning")
   - `job_id`: UUID field linked to Temporal workflow (indexed for fast retrieval)
   - `detail`: JSONB field for semi-structured data
   - `inserted_at`, `updated_at`: Timestamps

2. **Oban Worker**: `LogApp.LogWorker` processes messages enqueued by Temporal workflows
   - Accepts log messages with level, job_id, and detail
   - Creates log entries in the database
   - Broadcasts updates to connected LiveView clients

3. **LiveView Dashboard**: `/logs` displays all logs in real-time
   - Shows logs in a table format
   - Auto-updates when new logs arrive
   - Supports filtering and searching (can be extended)

## How to Use

### 1. Starting the Application

```bash
cd /Users/rblren/Elixir/log_app
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
```

The server will start on `http://localhost:4000`

### 2. Accessing the Logs Dashboard

Navigate to `http://localhost:4000/logs` to see the real-time logs display.

### 3. Sending Logs from Temporal Workflows

To send logs from your Temporal workflow, enqueue a job to the Oban default queue:

```elixir
# In your Temporal workflow or any part of your application
LogApp.LogWorker.new(%{
  "level" => "info",
  "job_id" => "550e8400-e29b-41d4-a716-446655440000",
  "detail" => %{
    "message" => "Workflow step completed",
    "duration_ms" => 1234,
    "status" => "success"
  }
})
|> Oban.insert!()
```

### 4. LogWorker Interface

The `LogWorker` expects job arguments in the following format:

```elixir
%{
  "level" => "string",      # Log level (info, error, warning, debug, etc.)
  "job_id" => "uuid-string", # UUID of the Temporal workflow
  "detail" => %{...}         # Optional JSONB data (map)
}
```

### 5. Example Log Entries

**Info level log:**
```elixir
LogApp.LogWorker.new(%{
  "level" => "info",
  "job_id" => "550e8400-e29b-41d4-a716-446655440000",
  "detail" => %{"message" => "Operation started"}
})
|> Oban.insert!()
```

**Error log with details:**
```elixir
LogApp.LogWorker.new(%{
  "level" => "error",
  "job_id" => "550e8400-e29b-41d4-a716-446655440001",
  "detail" => %{
    "error" => "Network timeout",
    "retry_count" => 3,
    "next_retry_at" => DateTime.utc_now()
  }
})
|> Oban.insert!()
```

## Database Schema

### logs table

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | bigint | No | Primary key, auto-increment |
| level | varchar | No | Log level string |
| job_id | uuid | No | Temporal workflow UUID (indexed) |
| detail | jsonb | Yes | Semi-structured log data |
| inserted_at | timestamp | No | Creation timestamp (UTC) |
| updated_at | timestamp | No | Update timestamp (UTC) |

**Indexes:**
- Primary key on `id`
- Index on `job_id` for fast workflow-based log retrieval

### oban_jobs table (for Oban)

Managed by Oban for job queue management. See Oban documentation for details.

## Configuration

### Development Configuration (`config/dev.exs`)

```elixir
config :log_app, LogApp.Repo,
  username: "rblren",        # Current user
  password: "",              # No password needed for local dev
  hostname: "localhost",
  database: "log_app_dev",
  pool_size: 10
```

### Oban Configuration (`config/config.exs`)

```elixir
config :log_app, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10],
  repo: LogApp.Repo
```

## Module Overview

### LogApp.Log (Schema)
Ecto schema for the logs table with validation.

### LogApp.Logs (Context)
Business logic for logs:
- `list_logs()`: Retrieve all logs ordered by newest first
- `get_log!(id)`: Get a single log by ID
- `create_log(attrs)`: Create a new log entry
- `create_log_notification(log)`: Broadcast log to connected clients

### LogApp.LogWorker (Oban Worker)
Processes incoming log messages from the Oban queue:
- Transforms queue arguments into log entries
- Inserts logs into the database
- Broadcasts updates to LiveView clients

### LogAppWeb.LogLive.Index (LiveView)
Real-time logs dashboard:
- Subscribes to `logs:updates` channel
- Displays logs in a table
- Auto-updates when new logs arrive

## Real-Time Updates

The application uses Phoenix PubSub for real-time updates:

1. When a log is created by the LogWorker, it broadcasts to the `logs:updates` channel
2. All connected LiveView clients receive the broadcast
3. The logs list is updated in real-time on connected browsers

## Future Enhancements

- Add filtering by log level
- Add search by job_id
- Add pagination for large log volumes
- Add export functionality (CSV, JSON)
- Add log retention policies
- Add aggregations and statistics dashboard
- Add log detail view with expanded information

## Development Notes

- All timestamps are in UTC
- job_id should be a valid UUID
- detail field accepts any JSON-serializable map
- Oban is configured to use PostgreSQL notifier for real-time job processing
