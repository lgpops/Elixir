from __future__ import annotations

import json
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Dict, Tuple

Result = Tuple[bool, Dict[str, Any]]


@dataclass
class LogAppClient:
    base_url: str = "http://localhost:4001"
    timeout: float = 5.0
    headers: Dict[str, str] = field(default_factory=dict)

    def send_info(self, workflow_id: str, text_message: str) -> Result:
        return self.send_log("info", workflow_id, {"message": text_message})

    def send_log(self, level: str, workflow_id: str, message: Dict[str, Any]) -> Result:
        payload = {
            "level": level,
            "workflow_id": workflow_id,
            "message": message,
        }

        data = json.dumps(payload).encode("utf-8")
        url = f"{self.base_url.rstrip('/')}/logs"

        request_headers = {"Content-Type": "application/json", **self.headers}

        request = urllib.request.Request(url=url, data=data, method="POST", headers=request_headers)

        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                body = response.read().decode("utf-8")
                parsed = json.loads(body) if body else {}
                return True, parsed
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8") if error.fp else ""
            try:
                parsed = json.loads(body) if body else {}
            except json.JSONDecodeError:
                parsed = {"raw": body}
            return False, {"status": error.code, "body": parsed}
        except urllib.error.URLError as error:
            return False, {"error": str(error.reason)}


def send_info(workflow_id: str, text_message: str, base_url: str = "http://localhost:4001") -> Result:
    client = LogAppClient(base_url=base_url)
    return client.send_info(workflow_id, text_message)


def send_log(
    level: str,
    workflow_id: str,
    message: Dict[str, Any],
    base_url: str = "http://localhost:4001",
) -> Result:
    client = LogAppClient(base_url=base_url)
    return client.send_log(level, workflow_id, message)
