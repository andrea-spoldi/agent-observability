# Migrate traces/metrics backend from OpenObserve to Tempo + Prometheus + Grafana

## Context

The `agent-observability` skill's otel-collector currently exports traces and
metrics to a local OpenObserve instance (`otlphttp/openobserve` exporter,
started outside this repo via `docker run`). It works and was verified
end-to-end, but the user wants the more standard Grafana ecosystem —
Tempo for traces, Prometheus for metrics, Grafana for dashboards — because
it's a better fit for building dashboards going forward.

## Decision

Replace OpenObserve entirely (not run alongside it). Add three new services
to `docker-compose.yaml`: `tempo`, `prometheus`, `grafana`. The otel-collector
keeps its existing receivers (OTLP gRPC/HTTP on 4317/4318, unchanged — hooks
don't change at all) and swaps its exporters.

## Architecture

```
hooks (otel-cli, curl) → otel-collector:4317/4318
                              ├─ traces  → otlp/tempo exporter → tempo:4317 (OTLP) → local-disk blocks
                              └─ metrics → prometheus exporter → :8889/metrics  ← scraped by prometheus:9090
                                                                                        ↓
                                                                            grafana:3000 (Tempo + Prometheus
                                                                            datasources auto-provisioned)
```

## Components

| Service | Image | Config file | Host port | Purpose |
|---|---|---|---|---|
| `tempo` | `grafana/tempo:latest` | `.claude/skills/agent-observability/assets/tempo-config.yaml` | none (internal only) | Receives OTLP traces from the collector, stores blocks on a named Docker volume (`tempo-data`) using the local-filesystem storage backend |
| `prometheus` | `prom/prometheus:latest` | `.claude/skills/agent-observability/assets/prometheus.yml` | `9090` | Scrapes the collector's `:8889/metrics` on a ~15s interval |
| `grafana` | `grafana/grafana:latest` | `.claude/skills/agent-observability/assets/grafana-datasources.yaml` (provisioning) | `3000` | Dashboards. Default `admin/admin` login. Tempo + Prometheus datasources pre-wired via provisioning — no manual datasource setup. No starter dashboard provisioned; dashboards are built manually in the UI. |

## otel-collector-config.yaml changes

- Remove the `otlphttp/openobserve` exporter block entirely.
- Uncomment and configure the existing `otlp/tempo` exporter stub:
  `endpoint: tempo:4317`, `tls.insecure: true` (internal Docker network, no
  cert needed).
- Uncomment and configure the existing `prometheus` exporter stub:
  `endpoint: 0.0.0.0:8889`.
- Pipeline exporters become `traces: [debug, otlp/tempo]`,
  `metrics: [debug, prometheus]`.

## docker-compose.yaml changes

- Add `tempo`, `prometheus`, `grafana` services as described above.
- Publish `8889` on the `otel-collector` service (for Prometheus to scrape).
- Remove the `OPENOBSERVE_AUTH` environment passthrough on `otel-collector`
  — no longer needed.

## Cleanup

- Delete `.env` and `.env.example` (only ever held `OPENOBSERVE_AUTH`).
- Remove the `.env` gitignore entry added for that secret.
- Update `CLAUDE.md`'s architecture-constraints section: replace the
  OpenObserve-specific notes with the new Tempo/Prometheus/Grafana wiring,
  since that file exists specifically to capture non-obvious constraints
  future sessions need (per its own stated purpose).
- The externally-run `openobserve` Docker container (started via `docker run`,
  not part of this repo's compose file) is left running — not managed by
  this repo, out of scope to stop it. Note for the user to `docker stop
  openobserve` manually if they want to reclaim port 5080.

## Verification plan

1. `docker compose up -d` all services; check logs for clean startup (no
   exporter/config errors) on collector, tempo, prometheus, grafana.
2. Emit a real span + counter through the actual `start_span`/`end_span`/
   `emit_counter` functions in `lib/common.sh` — not synthetic payloads.
3. Query Tempo's HTTP API (`/api/search`) directly to confirm the test trace
   landed.
4. Query Prometheus's HTTP API (`/api/v1/query`) directly to confirm the test
   counter landed.
5. Hit Grafana's `/api/health` and `/api/datasources` to confirm it's up and
   the Tempo + Prometheus datasources are provisioned correctly.

## Out of scope

- Starter/pre-built Grafana dashboards (explicitly declined this round).
- Logs (Loki) — this stack has never handled logs, not adding it now.
- TLS/auth hardening on any of the new services — local sandbox only, same
  posture as the current OpenObserve setup.
