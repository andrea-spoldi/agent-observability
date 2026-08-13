# TASKS.md — test-o11y

```json
{
  "project": "test-o11y",
  "updated": "2026-08-12",
  "_session_note": "S-005 spanned 2026-08-11 to 2026-08-12 (resumed after a session boundary). Replaced OpenObserve entirely with a Tempo (traces) + Prometheus (metrics) + Grafana (dashboards, datasources auto-provisioned) stack per the SDD plan at docs/superpowers/plans/2026-08-11-tempo-grafana-migration.md, executed task-by-task with real per-task commits (fb0d8fc/ab992b8/379c49b for Task 1, 41d206d for Task 2, f9b33be for Task 3). Task 1 hit a real blocker mid-session-1: the brief's compactor.compaction.block_retention block is valid YAML but Tempo v3.0.0 removed the legacy compactor component from its schema, so the container refused to start with it present — paused for a controller/user decision. On resume, user chose to drop the block and accept Tempo's default 336h retention (deferring retention hardening to a future task) rather than pin an older Tempo version or hunt for a v3.0.0-native equivalent. All three backends verified end-to-end together via real hook-lib span/counter emission (start_span/end_span/emit_counter), queried back from Tempo's /api/search and Prometheus's query API directly, with Grafana's health check and both datasources (Tempo, Prometheus) confirmed provisioned via its API. T-005 and T-008 remain the top pending backlog items for the next session. Untracked clipped-article file at repo root still unaddressed, low priority. The openobserve container from the earlier proof-of-concept is still running (started via plain docker run, not part of this repo's docker-compose.yaml) — user can docker stop/rm it once satisfied the new stack covers their needs.",

  "current_session": {
    "id": "S-012",
    "goal": "Update README.md, SKILL.md, CLAUDE.md to explain how to use the PoC and fix stale content",
    "task_ref": null,
    "started": "2026-08-13",
    "status": "done",
    "blocker": null
  },

  "backlog": [
    {
      "id": "T-001",
      "title": "Fix ${SKILL_DIR} placeholder in .claude/hooks.json",
      "description": "hooks.json was copied from the skill's assets/hooks.json template but still has the literal, unresolved ${SKILL_DIR} placeholder in each command path. Claude Code does not set that env var, so hooks currently fail to resolve their script path. Replace with the absolute path to .claude/skills/agent-observability/assets/hooks/.",
      "size": "S",
      "priority": 1,
      "status": "done",
      "tags": ["hooks", "bugfix"]
    },
    {
      "id": "T-002",
      "title": "Run install.sh preflight",
      "description": "Run .claude/skills/agent-observability/assets/install.sh to verify jq + otel-cli are present and hook scripts are chmod +x.",
      "size": "S",
      "priority": 2,
      "status": "done",
      "tags": ["hooks", "setup"]
    },
    {
      "id": "T-003",
      "title": "Stand up the otel-collector via docker-compose",
      "description": "docker compose up otel-collector, confirm it accepts OTLP on 4317/4318 using the config at assets/otel-collector-config.yaml.",
      "size": "S",
      "priority": 3,
      "status": "done",
      "tags": ["infra", "otel"]
    },
    {
      "id": "T-004",
      "title": "Verify hooks fire end-to-end",
      "description": "Run a real tool call in a Claude Code session, confirm PreToolUse/PostToolUse open/close an OTEL span and Stop emits a session summary. Check session log dir (default /tmp/agent-otel-session/) and collector output.",
      "size": "M",
      "priority": 4,
      "status": "done",
      "tags": ["hooks", "verification"]
    },
    {
      "id": "T-005",
      "title": "Fix tool-name mismatch in stop.sh's read-before-write check",
      "description": "stop.sh's read-before-write violation detector (assets/hooks/stop.sh lines ~60-70) matches against tool names 'bash_tool', 'view', 'str_replace', 'create_file' — none of which are real Claude Code tool names (actual: 'Bash', 'Read', 'Edit', 'Write'). The check can never fire in this harness. Needs a decision on the right Claude Code tool → read/write mapping (e.g. Read=read, Edit/Write=write, Bash treated how?) before fixing.",
      "size": "S",
      "priority": 5,
      "status": "done",
      "tags": ["hooks", "bugfix", "stop.sh"],
      "blocks": ["T-011", "T-012", "T-013"]
    },
    {
      "id": "T-006",
      "title": "Publish reproducible sandbox to GitHub",
      "description": "git init, add remote origin (https://github.com/andrea-spoldi/agent-observability.git), write .gitignore and README.md, and push. Required making hook paths portable across machines first (see D-007) — the committed config previously hardcoded this machine's absolute path.",
      "size": "M",
      "priority": 6,
      "status": "done",
      "tags": ["git", "docs", "publish"]
    },
    {
      "id": "T-007",
      "title": "Fix fake-metrics gap: emit_counter() never sends real OTLP metrics",
      "description": "otel-cli (assets/lib/common.sh) only exposes span/exec/status/server subcommands — no metrics command. emit_counter() fakes a counter by sending a `span` named `metric.<name>` with the value in span attributes. Confirmed live: the collector's debug exporter logs `\"otelcol.signal\": \"traces\"` for every emit_counter call, never `\"metrics\"` — nothing ever reaches the collector's metrics pipeline or /v1/metrics. Needs a design decision on the fix approach (see D-008 once decided) before implementing.",
      "size": "M",
      "priority": 7,
      "status": "done",
      "tags": ["otel", "bugfix", "metrics"]
    },
    {
      "id": "T-008",
      "title": "Fix stale TraceQL/PromQL examples in metrics-dictionary.md",
      "description": "The 'Trace Queries' section documents queries against span attributes `span.agent.tool.is_retry` and `span.agent.tool.is_duplicate` that are never actually set on any span — retry-switch and duplicate-call detection only ever happens in stop.sh's post-hoc session.jsonl analysis and is only emitted as a metric (agent.tool.retry_switches, agent.tool.duplicate_calls), never as a span attribute on the original tool-call span. Either add the attributes to the relevant spans, or rewrite/remove these TraceQL examples. ALSO (found during T-010): every PromQL example in this file uses bare names like `agent_tool_call_total`, but the collector's prometheus exporter has `namespace: agent` set, so real metric names are double-prefixed (`agent_agent_tool_call_total`, etc., with an auto-appended `_total` on metrics whose OTLP name doesn't already end in 'total' — see D-009). Every PromQL example needs the corrected names.",
      "size": "S",
      "priority": 8,
      "status": "done",
      "tags": ["docs", "bugfix", "metrics-dictionary"]
    },
    {
      "id": "T-010",
      "title": "Create Grafana dashboards for OTEL metrics and traces",
      "description": "T-009 deferred dashboard creation ('no starter dashboard per plan constraints'). Build provisioned-via-file Grafana dashboard(s) covering the nine metrics in metrics-dictionary.md (success rate, error breakdown, param issues, duplicate calls, read-before-write violations, retry switches, consecutive errors, session success rate) against the Prometheus datasource, plus a Tempo-backed trace/span exploration view. metrics-dictionary.md already has a suggested 4-row layout (Session Overview / Tool Breakdown / Quality Signals / Selection Patterns) to use as a starting point. Must follow the file-provisioning pattern already used for datasources (assets/grafana-datasources.yaml mounted via docker-compose.yaml) per CLAUDE.md's constraint that UI-only Grafana edits don't survive a container recreate.",
      "size": "M",
      "priority": 4,
      "status": "done",
      "tags": ["grafana", "dashboards", "observability"]
    },
    {
      "id": "T-011",
      "title": "Add Skill Activations section to stop.sh",
      "description": "From stop-sh-changes.md (untracked proposal doc at repo root, never implemented — grepped stop.sh to confirm none of this exists yet). Scan the session log for Read calls whose target matches `.claude/skills/.*/SKILL.md` or `/mnt/skills/.*/SKILL.md`, extract the skill name, emit `agent.skill.activation` (counter per skill name) and `agent.skill.activations_per_session` (total distinct skills activated). T-005 (resolved 2026-08-12, D-011) confirmed the real tool name for this is `Read`, not the doc's `view` — use that.",
      "size": "S",
      "priority": 9,
      "status": "done",
      "tags": ["hooks", "feature", "stop.sh", "metrics"]
    },
    {
      "id": "T-012",
      "title": "Add Task Decomposition Efficiency section to stop.sh",
      "description": "From stop-sh-changes.md (untracked proposal doc at repo root, never implemented). Classify each tool call into a phase (read/write/execute/other), count 'bursts' of consecutive same-phase calls, emit `agent.decomposition.burst_count`, `agent.decomposition.avg_burst_size_x10` (x10 to avoid float issues in counter emission), `agent.decomposition.max_burst_size`, `agent.decomposition.productive_ratio_pct`. T-005 (resolved 2026-08-12, D-011) settled the tool-name mapping this phase classification should reuse: Read=read, Edit=write, Bash(redirect)=write, Write=exempt/other — the doc's phase table used fictional names ('view'/'str_replace'/'create_file'/'bash_tool').",
      "size": "M",
      "priority": 10,
      "status": "pending",
      "tags": ["hooks", "feature", "stop.sh", "metrics"]
    },
    {
      "id": "T-013",
      "title": "Add Agent Robustness (error recovery) section to stop.sh",
      "description": "From stop-sh-changes.md (untracked proposal doc at repo root, never implemented). For each error with a non-empty target, look ahead up to 3 calls for a success on the same target and classify as 'recovered'. Emit `agent.robustness.score_pct` (recovered/total, defaults to 100 if zero errors), `agent.robustness.recovered`, `agent.robustness.unrecovered`. Doc includes a dry-run validation against a synthetic 10-call log (33% recovery score) that can seed a real test case. Not directly blocked on T-005 (doesn't depend on the read/write/execute phase mapping), but should land after it for consistency with T-011/T-012's tool-name handling in the same file.",
      "size": "M",
      "priority": 11,
      "status": "pending",
      "tags": ["hooks", "feature", "stop.sh", "metrics"]
    }
  ],

  "decisions": [
    {
      "id": "D-001",
      "date": "2026-08-11",
      "decision": "Hardcode the absolute path to agent-observability's hooks/ in .claude/hooks.json instead of using ${SKILL_DIR}",
      "rationale": "${SKILL_DIR} was a template placeholder from the skill's assets/hooks.json, not an env var Claude Code actually sets — hooks were silently failing to resolve. Hardcoding is fine for a single-repo sandbox; would need revisiting if this hooks.json is ever templated across repos.",
      "supersedes": null
    },
    {
      "id": "D-002",
      "date": "2026-08-11",
      "decision": "Added ports: [\"4317:4317\", \"4318:4318\"] to the otel-collector service in docker-compose.yaml",
      "rationale": "The original docker-compose.yaml had no ports mapping, so the collector was running but unreachable from the host (connection refused). Hook scripts run on the host, not inside Docker, so both OTLP gRPC (4317) and HTTP (4318) needed to be published to match what install.sh and otel-cli expect.",
      "supersedes": null
    },
    {
      "id": "D-003",
      "date": "2026-08-11",
      "decision": "Created .claude/settings.json with the hooks wired under a top-level \"hooks\" key (proper {matcher, hooks:[{type, command}]} schema); left .claude/hooks.json in place as an inert reference template.",
      "rationale": "Claude Code does not read a standalone .claude/hooks.json file at all — confirmed against this user's own ~/.claude/settings.json, which uses the hooks key. D-001's fix was real but landed in a file the harness never loads, which is why nothing fired even in a fresh session. This supersedes S-001's assumption that T-004 was blocked only on a session restart.",
      "supersedes": "S-001 blocker assumption (fresh-session-needed)"
    },
    {
      "id": "D-004",
      "date": "2026-08-11",
      "decision": "Fixed CALL_ID derivation in pre_tool_use.sh/post_tool_use.sh to read .tool_use_id (falling back to .call_id, then a generated id) instead of only .call_id.",
      "rationale": "Real Claude Code hook payloads use the key tool_use_id, not call_id — confirmed by capturing a live payload. The old code's jq '.call_id // empty' always succeeded with an empty string (jq doesn't error on a missing key), so the intended `|| echo call-$(now_ms)` fallback never triggered. Empty CALL_ID produced hidden dotfiles (.span, .ts) that post_tool_use.sh's glob-based fallback (*.span) couldn't match by default in bash, so spans were opened but never closed and duration was always logged as 0.",
      "supersedes": null
    },
    {
      "id": "D-005",
      "date": "2026-08-11",
      "decision": "Made now_ms() in lib/common.sh validate that `date +%s%3N` produced a numeric value, falling back to python3 if not.",
      "rationale": "BSD/macOS date doesn't support the %3N (milliseconds) format — it exits 0 but leaves the literal characters '3N' un-substituted (e.g. '17864438323N'), so the existing `|| python3` fallback never triggered since it only checks exit status, not output validity. This corrupted every duration_ms computation on macOS.",
      "supersedes": null
    },
    {
      "id": "D-006",
      "date": "2026-08-11",
      "decision": "Changed the default OTEL_EXPORTER_OTLP_ENDPOINT in lib/common.sh from http://localhost:4317 to http://localhost:4318.",
      "rationale": "otel-cli selects OTLP/HTTP vs OTLP/gRPC based on the endpoint's URL scheme: an http:// prefix means OTLP/HTTP, which must target the HTTP port (4318). Port 4317 is gRPC-only. Sending http:// to 4317 caused otel-cli to speak HTTP/1.1 to a gRPC (HTTP/2) server, silently failing (errors are swallowed by the hook scripts' `2>/dev/null || true`). Confirmed by manually testing otel-cli against both ports with --verbose --fail, then confirming trace receipt in collector logs after the fix.",
      "supersedes": null
    },
    {
      "id": "D-007",
      "date": "2026-08-11",
      "decision": "Replaced the hardcoded absolute path (/Users/andreaspoldi/my/test-o11y/...) in .claude/settings.json's hook commands with the ${CLAUDE_PROJECT_DIR} variable Claude Code sets for every hook invocation. Relocated the reference hooks.json template from the project root to assets/hooks.json (matching SKILL.md's documented file manifest, which had referenced a file that never existed there) and gave it the same placeholder plus the correct nested schema.",
      "rationale": "D-001 explicitly flagged the hardcoded path as sandbox-only and said it would need revisiting if hooks.json were ever templated across repos — that's exactly what publishing to GitHub for reproduction elsewhere requires. Verified ${CLAUDE_PROJECT_DIR} is real (official docs) and actually reaches the hook subprocess (captured its value from a live hook firing) before committing it to a public repo.",
      "supersedes": "D-001 (hardcoded path was correct for a single-machine sandbox; superseded now that the repo needs to work after a clone)"
    },
    {
      "id": "D-008",
      "date": "2026-08-11",
      "decision": "Rewrote emit_counter() in lib/common.sh to POST a real OTLP Sum metric (delta temporality, isMonotonic=true) as OTLP/HTTP JSON via curl+jq to ${OTEL_ENDPOINT}/v1/metrics, instead of faking a counter as an otel-cli span. Kept the exact same function signature (name, value, key=val...), so pre_tool_use.sh, post_tool_use.sh, and stop.sh needed zero changes. otel-cli itself is untouched and still handles all tracing (start_span/end_span).",
      "rationale": "Confirmed otel-cli's latest release (v0.4.5, Apr 2024) still has no metrics command — a hoped-for v0.5.0 with metrics/logs support never shipped — ruling out staying within otel-cli. User explicitly chose preserving the exact metric names/shape from metrics-dictionary.md over letting the collector derive different-shaped metrics from spans (e.g. via the spanmetrics connector), which also wouldn't have covered stop.sh's four session-level analysis metrics (they have no corresponding span to derive from). DELTA (not CUMULATIVE) temporality because each hook invocation is a fresh, stateless bash process with no persisted running total. Verified the collector's OTLP/HTTP receiver accepts JSON (not just protobuf) before committing to this approach, and verified full metric content (name/type/temporality/attributes/value) via the debug exporter's detailed verbosity before shipping. One implementation bug caught during testing: jq's --args flag requires the filter immediately after it, with positional args after the filter — putting them before it makes jq try to parse the first positional arg as the filter.",
      "supersedes": null
    },
    {
      "id": "D-009",
      "date": "2026-08-12",
      "decision": "Wrote all T-010 dashboard PromQL against the real double-prefixed metric names (e.g. `agent_agent_tool_call_total`) instead of the bare names documented in metrics-dictionary.md, and flagged the doc as stale (folded into T-008's scope) rather than fixing the docs in this session.",
      "rationale": "Verified live against Prometheus's own label-values API before building dashboard queries: the collector's prometheus exporter config sets `namespace: agent`, and every OTLP metric name already starts with `agent.` — so `agent.tool.call.total` becomes `agent_agent_tool_call_total`, not `agent_tool_call_total` as every example in metrics-dictionary.md shows. Also confirmed the exporter auto-appends `_total` to metrics whose name doesn't already end in 'total' (e.g. `agent.session.success_rate_pct` -> `..._pct_total`). Fixing the docs was out of scope for a dashboard task, so T-008 (already tracking stale docs in this same file) was extended to cover it instead of opening a near-duplicate task.",
      "supersedes": null
    },
    {
      "id": "D-010",
      "date": "2026-08-12",
      "decision": "Added a `delta_to_cumulative` processor to the otel-collector's metrics pipeline (otel-collector-config.yaml), between `attributes` and the `prometheus`/`debug` exporters.",
      "rationale": "Live-verified while validating T-010's dashboards: emit_counter() sends DELTA-temporality Sums (D-008's explicit choice, since each hook invocation is a stateless process). Fed directly to the Prometheus exporter without conversion, series didn't behave as real cumulative counters — a `tool_name=\"Bash\"` series was observed to exist, then vanish, then get overwritten rather than accumulate, making `rate()`/`increase()` (the query pattern the dashboards and metrics-dictionary.md both depend on) unreliable regardless of correct naming. Confirmed the fix by watching the same counter go from isolated single-sample values to a real monotonically-accumulating series (1 -> 4 across three spaced-out Bash calls) with `increase()` correctly reporting growth, both directly against Prometheus and proxied through Grafana's own datasource API.",
      "supersedes": null
    },
    {
      "id": "D-011",
      "date": "2026-08-12",
      "decision": "stop.sh's read-before-write check now uses: Read=read; Edit=write (Claude Code requires a prior Read on the same file before Edit succeeds, so this is a meaningful check); Bash with a `>`/`>>` redirect in its command=write (same string-matching heuristic as before, just fixed to the real tool name); Write=exempt from the check entirely (no naming fix maps to it — it's intentionally excluded).",
      "rationale": "Write in Claude Code is used for both creating brand-new files and overwriting existing ones, and post_tool_use.sh's session-log record has no field distinguishing the two cases. Flagging every Write as a potential violation would mostly catch ordinary new-file creation, not blind edits — so it gets the same exemption the original (fictional-tool-name) code gave 'create_file'. Verified against a synthetic session log covering all four cases (Edit-after-Read, Edit-without-Read, Write-to-new-file, Bash-redirect-to-unread-file): exactly the 2 expected violations fired (Edit-without-Read, Bash-redirect), with Write correctly never appearing in the write-targets set at all.",
      "supersedes": null
    },
    {
      "id": "D-012",
      "date": "2026-08-12",
      "decision": "Fixed metrics-dictionary.md's PromQL examples to the real double-prefixed metric names (D-009), corrected its TraceQL session-lookup query from `resource.agent.session.id` to `span.agent.session.id`, and removed the `span.agent.tool.is_retry`/`is_duplicate` TraceQL examples entirely (replaced with a note pointing at the equivalent PromQL metrics) rather than adding those attributes to spans. Also fixed the doc's remaining fictional-tool-name references (`str_replace`/`bash`/`view`/`create_file` in thresholds and common-pattern examples) to match D-011's real names, and fixed the same `resource.` → `span.` bug in T-010's own traces.json dashboard (found by testing the doc's claim empirically, not just trusting it).",
      "rationale": "Fetched a real trace's raw structure directly from Tempo's API before writing anything — confirmed `agent.session.id`/`agent.tool.name`/`agent.tool.params_hash` are span-level attributes (the resource only carries `service.name`), so the doc's original `resource.agent.session.id` query was wrong, not just the is_retry/is_duplicate ones T-008 originally flagged. Verified `resource.` returns 0 traces and `span.` returns real traces via direct Tempo search on two different session IDs, then re-verified end-to-end through Grafana's own datasource proxy after fixing traces.json. Chose to remove (not implement) the is_retry/is_duplicate attributes: that classification requires seeing calls *after* the one in question, which pre_tool_use.sh cannot know at span-creation time — adding it would mean rearchitecting span creation, out of scope for a docs-accuracy task.",
      "supersedes": null
    },
    {
      "id": "D-013",
      "date": "2026-08-12",
      "decision": "Implemented T-011's Skill Activations section against the real `Skill` tool (tool_name==\"Skill\", target==skill name) instead of the proposal doc's approach (detecting a Read of a SKILL.md path). Required a small upstream fix first: added `.skill` to post_tool_use.sh's TARGET-extraction fallback chain (`.path // .file // .file_path // .filepath // .command // .skill`), since the Skill tool's input has none of the existing fallback fields and target was landing as empty string on every real Skill record.",
      "rationale": "Checked real archived session-log records for tool==\"Skill\" before writing any stop.sh code (same discipline as D-010/D-011's live-data verification) — found 4 real Skill invocations, every one with target==\"\". The proposal doc's premise (skill activation = a Read of `.claude/skills/.*/SKILL.md`) doesn't hold in this harness: skill invocation goes through a dedicated Skill tool, not a file read, the same category of doc/reality mismatch T-005 fixed for tool names. Fixing target-extraction upstream is smaller and more correct than working around it in stop.sh, and it simplifies the stop.sh side too — target already IS the skill name, no path-parsing/sed needed as the original doc assumed. Verified both the extraction (`.skill` fallback resolves correctly, doesn't affect existing Read/Edit/Bash extraction) and the aggregation logic (per-skill counts, distinct-skill count) against synthetic data before considering it done.",
      "supersedes": null
    },
    {
      "id": "D-014",
      "date": "2026-08-13",
      "decision": "Changed all four panels in traces.json from `\"type\": \"traces\"` to `\"type\": \"table\"`.",
      "rationale": "User reported the Traces dashboard looked empty. Investigated in a real browser (not just curl) — Grafana's panel menu > Inspect > Data confirmed the query WAS returning full real trace data (15+ rows), and the panel editor's 'Table view' raw-data toggle rendered it correctly, but the actual 'Traces' panel visualization showed 'No data found in response' regardless. Root cause: the `traces` panel type renders a single trace's span waterfall, not a list of search results — it can't consume the multi-trace list shape Tempo's TraceQL search returns for a query like `{}`. Confirmed the fix live in Grafana's panel editor (switching one panel's visualization to 'Table' — Grafana's own top-recommended suggestion — rendered it correctly with clickable trace-ID links) before editing the source JSON, and re-verified all four panels post-fix, including the session-scoped one with a real live session ID.",
      "supersedes": null
    },
    {
      "id": "D-015",
      "date": "2026-08-13",
      "decision": "Rewrote the 'Overall Success Rate' panel to compute success rate from agent_agent_tool_call_total's own outcome label (`{outcome=\"success\"} / total`) instead of `1 - (error_total / call_total)`. Left 'Session Success Rate' as-is but strengthened its description to explicitly say 0%/No data during an active, still-running session is expected, not a real failure signal.",
      "rationale": "User asked why these two panels showed No data / 0%. Verified against live Prometheus: agent_agent_tool_call_error_total doesn't exist at all (zero errors ever recorded) — a division formula against an absent series returns no data in PromQL, not zero, so '1 - (errors/total)' wrongly showed 'No data' on a clean run instead of 100%. Fixed by computing the ratio from a metric that's guaranteed to exist (call_total is emitted on every single call, success or error) — verified the new query returns 1 (100%) against live data. Session Success Rate's 0% has a different, non-buggy cause already documented at D-009/D-010: it's a once-per-session delta counter, and increase() needs 2+ points in the window to show a nonzero delta — an ongoing session with no recent stop.sh run legitimately has nothing new to sum. Chose not to change that query further since doing so correctly would require redesigning how the metric is emitted (out of scope for a dashboard-panel question); documented the behavior instead so it reads as expected, not broken.",
      "supersedes": null
    }
  ],

  "completed": [
    {
      "id": "T-001",
      "title": "Fix ${SKILL_DIR} placeholder in .claude/hooks.json",
      "completed_date": "2026-08-11",
      "session_ref": "S-001",
      "notes": "Replaced all three hook commands (PreToolUse, PostToolUse, Stop) with absolute paths to assets/hooks/*.sh."
    },
    {
      "id": "T-002",
      "title": "Run install.sh preflight",
      "completed_date": "2026-08-11",
      "session_ref": "S-001",
      "notes": "jq already present. otel-cli was missing, downloaded to ~/.local/bin/otel-cli (confirmed on PATH). Hook scripts chmod +x. Collector unreachable at localhost:4317 as expected — that's T-003."
    },
    {
      "id": "T-003",
      "title": "Stand up the otel-collector via docker-compose",
      "completed_date": "2026-08-11",
      "session_ref": "S-001",
      "notes": "Container was already up but ports weren't published. Added ports mapping to docker-compose.yaml, force-recreated, confirmed 4317 and 4318 both reachable from host."
    },
    {
      "id": "T-004",
      "title": "Verify hooks fire end-to-end",
      "completed_date": "2026-08-11",
      "session_ref": "S-002",
      "notes": "Found the real blocker was structural (see D-003) plus three latent bugs (D-004, D-005, D-006) that only surfaced once hooks actually started firing. After all four fixes: PreToolUse/PostToolUse correctly open/close spans named by real tool_use_id, duration_ms reflects real elapsed time, collector logs confirm trace receipt (\"resource spans\": 1), and a manual stop.sh run archived the session log and reset state cleanly. Also fixed CLAUDE.md and SKILL.md, which both documented the now-disproven hooks.json-is-authoritative assumption."
    },
    {
      "id": "T-006",
      "title": "Publish reproducible sandbox to GitHub",
      "completed_date": "2026-08-11",
      "session_ref": "S-003",
      "notes": "Made hook paths portable via ${CLAUDE_PROJECT_DIR} (D-007), verifying the variable both exists (official docs) and reaches the hook subprocess (captured live) before committing it. Relocated the hooks.json template to assets/ to match SKILL.md's file manifest. Wrote .gitignore (excludes settings.local.json and OS cruft) and README.md (quick start, architecture diagram, known limitations, pointer to TASKS.md decision log). git init + remote add origin + initial commit (20 files) + push to https://github.com/andrea-spoldi/agent-observability main. Verified with a full install.sh + real-tool-call + collector-log pass after all changes, before pushing."
    },
    {
      "id": "T-007",
      "title": "Fix fake-metrics gap: emit_counter() never sends real OTLP metrics",
      "completed_date": "2026-08-11",
      "session_ref": "S-004",
      "notes": "Implemented per D-008: emit_counter() now posts real OTLP Sum metrics via curl+jq, zero changes needed to the three call sites. Ruled out staying within otel-cli by checking its release history (still v0.4.5, metrics never shipped). Verified the collector's HTTP receiver accepts OTLP JSON (not just protobuf) before committing to the approach. Hit and fixed one bug during testing: jq's --args needs the filter immediately after it, positional args after — had them reversed initially, which made jq try to compile 'tool_name=Bash' as a jq program. Verified end-to-end: collector debug exporter (bumped to verbosity:detailed temporarily, reverted after) showed correct name/type/temporality/attributes/value for a real emit_counter call, and both pre/post-hook call-level metrics and stop.sh's session-level metrics land correctly. Added a curl preflight check to install.sh since it's now a runtime dependency, not just install-time. Updated README.md and CLAUDE.md to describe the new mechanism. Opened T-008 for an unrelated stale-docs issue found along the way (metrics-dictionary.md's TraceQL examples reference span attributes that don't exist)."
    },
    {
      "id": "T-009",
      "title": "Replace OpenObserve with Tempo + Prometheus + Grafana",
      "completed_date": "2026-08-12",
      "session_ref": "S-005",
      "notes": "Executed as a 4-task SDD plan (docs/superpowers/plans/2026-08-11-tempo-grafana-migration.md; design doc at docs/superpowers/specs/2026-08-11-tempo-grafana-migration-design.md). Task 1 (Tempo): hit a real blocker — the brief's compactor.compaction.block_retention block is valid YAML but Tempo v3.0.0 removed the legacy compactor component from its schema, so the container refused to start with it present (commit ab992b8 shipped the spec-faithful-but-broken version; paused for controller/user decision at the session boundary). On resume, user chose to drop the block and accept Tempo's default 336h retention rather than pin an older Tempo version or hunt for a v3.0.0-native retention equivalent (commit 379c49b); retention hardening deferred to a future task. Task 2 (Prometheus, commit 41d206d): collector's prometheus exporter wired into the metrics pipeline, Prometheus container added scraping :8889 every 15s. Task 3 (Grafana, commit f9b33be): datasources auto-provisioned via file (assets/grafana-datasources.yaml), no starter dashboard per plan constraints. All verification used real data through the actual hook lib (start_span/end_span/emit_counter), never synthetic payloads — confirmed via Tempo's /api/search, Prometheus's query API, and Grafana's /api/health + /api/datasources, first per-task and then as a full-stack proof with all four services running together. Also resolved the hardcoded-credential issue found at the start of S-005 as a side effect — the OpenObserve exporter and its Authorization header are gone entirely. The orphaned openobserve container from the earlier proof-of-concept (started via plain docker run, outside this repo's docker-compose.yaml) is still running and still holds port 5080; user can docker stop/rm it once satisfied."
    },
    {
      "id": "T-010",
      "title": "Create Grafana dashboards for OTEL metrics and traces",
      "completed_date": "2026-08-12",
      "session_ref": "S-006",
      "notes": "Two dashboards, both provisioned via file per user's choice to split metrics and traces rather than combine: 'Agent Tool Metrics' (assets/dashboards/tool-metrics.json, Prometheus, 4-row layout per metrics-dictionary.md's suggestion — dropped the duration box-plot and error-rate heatmap since no duration metric is emitted and Sankey since it needs an unavailable community plugin, substituting panel types the actual counter/gauge-shaped metrics support) and 'Agent Tool Traces' (assets/dashboards/traces.json, Tempo, all-traces/error-spans/slow-calls/session-scoped panels using only span attributes confirmed to actually exist — agent.tool.name, agent.session.id — not the is_retry/is_duplicate attributes T-008 already flagged as fictional). Added explicit `uid: tempo`/`uid: prometheus` to grafana-datasources.yaml so dashboard JSON can reference stable datasource UIDs. New assets/grafana-dashboards-provider.yaml + docker-compose.yaml volume mounts wire the dashboards directory into Grafana's file-provisioning path, matching the existing datasource pattern (CLAUDE.md updated to document it, still 48 lines). Found two real bugs while verifying against live data rather than trusting the docs: (1) every metric name in metrics-dictionary.md's PromQL examples is stale — real names are double-prefixed by the collector's `namespace: agent` exporter setting plus an auto-appended `_total` (D-009; folded into T-008's scope rather than opening a duplicate task); (2) emit_counter()'s DELTA-temporality metrics weren't accumulating correctly through the Prometheus exporter at all — series appeared/vanished/overwrote instead of incrementing, which would have made every increase()/rate() panel unreliable. Fixed by adding a `delta_to_cumulative` processor to the collector's metrics pipeline (D-010). Verified end-to-end post-fix: watched a real Bash-tool counter accumulate 1->4 across three spaced tool calls with correct `increase()` output, both directly against Prometheus and proxied through Grafana's own datasource API, plus confirmed real trace data resolves through Grafana's Tempo proxy."
    },
    {
      "id": "T-005",
      "title": "Fix tool-name mismatch in stop.sh's read-before-write check",
      "completed_date": "2026-08-12",
      "session_ref": "S-007",
      "notes": "Decision (D-011): Read=read, Edit=write (Claude Code enforces a prior Read before Edit, so this check is meaningful), Bash-with-redirect=write (same heuristic as before, just correctly named), Write=exempt (no prior-existence signal in the hook payload to distinguish legitimate new-file creation from a blind overwrite, same treatment the old fictional-tool-name code gave 'create_file'). Also dropped the now-dead 'create_file' skip-loop since Write no longer enters the write-targets set at all. Verified against a synthetic 5-record session log (not the live one, to avoid disrupting hook state mid-session) covering all four cases: Edit-after-Read (no violation), Edit-without-Read (violation), Write-to-new-file (never flagged), Bash-redirect-to-unread-target (violation) — exactly 2 violations fired, matching expectations. Unblocks T-011 and T-012, which depended on the same tool-name mapping decision."
    },
    {
      "id": "T-008",
      "title": "Fix stale TraceQL/PromQL examples in metrics-dictionary.md",
      "completed_date": "2026-08-12",
      "session_ref": "S-008",
      "notes": "Fixed every PromQL example to the real double-prefixed metric names (D-009), added an explanatory note at the top of the doc so future readers understand why (rather than re-deriving it per-metric). Found and fixed a third, previously-unflagged bug while verifying against a live trace's raw structure: the TraceQL session-lookup query used `resource.agent.session.id`, but agent.session.id is actually a span-level attribute (only service.name is resource-level) — confirmed empirically (0 vs N traces returned) before touching anything, then fixed to `span.agent.session.id` here AND in T-010's traces.json dashboard, which had unknowingly inherited the same bug from trusting this doc. Removed the is_retry/is_duplicate TraceQL examples (D-012: that classification can't exist as a span attribute given how pre_tool_use.sh works) rather than trying to implement the attributes, replacing them with a pointer to the equivalent PromQL metrics. Also cleaned up the doc's remaining fictional-tool-name references (str_replace/bash/view/create_file) to match D-011, and added a short note reconciling the aspirational 'Dashboard Layout Suggestion' section with what T-010 actually built (duration/heatmap/Sankey panels couldn't be implemented as literally suggested). All fixes re-verified against a live collector/Tempo/Grafana stack, not just reasoned about."
    },
    {
      "id": "T-011",
      "title": "Add Skill Activations section to stop.sh",
      "completed_date": "2026-08-12",
      "session_ref": "S-009",
      "notes": "Implemented against the real `Skill` tool rather than the proposal doc's Read-of-SKILL.md approach — checked archived session-log records first and found skill invocations go through their own dedicated tool, not a file read, with target always empty on those records (D-013). Fixed by adding `.skill` to post_tool_use.sh's target-extraction fallback chain, which made target equal the skill name directly and simplified stop.sh's implementation (no path-parsing needed, unlike the original proposal). New Section 5 in stop.sh (renumbered: summary metrics 5→6, archive 6→7; header comment updated) emits `agent.skill.activation` per skill name (real per-invocation counts, not just presence — a skill invoked twice shows count=2) and `agent.skill.activations_per_session` (distinct skill count). Verified both the extraction fix and the aggregation logic against synthetic data: 2 distinct skills, one invoked twice, correctly produced activation counts of 2 and 1, and a distinct-count of 2."
    },
    {
      "id": "T-010 (regression fix)",
      "title": "Fix empty Traces dashboard — wrong panel type",
      "completed_date": "2026-08-13",
      "session_ref": "S-010",
      "notes": "User reported the Traces dashboard looked empty. T-010's original verification had only checked the datasource proxy API returned data (curl), never actually loaded the dashboard in a browser — that gap is exactly why this shipped unnoticed. This time investigated in a real browser: Grafana's panel Inspect > Data confirmed the query WAS returning full real data, and the panel editor's raw 'Table view' toggle rendered it fine, but the panel's actual visualization still said 'No data found in response'. Root cause (D-014): all four panels used `\"type\": \"traces\"`, which renders a single trace's span waterfall — it can't display a multi-trace search-result list, which is what every query in this dashboard returns. Confirmed the fix live in Grafana's panel editor first (switched to Grafana's own top-suggested 'Table' visualization, saw it render correctly with clickable trace-ID links) before editing traces.json, then redeployed and re-verified all four panels in-browser, including the session-scoped one filtered to a real live session ID."
    },
    {
      "id": "T-010 (regression fix #2)",
      "title": "Fix Overall/Session Success Rate panels showing No data / 0%",
      "completed_date": "2026-08-13",
      "session_ref": "S-011",
      "notes": "User asked why these two panels looked wrong. Verified both against live Prometheus before touching anything (D-015): 'Overall Success Rate' used `1 - (error_total/call_total)`, but agent_agent_tool_call_error_total doesn't exist in Prometheus at all yet (zero errors ever recorded across any session) — dividing by an absent series returns no data in PromQL, not zero, so a clean run wrongly showed 'No data' instead of 100%. Fixed by computing the ratio from call_total's own outcome label instead (`{outcome=\"success\"}/total`), which is guaranteed to exist since it's emitted on every call regardless of outcome — verified the new query returns 1 (100%) live. 'Session Success Rate' at 0% turned out not to be a bug: it's the same once-per-session delta-counter behavior already documented at D-009/D-010 — increase() needs 2+ points in the window to show a nonzero delta, and an actively-running session with no recent stop.sh run legitimately has nothing new to sum. Left that query as-is (fixing it properly would mean redesigning how the metric is emitted, out of scope here) and strengthened the panel's description instead so the 0% reads as expected behavior, not a failure."
    },
    {
      "id": "docs-update",
      "title": "Update README.md, SKILL.md, CLAUDE.md to explain how to use the PoC",
      "completed_date": "2026-08-13",
      "session_ref": "S-012",
      "notes": "README.md was still describing the pre-T-009 single-collector setup with no mention of Tempo/Prometheus/Grafana at all, and its 'Known limitations' section claimed T-005/T-008 were still open (both done days ago). Rewrote: quick start now covers the full 4-service docker-compose stack, added a 'Viewing the data' section (Grafana URL/login, the two dashboards, scrape-delay expectations, direct backend access), replaced the stale limitations list with the three that are actually still true (once-per-session success-rate counter behavior, TraceQL can't see retry/duplicate, T-012/T-013 not yet built), and updated the decision-log pointer from D-008 to D-015. SKILL.md (the portable/generic skill doc, meant for adopting this elsewhere) was more substantially wrong — it described the never-implemented aspirational design rather than what's actually built: `agent.tool.calls_per_session` documented as Histogram when it's actually a Counter; span attributes list included agent.tool.outcome/is_retry/is_duplicate, none of which are real (confirmed empirically in T-008/D-012 — outcome is only on span status, retry/duplicate are metrics-only); the read-before-write and trace examples still used fictional tool names (str_replace/view/bash_tool) instead of D-011's real Read/Edit/Write/Bash mapping; Setup Step 2 was a generic `docker run` one-liner with no mention of this repo's actual working Tempo+Prometheus+Grafana compose stack or the two adoption gotchas (D-009 metric-naming double-prefix, D-010 delta_to_cumulative requirement) anyone reusing this with their own Prometheus would hit; file manifest was missing every dashboard/backend-config asset added since T-009/T-010. Added a new Skill Activation metrics section (T-011) that didn't exist in the doc at all. CLAUDE.md got a new bullet documenting the delta_to_cumulative/metric-naming gotchas (real, previously-undocumented architecture constraints), and had its redundant 'Stack shorthand' section removed to stay under the project's own 50-line budget (47 lines after the trade)."
    }
  ]
}
```

## Backlog (human view)

| ID | Title | Size | Priority | Status |
|----|-------|------|----------|--------|
| T-001 | Fix `${SKILL_DIR}` placeholder in `.claude/hooks.json` | S | 1 | done |
| T-002 | Run `install.sh` preflight | S | 2 | done |
| T-003 | Stand up the otel-collector via docker-compose | S | 3 | done |
| T-004 | Verify hooks fire end-to-end | M | 4 | done |
| T-005 | Fix tool-name mismatch in `stop.sh`'s read-before-write check | S | 5 | done |
| T-006 | Publish reproducible sandbox to GitHub | M | 6 | done |
| T-007 | Fix fake-metrics gap: `emit_counter()` never sends real OTLP metrics | M | 7 | done |
| T-008 | Fix stale TraceQL/PromQL examples in `metrics-dictionary.md` | S | 8 | done |
| T-009 | Replace OpenObserve with Tempo + Prometheus + Grafana | M | 4 | done |
| T-010 | Create Grafana dashboards for OTEL metrics and traces | M | 4 | done |
| T-011 | Add Skill Activations section to `stop.sh` | S | 9 | done |
| T-012 | Add Task Decomposition Efficiency section to `stop.sh` | M | 10 | pending |
| T-013 | Add Agent Robustness (error recovery) section to `stop.sh` | M | 11 | pending |

## Decisions

- **D-001** (2026-08-11): Hardcoded absolute path in `hooks.json` instead of `${SKILL_DIR}` — see JSON block above for rationale.
- **D-002** (2026-08-11): Published ports 4317/4318 in `docker-compose.yaml` — collector was running but unreachable from host.
- **D-003** (2026-08-11): Wired hooks into `.claude/settings.json` — Claude Code never reads `.claude/hooks.json` at all. Supersedes S-001's assumption that a fresh session alone would fix T-004.
- **D-004** (2026-08-11): Fixed `CALL_ID` derivation to use the real payload field `tool_use_id` instead of the nonexistent `call_id` — fixes span/timestamp files silently colliding on hidden dotfiles.
- **D-005** (2026-08-11): Fixed `now_ms()` to validate `date`'s output is numeric before trusting it — BSD/macOS `date` doesn't support `%3N` and was silently corrupting every duration measurement.
- **D-006** (2026-08-11): Fixed the default OTEL endpoint from port 4317 (gRPC) to 4318 (HTTP) to match `otel-cli`'s `http://` scheme-based protocol selection — traces were silently never reaching the collector.
- **D-007** (2026-08-11): Replaced the hardcoded absolute path in `.claude/settings.json` with `${CLAUDE_PROJECT_DIR}` and relocated the `hooks.json` template to `assets/` — supersedes D-001, needed for the repo to work after a clone.
- **D-008** (2026-08-11): Rewrote `emit_counter()` to POST real OTLP `Sum` metrics (delta temporality) via `curl`+`jq` instead of faking counters as `otel-cli` spans — `otel-cli` still has no metrics command as of its latest release (v0.4.5). Zero changes needed to the three call sites since the function signature stayed the same.
- **D-009** (2026-08-12): Built T-010's dashboards against the real double-prefixed metric names (`agent_agent_tool_call_total`, not `agent_tool_call_total`) — the collector's `namespace: agent` exporter setting doubles up with metric names that already start with `agent.`. `metrics-dictionary.md`'s PromQL examples are all stale on this; folded into T-008 rather than opening a duplicate doc-fix task.
- **D-010** (2026-08-12): Added a `delta_to_cumulative` processor to the collector's metrics pipeline — D-008's DELTA-temporality counters weren't accumulating correctly through the Prometheus exporter (series appeared/vanished/overwrote instead of incrementing), which would have made every `rate()`/`increase()` query unreliable. Verified fixed by watching a real counter accumulate correctly across spaced tool calls.
- **D-011** (2026-08-12): `stop.sh`'s read-before-write check now maps `Read`=read, `Edit`=write, `Bash`-with-redirect=write, and exempts `Write` entirely (no signal in the hook payload distinguishes new-file creation from a blind overwrite). Verified against a synthetic 4-case session log — exactly the 2 expected violations fired.
- **D-012** (2026-08-12): Fixed `metrics-dictionary.md`'s PromQL to the real metric names (D-009) and its TraceQL session query from `resource.agent.session.id` to `span.agent.session.id` — found via a live trace's raw structure that session id is span-level, not resource-level (only `service.name` is resource-level). Same bug existed in T-010's `traces.json`; fixed there too. Removed the fictional `is_retry`/`is_duplicate` TraceQL examples rather than implementing them — that classification needs to see future calls, which `pre_tool_use.sh` can't at span-creation time.
- **D-013** (2026-08-12): Skill activation detection uses the real `Skill` tool (target==skill name, via a new `.skill` fallback in `post_tool_use.sh`'s target-extraction), not the proposal doc's Read-of-SKILL.md approach — checked real archived session logs first and found every `Skill` record had an empty target, since skill invocation is its own tool in this harness, not a file read.
- **D-014** (2026-08-13): Traces dashboard's 4 panels switched from `\"type\": \"traces\"` to `\"type\": \"table\"` — the `traces` panel type renders one trace's span waterfall, not a multi-trace search-result list, which is what every panel's query actually returns. Found by loading the dashboard in a real browser (T-010's original verification never had) and confirmed via Grafana's own Inspect > Data and panel-editor visualization switcher before touching the source file.
- **D-015** (2026-08-13): 'Overall Success Rate' now computes from `call_total{outcome="success"}/call_total` instead of `1 - (error_total/call_total)` — the error-total metric doesn't exist until the first error ever happens, and dividing by an absent series returns no data in PromQL, not zero. 'Session Success Rate' left as-is at 0%/No data during an active session — that's expected once-per-session delta-counter behavior (D-009/D-010), not a bug; description strengthened to say so.

## Completed

- **T-001** (2026-08-11, S-001): Fixed `${SKILL_DIR}` placeholder in `.claude/hooks.json`.
- **T-002** (2026-08-11, S-001): Ran `install.sh` preflight — jq ok, otel-cli installed, hooks chmod +x.
- **T-003** (2026-08-11, S-001): Published collector ports, confirmed reachable at localhost:4317/4318.
- **T-004** (2026-08-11, S-002): Verified hooks fire end-to-end after fixing four compounding bugs (D-003 through D-006). Confirmed via collector logs (`"resource spans": 1`), a correct `duration_ms`, correctly-named span files, and a clean manual `stop.sh` run (archived log, reset session state). Also corrected `CLAUDE.md` and `SKILL.md`, which both documented the disproven "hooks.json is authoritative" assumption.
- **T-006** (2026-08-11, S-003): Made hook config portable (D-007), wrote `.gitignore`/`README.md`, and pushed the initial commit to `https://github.com/andrea-spoldi/agent-observability` (main).
- **T-007** (2026-08-11, S-004): `emit_counter()` now sends real OTLP metrics (D-008) instead of fake spans — verified with detailed collector-log output showing correct name/type/temporality/attributes/value, and confirmed both per-call and session-level (`stop.sh`) metrics land correctly.
- **T-009** (2026-08-12, S-005): Replaced OpenObserve with Tempo (traces) + Prometheus (metrics) + Grafana (dashboards, datasources auto-provisioned) via a 4-task SDD plan. Hit and resolved a real Tempo v3.0.0 schema blocker (dropped the brief's `compactor` block, accepted default retention — user's call). Verified end-to-end via real hook-lib span/counter emission queried back from Tempo and Prometheus directly, plus Grafana health/datasource checks, with all four services running together. Commits: `379c49b`, `41d206d`, `f9b33be`.
- **T-010** (2026-08-12, S-006): Built two provisioned Grafana dashboards — `Agent Tool Metrics` (Prometheus, 4-row layout) and `Agent Tool Traces` (Tempo, session/error/slow-call search). Found and fixed two real pipeline bugs while verifying against live data: metrics-dictionary.md's PromQL examples use stale (non-double-prefixed) metric names (D-009), and DELTA-temporality counters weren't accumulating through the Prometheus exporter at all until a `delta_to_cumulative` processor was added (D-010). Verified end-to-end: real Bash-tool counter accumulating correctly, real traces resolving through Grafana's Tempo proxy.
- **T-005** (2026-08-12, S-007): Fixed `stop.sh`'s read-before-write check to use real Claude Code tool names (D-011: `Read`=read, `Edit`=write, `Bash`-redirect=write, `Write`=exempt). Verified against a synthetic session log covering all four cases — correct violations fired. Unblocks T-011/T-012.
- **T-008** (2026-08-12, S-008): Fixed `metrics-dictionary.md`'s stale PromQL (D-009 naming) and TraceQL. Found a third bug while verifying live — session-id was queried via `resource.` when it's actually a span-level attribute (D-012) — and fixed the same bug in T-010's `traces.json`. Removed the never-real `is_retry`/`is_duplicate` TraceQL examples instead of implementing them. Also cleaned up leftover fictional tool names elsewhere in the doc.
- **T-011** (2026-08-12, S-009): Added Skill Activations to `stop.sh`, but not as the proposal doc described — found real Skill invocations always had an empty target, since skill activation is its own tool here, not a Read of SKILL.md (D-013). Fixed target-extraction upstream in `post_tool_use.sh` first, which also simplified the stop.sh side. Verified against synthetic data: correct per-skill and distinct-skill counts.
- **T-010 regression fix** (2026-08-13, S-010): Traces dashboard looked empty to the user despite T-010's earlier API-level verification passing — the gap was never loading it in an actual browser. Root cause: wrong panel type (D-014, `traces` vs `table`). Fixed and re-verified all 4 panels in-browser with real data, including the session-scoped filter.
- **T-010 regression fix #2** (2026-08-13, S-011): User asked why 'Overall Success Rate' showed No data and 'Session Success Rate' showed 0%. First was a real query bug (D-015, dividing by an absent error metric); fixed and verified returns 100% live. Second is expected once-per-session counter behavior, not a bug — documented in the panel instead of chased further.
- **Docs update** (2026-08-13, S-012): Rewrote `README.md` (was pre-T-009, no Tempo/Prometheus/Grafana mentioned, "known limitations" listed two already-fixed bugs) and `SKILL.md` (still described the never-implemented aspirational design — wrong metric types, fictional span attributes, fictional tool names, missing T-011's Skill Activation metrics, no adoption gotchas for D-009/D-010). Trimmed `CLAUDE.md` back under 50 lines after adding the delta_to_cumulative/naming-prefix constraint.
