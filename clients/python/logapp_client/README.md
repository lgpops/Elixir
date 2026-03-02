# logapp-client

Python SDK for posting logs into a LogApp ingress endpoint.

## Install (local)

```bash
pip install -e .
```

## Usage

```python
from logapp_client import LogAppClient

client = LogAppClient(base_url="http://localhost:4001")
ok, result = client.send_info(
    "550e8400-e29b-41d4-a716-446655440000",
    "hello from python client",
)
print(ok, result)
```

```python
from logapp_client import send_log

ok, result = send_log(
    "warning",
    "550e8400-e29b-41d4-a716-446655440000",
    {"event": "cpu_spike", "value": 91},
    base_url="http://localhost:4001",
)
print(ok, result)
```
