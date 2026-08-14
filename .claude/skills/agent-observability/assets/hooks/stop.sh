#!/usr/bin/env bash
# stop.sh — Fires when the session ends.
# No stdin input expected.
#
# Responsibilities:
#   1. Analyze session log for duplicate calls (efficiency)
#   2. Detect read-before-write violations (efficiency)
#   3. Detect retry switches (selection accuracy)
#   4. Detect consecutive errors (selection accuracy)
#   5. Detect skill activations (usage)
#   6. Analyze task decomposition (burst patterns across read/write/execute phases)
#   7. Emit summary metrics
#   8. Archive session log

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
SUCCESS_COUNT="$(jq -c 'select(.outcome=="success")' "${OTEL_SESSION_LOG}" | wc -l)"
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
# 5. Skill activations
# ---------------------------------------------------------------------------
# The Skill tool's input has no path/file/command field, so post_tool_use.sh
# falls back to .skill for its target — target IS the skill name here, no
# path parsing needed (unlike the original proposal, which assumed skill
# activation showed up as a Read of a SKILL.md file; it doesn't in this
# harness — Skill is its own tool).
SKILL_TARGETS="$(jq -r '
  select(.tool == "Skill" and .target != "") | .target
' "${OTEL_SESSION_LOG}" 2>/dev/null)"

if [[ -n "${SKILL_TARGETS}" ]]; then
  echo "${SKILL_TARGETS}" | sort | uniq -c | while read -r count skill; do
    emit_counter "agent.skill.activation" "${count}" \
      "skill_name=${skill}" \
      "session_id=${SESSION_ID}"
    log_debug "  skill activation: ${skill} x${count}"
  done

  DISTINCT_SKILLS="$(echo "${SKILL_TARGETS}" | sort -u | wc -l | tr -d ' ')"
  emit_counter "agent.skill.activations_per_session" "${DISTINCT_SKILLS}" \
    "session_id=${SESSION_ID}"
fi

# ---------------------------------------------------------------------------
# 6. Task decomposition efficiency — burst patterns across phases
# ---------------------------------------------------------------------------
# Phase mapping (Claude Code's real tool names, per D-011 — the original
# proposal used fictional names like view/str_replace/bash_tool). Unlike the
# read-before-write check in section 2, Write counts as "write" here: this is
# just labeling what kind of action each call was, not judging whether it was
# safe, so the new-file-vs-overwrite ambiguity that made Write worth
# excluding there doesn't apply here.
#   read    = Read
#   write   = Edit, Write
#   execute = Bash
#   other   = everything else (Skill, WebFetch, MCP tools, ...)
# A "burst" is a maximal run of consecutive same-phase calls. Short, focused
# bursts (read -> write -> execute) suggest good decomposition; long,
# erratic ones suggest the agent is thrashing.
PHASES="$(jq -r '
  if .tool == "Read" then "read"
  elif (.tool == "Edit" or .tool == "Write") then "write"
  elif .tool == "Bash" then "execute"
  else "other"
  end
' "${OTEL_SESSION_LOG}" 2>/dev/null)"

BURST_COUNT=0
MAX_BURST=0
PREV_PHASE=""
CURRENT_SIZE=0
if [[ -n "${PHASES}" ]]; then
  while IFS= read -r phase; do
    [[ -z "${phase}" ]] && continue
    if [[ "${phase}" == "${PREV_PHASE}" ]]; then
      CURRENT_SIZE=$(( CURRENT_SIZE + 1 ))
    else
      if [[ -n "${PREV_PHASE}" ]]; then
        BURST_COUNT=$(( BURST_COUNT + 1 ))
        (( CURRENT_SIZE > MAX_BURST )) && MAX_BURST=${CURRENT_SIZE}
      fi
      PREV_PHASE="${phase}"
      CURRENT_SIZE=1
    fi
  done <<< "${PHASES}"
  # close out the final burst
  BURST_COUNT=$(( BURST_COUNT + 1 ))
  (( CURRENT_SIZE > MAX_BURST )) && MAX_BURST=${CURRENT_SIZE}
fi

if (( BURST_COUNT > 0 )); then
  AVG_BURST_SIZE_X10=$(( (10 * TOTAL_CALLS) / BURST_COUNT ))
  emit_counter "agent.decomposition.burst_count" "${BURST_COUNT}" \
    "session_id=${SESSION_ID}"
  emit_counter "agent.decomposition.avg_burst_size_x10" "${AVG_BURST_SIZE_X10}" \
    "session_id=${SESSION_ID}"
  emit_counter "agent.decomposition.max_burst_size" "${MAX_BURST}" \
    "session_id=${SESSION_ID}"
  log_debug "  decomposition: ${BURST_COUNT} bursts, max ${MAX_BURST}, avg x10 ${AVG_BURST_SIZE_X10}"
fi

if (( TOTAL_CALLS > 0 )); then
  # "Productive ratio" per the proposal doc is the success rate of calls
  # within bursts — since bursts partition the whole session, that's
  # identical to the overall session success rate below. Emitted under its
  # own name for decomposition-specific dashboards/alerts; not a bug that
  # it matches agent.session.success_rate_pct.
  PRODUCTIVE_RATIO_PCT=$(( SUCCESS_COUNT * 100 / TOTAL_CALLS ))
  emit_counter "agent.decomposition.productive_ratio_pct" "${PRODUCTIVE_RATIO_PCT}" \
    "session_id=${SESSION_ID}"
fi

# ---------------------------------------------------------------------------
# 7. Session-level summary metrics
# ---------------------------------------------------------------------------
emit_counter "agent.tool.calls_per_session" "${TOTAL_CALLS}" \
  "session_id=${SESSION_ID}"

# Success rate as a convenience gauge
if (( TOTAL_CALLS > 0 )); then
  # Emit as integer percentage (0-100)
  RATE=$(( SUCCESS_COUNT * 100 / TOTAL_CALLS ))
  emit_counter "agent.session.success_rate_pct" "${RATE}" \
    "session_id=${SESSION_ID}"
fi

# ---------------------------------------------------------------------------
# 8. Archive session log
# ---------------------------------------------------------------------------
ARCHIVE_DIR="${OTEL_SESSION_DIR}/archive"
mkdir -p "${ARCHIVE_DIR}"
ARCHIVE_NAME="session-${SESSION_ID}-$(date +%Y%m%d-%H%M%S).jsonl"
cp "${OTEL_SESSION_LOG}" "${ARCHIVE_DIR}/${ARCHIVE_NAME}"

# Clean up for next session
rm -f "${OTEL_SESSION_LOG}" "${OTEL_SESSION_ID_FILE}"
rm -f "${OTEL_SPANS_DIR}"/*.span "${OTEL_SPANS_DIR}"/*.ts 2>/dev/null || true

log_debug "Session ${SESSION_ID} archived to ${ARCHIVE_NAME}"
