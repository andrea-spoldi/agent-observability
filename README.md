# agent-observability sandbox

A minimal, working example of instrumenting a [Claude Code](https://claude.com/claude-code)
session with OpenTelemetry: bash hooks open/close a span per tool call, log a
structured JSONL record for post-session analysis, and emit summary metrics
when the session ends — shipped to a local `otel-collector`, then on to
**Tempo** (traces), **Prometheus** (metrics), and **Grafana** (dashboards for
both), all via one `docker-compose.yaml`.

The instrumentation itself lives in `.claude/skills/agent-observability/` as a
Claude Code [skill](https://code.claude.com/docs/en/skills.md); this repo is a
sandbox for exercising it end-to-end.

## Prerequisites

- [Claude Code](https://claude.com/claude-code)
- [Docker](https://www.docker.com/) (for the collector + backends)
- `jq`
- `otel-cli` — `install.sh` below will download it for you if missing

## Quick start

```bash
git clone https://github.com/andrea-spoldi/agent-observability.git
cd agent-observability

# 1. Preflight: checks jq/otel-cli/curl, chmods hook scripts, checks collector reachability
bash .claude/skills/agent-observability/assets/install.sh

# 2. Start the collector + Tempo + Prometheus + Grafana (must run from the
#    repo root — docker-compose.yaml's volume mounts are relative paths
#    resolved against it)
docker compose up -d

# 3. Open this repo in Claude Code and use it normally.
#    Hooks are already wired in .claude/settings.json via ${CLAUDE_PROJECT_DIR},
#    so no manual config merge is needed for this repo specifically.
```

Use Claude Code for a bit — run a few tool calls (`Read`, `Edit`, `Bash`,
invoke a skill, whatever you'd do normally) — then look at the data.

## Viewing the data

**Grafana** (`http://localhost:3000`, default login `admin` / `admin` — you
can skip the forced password-change prompt, it's a local dev-only instance)
has two pre-built dashboards, provisioned automatically:

- **Agent Tool Metrics** — success rate, call volume by tool, error
  breakdown, param-quality issues, duplicate calls, read-before-write
  violations, retry switches, consecutive errors.
- **Agent Tool Traces** — recent traces, error spans, slow (>5s) calls, and a
  session-ID filter to see one session's calls in isolation.

Metrics land in Grafana on a delay: the collector scrapes/exports every 15s
and Prometheus scrapes the collector every 15s on top of that, so allow up to
~30s after a tool call before its metric shows up. Traces appear closer to
real time.

You can also hit the backends directly:

```bash
# Structured per-call log for the current session
cat "${OTEL_SESSION_DIR:-/tmp/agent-otel-session}/session.jsonl"

# What the collector actually received (debug exporter logs to stdout)
docker compose logs -f otel-collector

# Prometheus's own UI/API
open http://localhost:9090

# Tempo's search API directly
curl -s "http://localhost:3200/api/search?limit=5" | jq
```

At session end, `stop.sh` analyzes `session.jsonl` for tool-call quality
signals (duplicate calls, retry switches, consecutive errors, skill
activations), emits summary metrics, archives the log to
`${OTEL_SESSION_DIR}/archive/`, and resets state for the next session.

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

otel-collector
   ├─ traces  → otlp/tempo exporter  → Tempo   (:3200)  → Grafana "Agent Tool Traces"
   └─ metrics → prometheus exporter  → Prometheus (:9090) → Grafana "Agent Tool Metrics"
```

Traces go out via `otel-cli span` (its only relevant subcommand — it has no
metrics API). Counters go out as real OTLP `Sum` metrics (delta temporality)
posted directly to `${OTEL_ENDPOINT}/v1/metrics` as OTLP/HTTP JSON via `curl`
+ `jq`, built inline in `emit_counter()` — delta rather than cumulative
because each hook invocation is a fresh, stateless process with no running
total to report. The collector's `delta_to_cumulative` processor converts
these into real, accumulating Prometheus counters before they're scraped —
without it, series don't behave like counters at all (found and fixed the
hard way; see `D-010` in `TASKS.md`).

See `assets/references/metrics-dictionary.md` for the full metric catalogue
and PromQL/TraceQL examples. One naming gotcha worth knowing up front: the
collector's Prometheus exporter has `namespace: agent` set, and every metric
name already starts with `agent.` — so the real Prometheus name is
double-prefixed (`agent.tool.call.total` → `agent_agent_tool_call_total`),
with `_total` auto-appended if the name doesn't already end in it.

## Known limitations

- `agent.session.success_rate_pct` gets exactly one data point per session,
  written by `stop.sh` when a session ends. During a long-running, still-open
  session with no recent session boundary, its dashboard panel will
  legitimately show 0% — that's a property of once-per-session counters, not
  a bug (see `D-009`/`D-010`/`D-015` in `TASKS.md`).
- Retry-switch and duplicate-call detection (`agent.tool.retry_switches`,
  `agent.tool.duplicate_calls`) only exist as post-hoc metrics from
  `stop.sh`'s session-log analysis — there's no way to find them via TraceQL,
  since the originating span has no way to know at creation time whether a
  later call will turn out to be a retry or duplicate.
- Two more `stop.sh` analysis sections (task-decomposition efficiency,
  error-recovery/"robustness" scoring) are drafted but not yet implemented —
  tracked as `T-012`/`T-013` in `TASKS.md`.

## Project history

`TASKS.md` has the full backlog and a decision log (`D-001`…`D-015`) covering
every bug found while getting this working — several are non-obvious
environment quirks (BSD `date` vs GNU `date`, `otel-cli`'s HTTP-vs-gRPC port
selection, Claude Code's actual hook payload field names and tool names,
Prometheus's DELTA-vs-CUMULATIVE counter semantics, jq's `--args` ordering)
worth reading before changing the hook scripts or dashboards. The backend
stack was originally OpenObserve, replaced with Tempo + Prometheus + Grafana
in `T-009` for clearer separation between traces and metrics.
