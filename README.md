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
│   └── setup-hosts.sh          # Auto-registers test hosts via Zabbix API on first boot
└── test-servers/
    └── web/
        ├── Dockerfile           # Custom image: Nginx + Zabbix Agent2
        ├── docker-entrypoint.sh # Starts nginx then hands off to the agent entrypoint
        ├── nginx.conf           # Nginx config (exposes /nginx_status for metrics)
        └── html/index.html      # Test web page
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
| `zabbix-init` | alpine:3.19 | Registers test hosts via API on first boot (runs once) |

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

### Start completely fresh

```bash
docker compose down -v   # removes DB volume
docker compose up -d     # full rebuild from scratch
```
