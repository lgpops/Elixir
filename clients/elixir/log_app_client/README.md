# log_app_client

Elixir SDK for posting logs into a LogApp ingress endpoint.

## Installation

Add to your dependencies:

```elixir
def deps do
  [
    {:log_app_client, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
client = LogAppClient.new(base_url: "http://localhost:4001")

LogAppClient.send_info(
  client,
  "550e8400-e29b-41d4-a716-446655440000",
  "hello from elixir client"
)

LogAppClient.send_log(
  client,
  "warning",
  "550e8400-e29b-41d4-a716-446655440000",
  %{"event" => "rate_spike", "value" => 42}
)
```
