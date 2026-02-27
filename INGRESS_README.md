# LogApp Ingress and Queue

This application exposes an ingestion endpoint on port `4001` and displays logs via LiveView on port `4000`.

## Architecture

- Cowboy ingress receives `POST /logs`
- `LogApp.Ingress.Router` validates JSON payloads
- `LogApp.LogQueue` (GenServer) enqueues and processes logs in FIFO order
- Queue persists to PostgreSQL and broadcasts through PubSub
- Dashboard subscribed to `logs:updates` receives live updates

## Data Flow

External Source → Cowboy Ingress → LogQueue (FIFO) → PostgreSQL (`logs`) → PubSub (`logs:updates`) → LiveView (WebSocket)

## Endpoint

- Method: `POST`
- URL: `http://localhost:4001/logs`
- Required keys: `level`, `workflow_id`, `message`

## Example

```bash
curl -X POST http://localhost:4001/logs \
  -H "Content-Type: application/json" \
  -d '{
    "level": "info",
    "workflow_id": "769241.675049276",
    "message": {
      "message": "Analysing documents in: docs/email-dir/2026-02-24T08-45-25-063574Z"
    }
  }'
```

## HTTP Error Handling

- `400` invalid JSON or missing required fields
- `422` schema validation errors (`level`, `workflow_id`, `message`)
- `503` queue timeout/unavailable
- `500` unexpected internal failures

## Notes

- Queue ordering is guaranteed per node by single-process FIFO handling.
- Ingress does not write directly to the database.
- Persistence and broadcast happen only in `LogApp.LogQueue`.
