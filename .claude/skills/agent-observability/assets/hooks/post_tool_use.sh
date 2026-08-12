#!/usr/bin/env bash
# post_tool_use.sh — Fires AFTER every tool call.
# Receives JSON on stdin with: tool_name, tool_input, tool_output, is_error
#
# Responsibilities:
#   1. Close the span opened by pre_tool_use
#   2. Emit tool call success/error counter
#   3. Append structured record to session log for later analysis

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

ensure_session_dir

# ---------------------------------------------------------------------------
# Parse hook input
# ---------------------------------------------------------------------------
INPUT="$(cat)"
TOOL_NAME="$(echo "${INPUT}" | jq -r '.tool_name // "unknown"')"
TOOL_INPUT="$(echo "${INPUT}" | jq -c '.tool_input // {}')"
TOOL_OUTPUT="$(echo "${INPUT}" | jq -c '.tool_output // .tool_result // ""')"
IS_ERROR="$(echo "${INPUT}" | jq -r '.is_error // false')"
CALL_ID="$(echo "${INPUT}" | jq -r '.tool_use_id // .call_id // empty' 2>/dev/null)"

# Fallback only applies if the harness ever omits tool_use_id/call_id entirely.
if [[ -z "${CALL_ID}" ]]; then
  SPAN_FILE="$(ls -t "${OTEL_SPANS_DIR}"/*.span 2>/dev/null | head -1 || true)"
  TS_FILE="$(ls -t "${OTEL_SPANS_DIR}"/*.ts 2>/dev/null | head -1 || true)"
else
  SPAN_FILE="${OTEL_SPANS_DIR}/${CALL_ID}.span"
  TS_FILE="${OTEL_SPANS_DIR}/${CALL_ID}.ts"
fi

PHASH="$(param_hash "${TOOL_NAME}:${TOOL_INPUT}")"

log_debug "PostToolUse: ${TOOL_NAME} is_error=${IS_ERROR}"

# ---------------------------------------------------------------------------
# 1. Determine outcome
# ---------------------------------------------------------------------------
OUTCOME="success"
ERROR_TYPE=""

if [[ "${IS_ERROR}" == "true" ]]; then
  OUTCOME="error"
  # Try to classify the error
  ERROR_TYPE="$(echo "${TOOL_OUTPUT}" | jq -r '
    if type == "string" then
      if test("permission denied"; "i") then "permission_denied"
      elif test("no such file"; "i") then "file_not_found"
      elif test("command not found"; "i") then "command_not_found"
      elif test("syntax error"; "i") then "syntax_error"
      elif test("timed? ?out"; "i") then "timeout"
      else "unknown"
      end
    else "unknown"
    end
  ' 2>/dev/null || echo "unknown")"
fi

# ---------------------------------------------------------------------------
# 2. Close span
# ---------------------------------------------------------------------------
SPAN_STATUS="OK"
[[ "${OUTCOME}" == "error" ]] && SPAN_STATUS="ERROR"

if [[ -n "${SPAN_FILE}" && -f "${SPAN_FILE}" ]]; then
  end_span "${SPAN_FILE}" "${SPAN_STATUS}"
fi

# ---------------------------------------------------------------------------
# 3. Compute duration
# ---------------------------------------------------------------------------
DURATION_MS=0
if [[ -n "${TS_FILE}" && -f "${TS_FILE}" ]]; then
  START_MS="$(cat "${TS_FILE}")"
  END_MS="$(now_ms)"
  DURATION_MS=$(( END_MS - START_MS ))
  rm -f "${TS_FILE}"
fi

# ---------------------------------------------------------------------------
# 4. Emit metrics
# ---------------------------------------------------------------------------
# 4a. Call total (success or error)
emit_counter "agent.tool.call.total" 1 \
  "tool_name=${TOOL_NAME}" \
  "outcome=${OUTCOME}"

# 4b. Error detail (only on error)
if [[ "${OUTCOME}" == "error" ]]; then
  emit_counter "agent.tool.call.error.total" 1 \
    "tool_name=${TOOL_NAME}" \
    "error_type=${ERROR_TYPE}"
fi

# ---------------------------------------------------------------------------
# 5. Append to session log (for stop.sh analysis)
# ---------------------------------------------------------------------------
# Extract a target file/path if present — used for efficiency/selection analysis.
# .skill covers the Skill tool, whose input has no path/file/command field.
TARGET="$(echo "${TOOL_INPUT}" | jq -r '
  (.path // .file // .file_path // .filepath // .command // .skill // "") | tostring | .[0:200]
' 2>/dev/null || echo "")"

RECORD="$(jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
  --arg tool "${TOOL_NAME}" \
  --arg outcome "${OUTCOME}" \
  --arg error_type "${ERROR_TYPE}" \
  --arg phash "${PHASH}" \
  --arg target "${TARGET}" \
  --argjson duration "${DURATION_MS}" \
  --arg session_id "$(get_session_id)" \
  '{
    ts: $ts,
    tool: $tool,
    outcome: $outcome,
    error_type: $error_type,
    params_hash: $phash,
    target: $target,
    duration_ms: $duration,
    session_id: $session_id
  }'
)"

log_tool_call "${RECORD}"
