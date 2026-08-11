# test-o11y

OTEL observability sandbox for Claude Code: instruments hooks (PreToolUse,
PostToolUse, Stop) via the `agent-observability` skill to emit tool-call
metrics/traces to a local otel-collector.

## Architecture constraints
- Hook scripts live in `.claude/skills/agent-observability/assets/hooks/` — do not
  duplicate them, reference by absolute path.
- Hooks are registered in `.claude/settings.json` under the `hooks` key (each entry
  needs `{"hooks": [{"type": "command", "command": "..."}]}`). `.claude/hooks.json`
  is NOT read by Claude Code — it's an inert template; keeping it in sync with
  settings.json is manual.
- otel-cli's `--endpoint` scheme picks the protocol: `http://` selects OTLP/HTTP,
  which must target port 4318, not the gRPC port 4317 — `http://localhost:4317`
  silently sends nothing (otel-cli errors are swallowed unless `--verbose --fail`).
- The otel-collector config path is fixed in `docker-compose.yaml`; if the collector
  config moves, update the volume mount there too.

## Intentional decisions
- Hooks degrade gracefully: if the collector is unreachable, they still log to
  `${OTEL_SESSION_DIR:-/tmp/agent-otel-session}/` instead of failing the tool call.

## Stack shorthand
- Hook scripts: bash, using `jq` + `otel-cli`
- Collector: `otel/opentelemetry-collector-contrib` via docker-compose
