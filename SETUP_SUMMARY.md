# Phoenix Log Application - Setup Summary

Real-time logging app with:

- Phoenix + LiveView UI on port `4000`
- Cowboy ingress on port `4001` (`POST /logs`)
- Ordered GenServer queue (`LogApp.LogQueue`)
- PostgreSQL persistence (`logs` table)
- Phoenix PubSub broadcast (`logs:updates`)

## Runtime Flow

1. Client posts JSON to `http://localhost:4001/logs`
2. `LogApp.Ingress.Router` validates payload and enqueues log
3. `LogApp.LogQueue` processes entries FIFO
4. Queue writes via `LogApp.Logs.create_log/1`
5. Queue broadcasts `log_created` via `LogApp.Logs.broadcast_log/1`
6. LiveView updates connected dashboards over WebSocket

## Required Payload

```json
{
  "level": "info",
  "workflow_id": "769241.675049276",
  "message": {"event": "example"}
}
```

`level` must be one of: `debug`, `info`, `warning`, `error`.

## Response Codes

- `201` success
- `400` invalid JSON or missing required fields
- `422` payload fails schema validation
- `503` queue unavailable or timed out
- `500` unexpected internal error

## Start Commands

```bash
cd /Users/rblren/Elixir
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
```

Open `http://localhost:4000/logs`.

## Example Request

```bash
curl -X POST http://localhost:4001/logs \
  -H "Content-Type: application/json" \
  -d '{
    "level": "info",
    "workflow_id": "769241.675049276",
    "message": {"message": "Analysing documents"}
  }'
```

## Key Modules

- `LogApp.Ingress.Router` - HTTP parsing + enqueue
- `LogApp.LogQueue` - ordered queue processor
- `LogApp.Logs` - DB writes + PubSub broadcast
- `LogAppWeb.LogLive.Index` - real-time dashboard
