#!/usr/bin/env bash
# stop.sh — Fires when the session ends.
# No stdin input expected.
#
# Responsibilities:
#   1. Analyze session log for duplicate calls (efficiency)
#   2. Detect read-before-write violations (efficiency)
#   3. Detect retry switches (selection accuracy)
#   4. Detect consecutive errors (selection accuracy)
#   5. Emit summary metrics
#   6. Archive session log

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

ensure_session_dir

SESSION_ID="$(get_session_id)"

log_debug "Stop: analyzing session ${SESSION_ID}"

# ---------------------------------------------------------------------------
# Guard: skip if no session log
# ---------------------------------------------------------------------------
if [[ ! -f "${OTEL_SESSION_LOG}" ]]; then
  log_debug "No session log found, skipping analysis"
  exit 0
fi

TOTAL_CALLS="$(wc -l < "${OTEL_SESSION_LOG}")"
log_debug "Session had ${TOTAL_CALLS} tool calls"

# ---------------------------------------------------------------------------
# 1. Duplicate calls — same tool + same params_hash
# ---------------------------------------------------------------------------
DUPLICATES="$(jq -r '[.tool, .params_hash] | join("|")' "${OTEL_SESSION_LOG}" \
  | sort | uniq -d | while IFS='|' read -r tool phash; do
    count="$(jq -r "select(.tool==\"${tool}\" and .params_hash==\"${phash}\") | .tool" \
      "${OTEL_SESSION_LOG}" | wc -l)"
    echo "${tool}|${count}"
  done)"

if [[ -n "${DUPLICATES}" ]]; then
  while IFS='|' read -r tool count; do
    dupes=$(( count - 1 ))  # first call isn't a duplicate
    emit_counter "agent.tool.duplicate_calls" "${dupes}" \
      "tool_name=${tool}" \
      "session_id=${SESSION_ID}"
    log_debug "  duplicates: ${tool} x${dupes}"
  done <<< "${DUPLICATES}"
fi

# ---------------------------------------------------------------------------
# 2. Read-before-write violations
# ---------------------------------------------------------------------------
# Write tools: Edit (Claude Code's own contract requires a prior Read on the
#   same file before Edit will succeed, so a violation here is meaningful),
#   Bash (with > or >> in its command). Write is intentionally excluded: it's
#   the tool for creating brand-new files as much as overwriting existing
#   ones, and nothing in the hook payload distinguishes the two — flagging it
#   would mostly catch legitimate new-file creation, not blind edits.
# Read tools: Read
# A violation: write to a path with no prior read of that path in the session

WRITE_TARGETS="$(jq -r '
  select(
    .tool == "Edit" or
    (.tool == "Bash" and (.target | test("[>]")))
  ) | .target
' "${OTEL_SESSION_LOG}" 2>/dev/null | sort -u)"

READ_TARGETS="$(jq -r '
  select(.tool == "Read") | .target
' "${OTEL_SESSION_LOG}" 2>/dev/null | sort -u)"

VIOLATIONS=0
if [[ -n "${WRITE_TARGETS}" ]]; then
  while IFS= read -r wpath; do
    [[ -z "${wpath}" ]] && continue

    if ! echo "${READ_TARGETS}" | grep -qF "${wpath}"; then
      VIOLATIONS=$(( VIOLATIONS + 1 ))
      log_debug "  read-before-write violation: ${wpath}"
    fi
  done <<< "${WRITE_TARGETS}"
fi

if (( VIOLATIONS > 0 )); then
  emit_counter "agent.tool.read_before_write_violations" "${VIOLATIONS}" \
    "session_id=${SESSION_ID}"
fi

# ---------------------------------------------------------------------------
# 3. Retry switches — tool A errors, next call is tool B on same target
# ---------------------------------------------------------------------------
SWITCHES="$(jq -s '
  [range(1; length)] | map(
    select(
      .[0] as $prev |
      . as $curr |
      ($prev.outcome == "error") and
      ($curr.tool != $prev.tool) and
      ($curr.target != "" and $curr.target == $prev.target)
    ) |
    { from: .[0].tool, to: .[1].tool }
  )
' <(jq -s '
  [range(length - 1) as $i | [.[$i], .[$i+1]]][]
' "${OTEL_SESSION_LOG}") 2>/dev/null || echo "[]")"

SWITCH_COUNT="$(echo "${SWITCHES}" | jq 'length' 2>/dev/null || echo 0)"
if (( SWITCH_COUNT > 0 )); then
  echo "${SWITCHES}" | jq -r '.[] | [.from, .to] | join("|")' | while IFS='|' read -r from_tool to_tool; do
    emit_counter "agent.tool.retry_switches" 1 \
      "from_tool=${from_tool}" \
      "to_tool=${to_tool}" \
      "session_id=${SESSION_ID}"
    log_debug "  retry switch: ${from_tool} → ${to_tool}"
  done
fi

# ---------------------------------------------------------------------------
# 4. Consecutive errors on same tool
# ---------------------------------------------------------------------------
CONSEC="$(jq -s '
  reduce .[] as $item (
    {prev_tool: "", prev_outcome: "", streak: 0, results: []};
    if ($item.tool == .prev_tool and $item.outcome == "error" and .prev_outcome == "error")
    then .streak += 1
    else
      if (.streak >= 2)
      then .results += [{tool: .prev_tool, count: (.streak + 1)}]
      else .
      end
      | .streak = (if $item.outcome == "error" then 0 else 0 end)
    end
    | .prev_tool = $item.tool
    | .prev_outcome = $item.outcome
  ) |
  if (.streak >= 2)
  then .results += [{tool: .prev_tool, count: (.streak + 1)}]
  else .
  end |
  .results
' "${OTEL_SESSION_LOG}" 2>/dev/null || echo "[]")"

echo "${CONSEC}" | jq -r '.[] | [.tool, (.count|tostring)] | join("|")' 2>/dev/null \
  | while IFS='|' read -r tool count; do
    emit_counter "agent.tool.consecutive_errors" "${count}" \
      "tool_name=${tool}" \
      "session_id=${SESSION_ID}"
    log_debug "  consecutive errors: ${tool} x${count}"
  done

# ---------------------------------------------------------------------------
# 5. Session-level summary metrics
# ---------------------------------------------------------------------------
emit_counter "agent.tool.calls_per_session" "${TOTAL_CALLS}" \
  "session_id=${SESSION_ID}"

# Success rate as a convenience gauge
SUCCESS_COUNT="$(jq -r 'select(.outcome=="success")' "${OTEL_SESSION_LOG}" | wc -l)"
if (( TOTAL_CALLS > 0 )); then
  # Emit as integer percentage (0-100)
  RATE=$(( SUCCESS_COUNT * 100 / TOTAL_CALLS ))
  emit_counter "agent.session.success_rate_pct" "${RATE}" \
    "session_id=${SESSION_ID}"
fi

# ---------------------------------------------------------------------------
# 6. Archive session log
# ---------------------------------------------------------------------------
ARCHIVE_DIR="${OTEL_SESSION_DIR}/archive"
mkdir -p "${ARCHIVE_DIR}"
ARCHIVE_NAME="session-${SESSION_ID}-$(date +%Y%m%d-%H%M%S).jsonl"
cp "${OTEL_SESSION_LOG}" "${ARCHIVE_DIR}/${ARCHIVE_NAME}"

# Clean up for next session
rm -f "${OTEL_SESSION_LOG}" "${OTEL_SESSION_ID_FILE}"
rm -f "${OTEL_SPANS_DIR}"/*.span "${OTEL_SPANS_DIR}"/*.ts 2>/dev/null || true

log_debug "Session ${SESSION_ID} archived to ${ARCHIVE_NAME}"
