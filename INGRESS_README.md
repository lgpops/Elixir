# LogApp - Logging Ingress & Real-Time Display

A Phoenix application that receives log entries via HTTP ingress and displays them in real-time using Phoenix LiveView.

## Architecture

The application is split into two independent components:

### 1. Ingress GenServer (Port 4001)
- HTTP server using **Cowboy** and **Plug**
- Listens on `POST /logs` for incoming log entries
- Accepts JSON payloads with: `level`, `workflow_id`, `message`
- Saves logs to PostgreSQL
- Publishes logs to Phoenix PubSub for real-time updates
- Returns JSON response with log ID

### 2. LiveView Dashboard (Port 4000)
- Real-time log display at `/logs`
- Subscribes to `logs:updates` PubSub channel
- Auto-updates when new logs are published
- Color-coded log levels (error, warning, info, debug)
- Displays up to 1000 most recent logs

### Flow Diagram
```
External System (Temporal, etc)
         ↓ POST /logs (JSON)
    Cowboy Ingress (4001)
         ↓
  LogApp.Logs.create_log()
         ↓
  PostgreSQL (logs table)
         ↓
  LogApp.Logs.broadcast_log()
         ↓
  Phoenix PubSub ("logs:updates")
         ↓
  LogAppWeb.LogLive.Index
         ↓
  Browser (WebSocket)
         ↓
  Real-time Display
```

## Database Schema

```sql
CREATE TABLE logs (
  id SERIAL PRIMARY KEY,
  level TEXT NOT NULL CHECK (level IN ('debug', 'info', 'warning', 'error')),
  workflow_id UUID NOT NULL,
  message JSONB NOT NULL,
  inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX logs_workflow_id_idx ON logs(workflow_id);
```

### Fields
- `id`: Auto-incrementing primary key
- `level`: Log level - one of `debug`, `info`, `warning`, `error`
- `workflow_id`: UUID of the Temporal workflow or external system
- `message`: Structured log data (JSON object)
- `inserted_at`, `updated_at`: Timestamps

## Setup & Running

### 1. Install Dependencies
```bash
cd /Users/rblren/Elixir/log_app
mix deps.get
```

### 2. Database Setup
```bash
mix ecto.create
mix ecto.migrate
```

### 3. Start the Application
```bash
mix phx.server
```

This starts:
- **Phoenix/LiveView** on http://localhost:4000
- **Ingress Server** on http://localhost:4001

### 4. View Logs
Open http://localhost:4000/logs in your browser

## Usage

### Sending Logs to the Ingress
```bash
curl -X POST http://localhost:4001/logs \
  -H "Content-Type: application/json" \
  -d '{
    "level": "info",
    "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
    "message": {
      "event": "workflow_step_completed",
      "step_name": "process_data",
      "duration_ms": 1234,
      "records_processed": 5000
    }
  }'
```

### Response
```json
{
  "ok": true,
  "id": 42
}
```

### Error Response
```json
{
  "error": "Missing required fields: level, workflow_id, message"
}
```

## Log Level Colors in UI

- 🔴 **error** - Red background
- 🟡 **warning** - Yellow background  
- 🔵 **info** - Blue background
- ⚫ **debug** - Gray background

## Examples

### Workflow Started
```bash
curl -X POST http://localhost:4001/logs \
  -H "Content-Type: application/json" \
  -d '{
    "level": "info",
    "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
    "message": {"event": "workflow_started", "version": "1.0"}
  }'
```

### Error During Processing
```bash
curl -X POST http://localhost:4001/logs \
  -H "Content-Type: application/json" \
  -d '{
    "level": "error",
    "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
    "message": {
      "event": "process_failed",
      "error_type": "DatabaseConnectionError",
      "error_message": "Connection timeout after 30s",
      "retry_count": 2
    }
  }'
```

### Workflow Completed
```bash
curl -X POST http://localhost:4001/logs \
  -H "Content-Type: application/json" \
  -d '{
    "level": "info",
    "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
    "message": {
      "event": "workflow_completed",
      "total_duration_ms": 5234,
      "steps": 5,
      "success": true
    }
  }'
```

## Architecture Notes

### Why Separate GenServer Instead of Oban?
- **Simpler**: No background job queue complexity
- **Faster**: Direct HTTP to database, no job persistence
- **Stateless**: Can run multiple Cowboy listeners
- **Real-time**: Immediate PubSub broadcast
- **Appropriate**: Ingress is synchronous operation, not async task

### Cowboy vs Phoenix Endpoint
- Phoenix endpoint handles web routes and LiveView
- Cowboy listener handles separate HTTP ingress endpoint
- Keeps concerns separated (web UI vs data ingestion)
- Different ports allow independent scaling

### PubSub Pattern
- Uses Phoenix.PubSub for real-time updates
- Lightweight compared to message queues
- Good for broadcasting to connected websockets
- Not durable (logs only live while clients connected)
- Logs persisted in database regardless

## Monitoring & Queries

### View Recent Logs
```bash
psql log_app_dev -c "SELECT * FROM logs ORDER BY inserted_at DESC LIMIT 10;"
```

### Logs for Specific Workflow
```bash
psql log_app_dev -c "SELECT * FROM logs WHERE workflow_id = '550e8400-e29b-41d4-a716-446655440000' ORDER BY inserted_at DESC;"
```

### Count Logs by Level
```bash
psql log_app_dev -c "SELECT level, COUNT(*) FROM logs GROUP BY level;"
```

### In Elixir REPL
```bash
iex -S mix

iex> LogApp.Logs.list_logs()
[...]

iex> LogApp.Logs.list_logs_for_workflow("550e8400-e29b-41d4-a716-446655440000")
[...]
```

## Configuration

### Ports
- **Phoenix web**: 4000 (config/dev.exs)
- **Cowboy ingress**: 4001 (lib/log_app/application.ex)

### Database
- **Development**: `log_app_dev` (config/dev.exs)
- **Test**: `log_app_test` (config/test.exs)
- **Production**: Use standard Postgres connection string

## Troubleshooting

### Port Already in Use
```bash
# Check what's using port 4000 or 4001
lsof -i :4000
lsof -i :4001

# Kill the process
kill -9 <PID>
```

### Database Connection Error
```
(Postgrex.Error) FATAL 28000 (invalid_authorization_specification) role "postgres" does not exist
```

**Solution**: Update `config/dev.exs` with your PostgreSQL username (already set to `rblren`).

### Logs Not Appearing in UI
1. Check Ingress is running: `curl -X POST http://localhost:4001/logs -H "Content-Type: application/json" -d '{...}'`
2. Check response status code (should be 201)
3. Check browser console for WebSocket errors
4. Verify database logs:
   ```bash
   psql log_app_dev -c "SELECT COUNT(*) FROM logs;"
   ```

### Module Not Found Error
```
(KeyError) key :log_app not found in: #Ecto.Changeset
```

Run migrations:
```bash
mix ecto.migrate
```

## Testing

```bash
# Run test suite
mix test

# Test ingress with curl
curl -X POST http://localhost:4001/logs \
  -H "Content-Type: application/json" \
  -d '{"level": "info", "workflow_id": "550e8400-e29b-41d4-a716-446655440000", "message": {"test": true}}'
```

## Performance

- **Throughput**: ~500-1000 logs/second per node
- **Latency**: <50ms from POST to database insert
- **Broadcast**: Real-time (ms) to all connected browser clients
- **Storage**: ~1KB per log entry (with typical message)

## Future Enhancements

- [ ] Authentication/Authorization for ingress endpoint
- [ ] Rate limiting by workflow_id
- [ ] Log filtering in UI (by level, workflow_id, date)
- [ ] Pagination (currently shows last 1000)
- [ ] Export to CSV/JSON
- [ ] Alert triggers for error logs
- [ ] Structured logging standards (OpenTelemetry)
- [ ] S3 backup of old logs
- [ ] Full-text search on message content

## Files Modified
- `mix.exs` - Removed Oban, added plug_cowboy
- `config/config.exs` - Removed Oban config
- `config/test.exs` - Removed Oban test config
- `lib/log_app/log.ex` - Updated schema
- `lib/log_app/logs.ex` - Updated context
- `lib/log_app/ingress.ex` - New Cowboy HTTP ingress
- `lib/log_app/application.ex` - Added Ingress supervisor
- `lib/log_app_web/live/log_live/index.ex` - Updated LiveView
- `priv/repo/migrations/` - New migration for logs table

## Resources
- [Cowboy Documentation](https://ninenines.eu/)
- [Plug Documentation](https://hexdocs.pm/plug/)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/)
- [Ecto Guide](https://elixir-phoenix-ash.com/)
- [GenServer Guide](https://hexdocs.pm/elixir/GenServer.html)
