"""Diagnostic receiver for Zabbix native streaming (NDJSON over HTTP POST).

Validates every line, logs the received metrics and answers 200 when the whole
request is valid. Only Zabbix Server should send here.
"""

import hmac
import json
import logging
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

logging.basicConfig(level=logging.INFO, format="%(asctime)s [receiver] %(levelname)s %(message)s")
log = logging.getLogger(__name__)

PORT = int(os.environ.get("RECEIVER_PORT", "8090"))
EXPECTED_TOKEN = os.environ.get("RECEIVER_EXPECTED_TOKEN", "").strip()
LOG_RAW = os.environ.get("RECEIVER_LOG_RAW", "").strip().lower() in {"1", "true", "yes", "on"}
REQUIRED_FIELDS = ("host", "itemid", "name", "clock", "value")


def parse_ndjson(body: str) -> list[dict]:
    records = []
    for number, line in enumerate(body.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(f"line {number}: invalid JSON ({exc.msg})") from exc
        if not isinstance(record, dict):
            raise ValueError(f"line {number}: expected a JSON object")
        missing = [field for field in REQUIRED_FIELDS if field not in record]
        if missing:
            raise ValueError(f"line {number}: missing fields {missing}")
        records.append(record)
    return records


class Handler(BaseHTTPRequestHandler):
    def _reply(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:
        if EXPECTED_TOKEN:
            received = self.headers.get("Authorization", "")
            if not hmac.compare_digest(received, f"Bearer {EXPECTED_TOKEN}"):
                log.warning("Rejected: missing or wrong Authorization header")
                self._reply(401, {"error": "unauthorized"})
                return

        content_type = self.headers.get("Content-Type", "")
        if not content_type.startswith("application/x-ndjson"):
            log.warning("Unexpected Content-Type: %r", content_type)

        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        if LOG_RAW:
            log.info("RAW %s (%s):\n%s", self.path, content_type, body)
        try:
            records = parse_ndjson(body)
        except ValueError as exc:
            log.error("Rejected payload on %s: %s", self.path, exc)
            self._reply(422, {"error": str(exc)})
            return

        for record in records:
            host = record["host"].get("host") if isinstance(record["host"], dict) else record["host"]
            tags = ",".join(f"{t.get('tag')}={t.get('value')}" for t in record.get("item_tags", []))
            log.info(
                "%s | %s | %s | clock=%s | itemid=%s | tags=%s",
                host, record["name"], record["value"], record["clock"], record["itemid"], tags,
            )
        log.info("POST %s: %d records", self.path, len(records))
        self._reply(200, {"response": "success"})

    def log_message(self, format: str, *args: object) -> None:
        pass


if __name__ == "__main__":
    log.info("Listening for NDJSON on :%d", PORT)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
