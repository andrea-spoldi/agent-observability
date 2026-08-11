# agent-observability sandbox

A minimal, working example of instrumenting a [Claude Code](https://claude.com/claude-code)
session with OpenTelemetry: bash hooks open/close a span per tool call, log a
structured JSONL record for post-session analysis, and emit summary metrics
when the session ends — all shipped to a local `otel-collector` over OTLP.

The instrumentation itself lives in `.claude/skills/agent-observability/` as a
Claude Code [skill](https://code.claude.com/docs/en/skills.md); this repo is a
sandbox for exercising it end-to-end.

## Prerequisites

- [Claude Code](https://claude.com/claude-code)
- [Docker](https://www.docker.com/) (for the collector)
- `jq`
- `otel-cli` — `install.sh` below will download it for you if missing

## Quick start

```bash
git clone https://github.com/andrea-spoldi/agent-observability.git
cd agent-observability

# 1. Preflight: checks jq/otel-cli, chmods hook scripts, checks collector reachability
bash .claude/skills/agent-observability/assets/install.sh

# 2. Start the collector (must run from the repo root — the compose file's
#    volume mount is a relative path resolved against it)
docker compose up -d

# 3. Open this repo in Claude Code and use it normally.
#    Hooks are already wired in .claude/settings.json via ${CLAUDE_PROJECT_DIR},
#    so no manual config merge is needed for this repo specifically.
```

Watch it work:

```bash
# Structured per-call log for the current session
cat "${OTEL_SESSION_DIR:-/tmp/agent-otel-session}/session.jsonl"

# What the collector actually received (debug exporter logs to stdout)
docker compose logs -f otel-collector
```

At session end, `stop.sh` analyzes `session.jsonl` for tool-call quality
signals (duplicate calls, retry switches, consecutive errors), emits summary
metrics, archives the log to `${OTEL_SESSION_DIR}/archive/`, and resets state
for the next session.

## How the hooks are wired

Claude Code reads hook configuration from `.claude/settings.json` under a
`"hooks"` key — **not** from a standalone `.claude/hooks.json` file, which it
never reads. This repo's `.claude/settings.json` already has the three hooks
(`PreToolUse`, `PostToolUse`, `Stop`) registered, using the
`${CLAUDE_PROJECT_DIR}` variable Claude Code sets for every hook invocation so
the config works unmodified regardless of where you clone the repo.

`.claude/skills/agent-observability/assets/hooks.json` is a portable copy of
that same config, kept as the reference template for wiring this skill into a
*different* project — see the skill's `SKILL.md` for the adoption steps.

## Architecture

```
Claude Code tool call
   │
   ├─ PreToolUse  → pre_tool_use.sh   opens an OTEL span (keyed by tool_use_id),
   │                                   flags suspicious/empty/null params
   │
   ├─ (tool runs)
   │
   ├─ PostToolUse → post_tool_use.sh  closes the span, emits a call.total
   │                                   counter, appends a record to session.jsonl
   │
   └─ Stop        → stop.sh           analyzes session.jsonl, emits summary
                                        counters, archives + resets state
```

Traces and counters both go out via `otel-cli`, which only has a `span`
subcommand (no native metrics command) — counters are encoded as
attribute-tagged spans named `metric.<name>` rather than true OTLP metric data
points. See `assets/references/metrics-dictionary.md` for the full metric
catalogue and rationale.

## Known limitations

- `stop.sh`'s read-before-write violation check compares tool names against
  `bash_tool` / `view` / `create_file` / `str_replace`, which don't match
  Claude Code's actual tool names (`Bash`, `Read`, `Edit`, `Write`) — it can
  never fire as currently written. Tracked in `TASKS.md` as T-005.
- Metrics are simulated as spans (see Architecture above) due to `otel-cli`
  not exposing a metrics API.

## Project history

`TASKS.md` has the full backlog and a decision log (`D-001`…`D-006`) covering
every bug found while getting this working — several are non-obvious
environment quirks (BSD `date` vs GNU `date`, `otel-cli`'s HTTP-vs-gRPC port
selection, Claude Code's actual hook payload field names) worth reading before
changing the hook scripts.
