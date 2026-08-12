# test-o11y

OTEL observability sandbox for Claude Code: instruments hooks (PreToolUse,
PostToolUse, Stop) via the `agent-observability` skill to emit tool-call
metrics/traces to a local otel-collector.

## Architecture constraints
- Hook scripts live in `.claude/skills/agent-observability/assets/hooks/` — do not
  duplicate them, reference by absolute path.
- Hooks are registered in `.claude/settings.json` under the `hooks` key (each entry
  needs `{"hooks": [{"type": "command", "command": "..."}]}`). Claude Code does NOT
  read a standalone `hooks.json` file — `assets/hooks.json` is only a reference
  template; keeping it in sync with `settings.json` is manual.
- `${OTEL_ENDPOINT}` must be the OTLP/**HTTP** port (4318), not the gRPC-only port
  4317 — both traces (`otel-cli`, which picks protocol from the `http://` scheme)
  and metrics (`curl`, posted directly to `${OTEL_ENDPOINT}/v1/metrics`) depend on
  this. Sending either to 4317 silently sends nothing.
- The otel-collector config path is fixed in `docker-compose.yaml`; if the collector
  config moves, update the volume mount there too.
- Traces export to Tempo (`otlp/tempo` exporter → `tempo:4317`, OTLP/gRPC, internal
  compose network only). Metrics export to Prometheus via the collector's own
  `prometheus` exporter (`:8889/metrics`), which Prometheus scrapes every 15s —
  metrics do NOT reach Prometheus in real time, allow one scrape interval.
- Grafana's Tempo/Prometheus datasources are provisioned via
  `assets/grafana-datasources.yaml` mounted into
  `/etc/grafana/provisioning/datasources/`. Editing datasource URLs anywhere
  else (e.g. through the Grafana UI) won't survive a container recreate —
  edit that file instead. Datasource `uid`s (`tempo`, `prometheus`) are
  pinned in that file and referenced by `uid` from dashboard JSON — don't
  remove them, dashboards would stop resolving their datasource.
- Dashboards are provisioned the same way: `assets/dashboards/*.json` +
  `assets/grafana-dashboards-provider.yaml`, mounted into
  `/etc/grafana/provisioning/dashboards/`. Edit the JSON files, not the
  Grafana UI.
- All four services (`otel-collector`, `tempo`, `prometheus`, `grafana`) are
  defined in the one `docker-compose.yaml`; there is no separate compose file
  per service.

## Intentional decisions
- Hooks degrade gracefully: if the collector is unreachable, they still log to
  `${OTEL_SESSION_DIR:-/tmp/agent-otel-session}/` instead of failing the tool call.

## Stack shorthand
- Hook scripts: bash, using `jq` + `otel-cli` (traces) + `curl` (metrics, hand-built
  OTLP/HTTP JSON — `otel-cli` has no metrics command)
- Collector: `otel/opentelemetry-collector-contrib` via docker-compose
- Backends: `grafana/tempo` (traces), `prom/prometheus` (metrics),
  `grafana/grafana` (dashboards) — all via the same docker-compose.yaml
