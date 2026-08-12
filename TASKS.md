# TASKS.md — test-o11y

```json
{
  "project": "test-o11y",
  "updated": "2026-08-12",
  "_session_note": "S-005 spanned 2026-08-11 to 2026-08-12 (resumed after a session boundary). Replaced OpenObserve entirely with a Tempo (traces) + Prometheus (metrics) + Grafana (dashboards, datasources auto-provisioned) stack per the SDD plan at docs/superpowers/plans/2026-08-11-tempo-grafana-migration.md, executed task-by-task with real per-task commits (fb0d8fc/ab992b8/379c49b for Task 1, 41d206d for Task 2, f9b33be for Task 3). Task 1 hit a real blocker mid-session-1: the brief's compactor.compaction.block_retention block is valid YAML but Tempo v3.0.0 removed the legacy compactor component from its schema, so the container refused to start with it present — paused for a controller/user decision. On resume, user chose to drop the block and accept Tempo's default 336h retention (deferring retention hardening to a future task) rather than pin an older Tempo version or hunt for a v3.0.0-native equivalent. All three backends verified end-to-end together via real hook-lib span/counter emission (start_span/end_span/emit_counter), queried back from Tempo's /api/search and Prometheus's query API directly, with Grafana's health check and both datasources (Tempo, Prometheus) confirmed provisioned via its API. T-005 and T-008 remain the top pending backlog items for the next session. Untracked clipped-article file at repo root still unaddressed, low priority. The openobserve container from the earlier proof-of-concept is still running (started via plain docker run, not part of this repo's docker-compose.yaml) — user can docker stop/rm it once satisfied the new stack covers their needs.",

  "current_session": {
    "id": "S-006",
    "goal": "Create Grafana dashboards for OTEL metrics (Prometheus) and traces (Tempo)",
    "task_ref": "T-010",
    "started": "2026-08-12",
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
      "status": "pending",
      "tags": ["hooks", "bugfix", "stop.sh"]
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
      "status": "pending",
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
| T-005 | Fix tool-name mismatch in `stop.sh`'s read-before-write check | S | 5 | pending |
| T-006 | Publish reproducible sandbox to GitHub | M | 6 | done |
| T-007 | Fix fake-metrics gap: `emit_counter()` never sends real OTLP metrics | M | 7 | done |
| T-008 | Fix stale TraceQL/PromQL examples in `metrics-dictionary.md` | S | 8 | pending |
| T-009 | Replace OpenObserve with Tempo + Prometheus + Grafana | M | 4 | done |
| T-010 | Create Grafana dashboards for OTEL metrics and traces | M | 4 | done |

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

## Completed

- **T-001** (2026-08-11, S-001): Fixed `${SKILL_DIR}` placeholder in `.claude/hooks.json`.
- **T-002** (2026-08-11, S-001): Ran `install.sh` preflight — jq ok, otel-cli installed, hooks chmod +x.
- **T-003** (2026-08-11, S-001): Published collector ports, confirmed reachable at localhost:4317/4318.
- **T-004** (2026-08-11, S-002): Verified hooks fire end-to-end after fixing four compounding bugs (D-003 through D-006). Confirmed via collector logs (`"resource spans": 1`), a correct `duration_ms`, correctly-named span files, and a clean manual `stop.sh` run (archived log, reset session state). Also corrected `CLAUDE.md` and `SKILL.md`, which both documented the disproven "hooks.json is authoritative" assumption.
- **T-006** (2026-08-11, S-003): Made hook config portable (D-007), wrote `.gitignore`/`README.md`, and pushed the initial commit to `https://github.com/andrea-spoldi/agent-observability` (main).
- **T-007** (2026-08-11, S-004): `emit_counter()` now sends real OTLP metrics (D-008) instead of fake spans — verified with detailed collector-log output showing correct name/type/temporality/attributes/value, and confirmed both per-call and session-level (`stop.sh`) metrics land correctly.
- **T-009** (2026-08-12, S-005): Replaced OpenObserve with Tempo (traces) + Prometheus (metrics) + Grafana (dashboards, datasources auto-provisioned) via a 4-task SDD plan. Hit and resolved a real Tempo v3.0.0 schema blocker (dropped the brief's `compactor` block, accepted default retention — user's call). Verified end-to-end via real hook-lib span/counter emission queried back from Tempo and Prometheus directly, plus Grafana health/datasource checks, with all four services running together. Commits: `379c49b`, `41d206d`, `f9b33be`.
- **T-010** (2026-08-12, S-006): Built two provisioned Grafana dashboards — `Agent Tool Metrics` (Prometheus, 4-row layout) and `Agent Tool Traces` (Tempo, session/error/slow-call search). Found and fixed two real pipeline bugs while verifying against live data: metrics-dictionary.md's PromQL examples use stale (non-double-prefixed) metric names (D-009), and DELTA-temporality counters weren't accumulating through the Prometheus exporter at all until a `delta_to_cumulative` processor was added (D-010). Verified end-to-end: real Bash-tool counter accumulating correctly, real traces resolving through Grafana's Tempo proxy.
