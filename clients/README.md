# LogApp SDKs

This folder contains language-specific client SDKs for posting logs to a LogApp ingress endpoint.

- Elixir: `clients/elixir/log_app_client`
- Python: `clients/python/logapp_client`

## Common payload model

Both SDKs send `POST /logs` with:

- `level` (string) — e.g. `"info"`, `"warning"`, `"error"`
- `workflow_id` (string UUID)
- `message` (object/map)

## Elixir example

```elixir
client = LogAppClient.new(base_url: "http://localhost:4001")

{:ok, body} =
  LogAppClient.send_info(
    client,
    "550e8400-e29b-41d4-a716-446655440000",
    "hello from elixir sdk"
  )

{:ok, body2} =
  LogAppClient.send_log(
    client,
    "warning",
    "550e8400-e29b-41d4-a716-446655440000",
    %{"event" => "cpu_spike", "value" => 91}
  )
```

## Python example

```python
from logapp_client import LogAppClient

client = LogAppClient(base_url="http://localhost:4001")
ok, body = client.send_info(
    "550e8400-e29b-41d4-a716-446655440000",
    "hello from python sdk",
)

ok2, body2 = client.send_log(
    "warning",
    "550e8400-e29b-41d4-a716-446655440000",
    {"event": "cpu_spike", "value": 91},
)
```

## Notes for this repo

In this development setup, ingress may run over a Unix socket instead of TCP `:4001` depending on your config. If so, the in-app Elixir helper (`LogApp.send_info/2` and `LogApp.send_log/3`) is the easiest local option.
