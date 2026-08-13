---
name: agent-observability
description: >
  Instrument agentic Claude Code sessions with OpenTelemetry metrics and traces
  focused on tool-call quality. Emits four core metrics — tool call success rate,
  tool selection accuracy, tool usage efficiency, and tool call precision — via
  lightweight hook scripts that talk OTEL. Use this skill whenever the user wants
  to add observability, telemetry, monitoring, or metrics to an agentic workflow,
  or when they mention OpenTelemetry, OTEL, tracing, or tool-call analytics in
  the context of Claude Code or AI agents.
---

# Agent Observability Skill

Instrument a Claude Code agentic session with OpenTelemetry signals derived
exclusively from hook lifecycle events. Zero runtime dependencies beyond
`otel-cli` (a single Go binary) and `jq`.

## Overview

This skill turns Claude Code hooks into an observability pipeline. Every tool
call becomes a span; every session becomes a trace; four metrics capture how
well the agent uses its tools. The data flows through a standard OTEL Collector
to any backend (Prometheus, Jaeger, Grafana, Datadog, etc.).

```
┌─────────────────────────────────────────────────────┐
│  Claude Code Session                                │
│                                                     │
│  PreToolUse ──► pre_tool_use.sh  ──► open span      │
│  PostToolUse ─► post_tool_use.sh ─► close span      │
│                                    ► emit metrics    │
│                                    ► append session  │
│                                      log (JSONL)     │
│  Stop ────────► stop.sh ──────────► session summary  │
│                                    ► efficiency &    │
│                                      selection       │
│                                      analysis        │
│                                                     │
│  All signals ──► otel-cli ──► OTLP ──► Collector    │
└─────────────────────────────────────────────────────┘
```

## Metrics Contract

### 1. Tool Call Success Rate

How often tool calls complete without error.

| Signal | Type | Labels | Source |
|---|---|---|---|
| `agent.tool.call.total` | Counter | `tool_name`, `outcome` (success\|error) | PostToolUse |
| `agent.tool.call.error.total` | Counter | `tool_name`, `error_type` | PostToolUse |

An outcome is `error` when the tool result contains an `is_error: true` field
or the output matches known error patterns (stack traces, permission denied,
file not found). Everything else is `success`.

### 2. Tool Call Precision

How clean the parameters are — catches empty strings, null values, malformed
paths, and missing required fields.

| Signal | Type | Labels | Source |
|---|---|---|---|
| `agent.tool.params.issues` | Counter | `tool_name`, `issue_type` | PreToolUse |

Issue types: `empty_value`, `null_value`, `path_not_found`, `suspicious_param`.

A `suspicious_param` is a parameter whose value looks like a prompt fragment
rather than a real value (contains `<`, `>`, `{{`, common in hallucinated
placeholders).

### 3. Tool Usage Efficiency

How many calls are redundant or unnecessary within a session.

| Signal | Type | Labels | Source |
|---|---|---|---|
| `agent.tool.duplicate_calls` | Counter | `tool_name`, `session_id` | Stop (session log analysis) |
| `agent.tool.calls_per_session` | Counter | `session_id` | Stop |
| `agent.tool.read_before_write_violations` | Counter | `session_id` | Stop (session log analysis) |

A **duplicate call** is two calls to the same tool with identical (or
semantically equivalent) parameters within the same session.

A **read-before-write violation** is a write (`Edit`, or `Bash` with a `>`/`>>`
redirect in its command) that targets a path with no prior read (`Read`) of
that same path in the session. `Write` is intentionally excluded — it's the
tool for both creating brand-new files and overwriting existing ones, and
nothing in the hook payload distinguishes the two, so flagging it would mostly
catch legitimate new-file creation, not blind edits. Adjust the tool-name
mapping in `hooks/stop.sh`'s "Read-before-write violations" section to match
whatever harness's actual tool names you're instrumenting — Claude Code's are
`Read`/`Edit`/`Write`/`Bash`, not the generic `view`/`str_replace`/
`create_file`/`bash_tool` names you'll see in some other agent frameworks'
docs.

### 4. Tool Selection Accuracy

Proxy metric for whether the agent picked the right tool. Measured via retry
and correction patterns.

| Signal | Type | Labels | Source |
|---|---|---|---|
| `agent.tool.retry_switches` | Counter | `from_tool`, `to_tool`, `session_id` | Stop (session log analysis) |
| `agent.tool.consecutive_errors` | Counter | `tool_name`, `session_id` | Stop (session log analysis) |

A **retry switch** is when tool A fails and the very next call is to a
different tool B targeting the same resource (same file path or similar
parameters) — e.g. `Bash` fails, `Edit` immediately follows on the same file.
This suggests tool A was the wrong choice.

**Consecutive errors** on the same tool (3+ in a row) suggest a persistent
misselection — the agent is stuck rather than adapting.

### 5. Skill Activation

Which skills actually get used, and how often. Useful for pruning unused
skills or catching a skill invoked so repeatedly it suggests a workflow gap.

| Signal | Type | Labels | Source |
|---|---|---|---|
| `agent.skill.activation` | Counter | `skill_name`, `session_id` | Stop (session log analysis) |
| `agent.skill.activations_per_session` | Counter | `session_id` | Stop |

Detected via a dedicated `Skill` tool call, not a file read — some harnesses
expose skill invocation as a `Read` of the skill's definition file, but
Claude Code has its own `Skill` tool, whose `skill` input field becomes the
session-log record's `target`. If you're adapting this for a harness that
really does expose skills via file reads, match on the file path pattern
instead (e.g. `.*/skills/.*/SKILL\.md`) and extract the skill name from it.

## Traces

Each tool call is its own span (there's no single root span tying a session's
spans together in the trace backend — group them by the shared
`agent.session.id` attribute instead, e.g. Tempo's
`{ span.agent.session.id = "<id>" }`):

```
tool:Read /path/to/file.py     [200ms, OK]
tool:Edit file.py               [50ms, OK]
tool:Bash "npm test"            [3.2s, ERROR]
tool:Bash "npm test"            [2.8s, OK]     ← retry switch (metric only, not visible on the span)
tool:Read /path/to/file.py      [180ms, OK]    ← duplicate (metric only, not visible on the span)
```

Span attributes (verified against a live trace's raw structure — don't trust
this list without checking, it drifts easily):
- `agent.session.id` — unique per session (UUID). **Span-level**, not
  resource-level — query it as `span.agent.session.id` in TraceQL, not
  `resource.agent.session.id` (only `service.name` is resource-level; this
  was a real, previously-shipped doc bug — see `D-012` in `TASKS.md`).
- `agent.tool.name` — the tool invoked
- `agent.tool.params_hash` — hash of input params (for dedup detection)
- `agent.framework` — static value, added by the collector's `attributes`
  processor, not the hook itself

There is **no** `agent.tool.outcome`, `agent.tool.is_retry`, or
`agent.tool.is_duplicate` span attribute, despite what you might expect from
the metric names above. Outcome is only visible as the span's OTLP status
(OK/ERROR); retry and duplicate detection happen entirely post-hoc in
`stop.sh`'s session-log analysis, after the session ends — by definition
`pre_tool_use.sh` cannot know at span-creation time whether a call will later
turn out to be a retry or a duplicate, since that requires seeing calls that
haven't happened yet. Query those two via the Prometheus metrics
(`agent.tool.retry_switches`, `agent.tool.duplicate_calls`), not TraceQL.

## Setup

### Step 0 — Preflight

Run the install script. It checks for `jq`, downloads `otel-cli` if missing,
and validates the OTEL collector endpoint.

```bash
bash <skill_dir>/assets/install.sh
```

The script respects `OTEL_EXPORTER_OTLP_ENDPOINT` (default:
`http://localhost:4318` — note this must be the OTLP/**HTTP** port; otel-cli
picks HTTP vs gRPC from the `http://` scheme, and 4317 is gRPC-only). Set it
before running if your collector is elsewhere.

### Step 1 — Register hooks

Claude Code reads hooks from `.claude/settings.json` (or `settings.local.json`)
under a top-level `"hooks"` key — it does **not** read a standalone
`.claude/hooks.json` file. `assets/hooks.json` is a reference template showing
which events/scripts to wire up (using the portable `${CLAUDE_PROJECT_DIR}`
placeholder, which Claude Code sets to the project root for every hook
invocation); merge its `"hooks"` key into `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/skills/agent-observability/assets/hooks/pre_tool_use.sh\"" } ] }
    ],
    "PostToolUse": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/skills/agent-observability/assets/hooks/post_tool_use.sh\"" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/skills/agent-observability/assets/hooks/stop.sh\"" } ] }
    ]
  }
}
```

Note the nesting: each matcher entry needs a `hooks` array of
`{"type": "command", "command": ...}` objects — a bare `"command"` field on
the matcher itself is silently ignored.

### Step 2 — Run collector + backends

Use the provided `assets/otel-collector-config.yaml` or point to your own.
This repo's own `docker-compose.yaml` (repo root) is a complete, working
reference: `otel-collector` → `tempo` (traces) + `prometheus` (metrics) →
`grafana` (dashboards for both, auto-provisioned from `assets/`). From the
repo root:

```bash
docker compose up -d
```

If you're pointing your own Prometheus at this collector's config instead of
reusing the provided stack, two non-obvious things will otherwise silently
break your dashboards:

- The collector's `prometheus` exporter has `namespace: agent` set, and every
  metric name already starts with `agent.` — so the real Prometheus metric
  name is double-prefixed (`agent.tool.call.total` →
  `agent_agent_tool_call_total`), with `_total` auto-appended if the OTLP name
  doesn't already end in it. See `assets/references/metrics-dictionary.md`'s
  naming note for the full rule.
- `emit_counter()` sends DELTA-temporality Sum metrics (each hook invocation
  is a stateless process with no running total to report). Prometheus expects
  CUMULATIVE counters — without a `delta_to_cumulative` processor in the
  metrics pipeline (already present in `assets/otel-collector-config.yaml`),
  series won't accumulate correctly and `rate()`/`increase()` queries will
  silently return empty or misleading results.

### Step 3 — Work normally

The hooks fire automatically. At session end, the stop script runs the
efficiency and selection analysis on the session log and emits summary metrics.

## File manifest

```
assets/
  install.sh                        # Step 0: preflight
  hooks.json                        # Hook registration template
  hooks/
    pre_tool_use.sh                 # Opens span, checks param precision
    post_tool_use.sh                # Closes span, emits success/error
    stop.sh                         # Session analysis: efficiency + selection
  lib/
    common.sh                       # Shared functions (session dir, logging)
  otel-collector-config.yaml        # Collector config: OTLP in, Tempo + Prometheus out
  tempo-config.yaml                 # Tempo (traces backend)
  prometheus.yml                    # Prometheus scrape config (collector's :8889/metrics)
  grafana-datasources.yaml          # Grafana datasource provisioning (Tempo + Prometheus)
  grafana-dashboards-provider.yaml  # Grafana dashboard-provisioning pointer
  dashboards/
    tool-metrics.json               # "Agent Tool Metrics" dashboard (Prometheus)
    traces.json                     # "Agent Tool Traces" dashboard (Tempo)
  references/
    metrics-dictionary.md           # Full metric reference with queries
```

## Interpreting the data

The fastest way in is the two pre-built Grafana dashboards
(`assets/dashboards/`) — "Agent Tool Metrics" for the Prometheus-backed
counters below, "Agent Tool Traces" for span-level search (recent traces,
errors, slow calls, session filter). For raw query examples and suggested
alert thresholds, read `assets/references/metrics-dictionary.md`. The key
insight: no single metric tells the full story. The four core metrics form a
diamond:

- **High success rate + low efficiency** → the agent gets there but wastes
  calls (over-reading, duplicate edits)
- **High precision + low selection accuracy** → params are clean but wrong
  tool chosen (e.g., `Bash` when `Edit` was better)
- **Low precision + high success rate** → lucky; params are sloppy but tools
  are forgiving
- **Low selection accuracy + low success rate** → the agent is struggling;
  likely needs better prompting or tool descriptions
