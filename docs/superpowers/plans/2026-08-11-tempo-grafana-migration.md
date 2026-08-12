# Tempo + Prometheus + Grafana Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the OpenObserve exporter in the otel-collector with Tempo (traces), Prometheus (metrics), and Grafana (dashboards, datasources auto-provisioned), so this sandbox exports to the standard Grafana observability stack instead.

**Architecture:** otel-collector keeps its existing OTLP receivers (4317/4318) unchanged — hooks don't change at all. Only its exporters change: traces go out via `otlp/tempo` to a new `tempo` container (OTLP/gRPC, local-filesystem trace storage on a Docker volume); metrics go out via the collector's built-in `prometheus` exporter (`:8889/metrics`), scraped by a new `prometheus` container. A new `grafana` container gets both wired up as datasources via file-based provisioning — no manual UI setup, no starter dashboard.

**Tech Stack:** `grafana/tempo:latest`, `prom/prometheus:latest`, `grafana/grafana:latest`, docker-compose. No application code changes — this is entirely YAML config + compose wiring.

## Global Constraints

- Full design and rationale: `docs/superpowers/specs/2026-08-11-tempo-grafana-migration-design.md`.
- Replace OpenObserve entirely — do not keep it running alongside Tempo/Prometheus.
- No TLS/auth hardening on any new service — local sandbox only, same posture as the OpenObserve setup it replaces.
- No starter Grafana dashboard — datasources only, dashboards built manually later.
- No logs/Loki — this stack has never handled logs.
- **Each task gets its own local commit on `main`, made by the implementer as part of Subagent-Driven Development's review loop** — nothing is pushed anywhere. This supersedes an earlier draft of this constraint that said not to commit at all; the user explicitly approved per-task local commits when execution mode was chosen, since SDD's diff/review/ledger mechanism requires real commit ranges (BASE/HEAD) to function.
- All verification uses real data through the actual hook library (`lib/common.sh`'s `start_span`/`end_span`/`emit_counter`), not synthetic payloads — this project's established pattern from the OpenObserve proof-of-concept.
- Config file convention: new backend configs live alongside the existing collector config at `.claude/skills/agent-observability/assets/`, matching this project's existing layout.
- One deviation from the design doc's table, decided during planning: Tempo's query port (`3200`) is published to the host (`3200:3200`) rather than left internal-only. The design doc said internal-only, but every verification step needs to query Tempo directly from the host shell, and a read-only local query API carries no meaningful risk. Prometheus (`9090`) and Grafana (`3000`) were already going to be published.

---

### Task 1: Tempo — traces backend

**Files:**
- Create: `.claude/skills/agent-observability/assets/tempo-config.yaml`
- Modify: `.claude/skills/agent-observability/assets/otel-collector-config.yaml`
- Modify: `docker-compose.yaml`
- Delete: `.env`, `.env.example`
- Modify: `.gitignore`

**Interfaces:**
- Produces: a `tempo` service reachable inside the compose network at `tempo:4317` (OTLP/gRPC ingest) and from the host at `http://localhost:3200` (query API). Task 3 (Grafana) consumes `http://tempo:3200` as a datasource URL.
- Consumes: nothing from other tasks.

- [ ] **Step 1: Write the Tempo config**

Create `.claude/skills/agent-observability/assets/tempo-config.yaml`:

```yaml
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317

storage:
  trace:
    backend: local
    local:
      path: /var/tempo/traces
    wal:
      path: /var/tempo/wal

compactor:
  compaction:
    block_retention: 24h
```

- [ ] **Step 2: Add the `tempo` service to docker-compose.yaml**

Add a `tempo` service and a `tempo-data` named volume. Also remove the now-obsolete `OPENOBSERVE_AUTH` environment line from `otel-collector` — the file should read:

```yaml
services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib
    # Configure your collector pipeline as needed.
    ports:
      - "4317:4317"
      - "4318:4318"
    volumes:
         - .claude/skills/agent-observability/assets/otel-collector-config.yaml:/etc/otelcol-contrib/config.yaml

  tempo:
    image: grafana/tempo:latest
    command: ["-config.file=/etc/tempo/tempo-config.yaml"]
    volumes:
      - .claude/skills/agent-observability/assets/tempo-config.yaml:/etc/tempo/tempo-config.yaml
      - tempo-data:/var/tempo
    ports:
      - "3200:3200"

volumes:
  tempo-data:
```

- [ ] **Step 3: Update the collector config's exporters and traces pipeline**

In `.claude/skills/agent-observability/assets/otel-collector-config.yaml`:

1. Delete the entire `otlphttp/openobserve` exporter block (lines 55-61, including its comment).
2. Replace the commented-out `# Uncomment for Grafana Tempo` stub with a live `otlp/tempo` exporter.
3. Change the `traces` pipeline's `exporters` list from `[debug, otlphttp/openobserve]` to `[debug, otlp/tempo]`.
4. Change the `metrics` pipeline's `exporters` list from `[debug, otlphttp/openobserve]` to `[debug]` only, for now — Task 2 adds `prometheus` back to this list. Leaving a dangling reference to a removed exporter would make the collector fail to start, so this intermediate state must be valid on its own.

The exporters and service sections should read:

```yaml
exporters:
  # Always-on: readable in docker logs
  debug:
    verbosity: basic

  # Uncomment for Prometheus scraping
  # prometheus:
  #   endpoint: 0.0.0.0:8889
  #   namespace: agent
  #   resource_to_telemetry_conversion:
  #     enabled: true

  # Uncomment for Jaeger
  # otlp/jaeger:
  #   endpoint: jaeger:4317
  #   tls:
  #     insecure: true

  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true

service:
  telemetry:
    logs:
      level: warn
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, attributes]
      exporters: [debug, otlp/tempo]
    metrics:
      receivers: [otlp]
      processors: [batch, attributes]
      exporters: [debug]
```

- [ ] **Step 4: Delete the now-unused OpenObserve secret files**

```bash
rm /Users/andreaspoldi/my/test-o11y/.env /Users/andreaspoldi/my/test-o11y/.env.example
```

- [ ] **Step 5: Remove the `.env` gitignore entry**

In `.gitignore`, remove the block added for the OpenObserve secret:

```
# Local secrets (OpenObserve basic-auth token, etc). See .env.example.
.env
```

- [ ] **Step 6: Bring the stack up and check for clean startup**

```bash
cd /Users/andreaspoldi/my/test-o11y
docker compose up -d --force-recreate otel-collector tempo
sleep 2
docker logs test-o11y-otel-collector-1 --tail 30
docker logs test-o11y-tempo-1 --tail 30
```

Expected: no `error` level lines in either log. The collector log may show a `deprecated` warning about the `otlphttp` alias like before — that's fine, it's a warning not an error.

- [ ] **Step 7: Emit a real test span through the actual hook lib**

```bash
cd /Users/andreaspoldi/my/test-o11y/.claude/skills/agent-observability/assets
bash -c '
source lib/common.sh
SPAN_FILE=$(mktemp)
start_span "poc.tempo.verify" "$SPAN_FILE" tool_name=PoCTempoVerify
sleep 1
end_span "$SPAN_FILE" OK
echo done
'
sleep 3
```

- [ ] **Step 8: Query Tempo directly to confirm the span landed**

```bash
curl -s -G "http://localhost:3200/api/search" --data-urlencode 'q={ span.tool_name="PoCTempoVerify" }' | python3 -m json.tool
```

Expected: JSON with a non-empty `"traces"` array containing one trace whose `rootServiceName` is `claude-agent`.

---

### Task 2: Prometheus — metrics backend

**Files:**
- Create: `.claude/skills/agent-observability/assets/prometheus.yml`
- Modify: `.claude/skills/agent-observability/assets/otel-collector-config.yaml`
- Modify: `docker-compose.yaml`

**Interfaces:**
- Consumes: the `otel-collector-config.yaml` state left by Task 1 (metrics pipeline currently `exporters: [debug]`).
- Produces: a `prometheus` service reachable from the host at `http://localhost:9090`. Task 3 (Grafana) consumes `http://prometheus:9090` as a datasource URL.

- [ ] **Step 1: Write the Prometheus scrape config**

Create `.claude/skills/agent-observability/assets/prometheus.yml`:

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: otel-collector
    static_configs:
      - targets: ["otel-collector:8889"]
```

- [ ] **Step 2: Add the `prometheus` service and publish the collector's metrics port**

In `docker-compose.yaml`, add `- "8889:8889"` to `otel-collector`'s `ports` list (so the collector's Prometheus-format `/metrics` endpoint is also curl-able from the host during verification), and add a `prometheus` service plus a `prometheus-data` volume:

```yaml
services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib
    # Configure your collector pipeline as needed.
    ports:
      - "4317:4317"
      - "4318:4318"
      - "8889:8889"
    volumes:
         - .claude/skills/agent-observability/assets/otel-collector-config.yaml:/etc/otelcol-contrib/config.yaml

  tempo:
    image: grafana/tempo:latest
    command: ["-config.file=/etc/tempo/tempo-config.yaml"]
    volumes:
      - .claude/skills/agent-observability/assets/tempo-config.yaml:/etc/tempo/tempo-config.yaml
      - tempo-data:/var/tempo
    ports:
      - "3200:3200"

  prometheus:
    image: prom/prometheus:latest
    volumes:
      - .claude/skills/agent-observability/assets/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"

volumes:
  tempo-data:
  prometheus-data:
```

- [ ] **Step 3: Uncomment and wire the collector's `prometheus` exporter**

In `.claude/skills/agent-observability/assets/otel-collector-config.yaml`, uncomment the existing `prometheus` exporter stub and add it to the `metrics` pipeline's exporters:

```yaml
exporters:
  debug:
    verbosity: basic

  prometheus:
    endpoint: 0.0.0.0:8889
    namespace: agent
    resource_to_telemetry_conversion:
      enabled: true

  # Uncomment for Jaeger
  # otlp/jaeger:
  #   endpoint: jaeger:4317
  #   tls:
  #     insecure: true

  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true

service:
  telemetry:
    logs:
      level: warn
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, attributes]
      exporters: [debug, otlp/tempo]
    metrics:
      receivers: [otlp]
      processors: [batch, attributes]
      exporters: [debug, prometheus]
```

- [ ] **Step 4: Bring the stack up and check for clean startup**

```bash
cd /Users/andreaspoldi/my/test-o11y
docker compose up -d --force-recreate otel-collector prometheus
sleep 2
docker logs test-o11y-otel-collector-1 --tail 30
docker logs test-o11y-prometheus-1 --tail 30
```

Expected: no `error` level lines. Prometheus's log should show it loaded the config and is ready to receive web requests.

- [ ] **Step 5: Emit a real test counter through the actual hook lib**

```bash
cd /Users/andreaspoldi/my/test-o11y/.claude/skills/agent-observability/assets
bash -c '
source lib/common.sh
emit_counter "poc.prometheus.verify" 1 tool_name=PoCPromVerify
echo done
'
sleep 20   # give Prometheus one scrape interval to pick it up
```

- [ ] **Step 6: Confirm the collector is exposing it, then confirm Prometheus scraped it**

```bash
echo "--- collector /metrics ---"
curl -s http://localhost:8889/metrics | grep -i poc_prometheus_verify

echo "--- prometheus query ---"
curl -s -G "http://localhost:9090/api/v1/query" --data-urlencode 'query={__name__=~".*poc_prometheus_verify.*"}' | python3 -m json.tool
```

Expected: the first `curl` shows a `agent_poc_prometheus_verify...` line with a `tool_name="PoCPromVerify"` label; the second shows Prometheus's query API returning a non-empty `result` array for that same metric (`"status": "success"`, `"result"` not `[]`).

---

### Task 3: Grafana — dashboards, datasources auto-provisioned

**Files:**
- Create: `.claude/skills/agent-observability/assets/grafana-datasources.yaml`
- Modify: `docker-compose.yaml`

**Interfaces:**
- Consumes: `http://tempo:3200` (Task 1) and `http://prometheus:9090` (Task 2) as datasource URLs — both service names resolve inside the compose network.
- Produces: nothing further tasks depend on — this is the last task.

- [ ] **Step 1: Write the Grafana datasource provisioning file**

Create `.claude/skills/agent-observability/assets/grafana-datasources.yaml`:

```yaml
apiVersion: 1

datasources:
  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    isDefault: false
    editable: false

  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
```

- [ ] **Step 2: Add the `grafana` service to docker-compose.yaml**

```yaml
services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib
    # Configure your collector pipeline as needed.
    ports:
      - "4317:4317"
      - "4318:4318"
      - "8889:8889"
    volumes:
         - .claude/skills/agent-observability/assets/otel-collector-config.yaml:/etc/otelcol-contrib/config.yaml

  tempo:
    image: grafana/tempo:latest
    command: ["-config.file=/etc/tempo/tempo-config.yaml"]
    volumes:
      - .claude/skills/agent-observability/assets/tempo-config.yaml:/etc/tempo/tempo-config.yaml
      - tempo-data:/var/tempo
    ports:
      - "3200:3200"

  prometheus:
    image: prom/prometheus:latest
    volumes:
      - .claude/skills/agent-observability/assets/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    volumes:
      - .claude/skills/agent-observability/assets/grafana-datasources.yaml:/etc/grafana/provisioning/datasources/datasources.yaml
    ports:
      - "3000:3000"

volumes:
  tempo-data:
  prometheus-data:
```

Grafana's default login is `admin` / `admin` (built into the image, no extra env vars needed) — it will prompt for a password change on first UI login, which can be skipped.

- [ ] **Step 3: Bring the full stack up**

```bash
cd /Users/andreaspoldi/my/test-o11y
docker compose up -d --force-recreate
sleep 5
docker logs test-o11y-grafana-1 --tail 40
```

Expected: no `error` level lines; log shows Grafana's HTTP server starting on `:3000`.

- [ ] **Step 4: Confirm Grafana is healthy and both datasources are provisioned**

```bash
echo "--- health ---"
curl -s http://localhost:3000/api/health | python3 -m json.tool

echo "--- datasources ---"
curl -s -u admin:admin http://localhost:3000/api/datasources | python3 -c "
import json, sys
for ds in json.load(sys.stdin):
    print(ds['name'], ds['type'], ds['url'])
"
```

Expected: health returns `\"database\": \"ok\"`; datasources list shows both `Tempo tempo http://tempo:3200` and `Prometheus prometheus http://prometheus:9090`.

- [ ] **Step 5: Full-stack end-to-end proof**

Re-run the same real-hook-lib emission from Tasks 1 and 2 one more time now that all four services are up together, to prove the whole pipeline works as a unit, not just per-task in isolation:

```bash
cd /Users/andreaspoldi/my/test-o11y/.claude/skills/agent-observability/assets
bash -c '
source lib/common.sh
SPAN_FILE=$(mktemp)
start_span "poc.fullstack.verify" "$SPAN_FILE" tool_name=PoCFullStack
sleep 1
end_span "$SPAN_FILE" OK
emit_counter "poc.fullstack.verify" 1 tool_name=PoCFullStack
echo done
'
sleep 20

echo "--- tempo ---"
curl -s -G "http://localhost:3200/api/search" --data-urlencode 'q={ span.tool_name="PoCFullStack" }' | python3 -m json.tool

echo "--- prometheus ---"
curl -s -G "http://localhost:9090/api/v1/query" --data-urlencode 'query={__name__=~".*poc_fullstack_verify.*"}' | python3 -m json.tool
```

Expected: both queries return the test data, confirming the collector → Tempo and collector → Prometheus → Grafana-visible paths all work together.

---

### Task 4: Documentation and task tracking

**Files:**
- Modify: `CLAUDE.md`
- Modify: `TASKS.md`

**Interfaces:**
- Consumes: the finished, verified stack from Tasks 1-3.
- Produces: nothing further tasks depend on.

- [ ] **Step 1: Update CLAUDE.md's architecture constraints**

Add these non-obvious constraints (the OpenObserve exporter was never documented in `CLAUDE.md` in the first place, so this is new content, not a replacement):

Insert after the existing `${OTEL_ENDPOINT}` bullet in the "Architecture constraints" section:

```markdown
- Traces export to Tempo (`otlp/tempo` exporter → `tempo:4317`, OTLP/gRPC, internal
  compose network only). Metrics export to Prometheus via the collector's own
  `prometheus` exporter (`:8889/metrics`), which Prometheus scrapes every 15s —
  metrics do NOT reach Prometheus in real time, allow one scrape interval.
- Grafana's Tempo/Prometheus datasources are provisioned via
  `assets/grafana-datasources.yaml` mounted into
  `/etc/grafana/provisioning/datasources/`. Editing datasource URLs anywhere
  else (e.g. through the Grafana UI) won't survive a container recreate —
  edit that file instead.
- All four services (`otel-collector`, `tempo`, `prometheus`, `grafana`) are
  defined in the one `docker-compose.yaml`; there is no separate compose file
  per service.
```

- [ ] **Step 2: Update CLAUDE.md's stack shorthand**

Change:

```markdown
- Collector: `otel/opentelemetry-collector-contrib` via docker-compose
```

to:

```markdown
- Collector: `otel/opentelemetry-collector-contrib` via docker-compose
- Backends: `grafana/tempo` (traces), `prom/prometheus` (metrics),
  `grafana/grafana` (dashboards) — all via the same docker-compose.yaml
```

- [ ] **Step 3: Update TASKS.md**

Move `T-009` from `backlog`/`pending` to `completed`, matching the existing entries' format (see `T-007`'s completed entry for the pattern this project uses). Update `current_session.status` to `"done"`, and update `_session_note` to summarize: Tempo/Prometheus/Grafana stack replaced OpenObserve, verified end-to-end via real hook-lib span/counter emission queried back from Tempo and Prometheus APIs directly, Grafana datasources confirmed provisioned. Note that T-005 and T-008 remain the top pending backlog items for the next session.

- [ ] **Step 4: Final review of the full diff**

```bash
cd /Users/andreaspoldi/my/test-o11y
git status --short
git diff --stat
```

Confirm the diff only touches the files this plan describes (`otel-collector-config.yaml`, `docker-compose.yaml`, `.gitignore`, `CLAUDE.md`, `TASKS.md`, new `tempo-config.yaml`/`prometheus.yml`/`grafana-datasources.yaml`, deleted `.env`/`.env.example`) plus the already-staged spec doc from brainstorming. Commit this task's changes per the Global Constraints (local commit on `main`, nothing pushed).

- [ ] **Step 5: Tell the user about the orphaned OpenObserve container**

The `openobserve` Docker container from the earlier proof-of-concept was started with a plain `docker run`, not via this repo's `docker-compose.yaml`, so nothing in this plan stops it — it's still running and still holding port 5080. Mention to the user that they can `docker stop openobserve` (and `docker rm` if they want it gone entirely) once they've confirmed the Tempo/Prometheus/Grafana stack covers what they need.
