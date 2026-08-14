#!/usr/bin/env bash
# pre_tool_use.sh — Fires BEFORE every tool call.
# Receives JSON on stdin with: tool_name, tool_input
#
# Responsibilities:
#   1. Open a span for this tool call
#   2. Check parameter precision and emit issues
#   3. Record start timestamp for duration calculation

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

ensure_session_dir

# ---------------------------------------------------------------------------
# Parse hook input
# ---------------------------------------------------------------------------
INPUT="$(cat)"
TOOL_NAME="$(echo "${INPUT}" | jq -r '.tool_name // "unknown"')"
TOOL_INPUT="$(echo "${INPUT}" | jq -c '.tool_input // {}')"
CALL_ID="$(echo "${INPUT}" | jq -r '.tool_use_id // .call_id // empty' 2>/dev/null)"
[[ -z "${CALL_ID}" ]] && CALL_ID="call-$(now_ms)-$$"

PHASH="$(param_hash "${TOOL_NAME}:${TOOL_INPUT}")"
SPAN_FILE="${OTEL_SPANS_DIR}/${CALL_ID}.span"
TS_FILE="${OTEL_SPANS_DIR}/${CALL_ID}.ts"

log_debug "PreToolUse: ${TOOL_NAME} (${CALL_ID})"

# ---------------------------------------------------------------------------
# 1. Open span
# ---------------------------------------------------------------------------
# The Skill tool's input has a `skill` field (which skill is being invoked) —
# put it on the span so TraceQL can filter by skill directly
# ({ span.agent.skill.name = "..." }) instead of only seeing "a Skill call
# happened" with no identity. Session-level aggregates already exist via
# agent.skill.activation (stop.sh), but that's a once-per-session summary,
# not something queryable per-interaction.
SPAN_ATTRS=(
  "agent.tool.name=${TOOL_NAME}"
  "agent.tool.params_hash=${PHASH}"
)
if [[ "${TOOL_NAME}" == "Skill" ]]; then
  SKILL_NAME="$(echo "${TOOL_INPUT}" | jq -r '.skill // ""' 2>/dev/null)"
  [[ -n "${SKILL_NAME}" ]] && SPAN_ATTRS+=("agent.skill.name=${SKILL_NAME}")
fi

start_span "tool:${TOOL_NAME}" "${SPAN_FILE}" "${SPAN_ATTRS[@]}"

# Record start time for duration histogram
now_ms > "${TS_FILE}"

# ---------------------------------------------------------------------------
# 2. Parameter precision checks
# ---------------------------------------------------------------------------
# We inspect tool_input for common quality issues.
ISSUES="$(echo "${TOOL_INPUT}" | jq -r '
  [
    # Empty string values
    (to_entries[] | select(.value == "") | "empty_value:\(.key)"),
    # Null values
    (to_entries[] | select(.value == null) | "null_value:\(.key)"),
    # Suspicious placeholder patterns in string values
    (to_entries[]
      | select(.value | type == "string")
      | select(.value | test("(<[A-Z_]+>|\\{\\{|TODO|FIXME|PLACEHOLDER)"; "i"))
      | "suspicious_param:\(.key)")
  ] | .[]
' 2>/dev/null || true)"

if [[ -n "${ISSUES}" ]]; then
  while IFS= read -r issue; do
    issue_type="${issue%%:*}"
    issue_field="${issue#*:}"
    emit_counter "agent.tool.params.issues" 1 \
      "tool_name=${TOOL_NAME}" \
      "issue_type=${issue_type}" \
      "field=${issue_field}"
    log_debug "  param issue: ${issue_type} on ${issue_field}"
  done <<< "${ISSUES}"
fi

# ---------------------------------------------------------------------------
# 3. Check for path_not_found (if a 'path' or 'file' param exists)
# ---------------------------------------------------------------------------
FILE_PATH="$(echo "${TOOL_INPUT}" | jq -r '
  (.path // .file // .file_path // .filepath // empty)
' 2>/dev/null || true)"

if [[ -n "${FILE_PATH}" && ! -e "${FILE_PATH}" ]]; then
  # Only flag for read operations — writes create files
  if [[ "${TOOL_NAME}" == "view" || "${TOOL_NAME}" == "cat" ]]; then
    emit_counter "agent.tool.params.issues" 1 \
      "tool_name=${TOOL_NAME}" \
      "issue_type=path_not_found" \
      "field=path"
    log_debug "  path_not_found: ${FILE_PATH}"
  fi
fi
