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
| `agent.tool.duplicate_calls` | Counter | `tool_name` | Stop (session log analysis) |
| `agent.tool.calls_per_session` | Histogram | — | Stop |
| `agent.tool.read_before_write_violations` | Counter | `tool_name` | Stop (session log analysis) |

A **duplicate call** is two calls to the same tool with identical (or
semantically equivalent) parameters within the same session.

A **read-before-write violation** is a write tool (str_replace, create_file,
bash with redirect) that is NOT preceded by a read of the same target (view,
cat). This catches blind edits.

### 4. Tool Selection Accuracy

Proxy metric for whether the agent picked the right tool. Measured via retry
and correction patterns.

| Signal | Type | Labels | Source |
|---|---|---|---|
| `agent.tool.retry_switches` | Counter | `from_tool`, `to_tool` | Stop (session log analysis) |
| `agent.tool.consecutive_errors` | Counter | `tool_name` | Stop (session log analysis) |

A **retry switch** is when tool A fails and the very next call is to a
different tool B targeting the same resource (same file path or similar
parameters). This suggests tool A was the wrong choice.

**Consecutive errors** on the same tool suggest a persistent misselection.

## Traces

Each session produces one trace:

```
Session (root span)
  ├─ tool:view /path/to/file.py     [200ms, OK]
  ├─ tool:str_replace file.py        [50ms, OK]
  ├─ tool:bash "npm test"            [3.2s, ERROR]
  │    └─ event: error_output "..."
  ├─ tool:bash "npm test"            [2.8s, OK]     ← retry detected
  └─ tool:view /path/to/file.py      [180ms, OK]   ← duplicate detected
```

Span attributes:
- `agent.session.id` — unique per session (UUID)
- `agent.tool.name` — the tool invoked
- `agent.tool.outcome` — success | error
- `agent.tool.params_hash` — hash of input params (for dedup detection)
- `agent.tool.is_retry` — boolean, set by stop analysis
- `agent.tool.is_duplicate` — boolean, set by stop analysis

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

### Step 2 — Run collector

Use the provided `assets/otel-collector-config.yaml` or point to your own.
A docker-compose one-liner:

```bash
docker run --rm -p 4317:4317 -p 4318:4318 \
  -v $(pwd)/assets/otel-collector-config.yaml:/etc/otelcol/config.yaml \
  otel/opentelemetry-collector-contrib:latest
```

### Step 3 — Work normally

The hooks fire automatically. At session end, the stop script runs the
efficiency and selection analysis on the session log and emits summary metrics.

## File manifest

```
assets/
  install.sh                    # Step 0: preflight
  hooks.json                    # Hook registration template
  hooks/
    pre_tool_use.sh             # Opens span, checks param precision
    post_tool_use.sh            # Closes span, emits success/error
    stop.sh                     # Session analysis: efficiency + selection
  lib/
    common.sh                   # Shared functions (session dir, logging)
  otel-collector-config.yaml    # Minimal collector config
  references/
    metrics-dictionary.md       # Full metric reference with queries
```

## Interpreting the data

Read `assets/references/metrics-dictionary.md` for PromQL/TraceQL query
examples and suggested alert thresholds. The key insight: no single metric
tells the full story. The four metrics form a diamond:

- **High success rate + low efficiency** → the agent gets there but wastes
  calls (over-reading, duplicate edits)
- **High precision + low selection accuracy** → params are clean but wrong
  tool chosen (e.g., bash when str_replace was better)
- **Low precision + high success rate** → lucky; params are sloppy but tools
  are forgiving
- **Low selection accuracy + low success rate** → the agent is struggling;
  likely needs better prompting or tool descriptions
