# TASKS.md — test-o11y

```json
{
  "project": "test-o11y",
  "updated": "2026-08-11",
  "_session_note": "S-002 closed 2026-08-11. T-004 done — but the real blocker wasn't the fresh-session assumption from S-001, it was that Claude Code never reads .claude/hooks.json at all. Found and fixed four independent bugs to get hooks firing end-to-end. New backlog item T-005 opened for a leftover analysis bug in stop.sh.",

  "current_session": {
    "id": "S-002",
    "goal": "Verify hooks fire end-to-end (T-004)",
    "task_ref": "T-004",
    "started": "2026-08-11",
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

## Decisions

- **D-001** (2026-08-11): Hardcoded absolute path in `hooks.json` instead of `${SKILL_DIR}` — see JSON block above for rationale.
- **D-002** (2026-08-11): Published ports 4317/4318 in `docker-compose.yaml` — collector was running but unreachable from host.
- **D-003** (2026-08-11): Wired hooks into `.claude/settings.json` — Claude Code never reads `.claude/hooks.json` at all. Supersedes S-001's assumption that a fresh session alone would fix T-004.
- **D-004** (2026-08-11): Fixed `CALL_ID` derivation to use the real payload field `tool_use_id` instead of the nonexistent `call_id` — fixes span/timestamp files silently colliding on hidden dotfiles.
- **D-005** (2026-08-11): Fixed `now_ms()` to validate `date`'s output is numeric before trusting it — BSD/macOS `date` doesn't support `%3N` and was silently corrupting every duration measurement.
- **D-006** (2026-08-11): Fixed the default OTEL endpoint from port 4317 (gRPC) to 4318 (HTTP) to match `otel-cli`'s `http://` scheme-based protocol selection — traces were silently never reaching the collector.

## Completed

- **T-001** (2026-08-11, S-001): Fixed `${SKILL_DIR}` placeholder in `.claude/hooks.json`.
- **T-002** (2026-08-11, S-001): Ran `install.sh` preflight — jq ok, otel-cli installed, hooks chmod +x.
- **T-003** (2026-08-11, S-001): Published collector ports, confirmed reachable at localhost:4317/4318.
- **T-004** (2026-08-11, S-002): Verified hooks fire end-to-end after fixing four compounding bugs (D-003 through D-006). Confirmed via collector logs (`"resource spans": 1`), a correct `duration_ms`, correctly-named span files, and a clean manual `stop.sh` run (archived log, reset session state). Also corrected `CLAUDE.md` and `SKILL.md`, which both documented the disproven "hooks.json is authoritative" assumption.
