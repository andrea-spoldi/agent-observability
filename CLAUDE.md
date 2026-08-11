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

## Intentional decisions
- Hooks degrade gracefully: if the collector is unreachable, they still log to
  `${OTEL_SESSION_DIR:-/tmp/agent-otel-session}/` instead of failing the tool call.

## Stack shorthand
- Hook scripts: bash, using `jq` + `otel-cli` (traces) + `curl` (metrics, hand-built
  OTLP/HTTP JSON — `otel-cli` has no metrics command)
- Collector: `otel/opentelemetry-collector-contrib` via docker-compose
