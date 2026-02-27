# Log Application - User Guide

This Phoenix application ingests logs over HTTP, persists them to PostgreSQL, and streams updates to the dashboard via PubSub.

## Ingestion Flow

1. External system sends `POST /logs` to the Cowboy ingress on port `4001`
2. Ingress validates JSON and enqueues into `LogApp.LogQueue` (GenServer)
3. Queue processes requests in FIFO order
4. Queue persists each log to PostgreSQL (`logs` table)
5. Queue broadcasts `log_created` on `logs:updates`
6. LiveView on `/logs` updates in real time over WebSocket

## Payload Shape

```json
{
  "level": "info",
  "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
  "message": {
    "event": "workflow_step_completed"
  }
}
```

## HTTP Responses

- `201` on success: `%{"ok" => true, "id" => log_id}`
- `400` for invalid JSON or missing required fields
- `422` for schema validation errors (invalid level/UUID/message format)
- `503` when queue is unavailable or times out
- `500` for unexpected internal failures

## Start Locally

```bash
cd /Users/rblren/Elixir
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
```

## Notes

- The queue is in-order per node (single GenServer mailbox + FIFO queue)
- Database writes are centralized in `LogApp.LogQueue`, not the Phoenix web layer
- Dashboard reads historical logs and subscribes to PubSub for live updates
