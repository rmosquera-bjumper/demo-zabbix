# Zabbix Monitoring Lab (Docker Compose)

A beginner-friendly Zabbix lab environment that spins up a full monitoring stack with test targets using a single `docker compose up -d` command.

---

## What is Zabbix?

Zabbix is an open-source **enterprise monitoring platform** that collects, stores, and visualizes metrics from servers, network devices, and applications in real time — and fires alerts when something goes wrong.

```
  Monitored Server              Zabbix
  ┌────────────┐   metrics      ┌─────────────────┐
  │ Zabbix     │ ────────────→  │ Zabbix Server   │
  │ Agent      │                │  (collect/eval) │
  └────────────┘                └────────┬────────┘
                                         │ store
                                ┌────────▼────────┐
                                │   PostgreSQL    │
                                └────────┬────────┘
                                         │
                                ┌────────▼────────┐
                                │  Zabbix Web UI  │
                                │ (graphs/alerts) │
                                └─────────────────┘
```

### Core Components

| Component | Role |
|---|---|
| **Zabbix Server** | The monitoring engine. Receives data from agents, evaluates thresholds, fires alerts |
| **Zabbix Agent** | Lightweight process installed on monitored hosts. Collects CPU, memory, disk, etc. |
| **Zabbix Web UI** | Browser-based management console for graphs, dashboards, and alert configuration |
| **Database** | Stores collected metrics and configuration. This lab uses PostgreSQL |

### Key Concepts

| Term | Meaning |
|---|---|
| **Host** | A single monitored server or device |
| **Item** | Defines *what* to collect (e.g. CPU utilization, free memory) |
| **Trigger** | Alert condition (e.g. "CPU > 90% for 5 minutes → Warning") |
| **Template** | A reusable bundle of items and triggers. Link it to a host and monitoring starts immediately |
| **Host Group** | Logical grouping of hosts (e.g. Web Servers, Linux servers) |

---

## Repository Structure

```
demo-zabbix/
├── docker-compose.yml          # All service definitions
├── .env.example                # Environment variable template
├── init/
│   ├── setup-hosts.sh          # Auto-registers test hosts via Zabbix API on first boot
│   └── setup-streaming.sh      # Simulated sensor hosts + streaming connector (runs every time)
├── simulator/
│   └── simulate.sh             # Pushes sensor readings to Zabbix with zabbix_sender
└── test-servers/
    ├── web/
    │   ├── Dockerfile           # Custom image: Nginx + Zabbix Agent2
    │   ├── docker-entrypoint.sh # Starts nginx then hands off to the agent entrypoint
    │   ├── nginx.conf           # Nginx config (exposes /nginx_status for metrics)
    │   └── html/index.html      # Test web page
    └── stream-receiver/
        ├── Dockerfile           # Diagnostic NDJSON receiver (profile: streaming-test)
        └── receiver.py
```

### Containers

```
                    ┌──────────────────────────────────────┐
                    │         Docker network               │
                    │           zabbix-net                 │
  ┌─────────────────┼──────────────────────────────────────┤
  │                 │                                      │
  │  Monitoring     │  Test targets                        │
  │  ┌───────────┐  │  ┌────────────────────────────────┐  │
  │  │  zabbix   │  │  │ zabbix-agent-server            │  │
  │  │  -server  │◄─┼──│ (monitors the Zabbix Server    │  │
  │  │ :10051    │  │  │  container itself)             │  │
  │  └─────┬─────┘  │  └────────────────────────────────┘  │
  │        │        │  ┌────────────────────────────────┐  │
  │  ┌─────▼─────┐  │  │ test-linux-1                   │  │
  │  │ postgres  │  │  │ (Alpine Linux + Agent2)         │  │
  │  └───────────┘  │  └────────────────────────────────┘  │
  │  ┌───────────┐  │  ┌────────────────────────────────┐  │
  │  │  zabbix   │  │  │ test-linux-2                   │  │
  │  │  -web     │  │  │ (Alpine Linux + Agent2)         │  │
  │  │  :8080    │  │  └────────────────────────────────┘  │
  │  └───────────┘  │  ┌────────────────────────────────┐  │
  │                 │  │ test-web-server                 │  │
  │  ┌───────────┐  │  │ (Nginx + Agent2, port 8081)    │  │
  │  │  zabbix   │  │  └────────────────────────────────┘  │
  │  │  -init    │  │                                      │
  │  │ (once)    │  │                                      │
  │  └───────────┘  │                                      │
  └─────────────────┴──────────────────────────────────────┘
```

| Container | Image | Role |
|---|---|---|
| `zabbix-postgres` | postgres:16-alpine | Database for Zabbix config and metrics |
| `zabbix-server` | zabbix-server-pgsql:7.0 | Monitoring engine |
| `zabbix-web` | zabbix-web-nginx-pgsql:7.0 | Web UI (port 8080) |
| `zabbix-agent-server` | zabbix-agent2:7.0 | Agent monitoring the Zabbix Server container itself |
| `test-linux-1` | zabbix-agent2:7.0 | Test Linux server #1 |
| `test-linux-2` | zabbix-agent2:7.0 | Test Linux server #2 |
| `test-web-server` | custom build | Nginx + Zabbix Agent2, exposes port 8081 |
| `zabbix-init` | alpine:3.19 | Registers test hosts via API on first boot, syncs simulated sensors and the streaming connector (exits after setup) |
| `sensor-simulator` | zabbix-agent2:7.0 | Sends temperature, voltage and humidity for `sim-sensor-01..05` to trapper items |
| `stream-receiver` | custom build | Diagnostic streaming receiver, port 8090. **Only with `--profile streaming-test`** |

### Applied Templates

| Host | Template | Monitors |
|---|---|---|
| Zabbix Server | Linux by Zabbix agent | CPU, memory, disk, process count, etc. |
| Test Linux Server 1, 2 | Linux by Zabbix agent | Same as above |
| Test Web Server | Linux by Zabbix agent + Nginx by Zabbix agent | Linux metrics + Nginx request rate, connections |

---

## Getting Started

### Prerequisites

- Docker Desktop or Docker Engine installed

### 1. Configure environment

```bash
cp .env.example .env
```

The default values work as-is for local testing.

### 2. Start

```bash
docker compose up -d
```

On first run, startup takes **3–5 minutes** in this order:

1. `postgres` starts and initializes the database
2. `zabbix-server` and `zabbix-web` start
3. Wait for `zabbix-web` health check to pass (up to 2.5 minutes)
4. `zabbix-init` calls the Zabbix API to auto-register all test hosts

### 3. Check status

```bash
docker compose ps
```

All containers should show `Up` (except `zabbix-init` which exits with code 0 after setup).

```bash
# Follow logs
docker compose logs -f zabbix-init    # host registration progress
docker compose logs -f zabbix-server  # monitoring engine logs
```

### 4. Access

| URL | Description |
|---|---|
| http://localhost:8080 | Zabbix Web UI |
| http://localhost:8081 | Test Nginx web server |

**Credentials:** `Admin` / `zabbix`

### 5. Stop / Reset

```bash
# Stop (data preserved)
docker compose down

# Stop and wipe all data (including DB volume)
docker compose down -v
```

---

## Exploring the UI

### Check host availability

**Monitoring → Hosts** shows all registered hosts.

- **ZBX** badge green → agent is reachable and reporting
- **ZBX** badge red → agent unreachable (may take 1–2 minutes after startup to go green)

### View collected metrics

Click a host name → **Latest data** to see all currently collected metrics.

```
Example: test-linux-1 Latest data
  CPU utilization          0.42 %
  Available memory         891.12 MB
  Total memory             1 GB
  Number of running processes  12
  ...
```

### View graphs

**Monitoring → Hosts** → click **Graphs** next to a host name.

### View active alerts

**Monitoring → Problems** shows currently firing alerts. Default templates include triggers for:

- Agent unreachable
- High CPU or low memory
- Zombie processes detected
- Nginx not responding

---

## Testing Scenarios

### Test 1: Trigger an alert by stopping an agent

```bash
# Stop the agent
docker compose stop test-linux-1

# Check Monitoring → Problems (alert appears within ~1–2 minutes)

# Recover
docker compose start test-linux-1
```

### Test 2: Generate CPU load and watch it in graphs

```bash
docker exec test-linux-2 sh -c "
  for i in 1 2 3 4; do yes > /dev/null & done
  sleep 60
  kill \$(jobs -p)
"
```

Go to **Monitoring → Hosts → test-linux-2 → Graphs → CPU utilization** to see the spike.

### Test 3: Drive Nginx request metrics

```bash
for i in $(seq 1 50); do curl -s http://localhost:8081 > /dev/null; done
```

Check **Monitoring → Hosts → Test Web Server (Nginx) → Latest data** for `nginx.requests.total.rate`.

### Test 4: Use the Zabbix API directly

Zabbix exposes a full JSON-RPC API for all operations.

```bash
# Check API version (no auth required)
curl -s -X POST http://localhost:8080/api_jsonrpc.php \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"apiinfo.version","params":[],"id":1}' | jq .

# Login and list hosts
TOKEN=$(curl -s -X POST http://localhost:8080/api_jsonrpc.php \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"user.login","params":{"username":"Admin","password":"zabbix"},"id":1}' \
  | jq -r '.result')

curl -s -X POST http://localhost:8080/api_jsonrpc.php \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{"jsonrpc":"2.0","method":"host.get","params":{"output":["host","name"]},"id":1}' \
  | jq '.result[] | {host, name}'
```

---

## Zabbix Configuration Basics

### How templates work

A template bundles items (what to collect) and triggers (when to alert). Linking a template to a host instantly activates all its monitoring definitions.

```
Template: "Linux by Zabbix agent"
  ├── Item: CPU utilization       (collected every 30s)
  ├── Item: Available memory      (collected every 1m)
  ├── Item: Disk read rate        (collected every 1m)
  ├── Trigger: CPU > 90% (5 min avg) → Warning
  ├── Trigger: Free memory < 20%     → Average
  └── Graph: CPU usage
```

### Add a host manually

1. **Configuration → Hosts → Create host**
2. Set `Host name` (must match the agent's `ZBX_HOSTNAME`)
3. Under `Interfaces`, add the agent's DNS name and port `10050`
4. On the `Templates` tab, link `Linux by Zabbix agent`
5. Click `Add`

### Send alerts to Slack or email

1. **Administration → Media types** — configure notification channel (e.g. Slack webhook)
2. **Administration → Users → Admin → Media** — attach the channel to a user
3. **Configuration → Actions → Trigger actions** — define which conditions trigger notifications

---

## Metrics Streaming

Zabbix 7.0 can push collected item values in real time to an external HTTP endpoint through
**connectors**. This lab wires the full flow:

```
sensor-simulator ──zabbix_sender──► zabbix-server ──connector (HTTP POST, NDJSON)──► consumer
                                         │                                          (stream-receiver
                                         └── only items tagged stream=demo           or your app)
```

References for the deployed version (7.0 LTS covers everything needed; no upgrade to 8.0):

- [Streaming to external systems](https://www.zabbix.com/documentation/7.0/en/manual/config/export/streaming)
- [Real-time export protocol](https://www.zabbix.com/documentation/7.0/en/manual/appendix/protocols/real_time_export)
- [Connector API object](https://www.zabbix.com/documentation/7.0/en/manual/api/reference/connector/object)

### What gets exported

`setup-streaming.sh` creates the group **Simulated Sensors** with hosts `sim-sensor-01` … `sim-sensor-05`,
each with three trapper items fed by `sensor-simulator`:

| Item key | Name | Item tag | Streamed |
|---|---|---|---|
| `sim.temperature` | Temperature | `stream=demo` | Yes |
| `sim.voltage` | Voltage | `stream=demo` | Yes |
| `sim.humidity` | Humidity | — | No (proves the filter works) |

Metrics from the agent hosts (`test-linux-*`, `test-web-server`, Zabbix server) carry no `stream=demo` tag and
are never streamed.

The managed connector is named **`demo-zabbix-streaming`**:

| Connector setting | Value |
|---|---|
| Data type | Item values (no events) |
| Type of information | Numeric (float) |
| Tag filter | `stream` Equals `demo` |
| Concurrent sessions | 1 |
| HTTP authentication | Bearer if `STREAMING_BEARER_TOKEN` is set, otherwise None |

### Configuration variables

Set them in `.env` or in the shell.

| Variable | Default | Read by | Purpose |
|---|---|---|---|
| `ZBX_STARTCONNECTORS` | `1` | Zabbix Server image | Writes `StartConnectors`. Must be ≥ the connector's concurrent sessions. Needs `docker compose up -d zabbix-server` to apply |
| `ZBX_CACHEUPDATEFREQUENCY` | `10` | Zabbix Server image | Seconds between configuration cache reloads |
| `STREAMING_ENABLED` | `false` | `setup-streaming.sh` | `true` creates/updates the connector; `false` disables it if it exists |
| `STREAMING_URL` | — | `setup-streaming.sh` | Full receiver URL. Required (`http(s)://host…`) when enabled; otherwise init exits with code 2 and changes nothing |
| `STREAMING_BEARER_TOKEN` | — | `setup-streaming.sh` | Optional bearer token |
| `RECEIVER_LOG_RAW` | `false` | `stream-receiver` | Log the raw request body |

**`STREAMING_*` are not Zabbix variables.** They belong to our initializer, which translates them into the
connector configuration through the Zabbix API (`connector.create` / `connector.update`).

The initializer is idempotent: it looks the connector up by name, so re-running it never creates a duplicate.
It only touches `demo-zabbix-streaming`; any other connector is left alone. Tokens are never printed
(logs only show `bearer: yes/no`) and must never be committed (`.env` is git-ignored).

### Verify the server configuration

```bash
docker exec zabbix-server grep -E '^(StartConnectors|CacheUpdateFrequency)' /etc/zabbix/zabbix_server.conf
# StartConnectors=1
# CacheUpdateFrequency=10

docker compose logs zabbix-server | grep connector
# ... started [connector manager #1]
# ... started [connector worker #1]
```

### Test with the diagnostic receiver

One command enables the profile, enables streaming, points the connector to the receiver and re-runs the
initializer (`--force-recreate` is needed because `zabbix-init` has already exited):

```bash
STREAMING_ENABLED=true \
STREAMING_URL=http://stream-receiver:8090/v1/history \
docker compose --profile streaming-test up -d --build --force-recreate zabbix-init stream-receiver

docker compose logs -f stream-receiver
# sim-sensor-01 | Temperature | 23.97 | clock=... | itemid=... | tags=stream=demo
# sim-sensor-01 | Voltage | 234.5 | clock=... | itemid=... | tags=stream=demo
# ...
# POST /v1/history: 10 records        ← 5 hosts × 2 metrics, no Humidity
```

- With a token: add `STREAMING_BEARER_TOKEN=...`. The receiver then requires it (401 otherwise).
- Raw bodies: add `RECEIVER_LOG_RAW=true`.
- Filter check: `docker compose logs stream-receiver | grep -c Humidity` → `0`.

The receiver only ever gets data from Zabbix's native streaming; the simulator talks to `zabbix-server` only.

### Propagation delay

A created or modified connector takes effect on the next configuration cache reload
(`CacheUpdateFrequency`, 10 s here). To apply it immediately:

```bash
docker exec zabbix-server zabbix_server -R config_cache_reload
```

Until then the previous settings are used. For example, right after adding a token the receiver may reject a
request with 401, and Zabbix does not retry 401.

### Network targets

The URL is resolved **from inside the `zabbix-server` container**:

- **`localhost` is the Zabbix Server container itself**, not your machine nor another container. Don't use it.
- **Receiver in this Compose project**: use the service name, e.g. `http://stream-receiver:8090/v1/history`.
  A container from another project must join the `demo-zabbix_zabbix-net` network.
- **App on the Docker host**: `http://host.docker.internal:<port>/<path>`.
  - Docker Desktop (macOS/Windows): works out of the box.
  - Linux: needs `extra_hosts: ["host.docker.internal:host-gateway"]` on `zabbix-server` (already in
    `docker-compose.yml`). The app must listen on an interface reachable from the Docker bridge
    (e.g. `0.0.0.0`, not only `127.0.0.1`) and the firewall must allow it.

### Receiver contract

What a consumer must accept (Zabbix streaming protocol v1.0, item values):

- `POST` to the configured URL (used as-is; the docs name it `/v1/history` for item values).
- `Content-Type: application/x-ndjson`.
- `Authorization: Bearer <token>` when a token is configured.
- Body: **several JSON objects separated by newlines** in a single request. **It is not a JSON array.**
- Response: Zabbix treats 200–204 as success; the test receiver answers `200 {"response":"success"}`.
  Errors should be 4xx with `{"error":"..."}`. Zabbix does **not** retry 400, 401, 403, 404, 405, 415 or 422
  (that data is dropped); other codes and network errors are retried up to *Attempts* (1 here).

Real payload captured in this lab (Zabbix 7.0.31, `RECEIVER_LOG_RAW=true`), one request:

```
{"host":{"host":"sim-sensor-01","name":"sim-sensor-01"},"groups":["Simulated Sensors"],"item_tags":[{"tag":"stream","value":"demo"}],"itemid":50740,"name":"Temperature","clock":1792498160,"ns":102386377,"value":23.97,"type":0}
{"host":{"host":"sim-sensor-01","name":"sim-sensor-01"},"groups":["Simulated Sensors"],"item_tags":[{"tag":"stream","value":"demo"}],"itemid":50741,"name":"Voltage","clock":1792498160,"ns":102406460,"value":234.5,"type":0}
```

| Field | Type | Content |
|---|---|---|
| `host.host` / `host.name` | string | Technical / visible host name |
| `groups` | string array | Host groups |
| `item_tags` | array of `{tag, value}` | Item tags (may be empty) |
| `itemid` | number | Item ID |
| `name` | string | Visible item name |
| `clock` / `ns` | number | Value timestamp (epoch seconds + nanoseconds) |
| `value` | number or string | Collected value |
| `type` | number | Value type: 0 float, 1 character, 2 log, 3 unsigned, 4 text, 5 binary |

**The item key (`sim.temperature`) and units (`°C`, `V`) are not sent.** Consumers must identify metrics by
`itemid` or `name`, or rely on extra item tags, which do travel in `item_tags`.

### Switch to the real consumer

1. Edit `.env`:
   ```
   STREAMING_ENABLED=true
   STREAMING_URL=https://consumer.example.com/zabbix/history
   STREAMING_BEARER_TOKEN=<real token, never committed>
   ```
2. Re-run the initializer. This works even if its container already exited successfully:
   ```bash
   docker compose run --rm zabbix-init
   # or: docker compose up -d --force-recreate zabbix-init
   ```
3. Wait for the cache reload or force it with `config_cache_reload`.
4. Stop the diagnostic receiver if no longer needed: `docker compose --profile streaming-test stop stream-receiver`.

To turn streaming off, set `STREAMING_ENABLED=false` and repeat step 2. The connector is disabled, not deleted.

---

## Troubleshooting

### ZBX badge stays red

The server cannot reach the agent.

```bash
# Check agent logs
docker compose logs test-linux-1

# Test connectivity from the server container
docker exec zabbix-server sh -c "nc -zv test-linux-1 10050"
```

### zabbix-init failed to register hosts

The init container runs once automatically, but can be re-run manually:

```bash
docker compose run --rm zabbix-init sh /init/setup-hosts.sh
```

### Stream receiver gets nothing

```bash
docker compose logs zabbix-init | tail -5               # connector created/updated? URL valid?
docker compose logs zabbix-server | grep -i connector   # connector worker started? send errors?
docker exec zabbix-server zabbix_server -R config_cache_reload
```

### Start completely fresh

```bash
docker compose --profile streaming-test down -v   # removes DB volume (and the receiver, if running)
docker compose up -d                              # full rebuild from scratch
```
