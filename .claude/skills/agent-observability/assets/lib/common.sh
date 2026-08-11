#!/usr/bin/env bash
# common.sh — Shared functions for agent-observability hooks
# Sourced by all hook scripts, never executed directly.

set -euo pipefail

# ---------------------------------------------------------------------------
# Session directory — all per-session state lives here
# ---------------------------------------------------------------------------
OTEL_SESSION_DIR="${OTEL_SESSION_DIR:-/tmp/agent-otel-session}"
OTEL_SESSION_LOG="${OTEL_SESSION_DIR}/session.jsonl"
OTEL_SPANS_DIR="${OTEL_SESSION_DIR}/spans"
OTEL_SESSION_ID_FILE="${OTEL_SESSION_DIR}/session-id"

ensure_session_dir() {
  mkdir -p "${OTEL_SPANS_DIR}"
  if [[ ! -f "${OTEL_SESSION_ID_FILE}" ]]; then
    # Generate a stable session ID (UUID v4 via /proc or fallback)
    if command -v uuidgen &>/dev/null; then
      uuidgen > "${OTEL_SESSION_ID_FILE}"
    else
      cat /proc/sys/kernel/random/uuid > "${OTEL_SESSION_ID_FILE}" 2>/dev/null \
        || python3 -c "import uuid; print(uuid.uuid4())" > "${OTEL_SESSION_ID_FILE}"
    fi
  fi
}

get_session_id() {
  cat "${OTEL_SESSION_ID_FILE}" 2>/dev/null || echo "unknown"
}

# ---------------------------------------------------------------------------
# OTEL endpoint
# ---------------------------------------------------------------------------
OTEL_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-http://localhost:4318}"
OTEL_SERVICE_NAME="${OTEL_SERVICE_NAME:-claude-agent}"

# ---------------------------------------------------------------------------
# otel-cli wrappers
# ---------------------------------------------------------------------------
OTEL_CLI="${OTEL_CLI_PATH:-otel-cli}"

# Emit a counter increment via otel-cli
# Usage: emit_counter <metric_name> <value> <key=val> [key=val ...]
emit_counter() {
  local name="$1"; shift
  local value="$1"; shift
  local attrs=""
  for kv in "$@"; do
    attrs="${attrs:+${attrs},}${kv}"
  done

  "${OTEL_CLI}" span \
    --service "${OTEL_SERVICE_NAME}" \
    --name "metric.${name}" \
    --endpoint "${OTEL_ENDPOINT}" \
    --attrs "metric.name=${name},metric.value=${value}${attrs:+,${attrs}}" \
    --tp-required \
    2>/dev/null || true
}

# Start a span and write its context to a file for later closing
# Usage: start_span <span_name> <span_id_file> <key=val> [key=val ...]
start_span() {
  local name="$1"; shift
  local span_file="$1"; shift
  local attrs=""
  for kv in "$@"; do
    attrs="${attrs:+${attrs},}${kv}"
  done

  local session_id
  session_id="$(get_session_id)"

  # otel-cli span background — starts a span and writes TP to file
  "${OTEL_CLI}" span background \
    --service "${OTEL_SERVICE_NAME}" \
    --name "${name}" \
    --endpoint "${OTEL_ENDPOINT}" \
    --attrs "agent.session.id=${session_id}${attrs:+,${attrs}}" \
    --sockdir "${OTEL_SPANS_DIR}" \
    --tp-export \
    > "${span_file}" 2>/dev/null || true
}

# End a background span
# Usage: end_span <span_file> [--status <OK|ERROR>]
end_span() {
  local span_file="$1"; shift
  local status="${1:-OK}"

  if [[ -f "${span_file}" ]]; then
    "${OTEL_CLI}" span end \
      --sockdir "${OTEL_SPANS_DIR}" \
      --status-code "${status}" \
      2>/dev/null || true
    rm -f "${span_file}"
  fi
}

# ---------------------------------------------------------------------------
# Session log helpers
# ---------------------------------------------------------------------------

# Append a tool call record to the session JSONL log
# Usage: log_tool_call <json_object>
log_tool_call() {
  local record="$1"
  echo "${record}" >> "${OTEL_SESSION_LOG}"
}

# Compute a short hash of a string (for param dedup)
param_hash() {
  echo -n "$1" | sha256sum | cut -c1-16
}

# ---------------------------------------------------------------------------
# Timestamp helper (epoch millis)
# ---------------------------------------------------------------------------
now_ms() {
  local ms
  ms="$(date +%s%3N 2>/dev/null)"
  # BSD/macOS date doesn't support %3N — it exits 0 but leaves the literal
  # "3N" un-substituted, so we validate the output is numeric rather than
  # trusting the exit code.
  if [[ "${ms}" =~ ^[0-9]+$ ]]; then
    echo "${ms}"
  else
    python3 -c "import time; print(int(time.time()*1000))"
  fi
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log_debug() {
  if [[ "${OTEL_AGENT_DEBUG:-0}" == "1" ]]; then
    echo "[agent-otel] $*" >&2
  fi
}
