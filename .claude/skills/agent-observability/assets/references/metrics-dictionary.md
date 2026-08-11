# Metrics Dictionary

Complete reference for all signals emitted by the agent-observability skill.
Includes PromQL queries and suggested alert thresholds.

## Quick Reference

| Metric | Type | What it tells you |
|---|---|---|
| `agent.tool.call.total` | Counter | Raw call volume by tool and outcome |
| `agent.tool.call.error.total` | Counter | Error breakdown by type |
| `agent.tool.params.issues` | Counter | Parameter quality problems |
| `agent.tool.duplicate_calls` | Counter | Redundant identical calls |
| `agent.tool.calls_per_session` | Counter | Session complexity proxy |
| `agent.tool.read_before_write_violations` | Counter | Blind edits without prior read |
| `agent.tool.retry_switches` | Counter | Wrong-tool-then-correct patterns |
| `agent.tool.consecutive_errors` | Counter | Persistent misselection |
| `agent.session.success_rate_pct` | Gauge | Overall session health (0-100) |

## Detailed Metrics

### Tool Call Success Rate

#### `agent.tool.call.total`

Every tool invocation, labeled with outcome.

Labels: `tool_name`, `outcome` (success | error)

```promql
# Success rate per tool (last 1h)
sum(rate(agent_tool_call_total{outcome="success"}[1h])) by (tool_name)
/
sum(rate(agent_tool_call_total[1h])) by (tool_name)

# Overall success rate
1 - (
  sum(rate(agent_tool_call_total{outcome="error"}[1h]))
  /
  sum(rate(agent_tool_call_total[1h]))
)

# Most error-prone tools
topk(5, sum by (tool_name) (rate(agent_tool_call_total{outcome="error"}[1h])))
```

**Thresholds:**
- Healthy: > 90% success rate per tool
- Warning: 75-90%
- Critical: < 75%

#### `agent.tool.call.error.total`

Breakdown of errors by classification.

Labels: `tool_name`, `error_type` (permission_denied | file_not_found | command_not_found | syntax_error | timeout | unknown)

```promql
# Error distribution
sum by (error_type) (rate(agent_tool_call_error_total[1h]))

# File-not-found errors specifically (often indicates hallucinated paths)
sum(rate(agent_tool_call_error_total{error_type="file_not_found"}[1h]))
```

### Tool Call Precision

#### `agent.tool.params.issues`

Parameter quality issues caught at call time (before execution).

Labels: `tool_name`, `issue_type` (empty_value | null_value | path_not_found | suspicious_param), `field`

```promql
# Issue rate per tool
sum by (tool_name) (rate(agent_tool_params_issues[1h]))

# Suspicious params (placeholder hallucinations)
sum(rate(agent_tool_params_issues{issue_type="suspicious_param"}[1h]))

# Which fields are problematic
topk(10, sum by (field, issue_type) (agent_tool_params_issues))
```

**Thresholds:**
- Healthy: < 5% of calls have param issues
- Warning: 5-15%
- Critical: > 15% (agent is guessing at parameters)

### Tool Usage Efficiency

#### `agent.tool.duplicate_calls`

Identical calls (same tool + same parameters) within a session. The first
call is not counted — only the redundant repeats.

Labels: `tool_name`, `session_id`

```promql
# Average duplicates per session
avg(agent_tool_duplicate_calls)

# Tools with most duplication
topk(5, sum by (tool_name) (agent_tool_duplicate_calls))
```

**Common causes:**
- Re-reading a file that was just read (agent lost context)
- Retrying the same bash command hoping for a different result
- Re-viewing a directory listing

#### `agent.tool.read_before_write_violations`

Write operations (str_replace, bash with redirect) that target a file the
agent never read in this session. Indicates blind editing — the agent is
modifying a file based on assumption rather than observation.

Labels: `session_id`

```promql
# Violation rate per session
agent_tool_read_before_write_violations

# Average violations
avg(agent_tool_read_before_write_violations)
```

**Thresholds:**
- Healthy: 0-1 per session (occasional create_file is fine)
- Warning: 2-3
- Critical: > 3 (agent is editing blind)

### Tool Selection Accuracy

#### `agent.tool.retry_switches`

Detects the pattern: tool A fails on a target, then tool B is immediately
called on the same target. This strongly suggests tool A was the wrong choice.

Labels: `from_tool`, `to_tool`, `session_id`

```promql
# Most common wrong-choice patterns
topk(10, sum by (from_tool, to_tool) (agent_tool_retry_switches))

# Total selection errors per session
sum by (session_id) (agent_tool_retry_switches)
```

**Common patterns:**
- `bash` → `str_replace`: tried a sed command when str_replace was better
- `str_replace` → `bash`: edit was too complex for str_replace
- `view` → `bash cat`: view failed on binary file

#### `agent.tool.consecutive_errors`

Three or more consecutive errors on the same tool. Indicates the agent is
stuck and not adapting its approach.

Labels: `tool_name`, `session_id`

```promql
# Tools the agent gets stuck on
sum by (tool_name) (agent_tool_consecutive_errors)
```

**Thresholds:**
- Healthy: 0 per session
- Warning: 1 occurrence
- Critical: > 1 (agent is in a loop)

## Trace Queries (TraceQL / Jaeger)

```traceql
# Find all error spans in a session
{ resource.agent.session.id = "<session-id>" && status = error }

# Find retry switches
{ span.agent.tool.is_retry = true }

# Find duplicate calls
{ span.agent.tool.is_duplicate = true }

# Slow tool calls (> 5s)
{ span.agent.tool.name != "" && duration > 5s }
```

## Dashboard Layout Suggestion

**Row 1 — Session Overview**
- Success rate gauge (current session)
- Total calls counter
- Error rate sparkline

**Row 2 — Tool Breakdown**
- Calls by tool (stacked bar)
- Error rate by tool (heatmap)
- Duration by tool (box plot)

**Row 3 — Quality Signals**
- Param issues by type (pie)
- Duplicate calls by tool (bar)
- Read-before-write violations (stat)

**Row 4 — Selection Patterns**
- Retry switch Sankey diagram (from_tool → to_tool)
- Consecutive errors timeline
