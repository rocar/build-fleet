# Verified Review (0.12) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `REVIEW_SHAPE: verified` beside today's `debate` review: checkable findings, a panel of fresh verifiers, a quote-backed majority vote, a quote check that runs when the scribe finishes, and a finalize gate that recomputes the vote, plus the event-log essentials it records into.

**Architecture:** The rules exist twice and are tested equal: in jq (`scripts/lib/verified-review.jq`, used by `quote-check.sh` and `finalize-gate.sh`, the authority) and in JS (`workflows/review.js`, the workflow's provisional result). The workflow branches after the fan-out: debate keeps cross-examination and the survival vote; verified runs a 3-verifier panel and a pure-JS vote, then renders REVIEW.md lines the jq rules parse. A PostToolUse hook on the scribe's final write (the empty `.workflow-in-flight`) runs the quote check once per cycle and records one event; the gate reads it. `review-carry.sh` hands the next cycle its open set and budget exemption. Nothing changes while `REVIEW_SHAPE` is unset.

**Tech Stack:** bash 3.2 + BSD/GNU coreutils + jq ≥ 1.6 (scripts, hooks, harnesses); plain JS in the Claude Code Workflow runtime (no `Date`, no filesystem); node for the JS harnesses (skipped locally when absent, enforced in CI); markdown commands, agents, skills.

**Spec:** `docs/history/2026-10-14-verified-review.md` (read it first; every task cites its sections). Dependency spec: `docs/history/2026-10-14-dashboard.md` §3.1 and §3.4 (Part A). This plan builds only the Part A pieces the protocol needs: `log_event`, the event-log write guard, `finalize-gate.sh --report` and its gate event. The rest of Part A (refusal logging in every hook, `record-phase.sh`, `approval_status`, the debate-shape `ref:` line) is a separate plan once that spec is approved.

## Global Constraints

- **Work in the release worktree only:** `~/build-fleet-0.12` on the existing branch `release/0.12.0` (Task 1 creates the worktree). All paths are relative to it. Never edit `~/build-fleet`.
- **Tests first, every task:** write the harness, run it red, write the code, run it green, run `bash scripts/run-tests.sh`, then commit. Baseline: `suites: 30, failed: 0`. Each task states the expected suite count after it lands; the final count is **40**.
- **Hooks fail closed** (CLAUDE.md), with ONE deliberate exception this plan adds: `log_event` swallows its own failures, so logging never changes a gate's decision (spec dashboard §3.1). Task 13 writes that exception into CLAUDE.md.
- **bash 3.2 + GNU-coreutils compatible:** no associative arrays, no `mapfile`, no `${var,,}`; `sed -i` only with a suffix in tests; `sha256_stdin` probes `sha256sum` before `shasum -a 256`.
- **jq ≥ 1.6** (`--rawfile` is not used; `try … catch`, `capture`, `$__loc__`-free). CI's Ubuntu jq is 1.7.
- **Workflows:** after any `review.js` edit run the wrapped parse check `{ echo '(async function(){'; sed 's/^export const meta/const meta/' workflows/review.js; echo '})'; } > /tmp/review-wrapped.js && node --check /tmp/review-wrapped.js && echo "parse ok"` and `bash scripts/workflow-determinism-lint.sh workflows/review.js` (expect `BUILD_FLEET_LINT_PASS`).
- **The JS and jq rules are twins:** any change to one changes the other in the same commit; `scripts/verified-vote-parity.test.sh` must stay green.
- **Lenses are double-maintained** (`lens-drift.test.sh`): this plan does not touch any `## Review lens` text or the `LENS` block.
- **Severity table is quadruple-maintained** (`rubric-drift.test.sh`): never edit the `| Severity |` table. Task 11 adds a second drift-checked block (the verified rule) to the same four files.
- **Any agent whose body changes gets a refreshed `description:`** (reviewer, architect, qa); exact text in Task 11.
- **Signal lines are the machine contract.** New lines: `BUILD_FLEET_QUOTE_CHECK`, `BUILD_FLEET_FINALIZE_REPORT`, `BUILD_FLEET_REVIEW_CARRY`. New refusal reasons on `BUILD_FLEET_FINALIZE_GATE`: `quote-check-missing`, `spec-changed-since-review`; on `/build-fleet:review`: `shape-changed-mid-feature`. New workflow `incomplete` reason: `verifier-panel`. Never document an exit-code table.
- **No milestone jargon in user-facing text** (command and agent bodies say what happens, never "since 0.12").
- **Commit messages** end with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- **The verified drafts.** Every new file and every patch below was run before this plan was written, in a scratch copy of the repo at `a82c5b6`: `bash scripts/run-tests.sh` → `suites: 40, failed: 0` (bash 3.2, jq 1.7.1, node 26); the patches apply with `git apply` to `a82c5b6`; `review.js` passed the wrapped parse check and the determinism lint, and the six existing workflow suites stayed green. Copy them verbatim.

## Rulings (where this plan departs from the spec's letter)

1. **Events are keyed by `cycle_total`, not only `cycle`.** `CYCLE` resets on `/build-fleet:resolve-escalation`, so `cycle` collides across review phases; `CYCLE_TOTAL` never resets. The quote-check event carries both; "first event per cycle" (spec §3.4) is implemented as first per `cycle_total`, and `review-carry.sh` counts a phase's exempt cycles as `cycle_total` in `(CYCLE_TOTAL − CYCLE, CYCLE_TOTAL]`. Cost if wrong: none for users (fields are additive).
2. **The verified-review header keeps the raised severity.** `- [major] (id)` is the severity the reviewer raised; the final severity is recomputed from the `verdict:` lines (and summarised on `verified:`). This keeps the gate's input independent of the workflow's arithmetic.
3. **The spec's "smoke test" (§5) is a new suite, `scripts/verified-review-e2e.test.sh`,** not an edit of `docs/v0.5/smoke/smoke.sh`, which is the bug lane's smoke and stays untouched.
4. **The mirrored verified rule is drift-checked** by extending `rubric-drift.test.sh` to compare a marker-delimited block in the four rubric copies (spec §3.7 says the drift test keeps them identical; today it only covers the table).
5. **`/status` shows verified state through `finalize-gate.sh --report`;** `status-snapshot.sh` gains only `active.review_shape` (spec §3.6's summary counts are read from the report and the event by `/status`, not added to the snapshot schema).
6. **A carried finding whose raiser left the roster** is written by the workflow into the first roster role's block (`host`), with its `carried:` line, so it stays in the record every cycle; only its raiser can close it (put the raiser back on the roster, or disposition a major `adr`). Every reader of verified blocks (`quote-check.sh`, the gate's previous-cycle safety net, `review-carry.sh`) takes the roles from that cycle's headings (`cycle_roles`), not the roster, because a `--roles` flag is not persisted. Cost if wrong: a finding blocks finalize until a human restores its raiser.
7. **No fallback path to handle.** Spec §3.6 says "the no-workflow fallback path always runs `debate`"; `commands/review.md` has no non-workflow review path (it refuses with `workflow-runtime-unavailable`), so nothing is built for it.
8. **`commands/finalize.md` changes** (spec §3.6 says it is unchanged): it narrates the two new refusal reasons, so a refusal is never unexplained (the 0.10.1 lesson). Its gate call is unchanged.
9. **A carried finding its reviewer re-lists is the carried record, not a new finding** (spec §3.2/§3.3 amended in the same commit as this ruling). `materializeCarried` replaces a re-listed carried id with the carried record (original severity, text, quote, ref and test; `carried: {"from_cycle":N,"reason":"re-listed"}`), so re-listing can never demote, re-verify or kill an open finding; only a confirmed closure closes it. The delta prompt tells reviewers to leave a still-open finding out. `from_cycle` keeps the cycle of the first carry (the report returns `carried`). Cost if wrong: a reviewer cannot raise a carried finding's severity, only raise a new blocker.
10. **`/build-fleet:review` reaches the gate through `review-carry.sh`.** Spec §3.6 adds `finalize-gate.sh` to `/review`'s allowed tools; the command runs `review-carry.sh` instead, which calls `finalize-gate.sh --report` itself. When the last cycle is verified and the report is missing, `review-carry.sh` exits 2 with no line and `/review` refuses `carry-unavailable` rather than carry an empty open set. Cost if wrong: none (one more refusal reason).
11. **A quote path names the current feature.** `vr_check($docs; $slug)` maps `.sdd/<slug>/<file>` and `.sdd/_product/<file>` to their keys; another feature's path maps to no key and fails.

## Review Focus

Inputs the spec implies but no other task's tests pin, most likely to bite first. Each has its test in the owning task.

1. **A verifier that paraphrases instead of quoting** (the commonest model behaviour) must void only its own vote, never kill or lower a finding. → Task 4 `invented-refute-revives`, Task 6 `invented-refute-revives-open`, Task 9 e2e `gate-reopens-the-finding`.
2. **An `incomplete` run's marker release after the spec was revised** must not re-check and overwrite the cycle's result. → Task 4 `first-event-wins`, Task 5 `second-release-no-new-event`.
3. **A spec edited between a clean review and `/build-fleet:finalize`**, while the finalize `STATUS:` flip and later ADR appends stay legal. → Task 6 `spec-edit-refuses`, `status-flip-alone-passes`, `adr-append-passes`, `adr-edit-refuses`.
4. **A malformed `verdict:` line** (an agent-wrapped or hand-edited line) must never kill a finding. → Task 3 `malformed-verdict-never-kills`, Task 6 inherits via the shared rules.
5. **A carried finding whose original quote no longer exists in the revised spec** must stay open and must not be demoted by the quote check. → Task 3 `carried-is-open-and-unchecked`.

---

## File structure

| Path | Responsibility | Task |
|---|---|---|
| `hooks/scripts/_lib.sh` | + `log_event`, `read_events`, `sha256_stdin` | 2 |
| `hooks/scripts/guard-event-log.sh` (+`.test.sh`) (new) | Refuse agent Write/Edit of `EVENTS.jsonl` / `_events.jsonl` | 2 |
| `scripts/log-event.test.sh` (new) | Harness for the `_lib.sh` event helpers | 2 |
| `scripts/lib/verified-review.jq` (new) | The verified rules: parse, vote, severity, closure, carry, quote check, revival | 3 |
| `scripts/lib/review-blocks.sh` (new) | Block extraction, shape detection, roster, quote sources, fingerprints | 3 |
| `scripts/fixtures/verified-review.sh` (new) | Shared fixture builders for the verified suites | 3 |
| `scripts/verified-review-rules.test.sh` (new) | Harness for the jq rules | 3 |
| `scripts/quote-check.sh` (+`.test.sh`) (new) | Check a cycle's quotes; record one event | 4 |
| `hooks/scripts/check-review-quotes.sh` (+`.test.sh`) (new) | PostToolUse: run the quote check on the scribe's marker release | 5 |
| `hooks/hooks.json` | Register the two new hooks; description | 2, 5 |
| `scripts/finalize-gate.sh` | Verified path, `--report`, `spec-changed-since-review`, gate event | 6 |
| `scripts/finalize-gate-verified.test.sh` (new) | Harness for the verified gate path | 6 |
| `scripts/review-carry.sh` (+`.test.sh`) (new) | Open set + exempt cycles for the next verified cycle | 7 |
| `workflows/review.js` | Pure helpers (Task 8); verified branch, prompts, schemas, render, budget (Task 9) | 8, 9 |
| `scripts/workflow-review-verified.test.sh`, `scripts/verified-vote-parity.test.sh` (new) | JS helper harness; JS↔jq parity | 8 |
| `scripts/verified-review-e2e.test.sh` (new) | Rendered lines → hook → quote check → gate → carry | 9 |
| `commands/review.md`, `commands/revise.md`, `commands/status.md`, `scripts/status-snapshot.sh` (+test) | Settings, carry, budget, revise from the report, status | 10 |
| `skills/review-rubric/SKILL.md`, `agents/{architect,qa,reviewer}.md`, `scripts/rubric-drift.test.sh`, `skills/sdd-protocol/SKILL.md` | Mirrored verified rule; reviewer verify mode; descriptions; protocol docs | 11 |
| `commands/finalize.md` | Narrate the two new refusal reasons | 10 |
| `CLAUDE.md`, `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `ROADMAP.md`, `docs/v0.2/CONTRACT.md`, `docs/loops.md` | Release prep, contract docs | 13 |

Tasks 2–7 are bash/jq and independent of the workflow; Task 8 depends on nothing; Task 9 depends on 8 and (for its e2e suite) on 3–7. **Task 1's spike gates everything:** if plugin hooks do not fire for the scribe inside a workflow run, stop and return to the spec.

---

### Task 1: Release worktree, baseline, and the hook-in-workflow spike (spec §3.6 "An assumption the plan must verify first")

**Files:** none in the repo (a scratch project and a scratch plugin under `/tmp`).

- [ ] **Step 1: Create the worktree on the existing branch and record the baseline**

```bash
cd ~/build-fleet && git worktree add ~/build-fleet-0.12 release/0.12.0
cd ~/build-fleet-0.12 && git log --oneline -1   # expect: a82c5b6 docs(design): verified review — third Gemini review amendments
bash scripts/run-tests.sh 2>&1 | tail -1        # expect: suites: 30, failed: 0
```

- [ ] **Step 2: Build a probe plugin whose PostToolUse hook logs every Write**

```bash
mkdir -p /tmp/bf-probe/plugin/.claude-plugin /tmp/bf-probe/plugin/hooks /tmp/bf-probe/proj/.sdd/feat
cat > /tmp/bf-probe/plugin/.claude-plugin/plugin.json <<'EOF'
{ "name": "bf-probe", "version": "0.0.1", "description": "probe: does a plugin PostToolUse hook see a workflow subagent's Write?" }
EOF
cat > /tmp/bf-probe/plugin/hooks/hooks.json <<'EOF'
{ "hooks": { "PostToolUse": [ { "matcher": "Write", "hooks": [ { "type": "command", "command": "cat >> /tmp/bf-probe/hook.log; echo >> /tmp/bf-probe/hook.log" } ] } ] } }
EOF
mkdir -p /tmp/bf-probe/proj/.claude/workflows
cat > /tmp/bf-probe/proj/.claude/workflows/probe.js <<'EOF'
export const meta = { name: "probe", description: "one agent writes an empty marker", phases: [{ title: "Write" }] };
phase("Write");
await agent("Use the Write tool to overwrite .sdd/feat/.workflow-in-flight with EMPTY content (an empty string). Then reply done.", { label: "writer", phase: "Write" });
return { ok: true };
EOF
printf 'run-1' > /tmp/bf-probe/proj/.sdd/feat/.workflow-in-flight
: > /tmp/bf-probe/hook.log
```

- [ ] **Step 3: Run the workflow from an interactive session**

```bash
cd /tmp/bf-probe/proj && claude --plugin-dir /tmp/bf-probe/plugin
```
In the session type: `run the probe workflow with the Workflow tool` and approve it. Exit when it finishes.

- [ ] **Step 4: Read the log**

```bash
jq -c 'select(.tool_name == "Write") | {path: .tool_input.file_path, content: .tool_input.content}' /tmp/bf-probe/hook.log
```
Expected: one line with `path` ending `.sdd/feat/.workflow-in-flight` and `"content":""`.
**If the log is empty, STOP.** Report to Ray: plugin hooks do not see workflow subagents' writes, so the quote-check trigger (spec D7) needs a different home. Do not continue to Task 2.

- [ ] **Step 5: Record the result in the spec and commit**

Append to `docs/history/2026-10-14-verified-review.md` §3.6, after the "An assumption the plan must verify first" paragraph:
```
Verified <YYYY-MM-DD> (Claude Code <version from `claude --version`>): a plugin PostToolUse(Write)
hook received the workflow subagent's empty Write of `.workflow-in-flight`.
```
```bash
git add docs/history/2026-10-14-verified-review.md
git commit -m "docs(design): verified review — hook-in-workflow assumption verified

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Event-log essentials — `log_event`, `read_events`, `sha256_stdin`, and the write guard (dashboard spec §3.1)

**Files:**
- Modify: `hooks/scripts/_lib.sh` (append three helpers)
- Create: `hooks/scripts/guard-event-log.sh`, `hooks/scripts/guard-event-log.test.sh`, `scripts/log-event.test.sh`
- Modify: `hooks/hooks.json` (PreToolUse registration + description)

**Interfaces:**
- Produces: `log_event <slug> '<json-object>'` (appends `{v:1, ts, slug} + object` to `.sdd/<slug>/EVENTS.jsonl`, or `.sdd/_events.jsonl` for an empty slug; always returns 0); `read_events <slug> <source>` (compact JSON lines, malformed lines skipped); `sha256_stdin` (hex digest of stdin).

- [ ] **Step 1: Write the two harnesses**

`scripts/log-event.test.sh`:
```bash
#!/usr/bin/env bash
# Tests for log_event / read_events / sha256_stdin in hooks/scripts/_lib.sh.
# The rule under test: logging never changes a caller's decision — every failure is
# swallowed with a stderr note and return 0.
# Run: bash scripts/log-event.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$DIR/../hooks/scripts/_lib.sh"
work="$(mktemp -d)"; trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT
pass=0; fail=0
assert() { if eval "$2"; then pass=$((pass+1)); printf 'ok   %s\n' "$1"; else fail=$((fail+1)); printf 'FAIL %s (%s)\n' "$1" "$2"; fi; }
mkdir -p "$work/p/.sdd/feat"
run() { ( cd "$work/p" && CLAUDE_PROJECT_DIR="$work/p" bash -c ". '$LIB'; $1" ); }

run "log_event feat '{\"kind\":\"gate\",\"source\":\"script:x\",\"decision\":\"pass\"}'"; rc=$?
assert "append-rc0" "[ $rc -eq 0 ]"
assert "append-one-line" "[ \$(wc -l < '$work/p/.sdd/feat/EVENTS.jsonl') -eq 1 ]"
assert "append-schema" "jq -e '.v == 1 and .slug == \"feat\" and .kind == \"gate\" and .source == \"script:x\" and (.ts | test(\"Z\$\"))' '$work/p/.sdd/feat/EVENTS.jsonl' >/dev/null"
run "log_event '' '{\"kind\":\"gate\"}'"
assert "empty-slug-goes-to-project-log" "[ -f '$work/p/.sdd/_events.jsonl' ]"
out=$(run "log_event ../x '{}'; echo rc=\$?" 2>&1)
assert "bad-slug-swallowed" "printf '%s' \"\$out\" | grep -q 'rc=0'"
out=$(run "log_event feat 'not json'; echo rc=\$?" 2>&1)
assert "bad-payload-swallowed" "printf '%s' \"\$out\" | grep -q 'rc=0'"
chmod a-w "$work/p/.sdd/feat/EVENTS.jsonl"
out=$(run "log_event feat '{}'; echo rc=\$?" 2>&1)
assert "unwritable-swallowed" "printf '%s' \"\$out\" | grep -q 'rc=0' && printf '%s' \"\$out\" | grep -q 'event dropped'"
chmod u+w "$work/p/.sdd/feat/EVENTS.jsonl"
printf 'garbage line\n' >> "$work/p/.sdd/feat/EVENTS.jsonl"
n=$(run "read_events feat script:x" | wc -l | tr -d ' ')
assert "read-events-skips-malformed" "[ '$n' = 1 ]"
h=$(run "printf abc | sha256_stdin")
assert "sha256-known-vector" "[ '$h' = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' ]"
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
```

`hooks/scripts/guard-event-log.test.sh`:
```bash
#!/usr/bin/env bash
# Tests for hooks/scripts/guard-event-log.sh — agent writes to the event log are refused.
# Run: bash hooks/scripts/guard-event-log.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/guard-event-log.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/.sdd/feat"
pass=0; fail=0
check() { # check <name> <tool> <file_path> <want_rc>
  local rc=0
  ( cd "$work" && jq -cn --arg t "$2" --arg p "$3" '{tool_name:$t, tool_input:{file_path:$p, content:"x"}}' \
      | CLAUDE_PROJECT_DIR="$work" bash "$HOOK" >/dev/null 2>&1 ); rc=$?
  if [ "$rc" -eq "$4" ]; then pass=$((pass+1)); printf 'ok   %-40s rc=%s\n' "$1" "$rc"
  else fail=$((fail+1)); printf 'FAIL %-40s want=%s got=%s\n' "$1" "$4" "$rc"; fi
}
check "write-feature-events-refused"   Write ".sdd/feat/EVENTS.jsonl" 2
check "edit-feature-events-refused"    Edit  "$work/.sdd/feat/EVENTS.jsonl" 2
check "write-project-events-refused"   Write ".sdd/_events.jsonl" 2
check "write-review-allowed"           Write ".sdd/feat/REVIEW.md" 0
check "write-source-allowed"           Write "src/EVENTS.jsonl.md" 0
check "events-outside-sdd-allowed"     Write "docs/EVENTS.jsonl" 0
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run them red**

Run: `bash scripts/log-event.test.sh | tail -1; bash hooks/scripts/guard-event-log.test.sh | tail -1`
Expected: `log-event` FAILs (`log_event: command not found` makes every assertion fail); `guard-event-log` exits non-zero (`guard-event-log.sh: No such file`).

- [ ] **Step 3: Append the helpers to `_lib.sh`**

Save as `/tmp/lib.patch` and run `git apply /tmp/lib.patch`:
```diff
--- a/hooks/scripts/_lib.sh
+++ b/hooks/scripts/_lib.sh
@@ -179,3 +179,41 @@
     *) return 1 ;;
   esac
 }
+
+# --- Event log (build-fleet/event@1) ---
+
+# Append one event line to .sdd/<slug>/EVENTS.jsonl, or .sdd/_events.jsonl when the
+# slug is empty. $2 is a JSON object merged into {v, ts, slug}. Logging NEVER changes
+# a caller's decision: every failure (no jq, bad payload, unwritable file) is noted on
+# stderr and swallowed — the one deliberate exception to "hooks fail closed".
+# Usage: log_event <slug> '<json-object>'
+log_event() {
+  local slug="$1" extra="${2:-}" file ts line
+  [ -n "$extra" ] || extra='{}'
+  if [ -n "$slug" ]; then
+    case "$slug" in */*|..|.|-*) echo "build-fleet: log_event: bad slug '$slug'; event dropped" >&2; return 0 ;; esac
+    file=".sdd/${slug}/EVENTS.jsonl"
+  else
+    file=".sdd/_events.jsonl"
+  fi
+  command -v jq >/dev/null 2>&1 || { echo "build-fleet: log_event: jq not found; event dropped" >&2; return 0; }
+  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
+  line=$(jq -cn --arg ts "$ts" --arg slug "$slug" --argjson extra "$extra" '{v: 1, ts: $ts, slug: $slug} + $extra' 2>/dev/null) \
+    || { echo "build-fleet: log_event: bad event payload; event dropped" >&2; return 0; }
+  { printf '%s\n' "$line" >> "$file"; } 2>/dev/null \
+    || { echo "build-fleet: log_event: cannot append to ${file}; event dropped" >&2; return 0; }
+  return 0
+}
+
+# Echo the events of one kind/source from .sdd/<slug>/EVENTS.jsonl as compact JSON
+# lines, skipping malformed lines. Usage: read_events <slug> <source>
+read_events() {
+  local f=".sdd/$1/EVENTS.jsonl"
+  [ -f "$f" ] || return 0
+  jq -cR --arg src "$2" 'fromjson? // empty | select(type == "object" and .source == $src)' "$f" 2>/dev/null || true
+}
+
+# sha256 of stdin, hex only. GNU sha256sum, else BSD/macOS shasum.
+sha256_stdin() {
+  if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1
+}
```

- [ ] **Step 4: Create `hooks/scripts/guard-event-log.sh`**

```bash
#!/usr/bin/env bash
# PreToolUse(Write|Edit|NotebookEdit): the event log is append-only and written only by
# build-fleet's own scripts (log_event in _lib.sh). An agent tool call that targets
# .sdd/<slug>/EVENTS.jsonl or .sdd/_events.jsonl is refused (exit 2), whatever the
# phase and whether or not a workflow is in flight. Everything else passes (exit 0).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "${HERE}/_lib.sh"
input=$(cat)
if ! command -v jq >/dev/null 2>&1; then
  # Without jq the path cannot be read; refuse only when the raw payload names an event log.
  case "$input" in *EVENTS.jsonl*|*_events.jsonl*) echo "build-fleet: the event log is written only by build-fleet scripts (jq missing; refusing)." >&2; exit 2 ;; esac
  exit 0
fi
path=$(extract_file_path "$input" 2>/dev/null) || exit 0
[ -n "$path" ] || exit 0
case "$(basename "$path")" in
  EVENTS.jsonl|_events.jsonl)
    if path_in_sdd "$path" || case "$path" in */.sdd/*|.sdd/*) true ;; *) false ;; esac; then
      echo "build-fleet: ${path} is the append-only event log; only build-fleet's scripts write it. Agents never edit it." >&2
      exit 2
    fi ;;
esac
exit 0
```

- [ ] **Step 5: Register the guard in `hooks/hooks.json`**

In the `PreToolUse` entry whose `"matcher": "Write|Edit|NotebookEdit"`, append to its `hooks` array (after the `cap-spec-size.sh` entry):
```json
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/guard-event-log.sh\""
          }
```
At the end of the top-level `"description"` string, before its closing quote, append:
```
, refuse agent writes to the append-only event log (.sdd/<slug>/EVENTS.jsonl, .sdd/_events.jsonl)
```
Then: `jq empty hooks/hooks.json && echo json-ok`.

- [ ] **Step 6: Run green, then the suite**

Run: `bash scripts/log-event.test.sh | tail -1; bash hooks/scripts/guard-event-log.test.sh | tail -1; bash scripts/run-tests.sh 2>&1 | tail -1`
Expected: `passed=9 failed=0`; `passed=6 failed=0`; `suites: 32, failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add hooks/scripts/_lib.sh hooks/scripts/guard-event-log.sh hooks/scripts/guard-event-log.test.sh scripts/log-event.test.sh hooks/hooks.json
git commit -m "feat(events): log_event helpers and an agent-write guard for the event log

Logging never changes a gate's decision: every log_event failure is noted on
stderr and swallowed.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The shared verified rules and block helpers (spec §3.1–§3.5)

**Files:**
- Create: `scripts/lib/verified-review.jq`, `scripts/lib/review-blocks.sh`, `scripts/fixtures/verified-review.sh`, `scripts/verified-review-rules.test.sh`

**Interfaces:**
- Consumes: `sha256_stdin`, `read_progress_field` (Task 2 / existing `_lib.sh`).
- Produces (jq, used by Tasks 4, 6, 8's parity test): `vr_rank`, `vr_sev`, `vr_norm`, `vr_parse_block` (block text → findings `{id, severity, text, verdicts[], quote?, absent?, closure?, carried?, demoted?, ref?, test?, disposition?}`), `vr_outcome($fails)` (adds `final, killed, closed, demoted_reason, reopened_closure`), `vr_open($adrs)` (→ `"blocker"|"major"|"major-without-adr"|null`), `vr_quotes`, `vr_check($docs; $slug)`, `vr_revived($fails)`. `$fails` items are `{id, where: "anchor"|"verdict"|"closure", v?}`.
- Produces (bash): `last_cycle_block <review> <cycle> <role>`, `block_is_verified` (stdin), `cycle_roles <review> <cycle>` (the roles with a heading in that cycle), `quote_docs_json <slug>`, `quote_docs_fingerprint <slug>`, `fingerprint_matches <slug> <fingerprint-json>`.
- Produces (test fixtures): `vr_proj`, `vr_block`, `vr_up`, `vr_rf`, `vr_q`, `$VR_REASON`.

- [ ] **Step 1: Write the fixtures and the rules harness**

`scripts/fixtures/verified-review.sh`:
```bash
# scripts/fixtures/verified-review.sh — shared fixture builders for the verified-review
# suites (quote-check, check-review-quotes, finalize-gate verified cases, review-carry,
# e2e). Source it after setting $work. bash 3.2.

VR_REASON='The constraints section caps retries at three attempts explicitly.'

# vr_proj <name> <cycle> [<cycle_total>] → project with feature 'feat', roster qa,architect
vr_proj() {
  local p="$work/$1"
  mkdir -p "$p/.sdd/feat"
  printf 'feat\n' > "$p/.sdd/ACTIVE"
  printf 'FEATURE: feat\nPHASE: REVIEW\nCYCLE: %s\nCYCLE_TOTAL: %s\nREVIEW_ROLES: qa,architect\nREVIEW_SHAPE: verified\n' "$2" "${3:-$2}" > "$p/.sdd/feat/PROGRESS.md"
  printf 'STATUS: DRAFT\n# Upload\n## Behavior\nWhen offline, the client retries failed uploads.\n## Constraints\n*Retries* are capped at 3 attempts.\n' > "$p/.sdd/feat/spec.md"
  printf '# Acceptance\n- AC-1: an upload against a failing server stops after 3 attempts\n' > "$p/.sdd/feat/acceptance.md"
  printf '# Architecture Decisions — feat\n\n## ADR-1: keep retries client-side\n\n- **Status:** accepted\n' > "$p/.sdd/feat/DECISIONS.md"
  printf '# Review Log — feat\n\n' > "$p/.sdd/feat/REVIEW.md"
  printf '%s' "$p"
}
# vr_block <proj> <cycle> <role> <lines…> → append a verified block
vr_block() {
  local p="$1" c="$2" r="$3"; shift 3
  { printf '## Cycle %s — %s — 2026-10-20T00:00:00Z\nshape: verified\n' "$c" "$r"
    for l in "$@"; do printf '%s\n' "$l"; done
    printf 'status: concerns-raised\n\n'; } >> "$p/.sdd/feat/REVIEW.md"
}
vr_up()  { printf '  verdict: {"v":%s,"vote":"uphold","severity":"%s"}' "$1" "$2"; }
# vr_rf <v> <quote-text> → a refutation with evidence quoting <quote-text> from spec.md
vr_rf()  { printf '  verdict: {"v":%s,"vote":"refute","severity":"minor","reason":"%s","quote":{"file":"spec.md","text":"%s"}}' "$1" "$VR_REASON" "$2"; }
vr_q()   { printf '  quote: {"file":"spec.md","text":"%s"}' "$1"; }
```

`scripts/verified-review-rules.test.sh`:
```bash
#!/usr/bin/env bash
# Tests for scripts/lib/verified-review.jq — the REVIEW_SHAPE: verified rules shared by
# quote-check.sh and finalize-gate.sh: block parsing, the vote, severity, demotion,
# closures, carried entries, quote checks, revival.
# Run: bash scripts/verified-review-rules.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES="$(cat "$DIR/lib/verified-review.jq")"
pass=0; fail=0
# t <name> <block-text> <jq-expression over $fs> <expected-compact-json>
t() {
  local got
  got=$(printf '%s' "$2" | jq -Rsc "${RULES} vr_parse_block as \$fs | $3" 2>&1)
  if [ "$got" = "$4" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$1"
  else fail=$((fail+1)); printf 'FAIL %s\n     want %s\n     got  %s\n' "$1" "$4" "$got"; fi
}
R='The constraints section caps retries at three attempts explicitly.'
Q='{"file":"spec.md","text":"Retries are capped at 3 attempts"}'
H='## Cycle 1 — qa — 2026-10-20T00:00:00Z
shape: verified'
up() { printf '  verdict: {"v":%s,"vote":"uphold","severity":"%s"}' "$1" "$2"; }
rf() { printf '  verdict: {"v":%s,"vote":"refute","severity":"%s","reason":"%s","quote":%s}' "$1" "$2" "$R" "$Q"; }
lo() { printf '  verdict: {"v":%s,"vote":"uphold","severity":"%s","reason":"%s","quote":%s}' "$1" "$2" "$R" "$Q"; }
OUT='[$fs[] | vr_outcome([]) | {id, final, killed}]'

t "parse-fields" "$H
- [major] (qa-c1-1) Claim text
  quote: {\"file\":\"spec.md\",\"text\":\"abc def ghi\"}
  ref: §Behavior, AC-3
  test: a test
  disposition: fix
status: concerns-raised" '[$fs[] | {id, severity, text, ref, test, disposition, q: .quote.text}]' \
  '[{"id":"qa-c1-1","severity":"major","text":"Claim text","ref":"§Behavior, AC-3","test":"a test","disposition":"fix","q":"abc def ghi"}]'
t "kill-on-two-valid-refutes" "$H
- [major] (qa-c1-1) c
$(up 1 major)
$(rf 2 minor)
$(rf 3 minor)" "$OUT" '[{"id":"qa-c1-1","final":"minor","killed":true}]'
t "one-refute-is-not-a-veto" "$H
- [blocker] (qa-c1-1) c
$(rf 1 minor)
$(up 2 blocker)
$(up 3 blocker)" "$OUT" '[{"id":"qa-c1-1","final":"blocker","killed":false}]'
t "refute-without-quote-ignored" "$H
- [major] (qa-c1-1) c
  verdict: {\"v\":1,\"vote\":\"refute\",\"severity\":\"minor\",\"reason\":\"$R\"}
$(rf 2 minor)
$(up 3 major)" "$OUT" '[{"id":"qa-c1-1","final":"major","killed":false}]'
t "refute-short-reason-ignored" "$H
- [major] (qa-c1-1) c
  verdict: {\"v\":1,\"vote\":\"refute\",\"severity\":\"minor\",\"reason\":\"too short\",\"quote\":$Q}
$(rf 2 minor)
$(up 3 major)" "$OUT" '[{"id":"qa-c1-1","final":"major","killed":false}]'
t "lower-severity-needs-evidence" "$H
- [blocker] (qa-c1-1) c
$(up 1 minor)
$(up 2 minor)
$(up 3 blocker)" "$OUT" '[{"id":"qa-c1-1","final":"blocker","killed":false}]'
t "lower-severity-with-evidence" "$H
- [blocker] (qa-c1-1) c
$(lo 1 major)
$(lo 2 major)
$(up 3 blocker)" "$OUT" '[{"id":"qa-c1-1","final":"major","killed":false}]'
t "severity-never-raised" "$H
- [major] (qa-c1-1) c
$(up 1 blocker)
$(up 2 blocker)
$(up 3 blocker)" "$OUT" '[{"id":"qa-c1-1","final":"major","killed":false}]'
t "even-count-takes-higher-middle" "$H
- [blocker] (qa-c1-1) c
$(lo 1 minor)
$(up 3 blocker)" "$OUT" '[{"id":"qa-c1-1","final":"blocker","killed":false}]'
t "two-returned-kill-needs-both" "$H
- [major] (qa-c1-1) c
$(rf 1 minor)
$(up 3 major)" "$OUT" '[{"id":"qa-c1-1","final":"major","killed":false}]'
t "malformed-verdict-never-kills" "$H
- [major] (qa-c1-1) c
  verdict: {broken
$(rf 2 minor)
$(up 3 major)" "$OUT" '[{"id":"qa-c1-1","final":"major","killed":false}]'
t "test-invalid-majority-demotes" "$H
- [major] (qa-c1-1) c
  verdict: {\"v\":1,\"vote\":\"uphold\",\"severity\":\"major\",\"test_invalid\":true}
  verdict: {\"v\":2,\"vote\":\"uphold\",\"severity\":\"major\",\"test_invalid\":true}
$(up 3 major)" '[$fs[] | vr_outcome([]) | {final, demoted_reason}]' '[{"final":"minor","demoted_reason":"test-invalid"}]'
t "demoted-line-demotes" "$H
- [major] (qa-c1-1) c
  demoted: {\"reason\":\"no-test\"}" '[$fs[] | vr_outcome([]) | {final, demoted_reason}]' '[{"final":"minor","demoted_reason":"no-test"}]'
t "anchor-quote-failure-demotes" "$H
- [major] (qa-c1-1) c
$(up 1 major)
$(up 2 major)" '[$fs[] | vr_outcome([{id:"qa-c1-1",where:"anchor"}]) | {final, demoted_reason}]' '[{"final":"minor","demoted_reason":"anchor-quote-failed"}]'
t "closure-majority-closes" "$H
- [major] (qa-c1-1) c
  closure: {\"file\":\"spec.md\",\"text\":\"abc def ghi jkl\"}
  verdict: {\"v\":1,\"vote\":\"confirm\",\"severity\":\"major\"}
  verdict: {\"v\":2,\"vote\":\"confirm\",\"severity\":\"major\"}
  verdict: {\"v\":3,\"vote\":\"reject\",\"severity\":\"major\",\"reason\":\"no\"}" \
  '[$fs[] | vr_outcome([]) | {closed}] + [$fs[] | vr_outcome([{id:"qa-c1-1",where:"closure"}]) | {closed, reopened_closure}]' \
  '[{"closed":true},{"closed":false,"reopened_closure":true}]'
t "carried-is-open-and-unchecked" "$H
- [major] (qa-c1-5) c
  quote: {\"file\":\"spec.md\",\"text\":\"gone from the spec\"}
  carried: {\"from_cycle\":1,\"reason\":\"not-addressed\"}" \
  '[$fs[] | vr_outcome([{id:"qa-c1-5",where:"anchor"}]) | {final, open: vr_open([])}] + [$fs | vr_quotes | length]' '[{"final":"major","open":"major"},0]'
t "open-adr-exists-closes" "$H
- [major] (qa-c1-1) c
  disposition: adr ADR-2" '[$fs[] | vr_outcome([]) | vr_open([2]), vr_open([1])]' '[null,"major-without-adr"]'
t "revived-by-failed-refute-quote" "$H
- [major] (qa-c1-1) c
$(up 1 major)
$(rf 2 minor)
$(rf 3 minor)" '$fs | vr_revived([{id:"qa-c1-1",where:"verdict",v:3}])' '["qa-c1-1"]'
t "revived-by-restored-severity" "$H
- [blocker] (qa-c1-1) c
$(lo 1 major)
$(lo 2 major)
$(up 3 blocker)" '$fs | vr_revived([{id:"qa-c1-1",where:"verdict",v:2}])' '["qa-c1-1"]'
DOCS='{"spec.md":"STATUS: DRAFT\n# Up\n## 3.1 Behavior\nThe *client* retries\nfailed uploads—always.\n"}'
t "check-normalises-markup-dashes-newlines" "$H" \
  "[{file:\"spec.md\",text:\"The client retries failed uploads-always\"}, {file:\"spec.md\",text:\"the client retries\"}] | map(vr_check($DOCS; \"feat\"))" '[true,false]'
t "check-bounds" "$H" \
  "[{file:\"spec.md\",text:\"retries\"}, {file:\"spec.md\",text:(\"x\" * 501)}] | map(vr_check($DOCS; \"feat\"))" '[false,false]'
t "check-allowlist" "$H" \
  "[{file:\"../spec.md\",text:\"The client retries\"}, {file:\"notes.md\",text:\"The client retries\"}] | map(vr_check($DOCS; \"feat\"))" '[false,false]'
t "check-workspace-paths-mapped" "$H" \
  "[{file:\".sdd/feat/spec.md\",text:\"The client retries\"}, {file:\"./spec.md\",text:\"The client retries\"}, {file:\".sdd/_product/DECISIONS.md\",text:\"The client retries\"}, {file:\".sdd/other/spec.md\",text:\"The client retries\"}] | map(vr_check($DOCS; \"feat\"))" '[true,true,false,false]'
t "check-absent-section" "$H" \
  "[{file:\"spec.md\",section:\"Behavior\"}, {file:\"spec.md\",section:\"§3.1 Behavior\"}, {file:\"spec.md\",section:\"Security\"}] | map(vr_check($DOCS; \"feat\"))" '[true,true,false]'
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run red**

Run: `bash scripts/verified-review-rules.test.sh | tail -1`
Expected: non-zero exit (`cat: …/lib/verified-review.jq: No such file`; every case FAILs).

- [ ] **Step 3: Create `scripts/lib/verified-review.jq`**

```jq
# scripts/lib/verified-review.jq — the REVIEW_SHAPE: verified rules, shared by
# scripts/quote-check.sh and scripts/finalize-gate.sh. The JS twin lives in
# workflows/review.js (VERIFIED-RULES region); scripts/verified-vote-parity.test.sh
# keeps the two equal. Pure jq 1.6+, no I/O.

def vr_rank: if . == "blocker" then 2 elif . == "major" then 1 elif . == "minor" then 0 else -1 end;
def vr_sev: ["minor", "major", "blocker"][.];

# Normalisation applied to a quote and to the file it cites before an exact match.
def vr_norm:
  gsub("[‘’]"; "'") | gsub("[“”]"; "\"") | gsub("[–—]"; "-")
  | gsub("[*_`]"; "") | gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" ");

# Text of ONE "## Cycle N — role — ts" block → array of findings.
def vr_parse_block:
  split("\n")
  | reduce .[] as $l ({out: [], cur: null};
      if ($l | test("^- \\[(blocker|major|minor)\\] \\(")) then
        (if .cur != null then .out += [.cur] else . end)
        | .cur = (($l | capture("^- \\[(?<severity>blocker|major|minor)\\] \\((?<id>[^)]+)\\) ?(?<text>.*)$")) + {verdicts: []})
      elif .cur != null and ($l | test("^  [a-z_]+: ")) then
        ($l | capture("^  (?<k>[a-z_]+): (?<v>.*)$")) as $kv
        | if $kv.k == "verdict" then .cur.verdicts += [($kv.v | (try fromjson catch {invalid: true}))]
          elif ($kv.k == "quote" or $kv.k == "absent" or $kv.k == "closure" or $kv.k == "carried" or $kv.k == "demoted")
            then .cur[$kv.k] = ($kv.v | (try fromjson catch {invalid: true}))
          elif ($kv.k == "ref" or $kv.k == "test" or $kv.k == "disposition") then .cur[$kv.k] = $kv.v
          else . end
      elif .cur != null and ($l | test("^[^ ]")) then .out += [.cur] | .cur = null
      else . end)
  | (if .cur != null then .out + [.cur] else .out end);

def vr_failed($fails; $id; $where; $v):
  any($fails[]; .id == $id and .where == $where and ((.v // null) == $v));

# A verdict's evidence counts: an object verdict with a quote {file,text}, a reason of
# at least 40 characters, and a quote the quote check did not fail.
def vr_evidence($fails; $id):
  (type == "object") and ((.invalid // false) | not)
  and ((.quote | type) == "object") and (((.quote.file // "") | tostring | length) > 0)
  and (((.quote.text // "") | tostring | length) > 0)
  and ((.reason | type) == "string") and ((.reason | length) >= 40)
  and (vr_failed($fails; $id; "verdict"; .v) | not);

# One finding → the finding plus {final, killed, closed, demoted_reason, reopened_closure}.
def vr_outcome($fails):
  . as $f
  | ($f.severity | vr_rank) as $orig
  | [($f.verdicts // [])[] | select(type == "object" and ((.invalid // false) | not))] as $vs
  | ($vs | length) as $n
  | if ($f.carried != null) then
      $f + {final: $f.severity, killed: false, closed: false, demoted_reason: null, reopened_closure: false}
    elif ($f.closure != null) then
      ([$vs[] | select(.vote == "confirm")] | length) as $c
      | ($n >= 2 and $c * 2 > $n) as $voted
      | (vr_failed($fails; $f.id; "closure"; null)) as $qfail
      | $f + {final: $f.severity, killed: false, closed: ($voted and ($qfail | not)),
              demoted_reason: null, reopened_closure: ($voted and $qfail)}
    elif $orig < 1 then
      $f + {final: "minor", killed: false, closed: false, demoted_reason: null, reopened_closure: false}
    else
      ([$vs[] | select(.vote == "refute" and vr_evidence($fails; $f.id))] | length) as $r
      | ([$vs[] | (.severity | vr_rank) as $s
          | if ($s >= 0 and $s < $orig and vr_evidence($fails; $f.id)) then $s else $orig end] | sort) as $ranks
      | (if $n < 2 then $orig else $ranks[($n / 2 | floor)] end) as $med
      | ([$vs[] | select(.test_invalid == true)] | length) as $ti
      | (if (($f.demoted | type) == "object") then ($f.demoted.reason // "demoted")
         elif vr_failed($fails; $f.id; "anchor"; null) then "anchor-quote-failed"
         elif ($n >= 2 and $ti * 2 > $n) then "test-invalid"
         else null end) as $dem
      | $f + {killed: ($r >= 2), closed: false, demoted_reason: $dem, reopened_closure: false,
              final: (if $dem != null then "minor" else ([$med, $orig] | min | vr_sev) end)}
    end;

# After vr_outcome: why the finding is open, or null when it is not.
# $adrs: ADR numbers present in the feature DECISIONS.md.
def vr_open($adrs):
  if .killed or .closed then null
  elif .final == "blocker" then "blocker"
  elif .final == "major" then
    (if ((.disposition // "") | test("^adr ADR-0*[0-9]+"))
     then ((.disposition | capture("ADR-0*(?<n>[0-9]+)").n | tonumber) as $a
           | if ($adrs | index($a)) != null then null else "major-without-adr" end)
     else "major" end)
  else null end;

# Findings → the quotes to check. Carried entries are skipped: their evidence was
# checked in the cycle that raised them, against the spec as it was then.
def vr_quotes:
  [ .[] | select(.carried == null) | . as $f
    | (if ($f.quote | type) == "object" then {id: $f.id, where: "anchor", file: $f.quote.file, text: $f.quote.text} else empty end),
      (if ($f.absent | type) == "object" then {id: $f.id, where: "anchor", file: $f.absent.file, section: ($f.absent.section // "")} else empty end),
      (if ($f.closure | type) == "object" then {id: $f.id, where: "closure", file: $f.closure.file, text: $f.closure.text} else empty end),
      (($f.verdicts // [])[] | select(type == "object" and (.quote | type) == "object")
        | {id: $f.id, where: "verdict", v: .v, file: .quote.file, text: .quote.text}) ];

# A cited file name as the quote sources are keyed: models often write the workspace
# path (".sdd/<slug>/spec.md", ".sdd/_product/DECISIONS.md"); map those to the keys.
# Another feature's path (".sdd/<other>/spec.md") maps to no key, so it fails.
def vr_file($slug):
  tostring | sub("^\\./"; "")
  | if startswith(".sdd/_product/") then ltrimstr(".sdd/")
    elif startswith(".sdd/" + $slug + "/") then ltrimstr(".sdd/" + $slug + "/")
    else . end;

# One quote item → true when it passes. $docs: {"spec.md": "<raw>", ...} — only
# allow-listed files that exist are present. $slug: the feature under review.
def vr_check($docs; $slug):
  (.file // "" | vr_file($slug)) as $file
  | ($docs[$file] // null) as $raw
  | if $raw == null then false
    elif (.section != null) then
      (.section | tostring | vr_norm | ascii_downcase | ltrimstr("§") | ltrimstr(" ")) as $s
      | ($s | length) > 0 and any($raw | split("\n")[] | select(test("^#{1,6} "))
            | sub("^#{1,6} +"; "") | vr_norm | ascii_downcase;
            . == $s or (sub("^[0-9.]+ +"; "") == $s))
    else
      (.text // "" | tostring | vr_norm) as $q
      | ($q | length) >= 10 and ($q | length) <= 500 and (($raw | vr_norm) | index($q)) != null
    end;

# Findings → ids reopened once failed quotes are applied.
def vr_revived($fails):
  [ .[] | (vr_outcome([])) as $a | vr_outcome($fails) as $b
    | select(($a.killed and ($b.killed | not))
             or (($b.final | vr_rank) > ($a.final | vr_rank))
             or ($a.closed and ($b.closed | not)))
    | .id ];
```

- [ ] **Step 4: Create `scripts/lib/review-blocks.sh`**

```bash
# scripts/lib/review-blocks.sh — REVIEW.md block helpers shared by
# scripts/finalize-gate.sh, scripts/quote-check.sh and scripts/review-carry.sh.
# Source it; bash 3.2 + BSD/GNU compatible; no side effects.

# Print the LAST "## Cycle <cycle> — <role> —" block of <review> (heading through
# the line before the next "## " heading, or EOF). Prints nothing when absent.
# Usage: last_cycle_block <review-file> <cycle> <role>
last_cycle_block() {
  local review="$1" cycle="$2" role="$3" start next end
  [ -f "$review" ] || return 0
  start=$({ grep -nE "^##[[:space:]]+Cycle[[:space:]]+${cycle}[[:space:]]+[—–-][[:space:]]+${role}[[:space:]]+[—–-]" "$review" || true; } | tail -1 | cut -d: -f1)
  [ -n "$start" ] || return 0
  next=$({ tail -n +"$((start+1))" "$review" | grep -n '^## ' || true; } | head -1 | cut -d: -f1)
  if [ -n "$next" ]; then end=$((start+next-1)); else end=$(wc -l < "$review" | tr -d ' '); fi
  sed -n "${start},${end}p" "$review"
}

# Return 0 when a block (on stdin) is a verified-shape block: its second line is
# exactly "shape: verified".
block_is_verified() {
  [ "$(sed -n '2p' | tr -d '\r')" = "shape: verified" ]
}

# Echo the roles that have a "## Cycle <cycle> — <role> —" heading in <review>, one per
# line, first appearance first. Readers of verified blocks use this, not the roster: a
# --roles flag is not persisted, and a role may leave the roster with findings still open.
# Usage: cycle_roles <review-file> <cycle>
cycle_roles() {
  local review="$1" cycle="$2"
  [ -f "$review" ] || return 0
  { grep -E "^##[[:space:]]+Cycle[[:space:]]+${cycle}[[:space:]]+[^[:space:]]+[[:space:]]+[A-Za-z0-9_-]+[[:space:]]" "$review" || true; } \
    | sed -E "s/^##[[:space:]]+Cycle[[:space:]]+${cycle}[[:space:]]+[^[:space:]]+[[:space:]]+([A-Za-z0-9_-]+)[[:space:]].*/\1/" \
    | awk '!seen[$0]++'
}

# Echo a JSON object of the allow-listed quote sources that exist for <slug>:
# {"spec.md": "<raw>", "acceptance.md": …, "DECISIONS.md": …, "_product/DECISIONS.md": …}
# Usage: quote_docs_json <slug>
quote_docs_json() {
  local slug="$1" out='{}' k p
  for k in spec.md acceptance.md DECISIONS.md _product/DECISIONS.md; do
    case "$k" in _product/*) p=".sdd/$k" ;; *) p=".sdd/${slug}/$k" ;; esac
    [ -f "$p" ] || continue
    out=$(jq -Rs --arg k "$k" --argjson acc "$out" '$acc + {($k): .}' "$p")
  done
  printf '%s' "$out"
}

# Echo the review-time fingerprint of the quote sources for <slug>, as JSON:
# spec.md hashed without its STATUS: line; acceptance.md hashed; each DECISIONS.md as
# {len, sha256} of its full content (the gate later checks that prefix).
# Usage: quote_docs_fingerprint <slug>
quote_docs_fingerprint() {
  local slug="$1" out='{}' k p h n
  for k in spec.md acceptance.md DECISIONS.md _product/DECISIONS.md; do
    case "$k" in _product/*) p=".sdd/$k" ;; *) p=".sdd/${slug}/$k" ;; esac
    [ -f "$p" ] || continue
    case "$k" in
      spec.md) h=$(grep -v '^STATUS:' "$p" | sha256_stdin); out=$(jq -cn --argjson a "$out" --arg k "$k" --arg h "$h" '$a + {($k): {sha256: $h}}') ;;
      acceptance.md) h=$(sha256_stdin < "$p"); out=$(jq -cn --argjson a "$out" --arg k "$k" --arg h "$h" '$a + {($k): {sha256: $h}}') ;;
      *) n=$(wc -c < "$p" | tr -d ' '); h=$(sha256_stdin < "$p")
         out=$(jq -cn --argjson a "$out" --arg k "$k" --arg h "$h" --argjson n "$n" '$a + {($k): {len: $n, sha256: $h}}') ;;
    esac
  done
  printf '%s' "$out"
}

# Return 0 when the current quote sources still match a recorded fingerprint
# (spec.md without STATUS:, acceptance.md exact, DECISIONS files: recorded prefix
# unchanged, appends allowed). Usage: fingerprint_matches <slug> '<fingerprint-json>'
fingerprint_matches() {
  local slug="$1" fp="$2" k p want n h
  for k in spec.md acceptance.md DECISIONS.md _product/DECISIONS.md; do
    want=$(printf '%s' "$fp" | jq -r --arg k "$k" '.[$k].sha256 // empty')
    [ -n "$want" ] || continue
    case "$k" in _product/*) p=".sdd/$k" ;; *) p=".sdd/${slug}/$k" ;; esac
    [ -f "$p" ] || return 1
    case "$k" in
      spec.md) h=$(grep -v '^STATUS:' "$p" | sha256_stdin) ;;
      acceptance.md) h=$(sha256_stdin < "$p") ;;
      *) n=$(printf '%s' "$fp" | jq -r --arg k "$k" '.[$k].len')
         [ "$(wc -c < "$p" | tr -d ' ')" -ge "$n" ] || return 1
         h=$(head -c "$n" "$p" | sha256_stdin) ;;
    esac
    [ "$h" = "$want" ] || return 1
  done
  return 0
}
```

- [ ] **Step 5: Run green, then the suite**

Run: `bash scripts/verified-review-rules.test.sh | tail -1; bash scripts/run-tests.sh 2>&1 | tail -1`
Expected: `passed=24 failed=0`; `suites: 33, failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/verified-review.jq scripts/lib/review-blocks.sh scripts/fixtures/verified-review.sh scripts/verified-review-rules.test.sh
git commit -m "feat(review): the verified-review rules in jq, and shared REVIEW.md block helpers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `scripts/quote-check.sh` (spec §3.4)

**Files:**
- Create: `scripts/quote-check.sh`, `scripts/quote-check.test.sh`

**Interfaces:**
- Consumes: Task 2 helpers; Task 3 `review-blocks.sh` + `verified-review.jq`.
- Produces: `quote-check.sh <slug> --cycle N` → one `BUILD_FLEET_QUOTE_CHECK:` line; one event `{kind:"gate", source:"script:quote-check", decision, cycle, cycle_total, files, checked, failures, revived, exempt}` per `cycle_total` (first wins).

- [ ] **Step 1: Write the harness**

`scripts/quote-check.test.sh`:
```bash
#!/usr/bin/env bash
# Tests for scripts/quote-check.sh: checks every quote in a verified cycle, records ONE
# event per cycle_total (first wins), computes revived/exempt, fingerprints the files.
# Run: bash scripts/quote-check.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QC="$DIR/quote-check.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
. "$DIR/fixtures/verified-review.sh"
pass=0; fail=0
assert() { if eval "$2"; then pass=$((pass+1)); printf 'ok   %s\n' "$1"; else fail=$((fail+1)); printf 'FAIL %s (%s) out=%s\n' "$1" "$2" "${out:-}"; fi; }
run() { out=$( cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$QC" feat --cycle "$2" 2>/dev/null ); rc=$?; }
ev() { jq -c "select(.source == \"script:quote-check\") | $2" "$1/.sdd/feat/EVENTS.jsonl" 2>/dev/null | tail -1; }

p=$(vr_proj all-pass 1)
vr_block "$p" 1 qa '- [major] (qa-c1-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' "$(vr_up 1 major)" "$(vr_rf 2 'Retries are capped at 3 attempts')" "$(vr_rf 3 'Retries are capped at 3 attempts')"
vr_block "$p" 1 architect
run "$p" 1
assert "pass-rc0" "[ $rc -eq 0 ]"
assert "pass-signal" "printf '%s' \"\$out\" | grep -q '\"checked\":3,\"failed\":0,\"revived\":\\[\\],\"exempt\":false'"
assert "pass-event" "[ \"\$(ev '$p' '[.decision, .cycle, .cycle_total, .exempt]')\" = '[\"pass\",1,1,false]' ]"
assert "event-fingerprint" "[ \"\$(ev '$p' '.files | keys')\" = '[\"DECISIONS.md\",\"acceptance.md\",\"spec.md\"]' ]"
run "$p" 1
assert "first-event-wins" "printf '%s' \"\$out\" | grep -q '\"skipped\":\"already-checked\"' && [ \$(grep -c quote-check '$p/.sdd/feat/EVENTS.jsonl') -eq 1 ]"

p=$(vr_proj invented 1)
vr_block "$p" 1 qa '- [major] (qa-c1-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' "$(vr_up 1 major)" "$(vr_rf 2 'Retries are capped at 3 attempts')" "$(vr_rf 3 'Retries are capped at 9 attempts')"
vr_block "$p" 1 architect
run "$p" 1
assert "invented-refute-revives" "printf '%s' \"\$out\" | grep -q '\"failed\":1,\"revived\":\\[\"qa-c1-1\"\\],\"exempt\":true'"
assert "invented-failure-recorded" "[ \"\$(ev '$p' '.failures')\" = '[{\"id\":\"qa-c1-1\",\"where\":\"verdict\",\"v\":3}]' ]"

p=$(vr_proj bad-anchor 1)
vr_block "$p" 1 qa '- [major] (qa-c1-1) retry limit' "$(vr_q 'a sentence the spec never had')" '  test: t' "$(vr_up 1 major)" "$(vr_up 2 major)"
vr_block "$p" 1 architect
run "$p" 1
assert "failed-anchor-not-exempt" "printf '%s' \"\$out\" | grep -q '\"failed\":1,\"revived\":\\[\\],\"exempt\":false'"

p=$(vr_proj debate 1)
printf '## Cycle 1 — qa — t\n- [major] (qa-c1-1) x\n  disposition: fix\nstatus: concerns-raised\n' >> "$p/.sdd/feat/REVIEW.md"
run "$p" 1
assert "debate-skipped-no-event" "printf '%s' \"\$out\" | grep -q '\"skipped\":\"not-verified\"' && [ ! -f '$p/.sdd/feat/EVENTS.jsonl' ]"

p=$(vr_proj product-adr 1)
mkdir -p "$p/.sdd/_product"; printf '## ADR-3: one database\nAll services share one Postgres instance.\n' > "$p/.sdd/_product/DECISIONS.md"
vr_block "$p" 1 qa '- [major] (qa-c1-1) storage' "$(vr_q 'the client retries failed uploads')" '  test: t' \
  '  verdict: {"v":1,"vote":"refute","severity":"minor","reason":"The product ADR fixes the storage choice for every service here.","quote":{"file":"_product/DECISIONS.md","text":"All services share one Postgres instance."}}'
vr_block "$p" 1 architect
run "$p" 1
assert "product-adr-quote-allowed" "printf '%s' \"\$out\" | grep -q '\"failed\":0'"

p=$(vr_proj flag-role 1)
vr_block "$p" 1 qa
vr_block "$p" 1 coder '- [major] (coder-c1-1) retry limit' "$(vr_q 'a sentence the spec never had')" '  test: t' "$(vr_up 1 major)" "$(vr_up 2 major)"
run "$p" 1
assert "off-roster-block-checked" "printf '%s' \"\$out\" | grep -q '\"checked\":1,\"failed\":1'"

run "$p" x;  assert "bad-cycle-exit1" "[ $rc -eq 1 ]"
out=$( cd "$p" && bash "$QC" ../x --cycle 1 2>/dev/null ); rc=$?; assert "bad-slug-exit1" "[ $rc -eq 1 ]"
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run red**

Run: `bash scripts/quote-check.test.sh | tail -1`
Expected: non-zero exit with most cases FAILing (`quote-check.sh: No such file`); the two exit-code cases may pass because a missing script also exits non-zero.

- [ ] **Step 3: Create `scripts/quote-check.sh`** (then `chmod +x scripts/quote-check.sh`)

```bash
#!/usr/bin/env bash
# scripts/quote-check.sh — check every quote in a verified review cycle against the
# files it cites, and record the result as ONE event (REVIEW_SHAPE: verified).
#
# Run by hooks/scripts/check-review-quotes.sh when the scribe releases the
# .workflow-in-flight marker (its final write), so the spec is exactly as reviewed.
# Rules live in scripts/lib/verified-review.jq (shared with finalize-gate.sh).
#
# Usage: quote-check.sh <slug> --cycle N
# Output (stdout, one line):
#   BUILD_FLEET_QUOTE_CHECK: {"slug","cycle","cycle_total","checked","failed","revived":[…],"exempt":bool,"skipped":null|"<reason>"}
# Event (first per cycle_total wins): kind gate, source script:quote-check,
#   decision pass|fail, cycle, cycle_total, files (fingerprint), checked, failures,
#   revived, exempt.
# Exit: 0 = checked or skipped; 1 = bad usage / unreadable workspace.
# bash 3.2 + BSD/GNU compatible. Requires jq.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
slug="${1:-}"
[ -n "$slug" ] || { echo "usage: quote-check.sh <slug> --cycle N" >&2; exit 1; }
case "$slug" in */*|..|.|-*) echo "quote-check.sh: bad slug '$slug'" >&2; exit 1 ;; esac
[ "${2:-}" = "--cycle" ] || { echo "usage: quote-check.sh <slug> --cycle N" >&2; exit 1; }
cycle="${3:-}"
case "$cycle" in ''|*[!0-9]*) echo "quote-check.sh: --cycle needs an integer" >&2; exit 1 ;; esac
command -v jq >/dev/null 2>&1 || { echo "quote-check.sh: jq is required" >&2; exit 1; }

# shellcheck source=../hooks/scripts/_lib.sh
. "${HERE}/../hooks/scripts/_lib.sh"
# shellcheck source=lib/review-blocks.sh
. "${HERE}/lib/review-blocks.sh"
RULES="$(cat "${HERE}/lib/verified-review.jq")"

dir=".sdd/${slug}"; progress="${dir}/PROGRESS.md"; review="${dir}/REVIEW.md"
[ -f "$progress" ] || { echo "quote-check.sh: ${progress} not found" >&2; exit 1; }
cycle_total=$(read_progress_field "$slug" CYCLE_TOTAL)
case "$cycle_total" in ''|*[!0-9]*) cycle_total="$cycle" ;; esac

signal() { # signal <checked> <failed> <revived-json> <exempt> <skipped-json>
  printf 'BUILD_FLEET_QUOTE_CHECK: %s\n' "$(jq -cn --arg s "$slug" --argjson c "$cycle" --argjson t "$cycle_total" \
    --argjson k "$1" --argjson f "$2" --argjson r "$3" --argjson e "$4" --argjson sk "$5" \
    '{slug: $s, cycle: $c, cycle_total: $t, checked: $k, failed: $f, revived: $r, exempt: $e, skipped: $sk}')"
}

# First event per cycle_total wins: an incomplete run's marker release must never
# re-check this cycle against a spec revised since.
if read_events "$slug" "script:quote-check" | jq -e --argjson t "$cycle_total" 'select(.cycle_total == $t)' >/dev/null 2>&1; then
  signal 0 0 '[]' false '"already-checked"'; exit 0
fi

blocks=""
for role in $(cycle_roles "$review" "$cycle"); do
  b=$(last_cycle_block "$review" "$cycle" "$role")
  [ -n "$b" ] || continue
  printf '%s\n' "$b" | block_is_verified || continue
  blocks="${blocks}${b}"$'\n'
done
if [ -z "$blocks" ]; then signal 0 0 '[]' false '"not-verified"'; exit 0; fi

docs=$(quote_docs_json "$slug")
result=$(printf '%s' "$blocks" | jq -Rs --argjson docs "$docs" --arg slug "$slug" "${RULES}"'
  split("\n## ") | map(vr_parse_block) | add // [] | . as $fs
  | ($fs | vr_quotes | map(. + {pass: vr_check($docs; $slug)})) as $q
  | ([$q[] | select(.pass | not) | {id, where} + (if .v != null then {v} else {} end)]) as $fails
  | ($fs | vr_revived($fails)) as $rev
  | {checked: ($q | length), failures: $fails, revived: $rev, exempt: (($rev | length) > 0)}') \
  || { echo "quote-check.sh: could not evaluate ${review}" >&2; exit 1; }

fp=$(quote_docs_fingerprint "$slug")
failed=$(printf '%s' "$result" | jq '.failures | length')
decision=pass; [ "$failed" -eq 0 ] || decision=fail
log_event "$slug" "$(printf '%s' "$result" | jq -c --arg d "$decision" --argjson c "$cycle" --argjson t "$cycle_total" --argjson fp "$fp" \
  '{kind: "gate", source: "script:quote-check", decision: $d, cycle: $c, cycle_total: $t, files: $fp} + .')"
signal "$(printf '%s' "$result" | jq '.checked')" "$failed" "$(printf '%s' "$result" | jq -c '.revived')" \
  "$(printf '%s' "$result" | jq '.exempt')" null
exit 0
```

- [ ] **Step 4: Run green, then the suite**

Run: `bash scripts/quote-check.test.sh | tail -1; bash scripts/run-tests.sh 2>&1 | tail -1`
Expected: `passed=13 failed=0`; `suites: 34, failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/quote-check.sh scripts/quote-check.test.sh
git commit -m "feat(review): quote-check.sh checks a verified cycle's quotes and records one event

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The marker-release hook (spec §3.4, D7)

**Files:**
- Create: `hooks/scripts/check-review-quotes.sh`, `hooks/scripts/check-review-quotes.test.sh`
- Modify: `hooks/hooks.json`

**Interfaces:**
- Consumes: `scripts/quote-check.sh` (Task 4), `_lib.sh` (`extract_file_path`, `path_in_sdd`, `read_progress_field`).

- [ ] **Step 1: Write the harness**

`hooks/scripts/check-review-quotes.test.sh`:
```bash
#!/usr/bin/env bash
# Tests for hooks/scripts/check-review-quotes.sh — the quote check runs once, on the
# scribe's empty Write of .workflow-in-flight, only for a current-cycle verified block.
# Run: bash hooks/scripts/check-review-quotes.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/check-review-quotes.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
. "$DIR/../../scripts/fixtures/verified-review.sh"
pass=0; fail=0
# fire <name> <proj> <tool> <path> <content> <want-new-events>
fire() {
  local before after rc
  before=$(cat "$2/.sdd/feat/EVENTS.jsonl" 2>/dev/null | wc -l | tr -d ' ')
  ( cd "$2" && jq -cn --arg t "$3" --arg p "$4" --arg c "$5" '{tool_name:$t, tool_input:{file_path:$p, content:$c}}' \
      | CLAUDE_PROJECT_DIR="$2" bash "$HOOK" >/dev/null 2>&1 ); rc=$?
  after=$(cat "$2/.sdd/feat/EVENTS.jsonl" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$rc" -eq 0 ] && [ $((after-before)) -eq "$6" ]; then pass=$((pass+1)); printf 'ok   %-40s\n' "$1"
  else fail=$((fail+1)); printf 'FAIL %-40s rc=%s new=%s want=%s\n' "$1" "$rc" "$((after-before))" "$6"; fi
}
p=$(vr_proj v 1); vr_block "$p" 1 qa; vr_block "$p" 1 architect
M="$p/.sdd/feat/.workflow-in-flight"; printf 'run-1' > "$M"
fire "non-empty-marker-write-ignored" "$p" Write "$M" "run-1" 0
fire "review-md-write-ignored"        "$p" Write "$p/.sdd/feat/REVIEW.md" "" 0
fire "edit-of-marker-ignored"         "$p" Edit  "$M" "" 0
fire "marker-release-runs-check"      "$p" Write "$M" "" 1
fire "second-release-no-new-event"    "$p" Write "$M" "" 0
fire "relative-path-release"          "$(vr_proj r 1)" Write ".sdd/feat/.workflow-in-flight" "" 0
p=$(vr_proj d 1); printf '## Cycle 1 — qa — t\n- [minor] (qa-c1-1) x\nstatus: approved\n' >> "$p/.sdd/feat/REVIEW.md"
fire "debate-block-ignored"           "$p" Write "$p/.sdd/feat/.workflow-in-flight" "" 0
p=$(vr_proj s 2 2); vr_block "$p" 1 qa; vr_block "$p" 1 architect
fire "stale-cycle-ignored"            "$p" Write "$p/.sdd/feat/.workflow-in-flight" "" 0
p=$(vr_proj rel 1); vr_block "$p" 1 qa; vr_block "$p" 1 architect
fire "relative-path-verified-runs"    "$p" Write ".sdd/feat/.workflow-in-flight" "" 1
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run red**

Run: `bash hooks/scripts/check-review-quotes.test.sh | tail -1`
Expected: FAILs on `marker-release-runs-check` and `relative-path-verified-runs` (the hook is missing; bash exits 127, so every case reports a non-zero rc).

- [ ] **Step 3: Create `hooks/scripts/check-review-quotes.sh`**

```bash
#!/usr/bin/env bash
# PostToolUse(Write): run scripts/quote-check.sh when the scribe releases a workflow's
# .workflow-in-flight marker — its FINAL write, after every REVIEW.md block and every
# DECISIONS.md append has landed — and the newest REVIEW.md block is the current
# cycle in the verified shape. Does nothing otherwise (another file, a non-empty
# write, a debate block, an incomplete run that appended no block).
#
# Never changes the write's outcome: always exits 0. Fires inside workflow runs on
# purpose (it does not skip on .workflow-in-flight — the marker write IS the trigger).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "${HERE}/_lib.sh"
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
[ "$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" = "Write" ] || exit 0
path=$(extract_file_path "$input" 2>/dev/null) || exit 0
[ "$(printf '%s' "$input" | jq -r '.tool_input.content // "x"' 2>/dev/null)" = "" ] || exit 0
path_in_sdd "$path" || exit 0
case "$path" in */.workflow-in-flight) ;; *) exit 0 ;; esac
slug=$(basename "$(dirname "$path")")
case "$slug" in ''|.|..|.sdd|_product|-*) exit 0 ;; esac

review=".sdd/${slug}/REVIEW.md"
[ -f "$review" ] || exit 0
cycle=$(read_progress_field "$slug" CYCLE)
case "$cycle" in ''|*[!0-9]*) exit 0 ;; esac
# newest cycle heading must be the current cycle
last=$({ grep -E '^##[[:space:]]+Cycle[[:space:]]+[0-9]+[[:space:]]' "$review" || true; } | tail -1 | sed -E 's/^##[[:space:]]+Cycle[[:space:]]+([0-9]+).*/\1/')
[ "$last" = "$cycle" ] || exit 0
start=$({ grep -nE '^##[[:space:]]+Cycle[[:space:]]+[0-9]+[[:space:]]' "$review" || true; } | tail -1 | cut -d: -f1)
[ "$(sed -n "$((start+1))p" "$review" | tr -d '\r')" = "shape: verified" ] || exit 0

bash "${HERE}/../../scripts/quote-check.sh" "$slug" --cycle "$cycle" >/dev/null 2>&1 || true
exit 0
```

- [ ] **Step 4: Register it**

In `hooks/hooks.json`, add a new object to the `PostToolUse` array (after the existing `Write|Edit|NotebookEdit` object):
```json
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/check-review-quotes.sh\""
          }
        ]
      }
```
Append to the top-level `"description"` string:
```
, check a verified review's quotes against the spec when the scribe releases the workflow marker (recorded in the event log)
```
Then: `jq empty hooks/hooks.json && echo json-ok`.

- [ ] **Step 5: Run green, then the suite**

Run: `bash hooks/scripts/check-review-quotes.test.sh | tail -1; bash scripts/run-tests.sh 2>&1 | tail -1`
Expected: `passed=9 failed=0`; `suites: 35, failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add hooks/scripts/check-review-quotes.sh hooks/scripts/check-review-quotes.test.sh hooks/hooks.json
git commit -m "feat(review): run the quote check on the scribe's final marker release

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The finalize gate — verified path, `--report`, `spec-changed-since-review`, gate event (spec §3.5; dashboard spec §3.4)

**Files:**
- Modify: `scripts/finalize-gate.sh`
- Create: `scripts/finalize-gate-verified.test.sh`

**Interfaces:**
- Consumes: Tasks 2–4.
- Produces: `finalize-gate.sh <slug> [--roster csv] [--report]`. Gate mode: the unchanged `BUILD_FLEET_FINALIZE_GATE:` line (new reasons `quote-check-missing`, `spec-changed-since-review`), exit 0/2, and one event `{kind:"gate", source:"script:finalize-gate", decision:"pass"|"refuse", cycle, cycle_total, reasons}`. Report mode: `BUILD_FLEET_FINALIZE_REPORT: {feature, cycle, cycle_total, shape:"debate"|"verified"|"mixed", pass, reasons, open_blockers, open_majors, majors_without_adr, spec_changed, open:[{id, severity, text, raised_by, why, quote?, absent?, ref?, test?, disposition?, carried?}]}`, exit 0, writes nothing. `why` ∈ `blocker`, `major`, `major-without-adr`, `carried`, `carried-open`, `reopened-closure`.

- [ ] **Step 1: Write the verified harness**

`scripts/finalize-gate-verified.test.sh`:
```bash
#!/usr/bin/env bash
# Tests for the verified-shape path of scripts/finalize-gate.sh (blocks whose second line
# is "shape: verified"): vote recomputed from verdict lines + the quote-check event,
# quote-check-missing, spec-changed-since-review (gate mode only), carried findings,
# closures, --report, and the gate event. The debate path keeps its own suite
# (finalize-gate.test.sh), which must stay green unchanged.
# Run: bash scripts/finalize-gate-verified.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$DIR/finalize-gate.sh"; QC="$DIR/quote-check.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
. "$DIR/fixtures/verified-review.sh"
pass=0; fail=0
assert() { if eval "$2"; then pass=$((pass+1)); printf 'ok   %s\n' "$1"; else fail=$((fail+1)); printf 'FAIL %s (%s) out=%s\n' "$1" "$2" "${out:-}"; fi; }
qc()   { ( cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$QC" feat --cycle "$2" >/dev/null 2>&1 ); }
gate() { out=$( cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$GATE" feat "${@:2}" 2>/dev/null ); rc=$?; }
field() { printf '%s' "$out" | sed 's/^[A-Z_]*: //' | jq -c "$1"; }
KILL=("$(vr_up 1 major)" "$(vr_rf 2 'Retries are capped at 3 attempts')" "$(vr_rf 3 'Retries are capped at 3 attempts')")

p=$(vr_proj killed 1)
vr_block "$p" 1 qa '- [major] (qa-c1-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' "${KILL[@]}"
vr_block "$p" 1 architect '- [minor] (architect-c1-1) nit'
qc "$p" 1; gate "$p"
assert "killed-major-passes" "[ $rc -eq 0 ] && [ \"\$(field .reasons)\" = '[]' ]"
assert "gate-event-logged" "jq -e 'select(.source == \"script:finalize-gate\") | .decision == \"pass\"' '$p/.sdd/feat/EVENTS.jsonl' >/dev/null"

p=$(vr_proj no-event 1)
vr_block "$p" 1 qa '- [major] (qa-c1-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' "${KILL[@]}"
vr_block "$p" 1 architect
gate "$p"
assert "quote-check-missing-refuses" "[ $rc -eq 2 ] && field .reasons | grep -q quote-check-missing"

p=$(vr_proj invented 1)
vr_block "$p" 1 qa '- [major] (qa-c1-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' \
  "$(vr_up 1 major)" "$(vr_rf 2 'Retries are capped at 3 attempts')" "$(vr_rf 3 'Retries are capped at 9 attempts')"
vr_block "$p" 1 architect
qc "$p" 1; gate "$p"
assert "invented-refute-revives-open" "[ $rc -eq 2 ] && [ \"\$(field .open_majors)\" = '[\"qa-c1-1\"]' ]"

p=$(vr_proj blocker 1)
vr_block "$p" 1 qa '- [blocker] (qa-c1-2) no auth' '  absent: {"file":"spec.md","section":"Behavior","missing":"auth"}' '  test: t' \
  "$(vr_rf 1 'Retries are capped at 3 attempts')" "$(vr_up 2 blocker)" "$(vr_up 3 blocker)"
vr_block "$p" 1 architect
qc "$p" 1; gate "$p"
assert "single-refute-no-veto" "[ $rc -eq 2 ] && field .open_blockers | grep -q 'qa-c1-2'"

p=$(vr_proj adr 1)
vr_block "$p" 1 qa '- [major] (qa-c1-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' "$(vr_up 1 major)" "$(vr_up 2 major)" '  disposition: adr ADR-1'
vr_block "$p" 1 architect '- [major] (architect-c1-1) other' "$(vr_q 'the client retries failed uploads')" '  test: t' "$(vr_up 1 major)" "$(vr_up 2 major)" '  disposition: adr ADR-7'
qc "$p" 1; gate "$p"
assert "adr-closes-missing-adr-refuses" "[ \"\$(field .majors_without_adr)\" = '[\"architect-c1-1\"]' ] && [ \"\$(field .open_majors)\" = '[]' ]"

p=$(vr_proj changed 1)
vr_block "$p" 1 qa '- [major] (qa-c1-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' "${KILL[@]}"
vr_block "$p" 1 architect
qc "$p" 1
sed -i.bak 's/^STATUS: DRAFT/STATUS: FINALIZED/' "$p/.sdd/feat/spec.md"; gate "$p"
assert "status-flip-alone-passes" "[ $rc -eq 0 ]"
printf '\n## ADR-2: appended later\n' >> "$p/.sdd/feat/DECISIONS.md"; gate "$p"
assert "adr-append-passes" "[ $rc -eq 0 ]"
printf 'A new requirement.\n' >> "$p/.sdd/feat/spec.md"; gate "$p"
assert "spec-edit-refuses" "[ $rc -eq 2 ] && field .reasons | grep -q spec-changed-since-review"
gate "$p" --report
assert "report-flags-not-refuses" "[ $rc -eq 0 ] && [ \"\$(field .spec_changed)\" = true ] && ! field .reasons | grep -q spec-changed"
sed -i.bak 's/keep retries client-side/keep retries server-side/' "$p/.sdd/feat/DECISIONS.md"; sed -i.bak '$d' "$p/.sdd/feat/spec.md"; gate "$p"
assert "adr-edit-refuses" "[ $rc -eq 2 ] && field .reasons | grep -q spec-changed-since-review"

p=$(vr_proj closure 2 2)
vr_block "$p" 1 qa '- [major] (qa-c1-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' "$(vr_up 1 major)" "$(vr_up 2 major)" '  disposition: fix'
vr_block "$p" 1 architect
vr_block "$p" 2 qa '- [major] (qa-c1-1) retry limit' '  closure: {"file":"spec.md","text":"Retries are capped at 3 attempts"}' \
  '  verdict: {"v":1,"vote":"confirm","severity":"major"}' '  verdict: {"v":2,"vote":"confirm","severity":"major"}' '  verdict: {"v":3,"vote":"reject","severity":"major","reason":"no"}'
vr_block "$p" 2 architect
qc "$p" 2; gate "$p"
assert "confirmed-closure-closes" "[ $rc -eq 0 ]"

p=$(vr_proj carried 2 2)
vr_block "$p" 1 qa '- [major] (qa-c1-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' "$(vr_up 1 major)" "$(vr_up 2 major)" '  disposition: fix'
vr_block "$p" 1 architect
vr_block "$p" 2 qa
vr_block "$p" 2 architect
( cd "$p" && printf '%s\n' '{"v":1,"ts":"t","slug":"feat","kind":"gate","source":"script:quote-check","decision":"pass","cycle":1,"cycle_total":1,"files":{},"checked":1,"failures":[],"revived":[],"exempt":false}' >> .sdd/feat/EVENTS.jsonl )
qc "$p" 2; gate "$p" --report
assert "omitted-finding-carried-open" "[ \"\$(field '[.open[] | {id, why}]')\" = '[{\"id\":\"qa-c1-1\",\"why\":\"carried-open\"}]' ]"
assert "report-shape-verified" "[ \"\$(field .shape)\" = '\"verified\"' ]"
assert "report-logs-nothing" "! grep -q finalize-gate '$p/.sdd/feat/EVENTS.jsonl'"

QC1='{"v":1,"ts":"t","slug":"feat","kind":"gate","source":"script:quote-check","decision":"pass","cycle":1,"cycle_total":1,"files":{},"checked":1,"failures":[],"revived":[],"exempt":false}'
p=$(vr_proj off-roster 2 2)
vr_block "$p" 1 qa
vr_block "$p" 1 architect '- [major] (architect-c1-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' "$(vr_up 1 major)" "$(vr_up 2 major)" '  disposition: fix'
sed -i.bak 's/^REVIEW_ROLES: .*/REVIEW_ROLES: qa,coder/' "$p/.sdd/feat/PROGRESS.md"
vr_block "$p" 2 qa
vr_block "$p" 2 coder
printf '%s\n' "$QC1" >> "$p/.sdd/feat/EVENTS.jsonl"
qc "$p" 2; gate "$p" --report
assert "off-roster-raiser-carried-open" "[ \"\$(field '[.open[] | {id, why}]')\" = '[{\"id\":\"architect-c1-1\",\"why\":\"carried-open\"}]' ]"

p=$(vr_proj hosted 3 3)
sed -i.bak 's/^REVIEW_ROLES: .*/REVIEW_ROLES: qa,coder/' "$p/.sdd/feat/PROGRESS.md"
vr_block "$p" 3 qa '- [major] (architect-c1-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' '  carried: {"from_cycle":1,"reason":"not-addressed"}'
vr_block "$p" 3 coder
qc "$p" 3; gate "$p" --report
assert "hosted-carried-stays-open" "[ \"\$(field '[.open[] | {id, why, raised_by}]')\" = '[{\"id\":\"architect-c1-1\",\"why\":\"carried\",\"raised_by\":\"architect\"}]' ]"
assert "report-keeps-carried-origin" "[ \"\$(field '.open[0].carried')\" = '{\"from_cycle\":1,\"reason\":\"not-addressed\"}' ]"
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run red; confirm the debate harness is green before the change**

Run: `bash scripts/finalize-gate-verified.test.sh | tail -1; bash scripts/finalize-gate.test.sh | tail -1`
Expected: verified harness FAILs (today's gate parses verified blocks as debate and has no `--report`); `passed=19 failed=0` for the debate harness.

- [ ] **Step 3: Apply the gate patch**

Save as `/tmp/gate.patch` and run `git apply /tmp/gate.patch`:
```diff
--- a/scripts/finalize-gate.sh
+++ b/scripts/finalize-gate.sh
@@ -19,23 +19,45 @@
 #   A "  refuted-by: …" anywhere in that run closes a blocker or a major.
 #   `status:` lines are NOT evaluated (informational since v0.9).
 #
-# Usage: finalize-gate.sh <slug> [--roster a,b,c]
+# Verified blocks (second line "shape: verified", REVIEW_SHAPE: verified) are judged
+# by the rules in scripts/lib/verified-review.jq instead: the vote is recomputed from
+# the "verdict:" lines and the cycle's quote-check event (first per cycle_total);
+# no event ⇒ quote-check-missing; quote sources changed since the review ⇒
+# spec-changed-since-review (gate mode only); a finding open in the previous verified
+# cycle and absent from this one stays open (carried-open).
+#
+# Usage: finalize-gate.sh <slug> [--roster a,b,c] [--report]
 #   ROSTER defaults to REVIEW_ROLES in PROGRESS.md, else architect,qa,coder.
 # Output (stdout, exactly one line):
-#   BUILD_FLEET_FINALIZE_GATE: {"feature","cycle","pass":bool,"reasons":[…],"open_blockers":[…],"open_majors":[…],"majors_without_adr":[…]}
-# Exit: 0 = pass; 2 = refuse; 1 = bad usage / unreadable workspace.
-# bash 3.2 + BSD/GNU compatible; read-only. Requires jq for JSON string escaping.
+#   gate mode:   BUILD_FLEET_FINALIZE_GATE: {"feature","cycle","pass":bool,"reasons":[…],"open_blockers":[…],"open_majors":[…],"majors_without_adr":[…]}
+#   --report:    BUILD_FLEET_FINALIZE_REPORT: {…the same fields…, "cycle_total", "shape", "spec_changed", "open":[{id,severity,text,raised_by,why,…}]}
+# Gate mode logs one gate event (script:finalize-gate) to .sdd/<slug>/EVENTS.jsonl;
+# --report logs nothing, writes nothing, never refuses on spec-changed-since-review,
+# and always exits 0.
+# Exit (gate mode): 0 = pass; 2 = refuse; 1 = bad usage / unreadable workspace.
+# bash 3.2 + BSD/GNU compatible. Requires jq.
 set -uo pipefail
 
 slug="${1:-}"
 [ -n "$slug" ] || { echo "usage: finalize-gate.sh <slug> [--roster a,b,c]" >&2; exit 1; }
 case "$slug" in */*|..|.|-*) echo "finalize-gate.sh: bad slug '$slug'" >&2; exit 1 ;; esac
 shift
-roster_arg=""
-if [ "${1:-}" = "--roster" ]; then roster_arg="${2:-}"; fi
+roster_arg=""; report=false
+while [ $# -gt 0 ]; do
+  case "$1" in
+    --roster) roster_arg="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
+    --report) report=true; shift ;;
+    *) echo "finalize-gate.sh: unknown argument '$1'" >&2; exit 1 ;;
+  esac
+done
 command -v jq >/dev/null 2>&1 || { echo "finalize-gate.sh: jq is required" >&2; exit 1; }
 
-cd "${CLAUDE_PROJECT_DIR:-.}"
+HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
+# shellcheck source=../hooks/scripts/_lib.sh
+. "${HERE}/../hooks/scripts/_lib.sh"
+# shellcheck source=lib/review-blocks.sh
+. "${HERE}/lib/review-blocks.sh"
+RULES="$(cat "${HERE}/lib/verified-review.jq")"
 dir=".sdd/${slug}"
 progress="${dir}/PROGRESS.md"; review="${dir}/REVIEW.md"; decisions="${dir}/DECISIONS.md"
 [ -f "$progress" ] || { echo "finalize-gate.sh: ${progress} not found" >&2; exit 1; }
@@ -43,6 +65,8 @@
 field() { { grep -m1 "^$1:" "$progress" 2>/dev/null || true; } | sed -E "s/^$1:[[:space:]]*//" | tr -d '\r '; }
 cycle=$(field CYCLE)
 case "$cycle" in ''|*[!0-9]*) echo "finalize-gate.sh: CYCLE is not an integer ('${cycle}')" >&2; exit 1 ;; esac
+cycle_total=$(field CYCLE_TOTAL)
+case "$cycle_total" in ''|*[!0-9]*) cycle_total="$cycle" ;; esac
 
 roster="$roster_arg"
 [ -n "$roster" ] || roster=$(field REVIEW_ROLES)
@@ -50,17 +74,18 @@
 roles=$(printf '%s' "$roster" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep . || true)
 
 reasons=""; open_blockers=""; open_majors=""; without_adr=""
+vblocks=""; legacy_blocks=0
 add() { eval "$1=\"\${$1}\${$1:+\$'\\n'}\$2\""; }
 
 for role in $roles; do
   [ -f "$review" ] || { add reasons "missing-${role}"; continue; }
-  # last block for this role + cycle: heading line number
-  start=$({ grep -nE "^##[[:space:]]+Cycle[[:space:]]+${cycle}[[:space:]]+[—–-][[:space:]]+${role}[[:space:]]+[—–-]" "$review" || true; } | tail -1 | cut -d: -f1)
-  if [ -z "$start" ]; then add reasons "missing-${role}"; continue; fi
-  # block end: next "## " heading after start, or EOF
-  next=$({ tail -n +"$((start+1))" "$review" | grep -n '^## ' || true; } | head -1 | cut -d: -f1)
-  if [ -n "$next" ]; then end=$((start+next-1)); else end=$(wc -l < "$review" | tr -d ' '); fi
-  block=$(sed -n "${start},${end}p" "$review")
+  block=$(last_cycle_block "$review" "$cycle" "$role")
+  if [ -z "$block" ]; then add reasons "missing-${role}"; continue; fi
+  if printf '%s\n' "$block" | block_is_verified; then
+    vblocks="${vblocks}${block}"$'\n'
+    continue
+  fi
+  legacy_blocks=$((legacy_blocks+1))
 
   # blockers + majors: a finding is closed by a "refuted-by:"/"disposition: adr ADR-N"
   # continuation found ANYWHERE in the indented run of lines following it (C1: a
@@ -109,6 +134,60 @@
   done
 done
 
+# ---- verified blocks: recompute the vote from verdict lines + the quote-check event ----
+spec_changed=false; vopen='[]'
+adr_nums() { { grep -E '^##[[:space:]]+ADR-0*[0-9]+:' "$decisions" 2>/dev/null || true; } \
+  | sed -E 's/^##[[:space:]]+ADR-0*([0-9]+):.*/\1/' | jq -Rsc 'split("\n") | map(select(length > 0) | tonumber)'; }
+qc_event() { read_events "$slug" "script:quote-check" | jq -c --argjson t "$1" 'select(.cycle_total == $t)' | head -1; }
+verified_blocks_for() { # verified_blocks_for <cycle> → every verified block of that cycle, whatever the roster
+  local r b out=""
+  for r in $(cycle_roles "$review" "$1"); do
+    b=$(last_cycle_block "$review" "$1" "$r"); [ -n "$b" ] || continue
+    printf '%s\n' "$b" | block_is_verified && out="${out}${b}"$'\n'
+  done
+  printf '%s' "$out"
+}
+if [ -n "$vblocks" ]; then
+  adrs=$(adr_nums)
+  ev=$(qc_event "$cycle_total")
+  if [ -z "$ev" ]; then
+    add reasons "quote-check-missing"; fails='[]'
+  else
+    fails=$(printf '%s' "$ev" | jq -c '.failures // []')
+    fingerprint_matches "$slug" "$(printf '%s' "$ev" | jq -c '.files // {}')" || spec_changed=true
+  fi
+  # carried-open safety net: open at the end of the previous verified cycle, absent now
+  prev_open='[]'
+  if [ "$cycle" -ge 2 ]; then
+    pblocks=$(verified_blocks_for $((cycle-1)))
+    if [ -n "$pblocks" ]; then
+      pev=$(qc_event $((cycle_total-1)))
+      pfails=$(printf '%s' "${pev:-{\}}" | jq -c '.failures // []')
+      prev_open=$(printf '%s' "$pblocks" | jq -Rs --argjson fails "$pfails" --argjson adrs "$adrs" "${RULES}"'
+        split("\n## ") | map(vr_parse_block) | add // [] | map(vr_outcome($fails) | . + {why: vr_open($adrs)}) | map(select(.why != null))')
+    fi
+  fi
+  vopen=$(printf '%s' "$vblocks" | jq -Rs --argjson fails "$fails" --argjson adrs "$adrs" --argjson prev "$prev_open" "${RULES}"'
+    split("\n## ") | map(vr_parse_block) | add // [] | . as $fs
+    | ($fs | map(.id)) as $listed
+    | ($fs | map(vr_outcome($fails) | . + {why: (if .carried != null and vr_open($adrs) != null then "carried" elif .reopened_closure and vr_open($adrs) != null then "reopened-closure" else vr_open($adrs) end)})
+           | map(select(.why != null)))
+      + [$prev[] | select(.id as $i | $listed | index($i) | not) | . + {why: "carried-open"}]
+    | map({id, severity: .final, text, raised_by: (.id | sub("-c[0-9]+-[0-9]+$"; "")), why,
+           quote, absent, ref, test, disposition, carried} | with_entries(select(.value != null)))')
+  while IFS= read -r row; do
+    [ -n "$row" ] || continue
+    id=$(printf '%s' "$row" | jq -r '.id'); why=$(printf '%s' "$row" | jq -r '.why'); sev=$(printf '%s' "$row" | jq -r '.severity')
+    case "$why" in
+      major-without-adr) add without_adr "$id" ;;
+      *) if [ "$sev" = blocker ]; then add open_blockers "- [blocker] (${id}) $(printf '%s' "$row" | jq -r '.text')"; else add open_majors "$id"; fi ;;
+    esac
+  done <<EOF_ROWS
+$(printf '%s' "$vopen" | jq -c '.[]')
+EOF_ROWS
+  [ "$report" = true ] || [ "$spec_changed" = false ] || add reasons "spec-changed-since-review"
+fi
+
 [ -z "$open_blockers" ] || add reasons "open-blockers"
 [ -z "$open_majors" ] || add reasons "majors-open"
 [ -z "$without_adr" ] || add reasons "majors-without-adr"
@@ -116,6 +195,20 @@
 tojson() { if [ -z "$1" ]; then printf '[]'; else printf '%s\n' "$1" | jq -R . | jq -sc .; fi; }
 pass=true; [ -z "$reasons" ] || pass=false
 slug_json=$(jq -n --arg s "$slug" '$s')
+if [ "$report" = true ]; then
+  shape=debate
+  if [ -n "$vblocks" ]; then if [ "$legacy_blocks" -gt 0 ]; then shape=mixed; else shape=verified; fi; fi
+  printf 'BUILD_FLEET_FINALIZE_REPORT: %s\n' "$(jq -cn --argjson f "$slug_json" --argjson c "$cycle" --argjson t "$cycle_total" \
+    --arg shape "$shape" --argjson pass "$pass" --argjson reasons "$(tojson "$reasons")" \
+    --argjson ob "$(tojson "$open_blockers")" --argjson om "$(tojson "$open_majors")" --argjson wa "$(tojson "$without_adr")" \
+    --argjson sc "$spec_changed" --argjson open "$vopen" \
+    '{feature: $f, cycle: $c, cycle_total: $t, shape: $shape, pass: $pass, reasons: $reasons, open_blockers: $ob,
+      open_majors: $om, majors_without_adr: $wa, spec_changed: $sc, open: $open}')"
+  exit 0
+fi
 printf 'BUILD_FLEET_FINALIZE_GATE: {"feature":%s,"cycle":%s,"pass":%s,"reasons":%s,"open_blockers":%s,"open_majors":%s,"majors_without_adr":%s}\n' \
   "$slug_json" "$cycle" "$pass" "$(tojson "$reasons")" "$(tojson "$open_blockers")" "$(tojson "$open_majors")" "$(tojson "$without_adr")"
+decision=pass; [ "$pass" = true ] || decision=refuse
+log_event "$slug" "$(jq -cn --arg d "$decision" --argjson c "$cycle" --argjson t "$cycle_total" --argjson r "$(tojson "$reasons")" \
+  '{kind: "gate", source: "script:finalize-gate", decision: $d, cycle: $c, cycle_total: $t, reasons: $r}')"
 [ "$pass" = true ] && exit 0 || exit 2
```

- [ ] **Step 4: Run green — both harnesses — then the suite**

Run: `bash scripts/finalize-gate-verified.test.sh | tail -1; bash scripts/finalize-gate.test.sh | tail -1; bash scripts/run-tests.sh 2>&1 | tail -1`
Expected: `passed=18 failed=0`; `passed=19 failed=0` (debate path unchanged); `suites: 36, failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/finalize-gate.sh scripts/finalize-gate-verified.test.sh
git commit -m "feat(gate): finalize gate recomputes verified votes, adds --report and the gate event

Verified blocks are judged by scripts/lib/verified-review.jq with the cycle's
quote-check event; no event refuses quote-check-missing; quote sources changed
since the review refuse spec-changed-since-review (gate mode only).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `scripts/review-carry.sh` (spec §3.3 delta cycles, §3.4 budget exemption)

**Files:**
- Create: `scripts/review-carry.sh`, `scripts/review-carry.test.sh`

**Interfaces:**
- Consumes: Task 6 `--report`; Task 2 `read_events`.
- Produces: `review-carry.sh <slug>` → `BUILD_FLEET_REVIEW_CARRY: {feature, cycle, previous_shape:"verified"|"debate"|"none", carried:[…report .open…], open_count, exempt_cycles}`; exit 2 and no line when the last cycle is verified but the gate gave no report. Task 10's `/build-fleet:review` passes `carried` and `exempt_cycles` to the workflow.

- [ ] **Step 1: Write the harness**

`scripts/review-carry.test.sh`:
```bash
#!/usr/bin/env bash
# Tests for scripts/review-carry.sh — the carried open set and exempt_cycles that
# /build-fleet:review passes after a verified cycle.
# Run: bash scripts/review-carry.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RC="$DIR/review-carry.sh"; QC="$DIR/quote-check.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
. "$DIR/fixtures/verified-review.sh"
pass=0; fail=0
assert() { if eval "$2"; then pass=$((pass+1)); printf 'ok   %s\n' "$1"; else fail=$((fail+1)); printf 'FAIL %s (%s) out=%s\n' "$1" "$2" "${out:-}"; fi; }
carry() { out=$( cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$RC" feat 2>/dev/null ); rc=$?; }
field() { printf '%s' "$out" | sed 's/^[A-Z_]*: //' | jq -c "$1"; }
ev() { printf '{"v":1,"ts":"t","slug":"feat","kind":"gate","source":"script:quote-check","decision":"fail","cycle":%s,"cycle_total":%s,"files":{},"checked":1,"failures":[],"revived":["x"],"exempt":%s}\n' "$2" "$3" "$4" >> "$1/.sdd/feat/EVENTS.jsonl"; }

p=$(vr_proj none 0); carry "$p"
assert "no-cycle-none" "[ $rc -eq 0 ] && [ \"\$(field '[.previous_shape, .open_count, .exempt_cycles]')\" = '[\"none\",0,0]' ]"

p=$(vr_proj debate 1); printf '## Cycle 1 — qa — t\n- [major] (qa-c1-1) x\n  disposition: fix\nstatus: concerns-raised\n' >> "$p/.sdd/feat/REVIEW.md"; carry "$p"
assert "debate-carries-nothing" "[ \"\$(field '[.previous_shape, .open_count]')\" = '[\"debate\",0]' ]"

p=$(vr_proj open 1)
vr_block "$p" 1 qa '- [major] (qa-c1-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' "$(vr_up 1 major)" "$(vr_up 2 major)" '  disposition: fix'
vr_block "$p" 1 architect '- [minor] (architect-c1-1) nit'
( cd "$p" && CLAUDE_PROJECT_DIR="$p" bash "$QC" feat --cycle 1 >/dev/null 2>&1 ); carry "$p"
assert "verified-carries-open-set" "[ \"\$(field '[.previous_shape, (.carried | map(.id)), .carried[0].raised_by, .carried[0].quote.text]')\" = '[\"verified\",[\"qa-c1-1\"],\"qa\",\"the client retries failed uploads\"]' ]"
assert "no-exempt-yet" "[ \"\$(field .exempt_cycles)\" = 0 ]"

p=$(vr_proj exempt 2 5); vr_block "$p" 2 qa; vr_block "$p" 2 architect
ev "$p" 1 3 true    # before this phase (cycle_total 3 <= 5-2): not counted
ev "$p" 1 4 true    # this phase
ev "$p" 1 4 false   # later event for the same cycle_total: first wins
ev "$p" 2 5 false
carry "$p"
assert "exempt-counts-this-phase-first-event" "[ \"\$(field .exempt_cycles)\" = 1 ]"

p=$(vr_proj no-report 1)
vr_block "$p" 1 qa; vr_block "$p" 1 architect
mkdir -p "$work/broken/lib"; cp "$RC" "$work/broken/"; cp "$DIR/lib/"* "$work/broken/lib/"
mkdir -p "$work/hooks/scripts"; cp "$DIR/../hooks/scripts/_lib.sh" "$work/hooks/scripts/"
printf '#!/usr/bin/env bash\nexit 1\n' > "$work/broken/finalize-gate.sh"
out=$( cd "$p" && CLAUDE_PROJECT_DIR="$p" bash "$work/broken/review-carry.sh" feat 2>/dev/null ); rc=$?
assert "no-report-refuses" "[ $rc -eq 2 ] && ! printf '%s' \"\$out\" | grep -q BUILD_FLEET_REVIEW_CARRY"

p=$(vr_proj flag-role-carry 1)
vr_block "$p" 1 coder; carry "$p"
assert "shape-read-from-any-block" "[ \"\$(field .previous_shape)\" = '\"verified\"' ]"
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run red**

Run: `bash scripts/review-carry.test.sh | tail -1`
Expected: every case FAILs (script missing).

- [ ] **Step 3: Create `scripts/review-carry.sh`** (then `chmod +x`)

```bash
#!/usr/bin/env bash
# scripts/review-carry.sh — what /build-fleet:review must pass to the next verified
# cycle: the open findings carried forward and the review-budget exemption.
#
# Reads the CURRENT (last completed) cycle of .sdd/<slug>/. When its blocks are in the
# verified shape, `carried` is the open set from `finalize-gate.sh --report` (full
# finding objects) and `exempt_cycles` counts this review phase's cycles whose
# quote-check event is exempt (a finding reopened by a failed quote). The phase's
# cycles are those with cycle_total in (CYCLE_TOTAL - CYCLE, CYCLE_TOTAL] — CYCLE
# resets on resolve-escalation, CYCLE_TOTAL never does. Debate shape or no cycle yet:
# nothing is carried and exempt_cycles is 0.
#
# Usage: review-carry.sh <slug>
# Output (stdout, one line):
#   BUILD_FLEET_REVIEW_CARRY: {"feature","cycle","previous_shape":"verified"|"debate"|"none","carried":[…],"open_count":N,"exempt_cycles":N}
# Exit: 0; 1 = bad usage / unreadable workspace; 2 (no output line) = the last cycle is
# verified but finalize-gate.sh --report gave no report. Writes nothing. bash 3.2; requires jq.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
slug="${1:-}"
[ -n "$slug" ] || { echo "usage: review-carry.sh <slug>" >&2; exit 1; }
case "$slug" in */*|..|.|-*) echo "review-carry.sh: bad slug '$slug'" >&2; exit 1 ;; esac
command -v jq >/dev/null 2>&1 || { echo "review-carry.sh: jq is required" >&2; exit 1; }
# shellcheck source=../hooks/scripts/_lib.sh
. "${HERE}/../hooks/scripts/_lib.sh"
# shellcheck source=lib/review-blocks.sh
. "${HERE}/lib/review-blocks.sh"

progress=".sdd/${slug}/PROGRESS.md"; review=".sdd/${slug}/REVIEW.md"
[ -f "$progress" ] || { echo "review-carry.sh: ${progress} not found" >&2; exit 1; }
cycle=$(read_progress_field "$slug" CYCLE); case "$cycle" in ''|*[!0-9]*) cycle=0 ;; esac
total=$(read_progress_field "$slug" CYCLE_TOTAL); case "$total" in ''|*[!0-9]*) total="$cycle" ;; esac

out() { printf 'BUILD_FLEET_REVIEW_CARRY: %s\n' "$(jq -cn --arg f "$slug" --argjson c "$cycle" --arg s "$1" --argjson k "$2" --argjson e "$3" \
  '{feature: $f, cycle: $c, previous_shape: $s, carried: $k, open_count: ($k | length), exempt_cycles: $e}')"; }

[ "$cycle" -ge 1 ] || { out none '[]' 0; exit 0; }
shape=debate
for role in $(cycle_roles "$review" "$cycle"); do
  last_cycle_block "$review" "$cycle" "$role" | block_is_verified && { shape=verified; break; }
done
[ "$shape" = verified ] || { out debate '[]' 0; exit 0; }

report=$(bash "${HERE}/finalize-gate.sh" "$slug" --report 2>/dev/null | sed -n 's/^BUILD_FLEET_FINALIZE_REPORT: //p')
[ -n "$report" ] || { echo "review-carry.sh: finalize-gate.sh --report gave no report; refusing to carry an empty open set" >&2; exit 2; }
carried=$(printf '%s' "$report" | jq -c '.open // []')
exempt=$(read_events "$slug" "script:quote-check" | jq -s --argjson lo $((total - cycle)) --argjson hi "$total" \
  'group_by(.cycle_total) | map(.[0]) | map(select(.cycle_total > $lo and .cycle_total <= $hi and .exempt == true)) | length')
out verified "$carried" "${exempt:-0}"
```

- [ ] **Step 4: Run green, then the suite**

Run: `bash scripts/review-carry.test.sh | tail -1; bash scripts/run-tests.sh 2>&1 | tail -1`
Expected: `passed=7 failed=0`; `suites: 37, failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/review-carry.sh scripts/review-carry.test.sh
git commit -m "feat(review): review-carry.sh reports the carried open set and exempt cycles

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `review.js` pure helpers — settings normalizers and the JS twin of the rules (spec §3.3)

**Files:**
- Modify: `workflows/review.js` (LAYER1-PURE-HELPERS region only)
- Create: `scripts/workflow-review-verified.test.sh`, `scripts/verified-vote-parity.test.sh`

**Interfaces:**
- Consumes: `flattenText` (existing, same region); `scripts/lib/verified-review.jq` (parity test).
- Produces (used by Task 9): `normalizeShape(raw) → {shape, error}`, `normalizeVerifierModel(raw) → {model, error}`, `normalizeFlag(raw, name) → {value, error}`, `normalizeExemptCycles(raw) → {value, error}`, `normalizeCarried(raw, shape) → {carried, error}`, `vrRank(s)`, `vrEvidence(v)`, `demoteUncheckable(concerns) → {concerns, demoted}`, `rotateLeft(list, k)`, `verifiedOutcome(f)`, `applyVerifiedVote(findings, panels)` (returns findings with `verdicts`, `final`, `killed`, `closed`, `demoted?`, `severity` = final, `severity_raised`, `refuted` = killed‖closed), `materializeCarried(concerns, carried, cycle, roles)` (re-listed and omitted carried findings become carried records; an off-roster raiser's gets `host: roles[0]`), `formatVerifiedFindingLines(c, dispositionMap)`.

- [ ] **Step 1: Write both harnesses**

`scripts/workflow-review-verified.test.sh`:
```bash
#!/usr/bin/env bash
# Tests the verified-shape PURE helpers of workflows/review.js — extracted VERBATIM from
# between the LAYER1-PURE-HELPERS markers and run under node: the shape/settings
# normalizers, demoteUncheckable, rotateLeft, verifiedOutcome, applyVerifiedVote,
# materializeCarried and formatVerifiedFindingLines. Skips if node is absent. bash 3.2.
# Run: bash scripts/workflow-review-verified.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REVIEW="$DIR/../workflows/review.js"
if ! command -v node >/dev/null 2>&1; then echo "ok   workflow-review-verified (SKIPPED: node not found; enforced in CI)"; exit 0; fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wf-review-ver.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
awk '/LAYER1-PURE-HELPERS START/{f=1;next} /LAYER1-PURE-HELPERS END/{f=0;next} f' "$REVIEW" > "$TMP/helpers.js"
[ -s "$TMP/helpers.js" ] || { echo "FAIL could not extract LAYER1-PURE-HELPERS region"; exit 1; }
cat "$TMP/helpers.js" - > "$TMP/run.js" <<'JS'
let pass = 0, fail = 0;
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function check(name, cond) { if (cond) { pass++; console.log("ok   " + name); } else { fail++; console.log("FAIL " + name); } }
const R = "The constraints section caps retries at three attempts explicitly.";
const Q = { file: "spec.md", text: "Retries are capped at 3 attempts" };

check("shape-default-debate", normalizeShape(undefined).shape === "debate");
check("shape-verified", normalizeShape("verified").shape === "verified");
check("shape-bad", normalizeShape("vote").error !== null);
check("verifier-model-default-sonnet", normalizeVerifierModel(null).model === "sonnet");
check("verifier-model-bad", normalizeVerifierModel("gpt").error !== null);
check("flag-default-false", normalizeFlag(undefined, "x").value === false);
check("flag-string-true", normalizeFlag("true", "x").value === true);
check("flag-bad", normalizeFlag("yes", "x").error !== null);
check("exempt-default-0", normalizeExemptCycles(undefined).value === 0);
check("exempt-bad", normalizeExemptCycles(-1).error !== null);
check("carried-default-empty", eq(normalizeCarried(undefined, "verified").carried, []));
check("carried-debate-rejected", normalizeCarried([{ id: "qa-c1-1", raised_by: "qa", severity: "major" }], "debate").error !== null);
check("carried-minor-rejected", normalizeCarried([{ id: "qa-c1-1", raised_by: "qa", severity: "minor" }], "verified").error !== null);

const dm = demoteUncheckable([
  { id: "qa-c1-1", severity: "major", text: "a", anchor: { kind: "quote", file: "spec.md", text: "abc def ghij" }, test: "t" },
  { id: "qa-c1-2", severity: "major", text: "b", anchor: { kind: "none" }, test: "t" },
  { id: "qa-c1-3", severity: "blocker", text: "c", anchor: { kind: "absent", file: "spec.md", section: "Security", missing: "x" }, test: " " },
  { id: "qa-c1-4", severity: "minor", text: "d", anchor: { kind: "none" }, test: "" },
]);
check("demote-no-anchor-and-no-test", eq(dm.demoted, ["qa-c1-2", "qa-c1-3"]) && dm.concerns[1].demoted.reason === "no-anchor" && dm.concerns[2].demoted.reason === "no-test");
check("demote-minor-untouched", !dm.concerns[3].demoted);

check("rotate-0", eq(rotateLeft([1, 2, 3], 0), [1, 2, 3]));
check("rotate-1", eq(rotateLeft([1, 2, 3], 1), [2, 3, 1]));
check("rotate-wraps", eq(rotateLeft([1, 2], 3), [2, 1]));
check("rotate-empty", eq(rotateLeft([], 2), []));

const f = { id: "qa-c1-1", severity: "major", raised_by: "qa", text: "a", anchor: { kind: "quote", file: "spec.md", text: "abc def ghij" }, test: "t" };
const panels = [
  { verdicts: [{ id: "qa-c1-1", vote: "uphold", severity: "major", reason: "ok" }] },
  { verdicts: [{ id: "qa-c1-1", vote: "refute", severity: "minor", reason: R, quote: Q }] },
  { verdicts: [{ id: "qa-c1-1", vote: "refute", severity: "minor", reason: R, quote: Q }] },
];
let [c] = applyVerifiedVote([f], panels);
check("vote-kill", c.killed && c.refuted && c.verdicts.length === 3 && eq(c.verdicts.map((v) => v.v), [1, 2, 3]));
[c] = applyVerifiedVote([f], [panels[0], panels[1], null]);
check("vote-one-refute-of-two-survives", !c.killed && c.severity === "major" && eq(c.verdicts.map((v) => v.v), [1, 2]));
[c] = applyVerifiedVote([{ ...f, carried: { from_cycle: 1, reason: "not-addressed" } }], panels);
check("vote-carried-not-verified", c.verdicts.length === 0 && !c.refuted && c.severity === "major");
[c] = applyVerifiedVote([{ ...f, closure: { file: "spec.md", text: "Retries are capped at 3 attempts" } }],
  [{ verdicts: [{ id: "qa-c1-1", vote: "confirm", severity: "major", reason: "ok" }] }, { verdicts: [{ id: "qa-c1-1", vote: "confirm", severity: "major", reason: "ok" }] }, null]);
check("vote-closure-confirmed-refuted", c.closed && c.refuted);
[c] = applyVerifiedVote([f], [
  { verdicts: [{ id: "qa-c1-1", vote: "uphold", severity: "major", test_invalid: true, reason: "vacuous" }] },
  { verdicts: [{ id: "qa-c1-1", vote: "uphold", severity: "major", test_invalid: true, reason: "vacuous" }] },
  { verdicts: [{ id: "qa-c1-1", vote: "uphold", severity: "major", reason: "ok" }] },
]);
check("vote-test-invalid-demotes-with-line", c.severity === "minor" && c.demoted && c.demoted.reason === "test-invalid");

const K1 = { id: "qa-c1-1", raised_by: "qa", severity: "major", text: "a", quote: { file: "spec.md", text: "abc def ghij" }, test: "t" };
const K9 = { id: "qa-c1-9", raised_by: "qa", severity: "blocker", text: "z", absent: { file: "spec.md", section: "Security", missing: "auth" }, test: "t" };
const KA = { id: "architect-c1-2", raised_by: "architect", severity: "blocker", text: "y", quote: { file: "spec.md", text: "abc def ghij" }, test: "t", carried: { from_cycle: 1, reason: "not-addressed" } };
// qa re-lists qa-c1-1 badly (lower severity, no anchor) and twice; leaves qa-c1-9 out.
let mc = materializeCarried([{ id: "qa-c1-1", severity: "minor", raised_by: "qa", text: "again", anchor: { kind: "none" }, test: "" },
  { id: "qa-c1-1", severity: "major", raised_by: "qa", text: "dup", anchor: { kind: "none" }, test: "" }], [K1, K9], 2, ["qa", "coder"]);
check("carry-adds-omitted", eq(mc.map((x) => x.id), ["qa-c1-1", "qa-c1-9"]) && eq(mc[1].carried, { from_cycle: 1, reason: "not-addressed" }) && mc[1].anchor.kind === "absent");
check("carry-relisted-keeps-record", mc[0].severity === "major" && mc[0].text === "a" && eq(mc[0].anchor, { kind: "quote", file: "spec.md", text: "abc def ghij" }) && mc[0].test === "t" && eq(mc[0].carried, { from_cycle: 1, reason: "re-listed" }));
mc = materializeCarried([{ id: "qa-c1-1", severity: "major", raised_by: "qa", text: "a", closure: { file: "spec.md", text: "closed" } }], [K1, KA], 3, ["qa", "coder"]);
check("carry-closure-claim-untouched", mc[0].closure && !mc[0].carried && mc.length === 2);
check("carry-off-roster-hosted", mc[1].id === "architect-c1-2" && mc[1].host === "qa" && mc[1].raised_by === "architect");
check("carry-keeps-origin-cycle", eq(mc[1].carried, { from_cycle: 1, reason: "not-addressed" }));
const dm2 = demoteUncheckable([{ ...mc[0] }, { id: "qa-c1-7", severity: "major", raised_by: "qa", text: "c", anchor: { kind: "none" }, carried: { from_cycle: 1, reason: "not-addressed" } }]);
check("demote-skips-closure-and-carried", eq(dm2.demoted, []));

[c] = applyVerifiedVote([f], panels);
let lines = formatVerifiedFindingLines(c, {});
check("render-header-keeps-raised-severity", lines[0] === "- [major] (qa-c1-1) a");
check("render-quote-line", lines[1] === '  quote: {"file":"spec.md","text":"abc def ghij"}');
check("render-verdicts-and-summary", lines.filter((l) => l.startsWith("  verdict: ")).length === 3 && lines.indexOf("  verified: refuted 2/3") !== -1);
check("render-killed-no-disposition", !lines.some((l) => l.startsWith("  disposition:")));
[c] = applyVerifiedVote([f], [panels[0], panels[0], null]);
lines = formatVerifiedFindingLines(c, { "qa-c1-1": { action: "adr", adr_id: 4 } });
check("render-upheld-major-disposition", lines[lines.length - 1] === "  disposition: adr ADR-4");
console.log("-----\npassed=" + pass + " failed=" + fail);
process.exit(fail === 0 ? 0 : 1);
JS
node "$TMP/run.js"
```

`scripts/verified-vote-parity.test.sh`:
```bash
#!/usr/bin/env bash
# Parity: the verified-review rules exist twice — JS in workflows/review.js (the
# workflow's provisional result) and jq in scripts/lib/verified-review.jq (the gate's
# authoritative result). This renders fixtures with the JS (formatVerifiedFindingLines
# after applyVerifiedVote) and checks the jq rules reach the same final severity, kill
# and closure from the rendered REVIEW.md lines. Skips if node is absent. bash 3.2.
# Run: bash scripts/verified-vote-parity.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REVIEW="$DIR/../workflows/review.js"; RULES="$(cat "$DIR/lib/verified-review.jq")"
if ! command -v node >/dev/null 2>&1; then echo "ok   verified-vote-parity (SKIPPED: node not found; enforced in CI)"; exit 0; fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/vr-parity.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
awk '/LAYER1-PURE-HELPERS START/{f=1;next} /LAYER1-PURE-HELPERS END/{f=0;next} f' "$REVIEW" > "$TMP/helpers.js"
cat "$TMP/helpers.js" - > "$TMP/run.js" <<'JS'
const R = "The constraints section caps retries at three attempts explicitly.";
const q = { file: "spec.md", text: "Retries are capped at 3 attempts" };
const A = { kind: "quote", file: "spec.md", text: "xx yy zz ww" };
const v = (id, vote, severity, extra) => ({ verdicts: [{ id, vote, severity, ...(extra || {}) }] });
const fixtures = [
  ["killed-2of3", { id: "qa-c1-1", severity: "major", text: "a", anchor: A, test: "t" }, [v("qa-c1-1", "uphold", "major"), v("qa-c1-1", "refute", "minor", { reason: R, quote: q }), v("qa-c1-1", "refute", "minor", { reason: R, quote: q })]],
  ["one-refute-survives", { id: "qa-c1-2", severity: "blocker", text: "b", anchor: A, test: "t" }, [v("qa-c1-2", "refute", "minor", { reason: R, quote: q }), v("qa-c1-2", "uphold", "blocker"), v("qa-c1-2", "uphold", "major", { reason: "short" })]],
  ["lowered-with-evidence", { id: "qa-c1-3", severity: "blocker", text: "c", anchor: A, test: "t" }, [v("qa-c1-3", "uphold", "major", { reason: R, quote: q }), v("qa-c1-3", "uphold", "major", { reason: R, quote: q }), v("qa-c1-3", "uphold", "blocker")]],
  ["two-returned-even-median", { id: "qa-c1-4", severity: "blocker", text: "d", anchor: A, test: "t" }, [v("qa-c1-4", "uphold", "minor", { reason: R, quote: q }), null, v("qa-c1-4", "uphold", "blocker")]],
  ["test-invalid-majority", { id: "qa-c1-5", severity: "major", text: "e", anchor: A, test: "t" }, [v("qa-c1-5", "uphold", "major", { test_invalid: true, reason: "vacuous" }), v("qa-c1-5", "uphold", "major", { test_invalid: true, reason: "vacuous" }), v("qa-c1-5", "uphold", "major")]],
  ["closure-confirmed", { id: "qa-c1-6", severity: "major", text: "f", closure: { file: "spec.md", text: "Retries are capped at 3" } }, [v("qa-c1-6", "confirm", "major"), v("qa-c1-6", "confirm", "major"), v("qa-c1-6", "reject", "major", { reason: "no" })]],
  ["closure-rejected", { id: "qa-c1-7", severity: "blocker", text: "g", closure: { file: "spec.md", text: "Retries are capped at 3" } }, [v("qa-c1-7", "reject", "blocker", { reason: "no" }), v("qa-c1-7", "confirm", "blocker"), null]],
  ["carried", { id: "qa-c1-8", severity: "major", text: "h", anchor: A, test: "t", carried: { from_cycle: 1, reason: "not-addressed" } }, []],
  ["demoted-no-test", demoteUncheckable([{ id: "qa-c1-9", severity: "major", text: "i", anchor: A, test: "" }]).concerns[0], [v("qa-c1-9", "uphold", "major"), v("qa-c1-9", "uphold", "major"), v("qa-c1-9", "uphold", "major")]],
  ["raise-capped", { id: "qa-c1-10", severity: "major", text: "j", anchor: A, test: "t" }, [v("qa-c1-10", "uphold", "blocker"), v("qa-c1-10", "uphold", "blocker"), v("qa-c1-10", "uphold", "blocker")]],
];
console.log(JSON.stringify(fixtures.map(([name, f, panels]) => {
  const [c] = applyVerifiedVote([f], panels);
  return { name, js: { final: c.severity, killed: c.killed, closed: c.closed }, lines: formatVerifiedFindingLines(c, {}).join("\n") };
})));
JS
node "$TMP/run.js" > "$TMP/out.json" || { echo "FAIL node fixture run"; exit 1; }
jq -r "${RULES}"'.[] | . as $c | ($c.lines | vr_parse_block)[0] | vr_outcome([]) as $o
  | {final: $o.final, killed: $o.killed, closed: $o.closed} as $j
  | if $j == $c.js then "ok   parity-\($c.name)" else "FAIL parity-\($c.name) js=\($c.js|tojson) jq=\($j|tojson)" end' "$TMP/out.json" > "$TMP/res"
cat "$TMP/res"
f=$(grep -c '^FAIL' "$TMP/res"); p=$(grep -c '^ok' "$TMP/res")
echo "-----"; echo "passed=$p failed=$f"; [ "$f" -eq 0 ]
```

- [ ] **Step 2: Run red**

Run: `bash scripts/workflow-review-verified.test.sh | tail -1; bash scripts/verified-vote-parity.test.sh | tail -1`
Expected: both fail with `ReferenceError: normalizeShape is not defined` / `applyVerifiedVote is not defined`.

- [ ] **Step 3: Apply the helpers patch**

Save as `/tmp/review-helpers.patch` and run `git apply /tmp/review-helpers.patch`:
```diff
--- a/workflows/review.js
+++ b/workflows/review.js
@@ -271,6 +271,208 @@
   }
   return lines;
 }
+// REVIEW_SHAPE and its settings (verified review). Absent ⇒ today's behaviour.
+const REVIEW_SHAPES = ["debate", "verified"];
+const VERIFIER_MODELS = ["opus", "sonnet", "haiku"];
+
+function normalizeShape(raw) {
+  if (raw === undefined || raw === null) return { shape: "debate", error: null };
+  if (REVIEW_SHAPES.indexOf(raw) === -1) return { shape: null, error: `shape: must be one of ${REVIEW_SHAPES.join(", ")}` };
+  return { shape: raw, error: null };
+}
+
+function normalizeVerifierModel(raw) {
+  if (raw === undefined || raw === null) return { model: "sonnet", error: null };
+  if (VERIFIER_MODELS.indexOf(raw) === -1) return { model: null, error: `verifier_model: must be one of ${VERIFIER_MODELS.join(", ")}` };
+  return { model: raw, error: null };
+}
+
+function normalizeFlag(raw, name) {
+  if (raw === undefined || raw === null) return { value: false, error: null };
+  if (raw === true || raw === "true") return { value: true, error: null };
+  if (raw === false || raw === "false") return { value: false, error: null };
+  return { value: null, error: `${name}: must be true or false` };
+}
+
+// Cycles of this review phase whose quote check reopened a finding (scripts/review-carry.sh);
+// they do not count against the cycle budget.
+function normalizeExemptCycles(raw) {
+  if (raw === undefined || raw === null) return { value: 0, error: null };
+  const n = typeof raw === "string" ? parseInt(raw, 10) : raw;
+  if (typeof n !== "number" || Number.isNaN(n) || !Number.isInteger(n) || n < 0)
+    return { value: null, error: "exempt_cycles: must be an integer >= 0" };
+  return { value: n, error: null };
+}
+
+// The previous verified cycle's open set (finalize-gate.sh --report .open), carried forward.
+function normalizeCarried(raw, shape) {
+  if (raw === undefined || raw === null) return { carried: [], error: null };
+  if (shape !== "verified") return { carried: null, error: "carried: only valid with shape verified" };
+  if (!Array.isArray(raw)) return { carried: null, error: "carried: must be an array of finding objects" };
+  for (const k of raw) {
+    if (!k || typeof k.id !== "string" || typeof k.raised_by !== "string" || ["blocker", "major"].indexOf(k.severity) === -1)
+      return { carried: null, error: "carried: each entry needs id, raised_by and severity blocker|major" };
+  }
+  return { carried: raw.slice(), error: null };
+}
+
+// --- VERIFIED-RULES START — REVIEW_SHAPE: verified. JS twin of scripts/lib/verified-review.jq;
+// scripts/verified-vote-parity.test.sh renders findings with formatVerifiedFindingLines and
+// checks the jq rules reach the same outcome. Pure: no log()/agent()/args/budget.
+const VR_SEV = ["minor", "major", "blocker"];
+function vrRank(s) { return s === "blocker" ? 2 : s === "major" ? 1 : s === "minor" ? 0 : -1; }
+
+// A verdict's evidence counts: a quote {file,text} and a reason of at least 40 characters.
+// (Whether the quote is real is checked after apply, by scripts/quote-check.sh.)
+function vrEvidence(v) {
+  return !!v && typeof v === "object" && !!v.quote && typeof v.quote === "object" &&
+    typeof v.quote.file === "string" && v.quote.file.length > 0 &&
+    typeof v.quote.text === "string" && v.quote.text.length > 0 &&
+    typeof v.reason === "string" && v.reason.length >= 40;
+}
+
+// The schema requires anchor + test on every finding; a blocker/major whose anchor is
+// kind "none" (or whose quote/section is empty) or whose test is empty is demoted to minor.
+// Carried findings and closure claims are left alone: their evidence is the record's.
+function demoteUncheckable(concerns) {
+  const demoted = [];
+  const out = (concerns || []).map((c) => {
+    if (vrRank(c.severity) < 1 || c.carried || c.closure) return c;
+    const a = c.anchor || {};
+    const anchorOk = (a.kind === "quote" && typeof a.text === "string" && a.text.trim() !== "" && typeof a.file === "string" && a.file !== "") ||
+      (a.kind === "absent" && typeof a.section === "string" && a.section.trim() !== "" && typeof a.file === "string" && a.file !== "");
+    const testOk = typeof c.test === "string" && c.test.trim() !== "";
+    if (anchorOk && testOk) return c;
+    const reason = anchorOk ? "no-test" : "no-anchor";
+    demoted.push(c.id);
+    return { ...c, demoted: { reason } };
+  });
+  return { concerns: out, demoted };
+}
+
+// Verifier k sees the list rotated left by k (deterministic; the runtime has no randomness).
+function rotateLeft(list, k) {
+  const n = (list || []).length;
+  if (n === 0) return [];
+  const s = ((k % n) + n) % n;
+  return list.slice(s).concat(list.slice(0, s));
+}
+
+// One finding (with .verdicts = [{v, vote, severity, reason?, quote?, test_invalid?}]) →
+// {final, killed, closed, demoted_reason}. Mirrors vr_outcome with no failed quotes.
+function verifiedOutcome(f) {
+  const orig = vrRank(f.severity);
+  const vs = (f.verdicts || []).filter((v) => v && typeof v === "object");
+  const n = vs.length;
+  if (f.carried) return { final: f.severity, killed: false, closed: false, demoted_reason: null };
+  if (f.closure) {
+    const c = vs.filter((v) => v.vote === "confirm").length;
+    return { final: f.severity, killed: false, closed: n >= 2 && c * 2 > n, demoted_reason: null };
+  }
+  if (orig < 1) return { final: "minor", killed: false, closed: false, demoted_reason: null };
+  const r = vs.filter((v) => v.vote === "refute" && vrEvidence(v)).length;
+  const ranks = vs.map((v) => { const s = vrRank(v.severity); return s >= 0 && s < orig && vrEvidence(v) ? s : orig; }).sort((a, b) => a - b);
+  const med = n < 2 ? orig : ranks[Math.floor(n / 2)];
+  const ti = vs.filter((v) => v.test_invalid === true).length;
+  const dem = f.demoted && typeof f.demoted === "object" ? (f.demoted.reason || "demoted")
+    : n >= 2 && ti * 2 > n ? "test-invalid" : null;
+  return { final: dem ? "minor" : VR_SEV[Math.min(med, orig)], killed: r >= 2, closed: false, demoted_reason: dem };
+}
+
+// Attach each verifier's verdict to its finding, numbered v = 1..3 in panel order.
+// panels: [{verdicts:[{id,…}]}|null, …] (null = verifier failed). Returns findings with
+// .verdicts filled and the outcome merged in; `refuted` = killed or closed (so the
+// existing disposition/finalize helpers apply unchanged).
+function applyVerifiedVote(findings, panels) {
+  const byId = {};
+  (panels || []).forEach((p, i) => {
+    if (!p || !Array.isArray(p.verdicts)) return;
+    for (const v of p.verdicts) {
+      if (!v || typeof v.id !== "string") continue;
+      const { id, ...rest } = v;
+      (byId[id] ||= []).push({ v: i + 1, ...rest });
+    }
+  });
+  return (findings || []).map((f) => {
+    const verdicts = f.carried || vrRank(f.severity) < 1 ? [] : (byId[f.id] || []);
+    const withV = { ...f, verdicts };
+    const o = verifiedOutcome(withV);
+    const demoted = withV.demoted || (o.demoted_reason ? { reason: o.demoted_reason } : undefined);
+    return { ...withV, ...o, ...(demoted ? { demoted } : {}), severity: o.final, severity_raised: f.severity, refuted: o.killed || o.closed };
+  });
+}
+
+// Carried findings (from finalize-gate --report) stay open until a confirmed closure.
+// A reviewer's re-listing of one is replaced by the carried record (original severity,
+// text, anchor, ref and test; reason "re-listed"), so re-listing can never demote,
+// re-verify or drop it; one the reviewer left out is added (reason "not-addressed").
+// from_cycle keeps the cycle the finding was first carried from. A finding whose raiser
+// is not in <roles> is written in roles[0]'s block (`host`): it stays open, and only its
+// raiser can close it. Closure claims (entries with `closure`) pass through. Returns the
+// full list, each id once.
+function materializeCarried(concerns, carried, cycle, roles) {
+  const byId = {};
+  for (const k of carried || []) if (k && typeof k.id === "string") byId[k.id] = k;
+  const record = (k, reason) => ({
+    id: k.id, severity: k.severity, raised_by: k.raised_by, text: k.text,
+    anchor: k.quote ? { kind: "quote", ...k.quote } : k.absent ? { kind: "absent", ...k.absent } : { kind: "none" },
+    ref: k.ref || "", test: k.test || "",
+    carried: { from_cycle: k.carried && Number.isInteger(k.carried.from_cycle) ? k.carried.from_cycle : cycle - 1, reason },
+    ...(Array.isArray(roles) && roles.length > 0 && roles.indexOf(k.raised_by) === -1 ? { host: roles[0] } : {}),
+  });
+  const seen = {};
+  const out = [];
+  for (const c of concerns || []) {
+    if (!c) continue;
+    if (c.closure) { seen[c.id] = true; out.push(c); continue; }
+    if (byId[c.id]) {
+      if (!seen[c.id]) out.push(record(byId[c.id], "re-listed"));
+      seen[c.id] = true;
+      continue;
+    }
+    out.push(c);
+  }
+  for (const k of carried || []) {
+    if (!k || typeof k.id !== "string" || seen[k.id]) continue;
+    seen[k.id] = true;
+    out.push(record(k, "not-addressed"));
+  }
+  return out;
+}
+
+// REVIEW.md lines for one verified finding. The header keeps the RAISED severity; the
+// gate recomputes the final one from the verdict lines.
+function formatVerifiedFindingLines(c, dispositionMap) {
+  const j = (o) => JSON.stringify(o);
+  const lines = [`- [${c.severity_raised || c.severity}] (${c.id}) ${flattenText(c.text)}`];
+  const a = c.anchor || {};
+  if (a.kind === "quote") lines.push(`  quote: ${j({ file: a.file, text: flattenText(a.text) })}`);
+  else if (a.kind === "absent") lines.push(`  absent: ${j({ file: a.file, section: flattenText(a.section), missing: flattenText(a.missing) })}`);
+  if (c.ref) lines.push(`  ref: ${flattenText(Array.isArray(c.ref) ? c.ref.join(", ") : c.ref)}`);
+  if (c.test) lines.push(`  test: ${flattenText(c.test)}`);
+  if (c.closure) lines.push(`  closure: ${j({ file: c.closure.file, text: flattenText(c.closure.text) })}`);
+  for (const v of c.verdicts || []) {
+    const out = { v: v.v, vote: v.vote, severity: v.severity };
+    if (v.reason) out.reason = flattenText(v.reason);
+    if (v.quote) out.quote = { file: v.quote.file, text: flattenText(v.quote.text) };
+    if (v.test_invalid === true) out.test_invalid = true;
+    lines.push(`  verdict: ${j(out)}`);
+  }
+  if (c.carried) lines.push(`  carried: ${j(c.carried)}`);
+  if (c.demoted) lines.push(`  demoted: ${j(c.demoted)}`);
+  if (c.verdicts && c.verdicts.length > 0) {
+    const n = c.verdicts.length;
+    const summary = c.closure ? `closure ${c.closed ? "confirmed" : "rejected"} (${c.verdicts.filter((v) => v.vote === "confirm").length}/${n})`
+      : c.killed ? `refuted ${c.verdicts.filter((v) => v.vote === "refute").length}/${n}` : `upheld, severity ${c.final}`;
+    lines.push(`  verified: ${summary}`);
+  }
+  if (!c.refuted && c.final === "major") {
+    const d = dispositionMap[c.id];
+    lines.push(d && d.action === "adr" ? `  disposition: adr ADR-${d.adr_id}` : "  disposition: fix");
+  }
+  return lines;
+}
+// --- VERIFIED-RULES END ---
 // --- LAYER1-PURE-HELPERS END ---
 
 // --- LENS START — reviewer lenses, injected into the read-only reviewer agent ---
```

- [ ] **Step 4: Run green; parse, lint, existing workflow suites; full suite**

```bash
bash scripts/workflow-review-verified.test.sh | tail -1    # passed=35 failed=0
bash scripts/verified-vote-parity.test.sh | tail -1        # passed=10 failed=0
{ echo '(async function(){'; sed 's/^export const meta/const meta/' workflows/review.js; echo '})'; } > /tmp/review-wrapped.js && node --check /tmp/review-wrapped.js && echo "parse ok"
bash scripts/workflow-determinism-lint.sh workflows/review.js | tail -1   # BUILD_FLEET_LINT_PASS
for t in scripts/workflow-review-config.test.sh scripts/workflow-review-convergence.test.sh scripts/lens-drift.test.sh; do bash "$t" | tail -1; done
bash scripts/run-tests.sh 2>&1 | tail -1                   # suites: 39, failed: 0
```

- [ ] **Step 5: Commit**

```bash
git add workflows/review.js scripts/workflow-review-verified.test.sh scripts/verified-vote-parity.test.sh
git commit -m "feat(review): verified-review rules in the workflow's pure helpers, tested equal to the gate's

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: `review.js` wiring — the verified branch, prompts, schemas, render, budget (spec §3.1–§3.3, §3.6)

**Files:**
- Modify: `workflows/review.js`
- Create: `scripts/verified-review-e2e.test.sh`

**Interfaces:**
- Consumes: Task 8 helpers; Tasks 3–7 for the e2e suite.
- Produces: workflow args `shape`, `verifier_model`, `verify_blockers_solo`, `carried`, `exempt_cycles` (all optional; absent ⇒ today's behaviour); return fields `shape`, `verification` (`{raised, verified, killed, closed, demoted, carried, solo_panels}` or `null`); `incomplete` reason `verifier-panel`; REVIEW.md verified blocks (`shape: verified` second line, the §3.2 continuation lines).

What the patch does (read it before applying):
- `meta`: description names both shapes; phases gain `Verification panel` and `Vote`.
- Args: the five settings are normalized and validated through the existing `invalid-args` path; `effectiveBudget = cycleBudget + exempt_cycles`, added after the `MAX_CYCLE_BUDGET` clamp, and used for `exhausting`, `decideVerdict` and the envelope.
- Fan-out: `reviewPrompt(role, feature, cycle, lens, shape, carriedForRole)` adds, in the verified shape only, the finding grammar, the carried list with closure instructions, and a verified delta-cycle rule; `concernsSchemaFor(role, shape)` requires `anchor` + `test` and adds `closures`. `mergeConcerns` carries `anchor`, `ref`, `test`.
- Verified branch (after the existing delta-severity enforcement): closure claims accepted only for carried findings their reviewer raised; `materializeCarried` (with `ROLES`) then `demoteUncheckable`, which skips carried findings and closure claims; `buildEnvelope` writes a finding in the block of `host` when set; a shared 3-verifier panel (`verifierPrompt`, `VERIFICATION_SCHEMA`, `model: VERIFIER_MODEL`, list rotated per verifier) plus, with `verify_blockers_solo`, one 3-verifier panel per blocker; fewer than 2 verdict sets from any panel ⇒ `incomplete`/`verifier-panel` with the cleanup envelope; then `applyVerifiedVote`. The debate branch is the existing code, indented under `else`.
- Render: verified blocks get `shape: verified` and `formatVerifiedFindingLines`; debate blocks unchanged.

- [ ] **Step 1: Write the end-to-end harness**

`scripts/verified-review-e2e.test.sh`:
```bash
#!/usr/bin/env bash
# End to end, no model: REVIEW.md blocks rendered by the workflow's own JS
# (applyVerifiedVote + formatVerifiedFindingLines) → the scribe's marker release fires
# hooks/scripts/check-review-quotes.sh → scripts/quote-check.sh records the event →
# scripts/finalize-gate.sh decides; then a delta cycle carries the open finding and
# scripts/review-carry.sh reports it. Skips if node is absent. bash 3.2.
# Run: bash scripts/verified-review-e2e.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
if ! command -v node >/dev/null 2>&1; then echo "ok   verified-review-e2e (SKIPPED: node not found; enforced in CI)"; exit 0; fi
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
. "$DIR/fixtures/verified-review.sh"
pass=0; fail=0
assert() { if eval "$2"; then pass=$((pass+1)); printf 'ok   %s\n' "$1"; else fail=$((fail+1)); printf 'FAIL %s (%s) out=%s\n' "$1" "$2" "${out:-}"; fi; }
awk '/LAYER1-PURE-HELPERS START/{f=1;next} /LAYER1-PURE-HELPERS END/{f=0;next} f' "$ROOT/workflows/review.js" > "$work/helpers.js"
render() { # render <js-expression yielding [findings, panels]> → block lines on stdout
  { cat "$work/helpers.js"; printf 'const [fs, panels] = %s;\nfor (const f of fs) for (const l of formatVerifiedFindingLines(applyVerifiedVote([f], panels)[0], {})) console.log(l);\n' "$1"; } > "$work/r.js"
  node "$work/r.js"
}
release() { ( cd "$1" && jq -cn --arg p "$1/.sdd/feat/.workflow-in-flight" '{tool_name:"Write", tool_input:{file_path:$p, content:""}}' \
  | CLAUDE_PROJECT_DIR="$1" bash "$ROOT/hooks/scripts/check-review-quotes.sh" ); }
gate() { out=$( cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$ROOT/scripts/finalize-gate.sh" feat "${@:2}" 2>/dev/null ); rc=$?; }
R="'$VR_REASON'"
F1='{ id: "qa-c1-1", severity: "major", raised_by: "qa", text: "Retry limit unspecified", anchor: { kind: "quote", file: "spec.md", text: "the client retries failed uploads" }, test: "a failing server stops the client within N attempts" }'

# Cycle 1: two verifiers refute with a REAL quote, one with an INVENTED one → the kill falls.
p=$(vr_proj e2e 1)
lines=$(render "[[ $F1 ], [
  { verdicts: [{ id: 'qa-c1-1', vote: 'uphold', severity: 'major', reason: 'ok' }] },
  { verdicts: [{ id: 'qa-c1-1', vote: 'refute', severity: 'minor', reason: $R, quote: { file: 'spec.md', text: 'Retries are capped at 3 attempts' } }] },
  { verdicts: [{ id: 'qa-c1-1', vote: 'refute', severity: 'minor', reason: $R, quote: { file: 'spec.md', text: 'Retries are capped at 9 attempts' } }] }]]")
assert "workflow-saw-a-kill" "printf '%s' \"\$lines\" | grep -q 'verified: refuted 2/3'"
vr_block "$p" 1 qa "$lines"; vr_block "$p" 1 architect
release "$p"
assert "hook-recorded-exempt-event" "jq -e 'select(.source == \"script:quote-check\") | .exempt == true and .revived == [\"qa-c1-1\"]' '$p/.sdd/feat/EVENTS.jsonl' >/dev/null"
gate "$p"
assert "gate-reopens-the-finding" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q '\"open_majors\":\\[\"qa-c1-1\"\\]'"
out=$( cd "$p" && CLAUDE_PROJECT_DIR="$p" bash "$ROOT/scripts/review-carry.sh" feat ); 
assert "carry-reports-it-and-exempts" "printf '%s' \"\$out\" | grep -q '\"open_count\":1,\"exempt_cycles\":1'"

# Cycle 2: the reviewer closes it with a quote of the revised spec; the panel confirms.
printf 'The client retries failed uploads at most 3 times.\n' >> "$p/.sdd/feat/spec.md"
sed -i.bak 's/^CYCLE: 1/CYCLE: 2/; s/^CYCLE_TOTAL: 1/CYCLE_TOTAL: 2/' "$p/.sdd/feat/PROGRESS.md"
lines=$(render "[[{ id: 'qa-c1-1', severity: 'major', raised_by: 'qa', text: 'Retry limit unspecified', closure: { file: 'spec.md', text: 'The client retries failed uploads at most 3 times.' } }], [
  { verdicts: [{ id: 'qa-c1-1', vote: 'confirm', severity: 'major', reason: 'ok' }] },
  { verdicts: [{ id: 'qa-c1-1', vote: 'confirm', severity: 'major', reason: 'ok' }] }, null]]")
vr_block "$p" 2 qa "$lines"; vr_block "$p" 2 architect
release "$p"; gate "$p"
assert "closed-in-cycle-2-passes" "[ $rc -eq 0 ]"
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it — it passes already for the rules, so confirm the wiring is what is missing**

Run: `bash scripts/verified-review-e2e.test.sh | tail -1` → `passed=5 failed=0` (it exercises Task 8's helpers and Tasks 3–7, which exist).
Then confirm the workflow does not yet accept the shape:
```bash
grep -c 'normalizeShape(A.shape)' workflows/review.js   # expect: 0
```

- [ ] **Step 3: Apply the wiring patch**

Save as `/tmp/review-wiring.patch` and run `git apply /tmp/review-wiring.patch`:
```diff
--- a/workflows/review.js
+++ b/workflows/review.js
@@ -34,11 +34,13 @@
 
 export const meta = {
   name: "build-fleet-review",
-  description: "SDD spec review: fan-out reviewers (delta review from cycle 2), adversarial cross-examination, survival vote, architect disposition of surviving majors, scribe applies state",
+  description: "SDD spec review: fan-out reviewers (delta review from cycle 2), then either adversarial cross-examination + survival vote (debate shape) or a panel of fresh verifiers + quote-backed majority vote (verified shape), architect disposition of surviving majors, scribe applies state",
   phases: [
     { title: "Fan-out review", detail: "read-only reviewer agents review the spec in parallel (roster configurable; default architect, qa, coder); cycle >= 2 is a delta review" },
     { title: "Cross-examination", detail: "each reviewer challenges peers' concerns, citing spec/acceptance/DECISIONS" },
     { title: "Survival vote", detail: "retain concerns not refuted by a different-role reviewer" },
+    { title: "Verification panel", detail: "verified shape: 3 fresh verifiers judge every blocker/major and closure claim independently, quoting the spec" },
+    { title: "Vote", detail: "verified shape: kill on 2 valid refutations; severity is the median vote, lowered only with quoted evidence" },
     { title: "Disposition", detail: "architect classifies each surviving major: adr (trade-off, ADR drafted) or fix (PO must close it in the spec)" },
     { title: "Apply", detail: "scribe writes PROGRESS + REVIEW + DECISIONS deltas" },
   ],
@@ -521,6 +523,11 @@
 // Validation failures are NEVER a bare throw (a throw would strand the marker).
 const rolesResult = normalizeRoles(A.roles);
 const budgetResult = normalizeCycleBudget(A.cycle_budget);
+const shapeResult = normalizeShape(A.shape);
+const verifierModelResult = normalizeVerifierModel(A.verifier_model);
+const soloResult = normalizeFlag(A.verify_blockers_solo, "verify_blockers_solo");
+const exemptResult = normalizeExemptCycles(A.exempt_cycles);
+const carriedResult = normalizeCarried(A.carried, shapeResult.shape);
 
 const argErrors = [];
 if (!feature || typeof feature !== "string") argErrors.push("feature: required non-empty string");
@@ -528,6 +535,7 @@
 if (!now || typeof now !== "string") argErrors.push("now: required iso8601 string (the dispatching command supplies it — the script cannot call Date)");
 if (rolesResult.error) argErrors.push(rolesResult.error);
 if (budgetResult.error) argErrors.push(budgetResult.error);
+for (const r of [shapeResult, verifierModelResult, soloResult, exemptResult, carriedResult]) if (r.error) argErrors.push(r.error);
 if (argErrors.length > 0) {
   log(`Invalid args: ${argErrors.join("; ")}. No state advanced.`);
   if (feature && typeof feature === "string") {
@@ -546,6 +554,14 @@
 const cycleBudget = budgetResult.budget;
 const cycleTotalBefore = normalizeCycleTotal(A.cycle_total, cycle);
 const nextAdrId = normalizeNextAdrId(A.next_adr_id);
+const SHAPE = shapeResult.shape;
+const VERIFIER_MODEL = verifierModelResult.model;
+const VERIFY_BLOCKERS_SOLO = soloResult.value;
+const CARRIED = carriedResult.carried;
+// Cycles whose quote check reopened a finding do not count against the budget; added
+// AFTER the MAX_CYCLE_BUDGET clamp so decideVerdict does not escalate the exempt cycle.
+const effectiveBudget = cycleBudget + exemptResult.value;
+log(`Review shape: ${SHAPE}${SHAPE === "verified" ? `; verifier model ${VERIFIER_MODEL}; per-blocker panels ${VERIFY_BLOCKERS_SOLO}; carried ${CARRIED.length}; exempt cycles ${exemptResult.value} (effective budget ${effectiveBudget})` : ""}.`);
 log(`Reviewer roster: [${ROLES.join(", ")}]; cycle budget ${cycleBudget}; cumulative cycles before this run ${cycleTotalBefore}; next feature ADR id ${nextAdrId}.`);
 if (budgetResult.clamped) {
   log(`cycle_budget requested ${JSON.stringify(A.cycle_budget)} exceeds the protocol ceiling — capped to ${MAX_CYCLE_BUDGET}.`);
@@ -559,8 +575,8 @@
 
 // ---------- schemas (structured agent output) ----------
 
-function concernsSchemaFor(role) {
-  return {
+function concernsSchemaFor(role, shape) {
+  const base = {
     type: "object",
     additionalProperties: false,
     required: ["role", "status", "concerns"],
@@ -582,6 +598,44 @@
       },
     },
   };
+  if (shape !== "verified") return base;
+  // Verified shape: every finding carries an anchor and a test (a [minor] may use anchor
+  // kind "none"); delta cycles return closure claims for carried findings.
+  const item = base.properties.concerns.items;
+  item.required = ["id", "severity", "text", "anchor", "test"];
+  item.properties.anchor = {
+    type: "object",
+    additionalProperties: false,
+    required: ["kind"],
+    properties: {
+      kind: { type: "string", enum: ["quote", "absent", "none"] },
+      file: { type: "string" },
+      text: { type: "string" },
+      section: { type: "string" },
+      missing: { type: "string" },
+    },
+  };
+  item.properties.test = { type: "string" };
+  item.properties.ref = { type: "string" };
+  base.required = ["role", "status", "concerns", "closures"];
+  base.properties.closures = {
+    type: "array",
+    items: {
+      type: "object",
+      additionalProperties: false,
+      required: ["id", "closure"],
+      properties: {
+        id: { type: "string" },
+        closure: {
+          type: "object",
+          additionalProperties: false,
+          required: ["file", "text"],
+          properties: { file: { type: "string" }, text: { type: "string" } },
+        },
+      },
+    },
+  };
+  return base;
 }
 
 const REFUTATION_SCHEMA = {
@@ -615,6 +669,35 @@
   },
 };
 
+const VERIFICATION_SCHEMA = {
+  type: "object",
+  additionalProperties: false,
+  required: ["verdicts"],
+  properties: {
+    verdicts: {
+      type: "array",
+      items: {
+        type: "object",
+        additionalProperties: false,
+        required: ["id", "vote", "severity", "reason"],
+        properties: {
+          id: { type: "string" },
+          vote: { type: "string", enum: ["uphold", "refute", "confirm", "reject"] },
+          severity: { type: "string", enum: ["blocker", "major", "minor"] },
+          reason: { type: "string" },
+          quote: {
+            type: "object",
+            additionalProperties: false,
+            required: ["file", "text"],
+            properties: { file: { type: "string" }, text: { type: "string" } },
+          },
+          test_invalid: { type: "boolean" },
+        },
+      },
+    },
+  },
+};
+
 const DISPOSITION_SCHEMA = {
   type: "object",
   additionalProperties: false,
@@ -645,12 +728,12 @@
 
 const reviewerResults = await parallel(
   ROLES.map((role) => () =>
-    agent(reviewPrompt(role, feature, cycle, LENS[role]), {
+    agent(reviewPrompt(role, feature, cycle, LENS[role], SHAPE, CARRIED.filter((k) => k.raised_by === role)), {
       label: `review:${role}`,
       phase: "Fan-out review",
       agentType: "build-fleet:reviewer",
       ...(modelFor(role) ? { model: modelFor(role) } : {}),
-      schema: concernsSchemaFor(role),
+      schema: concernsSchemaFor(role, SHAPE),
     })
   )
 );
@@ -679,29 +762,114 @@
   log(`Delta-severity enforcement demoted new major(s) to minor (not permitted on a delta cycle): ${enforced.demoted.join(", ")}.`);
 }
 
-// ---------- Phase 2: cross-examination ----------
+let surviving;
+let verification = null;
 
-phase("Cross-examination");
+if (SHAPE === "verified") {
+  // ---------- Phase 2 (verified): verification panel ----------
+  // Closure claims count only for carried findings the claiming reviewer raised.
+  const carriedById = {};
+  for (const k of CARRIED) carriedById[k.id] = k;
+  const closures = [];
+  for (const r of reviews) {
+    for (const cl of r.payload.closures || []) {
+      const k = cl && carriedById[cl.id];
+      if (!k || k.raised_by !== r.role || !cl.closure) {
+        log(`Closure claim ignored (not a carried finding raised by ${r.role}): ${cl && cl.id}.`);
+        continue;
+      }
+      closures.push({ id: k.id, severity: k.severity, raised_by: k.raised_by, text: k.text, closure: cl.closure });
+    }
+  }
+  const closureIds = closures.map((c) => c.id);
+  const offRoster = CARRIED.filter((k) => ROLES.indexOf(k.raised_by) === -1).map((k) => k.id);
+  if (offRoster.length > 0) log(`Carried findings whose raiser is not in the roster are written in ${ROLES[0]}'s block and stay open until their raiser closes them: ${offRoster.join(", ")}.`);
+  const dem = demoteUncheckable(materializeCarried(allConcerns.filter((c) => closureIds.indexOf(c.id) === -1).concat(closures), CARRIED, cycle, ROLES));
+  if (dem.demoted.length > 0) log(`Demoted to minor (no anchor or no test): ${dem.demoted.join(", ")}.`);
+  const findings = dem.concerns;
+  const toVerify = findings.filter((f) => !f.carried && !f.demoted && (f.closure || vrRank(f.severity) >= 1));
+  const verifyItem = (f) => f.closure
+    ? { id: f.id, kind: "closure", severity: f.severity, text: f.text, closure: f.closure }
+    : { id: f.id, kind: "finding", severity: f.severity, text: f.text, anchor: f.anchor, ref: f.ref || "", test: f.test };
+  const soloIds = VERIFY_BLOCKERS_SOLO ? toVerify.filter((f) => !f.closure && f.severity === "blocker").map((f) => f.id) : [];
+  const shared = toVerify.filter((f) => soloIds.indexOf(f.id) === -1).map(verifyItem);
+
+  phase("Verification panel");
+
+  const runPanel = (items, tag) =>
+    parallel([0, 1, 2].map((k) => () =>
+      agent(verifierPrompt(feature, cycle, rotateLeft(items, k)), {
+        label: `verify:${tag}:${k + 1}`,
+        phase: "Verification panel",
+        agentType: "build-fleet:reviewer",
+        model: VERIFIER_MODEL,
+        schema: VERIFICATION_SCHEMA,
+      })
+    ));
+  const returned = (ps) => (ps || []).filter((p) => p && Array.isArray(p.verdicts)).length;
+  const sharedPanels = shared.length > 0 ? await runPanel(shared, "panel") : [];
+  const soloPanels = {};
+  for (const id of soloIds) {
+    soloPanels[id] = await runPanel([verifyItem(toVerify.filter((f) => f.id === id)[0])], id);
+  }
+  const short = [];
+  if (shared.length > 0 && returned(sharedPanels) < 2) short.push("shared panel");
+  for (const id of soloIds) if (returned(soloPanels[id]) < 2) short.push(`panel for ${id}`);
+  if (short.length > 0) {
+    log(`Verifier panel incomplete (${short.join(", ")} returned fewer than 2 verdict sets). Cleaning up without advancing state.`);
+    const scribeResult = await applyScribe(cleanupEnvelope(feature, now, runId));
+    return {
+      verdict: "incomplete",
+      reason: "verifier-panel",
+      panels: short,
+      feature,
+      cycle,
+      scribe_apply: scribeResult.ok ? "applied" : "failed",
+      scribe_error: scribeResult.error,
+      note: "No REVIEW.md entries written; PHASE/CYCLE unchanged. Re-run /build-fleet:review.",
+    };
+  }
 
-const xaResults = await parallel(
-  ROLES.map((role) => () =>
-    agent(crossExamPrompt(role, allConcerns, feature, cycle), {
-      label: `cross-exam:${role}`,
-      phase: "Cross-examination",
-      agentType: "build-fleet:reviewer",
-      ...(modelFor(role) ? { model: modelFor(role) } : {}),
-      schema: REFUTATION_SCHEMA,
-    })
-  )
-);
+  // ---------- Phase 3 (verified): vote (pure JS; the gate recomputes it) ----------
+
+  phase("Vote");
+
+  surviving = findings.map((f) => applyVerifiedVote([f], soloIds.indexOf(f.id) !== -1 ? soloPanels[f.id] : sharedPanels)[0]);
+  verification = {
+    raised: findings.filter((f) => !f.carried && !f.closure).length,
+    verified: toVerify.length,
+    killed: surviving.filter((c) => c.killed).length,
+    closed: surviving.filter((c) => c.closed).length,
+    demoted: surviving.filter((c) => c.demoted).length,
+    carried: surviving.filter((c) => c.carried).length,
+    solo_panels: soloIds.length,
+  };
+  log(`Verification: ${verification.verified} judged, ${verification.killed} refuted, ${verification.closed} closures confirmed, ${verification.demoted} demoted, ${verification.carried} carried.`);
+} else {
+  // ---------- Phase 2: cross-examination ----------
+
+  phase("Cross-examination");
+
+  const xaResults = await parallel(
+    ROLES.map((role) => () =>
+      agent(crossExamPrompt(role, allConcerns, feature, cycle), {
+        label: `cross-exam:${role}`,
+        phase: "Cross-examination",
+        agentType: "build-fleet:reviewer",
+        ...(modelFor(role) ? { model: modelFor(role) } : {}),
+        schema: REFUTATION_SCHEMA,
+      })
+    )
+  );
 
-const refutationMap = mergeRefutations(ROLES, xaResults);
+  const refutationMap = mergeRefutations(ROLES, xaResults);
 
-// ---------- Phase 3: survival vote (pure JS) ----------
+  // ---------- Phase 3: survival vote (pure JS) ----------
 
-phase("Survival vote");
+  phase("Survival vote");
 
-const surviving = applySurvivalVote(allConcerns, refutationMap);
+  surviving = applySurvivalVote(allConcerns, refutationMap);
+}
 
 // ---------- Phase 4: disposition (architect, read-only; scribe writes the ADRs) ----------
 
@@ -715,7 +883,7 @@
 if (survivingMajors.length === 0) {
   log("No surviving majors — disposition leg skipped.");
 } else {
-  const exhausting = cycle >= cycleBudget;
+  const exhausting = cycle >= effectiveBudget;
   let dispo = null;
   try {
     dispo = await agent(dispositionPrompt(feature, cycle, survivingMajors, nextAdrId, exhausting), {
@@ -775,7 +943,7 @@
 }
 
 const ready = computeFinalizeReady(surviving, dispositionMap);
-const verdict = decideVerdict(ready.openBlockers.length, ready.openMajors.length, cycle, cycleBudget);
+const verdict = decideVerdict(ready.openBlockers.length, ready.openMajors.length, cycle, effectiveBudget);
 
 log(
   `Cycle ${cycle}: ${surviving.length} concerns, ${ready.openBlockers.length} open blockers, ${ready.openMajors.length} open majors → verdict=${verdict}, finalize_ready=${ready.finalize_ready}`
@@ -787,13 +955,15 @@
 
 const outputTokens = outputTokensSoFar();
 const envelope = buildEnvelope({
-  feature, cycle, cycleBudget, cycleTotalBefore, now, reviews, surviving, dispositionMap,
-  decisionsAppendix, ready, verdict, outputTokens,
+  feature, cycle, cycleBudget: effectiveBudget, cycleTotalBefore, now, reviews, surviving, dispositionMap,
+  decisionsAppendix, ready, verdict, outputTokens, shape: SHAPE,
 });
 const scribeResult = await applyScribe(envelope);
 
 return {
   verdict,
+  shape: SHAPE,
+  verification,
   finalize_ready: ready.finalize_ready,
   feature,
   cycle,
@@ -813,7 +983,7 @@
 
 // ================= helpers =================
 
-function reviewPrompt(role, feature, cycle, lens) {
+function reviewPrompt(role, feature, cycle, lens, shape, carried) {
   const files = `Read these files yourself (you have Read/Grep/Glob and NOTHING that writes):
 - .sdd/${feature}/spec.md
 - .sdd/${feature}/acceptance.md
@@ -830,7 +1000,28 @@
 
 Do NOT write, edit, or create any file. Return only the structured object.`;
 
-  const cycleRules = cycle <= 1
+  const verified = shape === "verified";
+  const verifiedRules = !verified ? "" : `
+VERIFIED REVIEW. Every [blocker] and [major] must be checkable, or it is recorded as a [minor]:
+- anchor: EITHER {"kind":"quote","file":"spec.md"|"acceptance.md"|"DECISIONS.md"|"_product/DECISIONS.md","text":"<10–500 characters copied VERBATIM from that file: no paraphrase, no ellipsis>"}
+  OR {"kind":"absent","file":"spec.md","section":"<an existing heading of that file>","missing":"<what the spec should say there>"}.
+  A [minor] may use {"kind":"none"}.
+- test: one sentence naming a test that would FAIL if the finding is real.
+- ref: optional, e.g. "§Behavior, AC-3".
+Quotes are checked word for word against the files after this review; an invented quote demotes the finding.`;
+  const carriedRules = !(verified && carried && carried.length > 0) ? "" : `
+OPEN FINDINGS YOU RAISED, carried from the previous cycle. Handle EVERY one:
+${JSON.stringify(carried.map((k) => ({ id: k.id, severity: k.severity, text: k.text, ...(k.quote ? { quote: k.quote } : {}), ...(k.absent ? { absent: k.absent } : {}), why_open: k.why || null })), null, 2)}
+- Still open ⇒ leave it out of "concerns". It stays open exactly as recorded (severity, quote, test); re-listing it changes nothing.
+- Closed by the revised spec ⇒ return it in "closures" as {"id": "<id>", "closure": {"file": "<file>", "text": "<verbatim text of the revised spec that closes it>"}}.
+Only a closure the verifier panel confirms closes a carried finding.`;
+  const cycleRules = verified && cycle > 1
+    ? `This is cycle ${cycle}: a DELTA review. Two jobs, in order:
+1. CLOSURE: the carried findings listed below.
+2. NEW findings: [blocker] severity ONLY (correctness, security, data loss, or a contradiction
+   of spec/acceptance, including a regression introduced by a fix). You may add [minor] notes
+   (advisory). You may NOT raise a new [major]: the open-major set only shrinks after cycle 1.`
+    : cycle <= 1
     ? `This is cycle 1: a FULL review of the spec through your lens.`
     : `This is cycle ${cycle}: a DELTA review. Two jobs, in order:
 1. CLOSURE — for each of YOUR OWN findings from the previous cycle that carries "disposition: fix",
@@ -850,6 +1041,8 @@
 The severity rubric (blocker / major / minor) is in your instructions — use those exact words.
 
 ${cycleRules}
+${verifiedRules}
+${carriedRules}
 
 ${rules}
 
@@ -857,7 +1050,43 @@
 - role: "${role}"
 - status: "concerns-raised" if you hold any blocker/major, else "approved" (informational — the
   gate reads dispositions, not this line)
-- concerns: array of { id, severity, text }. Empty array + "approved" when you have nothing.`;
+${verified
+    ? `- concerns: array of { id, severity, text, anchor, test, ref? }. Empty array + "approved" when you have nothing.
+- closures: array of { id, closure: { file, text } }. Empty array when you claim no closure.`
+    : "- concerns: array of { id, severity, text }. Empty array + \"approved\" when you have nothing."}`;
+}
+
+function verifierPrompt(feature, cycle, items) {
+  return `You are a VERIFIER in a build-fleet spec review, cycle ${cycle}. Active feature: ${feature}.
+You did not raise these findings and you are not told who did. Judge each one ONLY against the files.
+
+Read these files yourself (you have Read/Grep/Glob and NOTHING that writes):
+- .sdd/${feature}/spec.md
+- .sdd/${feature}/acceptance.md
+- .sdd/${feature}/DECISIONS.md   (may not exist)
+- .sdd/_product/DECISIONS.md     (only for an ADR id a finding or the spec cites)
+Do NOT read REVIEW.md or REVIEW-archive.md. Do NOT write, edit, or create any file.
+
+For each item of kind "finding":
+- vote "refute" ONLY when the spec as written already answers the claim, and quote the text that answers it.
+  Otherwise vote "uphold". When unsure, uphold.
+- severity: blocker | major | minor, per the severity rubric in your instructions. A severity BELOW the
+  finding's own counts only with a quote of the text that makes it less serious and a reason of at least
+  40 characters; without them it counts as the finding's own severity.
+- test_invalid: true, with a reason, when the finding's test is vacuous or could not exercise the claim.
+  That is not a refutation.
+For each item of kind "closure": vote "confirm" when the quoted text of the revised spec really closes the
+finding, else "reject" with a reason.
+
+Every quote is {"file": "spec.md"|"acceptance.md"|"DECISIONS.md"|"_product/DECISIONS.md", "text": "<10–500
+characters copied VERBATIM from that file>"}. Quotes are checked word for word after this review; an
+invented quote voids your vote.
+
+Items (judge EVERY one, each on its own merits):
+${JSON.stringify(items, null, 2)}
+
+Return the structured object:
+- verdicts: array of { id, vote, severity, reason, quote?, test_invalid? }, exactly one per item.`;
 }
 
 function crossExamPrompt(role, allConcerns, feature, cycle) {
@@ -939,6 +1168,9 @@
         severity: c.severity,
         raised_by: r.role,
         text: c.text,
+        ...(c.anchor ? { anchor: c.anchor } : {}),
+        ...(c.ref ? { ref: c.ref } : {}),
+        ...(typeof c.test === "string" ? { test: c.test } : {}),
         refuted: false,
         refuted_by: null,
         refutation_reason: null,
@@ -988,12 +1220,14 @@
   });
 }
 
-function buildEnvelope({ feature, cycle, cycleBudget, cycleTotalBefore, now, reviews, surviving, dispositionMap, decisionsAppendix, ready, verdict, outputTokens }) {
+function buildEnvelope({ feature, cycle, cycleBudget, cycleTotalBefore, now, reviews, surviving, dispositionMap, decisionsAppendix, ready, verdict, outputTokens, shape }) {
   const reviewEntries = reviews.map((r) => {
-    const own = surviving.filter((c) => c.raised_by === r.role);
+    const own = surviving.filter((c) => (c.host || c.raised_by) === r.role);
     const lines = [`## Cycle ${cycle} — ${r.role} — ${now}`];
+    if (shape === "verified") lines.push("shape: verified");
     for (const c of own) {
-      for (const l of formatFindingLines(c, dispositionMap)) lines.push(l);
+      const rendered = shape === "verified" ? formatVerifiedFindingLines(c, dispositionMap) : formatFindingLines(c, dispositionMap);
+      for (const l of rendered) lines.push(l);
     }
     lines.push(`status: ${r.payload.status || "concerns-raised"}`);
     return lines.join("\n");
```

- [ ] **Step 4: Verify — wiring present, parse, lint, all workflow suites, full suite**

```bash
grep -c 'normalizeShape(A.shape)' workflows/review.js       # 1
grep -c 'phase("Verification panel")' workflows/review.js   # 1
{ echo '(async function(){'; sed 's/^export const meta/const meta/' workflows/review.js; echo '})'; } > /tmp/review-wrapped.js && node --check /tmp/review-wrapped.js && echo "parse ok"
bash scripts/workflow-determinism-lint.sh workflows/review.js | tail -1   # BUILD_FLEET_LINT_PASS
for t in scripts/workflow-*.test.sh scripts/lens-drift.test.sh scripts/verified-vote-parity.test.sh scripts/verified-review-e2e.test.sh; do printf '%s: ' "$t"; bash "$t" | tail -1; done
bash scripts/run-tests.sh 2>&1 | tail -1                     # suites: 40, failed: 0
```
Expected per suite: cycle-budget `all cycle-budget helpers pass`; determinism-lint `passed=42`; plan-review-config `passed=13`; review-config `passed=19`; review-convergence `passed=67`; review-verified `passed=35`; lens-drift `passed=3`; parity `passed=10`; e2e `passed=5`.

- [ ] **Step 5: Commit**

```bash
git add workflows/review.js scripts/verified-review-e2e.test.sh
git commit -m "feat(review): REVIEW_SHAPE verified — fresh verifier panel, quote-backed vote, carried findings

The debate shape is the existing path, unchanged, and remains the default.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Commands — review, revise, status; the snapshot field (spec §3.6)

**Files:**
- Modify: `commands/review.md`, `commands/revise.md`, `commands/status.md`, `scripts/status-snapshot.sh`, `scripts/status-snapshot.test.sh`

**Interfaces:**
- Consumes: `review-carry.sh` (Task 7), `finalize-gate.sh --report` (Task 6), workflow args (Task 9).

- [ ] **Step 1: Failing snapshot cases first, then the field**

The patch below adds two harness cases (`feat-review-shape-default`, `feat-review-shape-verified`) and the field. Apply only its `status-snapshot.test.sh` hunk first, run `bash scripts/status-snapshot.test.sh | tail -1` and see those two FAIL (empty value); then apply the `status-snapshot.sh` hunk. Simplest: save as `/tmp/snapshot.patch`, run `git apply --include='scripts/status-snapshot.test.sh' /tmp/snapshot.patch`, run red, then `git apply --include='scripts/status-snapshot.sh' /tmp/snapshot.patch`.
```diff
--- a/scripts/status-snapshot.sh
+++ b/scripts/status-snapshot.sh
@@ -42,6 +42,7 @@
 #       "status":"FINALIZED"|null,           # spec STATUS, or diagnosis STATUS for bugs
 #       "cycle":N|null,"change_cycle":N|null,# feature lane
 #       "sev":"sev1"|null,"fix_cycle":N|null,# bug lane
+#       "review_shape":"debate"|"verified",   # feature lane: REVIEW_SHAPE, default debate
 #       "escalated":true|false
 #     }|null
 #   }
@@ -187,15 +188,18 @@
     status="$(read_spec_status "$slug")"
     cycle="$(read_progress_field "$slug" CYCLE)"
     change_cycle="$(read_progress_field "$slug" CHANGE_CYCLE)"
+    review_shape="$(read_progress_field "$slug" REVIEW_SHAPE)"
+    [ -n "$review_shape" ] || review_shape=debate
     active_json="$(jq -n \
       --arg slug "$slug" --arg lane "$lane" --arg phase "$phase" \
       --arg status "$status" --arg cycle "$cycle" --arg change_cycle "$change_cycle" \
-      --argjson escalated "$escalated" \
+      --arg review_shape "$review_shape" --argjson escalated "$escalated" \
       '{slug:$slug, lane:$lane,
         phase: (if $phase  == "" then null else $phase  end),
         status:(if $status == "" then null else $status end),
         cycle:        (if $cycle        == "" then null else ($cycle|tonumber? // $cycle)               end),
         change_cycle: (if $change_cycle == "" then null else ($change_cycle|tonumber? // $change_cycle) end),
+        review_shape:$review_shape,
         escalated:$escalated}')"
   fi
 fi
--- a/scripts/status-snapshot.test.sh
+++ b/scripts/status-snapshot.test.sh
@@ -93,6 +93,10 @@
 eq "feat-cycle"         "$(q "$o" '.active.cycle')"       "1"
 eq "feat-change_cycle"  "$(q "$o" '.active.change_cycle')" "0"
 eq "feat-escalated"     "$(q "$o" '.active.escalated')"   "false"
+eq "feat-review-shape-default" "$(q "$o" '.active.review_shape')" "debate"
+printf 'REVIEW_SHAPE: verified\n' >> "$p/.sdd/auth/PROGRESS.md"
+o="$(cd "$p" && bash "$SNAP")"
+eq "feat-review-shape-verified" "$(q "$o" '.active.review_shape')" "verified"
 
 # ---- 4. escalated feature --------------------------------------------------
 printf 'phase: BUILD\ncycle 3 exhausted\n' > "$p/.sdd/auth/ESCALATION.md"
```

- [ ] **Step 2: Run green**

Run: `bash scripts/status-snapshot.test.sh | tail -1` → `passed=50 failed=0`.

- [ ] **Step 3: `commands/review.md`**

1. Frontmatter: `argument-hint: "[--roles <r1,r2,...>] [--cycle-budget <1-3>] [--shape debate|verified] [--verifier-model opus|sonnet|haiku] [--verify-blockers-solo] [--override-cost]"`; append to `allowed-tools`: `, Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-carry.sh":*)`.
2. Step 5, after the **budget** bullet, add:
   ```
      - **shape**: `--shape <debate|verified>` → else `REVIEW_SHAPE:` in PROGRESS.md → else unset (the workflow uses `debate`).
      - **verifier model**: `--verifier-model <opus|sonnet|haiku>` → else `VERIFIER_MODEL:` → else unset (`sonnet`).
      - **per-blocker panels**: `--verify-blockers-solo` → else `VERIFY_BLOCKERS_SOLO: true` → else unset.

      **Carry.** Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-carry.sh" "<slug>"` and relay its
      `BUILD_FLEET_REVIEW_CARRY:` line. When `previous_shape` is `verified`, the open set is its
      `carried` array (`open_count` items) and `effective_budget` becomes
      `effective_budget + exempt_cycles`, added after the clamp: a cycle whose quote check reopened
      a finding does not count against the budget. Otherwise the open set is read from REVIEW.md
      as below. If the script exits without a `BUILD_FLEET_REVIEW_CARRY:` line, refuse before
      dispatch: `BUILD_FLEET_REFUSE: {"command":"review","code":2,"reason":"carry-unavailable"}`,
      show its stderr, and say: the last cycle's open findings could not be read; run
      `/build-fleet:status` and re-run review once the gate's report works.

      **Shape is fixed per review phase.** When `previous_shape` is `debate` or `verified` and the
      resolved shape (flag, else PROGRESS.md, else `debate`) differs from it, refuse before dispatch:
      `BUILD_FLEET_REFUSE: {"command":"review","code":2,"reason":"shape-changed-mid-feature","previous":"<previous_shape>","requested":"<shape>"}`
      and say: switching shape mid-review would drop the open findings the other shape recorded;
      finish this review phase in its shape, or change `REVIEW_SHAPE` only at cycle 1.
   ```
3. In the **Cycle-budget precondition**, replace `the most recent REVIEW.md cycle still has open `[blocker]` items or `disposition: fix` majors` with `the open set is non-empty (verified: `open_count` > 0; debate: open `[blocker]` items or `disposition: fix` majors in the most recent REVIEW.md cycle)`.
4. Step 8's review-config line: add `"shape":<"debate"|"verified"|"default">,"exempt_cycles":<n>` after `"budget_source"`.
5. Step 9 `args`: after the roles/budget sentence add: `Plus "shape", "verifier_model" and "verify_blockers_solo" ONLY when resolved from a flag or PROGRESS.md. When the resolved shape is "verified" AND the carry line's previous_shape is "verified", also pass "carried": <its carried array, verbatim> and "exempt_cycles": <its exempt_cycles>. Omit every unset key.`
6. Step 12, in the `incomplete` bullet, after `disposition-incomplete` add: `` `reason: verifier-panel` means fewer than two verifiers returned a usable verdict set — re-run. `` And add a bullet: `- **Verified shape:** the quote check runs when the scribe finishes; the workflow's `finalize_ready` is provisional — `/build-fleet:status` and `/build-fleet:finalize` show the gate's answer.`

- [ ] **Step 4: `commands/revise.md`**

1. Frontmatter: `allowed-tools: Read, Task, Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/finalize-gate.sh":*)`.
2. Step 3, insert before `In `.sdd/<slug>/REVIEW.md`, take the **last** block`:
   ```
   **Verified cycle** (the newest `## Cycle <CYCLE>` blocks have `shape: verified` as their second
   line): run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/finalize-gate.sh" "<slug>" --report` and take the
   open items from its `open` array. Render each as `- [<severity>] (<id>) <text>`, appending
   ` — reopened: a quote that closed it was not found in the spec` when `why` is
   `reopened-closure`, and ` — carried from an earlier cycle` when `why` is `carried` or
   `carried-open`; `major-without-adr` items are not handed to the PO (the gate reports them).
   Skip the REVIEW.md extraction below. **Debate cycle:**
   ```

- [ ] **Step 5: `commands/status.md`**

1. Frontmatter: append `, Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/finalize-gate.sh":*)` to `allowed-tools`.
2. In step 4 ("Summarize the most recent REVIEW.md cycle"), add at its start: `If `REVIEW_SHAPE: verified` is set and the newest cycle blocks are verified, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/finalize-gate.sh" "<active>" --report` and print: the shape; open blockers and majors by id with their `why`; `spec_changed` when true ("the spec changed after it was reviewed — run /build-fleet:review"); and, from the last `script:quote-check` line of `.sdd/<active>/EVENTS.jsonl`, `checked` and `failures` (a failed quote means a reviewer or verifier cited text the spec does not contain).`

- [ ] **Step 6: `commands/finalize.md` (Ruling 8)**

In the `Reason codes (from the gate script; combine as needed):` list, after the `majors-without-adr` bullet, add:
```
   - `quote-check-missing` — a verified review cycle has no quote-check result (the check runs when the review's scribe finishes; it needs jq and the plugin's hooks enabled) — re-run `/build-fleet:review`
   - `spec-changed-since-review` — spec.md, acceptance.md or an existing DECISIONS.md entry changed after this cycle was reviewed (the STATUS line and appended ADRs do not count) — re-run `/build-fleet:review` so the change is reviewed
```

- [ ] **Step 7: Suite and commit**

Run: `bash scripts/run-tests.sh 2>&1 | tail -1` → `suites: 40, failed: 0`.
```bash
git add commands/review.md commands/revise.md commands/status.md commands/finalize.md scripts/status-snapshot.sh scripts/status-snapshot.test.sh
git commit -m "feat(commands): review passes verified settings and the carried open set; revise and status read the gate report

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Agents and skills — the mirrored verified rule, the reviewer's verify mode, descriptions, the protocol (spec §3.7)

**Files:**
- Modify: `skills/review-rubric/SKILL.md`, `agents/architect.md`, `agents/qa.md`, `agents/reviewer.md`, `scripts/rubric-drift.test.sh`, `skills/sdd-protocol/SKILL.md`

- [ ] **Step 1: Extend the drift test first (Ruling 4)**

Append to `scripts/rubric-drift.test.sh`, before the final `echo "-----"`:
```bash
# The verified-review rule is mirrored the same way, between these markers.
extract_verified() {
  awk '/<!-- verified-rule:start -->/{g=1;next} /<!-- verified-rule:end -->/{g=0} g' "$1" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}
vref=$(extract_verified "$ref_file")
if [ -z "$vref" ]; then printf 'FAIL %-44s no verified-rule block in %s\n' "verified-anchor-present-in-skill" "$ref_file"; fail=$((fail+1))
else printf 'ok   %-44s\n' "verified-anchor-present-in-skill"; pass=$((pass+1)); fi
for f in "${files[@]}"; do
  [ "$f" = "$ref_file" ] && continue
  name="verified-rule-matches-$(basename "$f")"
  if [ "$(extract_verified "$f")" = "$vref" ] && [ -n "$vref" ]; then printf 'ok   %-44s\n' "$name"; pass=$((pass+1))
  else printf 'FAIL %-44s drifted from %s\n' "$name" "$ref_file"; fail=$((fail+1)); fi
done
```
Run: `bash scripts/rubric-drift.test.sh | tail -1` → `passed=7 failed=4` (the verified block is not in any file yet).

- [ ] **Step 2: Add the block to all four files**

Insert this block, byte-identical, in each file, after a blank line, immediately after the paragraph that follows the severity table: the "Use these exact strings" paragraph in `skills/review-rubric/SKILL.md`, `agents/architect.md` and `agents/reviewer.md`. `agents/qa.md` has no such paragraph: put the block after a blank line following the table's last row, so the comment does not land inside the table.
```
<!-- verified-rule:start -->
In a verified review (`REVIEW_SHAPE: verified`), a `[blocker]` or `[major]` carries an anchor and a test,
or it is recorded as a `[minor]`. The anchor is a quote of 10–500 characters copied verbatim from
`spec.md`, `acceptance.md`, `DECISIONS.md` or `_product/DECISIONS.md`, or a named absence (the file, an
existing section heading, and what is missing). The test is one sentence naming a test that would fail
if the finding is real. Quotes are checked word for word after the review: a finding whose anchor quote
is not found is demoted, and a verifier's vote whose quote is not found does not count.
<!-- verified-rule:end -->
```
Run: `bash scripts/rubric-drift.test.sh | tail -1` → `passed=11 failed=0` (7 table checks + 4 verified checks).

- [ ] **Step 3: `skills/review-rubric/SKILL.md` — the verified section**

After the `## Delta review and disposition (v0.9)` section, add:
```
## Verified review

When `REVIEW_SHAPE: verified` is set, the cross-examination and survival vote are replaced:

- **A panel of three fresh verifiers** judges every blocker and major, and every closure claim, without
  seeing who raised it, the reviewer's reasoning, or each other. Each returns `uphold`/`refute`
  (closures: `confirm`/`reject`), a severity, a reason, and a quote when refuting or lowering severity.
- **A finding is killed by two valid refutations** (quote + a reason of at least 40 characters). One
  refutation is never enough.
- **Severity is the median vote**, capped at the raised severity; a lower vote counts only with quoted
  evidence. A majority `test_invalid` (the named test could not exercise the claim) demotes to minor.
- **Quotes are checked after the review** (`scripts/quote-check.sh`); the finalize gate recomputes
  every vote from the recorded verdicts and that check. A quote that is not found voids its vote; a
  finding that loses its kill this way is reopened, and that cycle does not count against the budget.
- **Open findings carry forward**: an open finding of the previous cycle is closed only by a quoted
  closure the panel confirms; otherwise it is carried unchanged (`carried:` line), whether or not its
  reviewer re-lists it.
- **Limit:** the quote check catches invented quotes, not a real quote used to argue a wrong point; the
  majority vote is the defence against that.
```

- [ ] **Step 4: `agents/reviewer.md` — verify mode and grammar**

After `## Discipline`, add:
```
## Verify mode

When the prompt says you are a VERIFIER, you judge findings someone else raised; you are not told who,
and you never see their reasoning or the other verifiers'. Judge each item only against `spec.md`,
`acceptance.md` and `DECISIONS.md` (a product ADR only when cited). Do not read REVIEW.md.

- `refute` only when the spec as written already answers the claim, with a verbatim quote of the text
  that answers it and a reason of at least 40 characters. Otherwise `uphold`; when unsure, uphold.
- A severity below the finding's own counts only with a quote of the text that makes it less serious.
- `test_invalid: true` (with a reason) when the finding's test is vacuous or could not exercise the
  claim. That is not a refutation.
- For a closure claim, `confirm` when the quoted text of the revised spec really closes the finding,
  else `reject` with a reason.
- Every quote is copied verbatim, 10–500 characters, from the named file. Quotes are checked word for
  word after the review; an invented quote voids your vote.
```
In the `## The REVIEW.md line grammar` block, after `status: concerns-raised | approved`, add (inside the same code block):
```

Verified shape (REVIEW_SHAPE: verified) — second line `shape: verified`, then per finding:
- [major] (<role>-c<N>-2) <text>
  quote: {"file":"spec.md","text":"<verbatim>"}      (or  absent: {"file","section","missing"})
  ref: §Section, AC-n
  test: <a test that would fail>
  verdict: {"v":1,"vote":"uphold|refute","severity":"…","reason":"…","quote":{"file","text"}}
  verified: <summary>
  disposition: fix | adr ADR-<M>
```

- [ ] **Step 5: Descriptions (bodies changed)**

- `agents/reviewer.md` description → `Use this agent ONLY inside workflows/review.js — the read-only reviewer that every fan-out, cross-examination, verification and disposition leg of /build-fleet:review runs as, with the role lens or the verifier brief injected by the workflow prompt. It has Read, Grep and Glob and nothing that writes, so a workflow reviewer can never append to REVIEW.md, fabricate a timestamp, or touch source; the scribe writes every block. Do NOT dispatch it directly, for CHANGE_REVIEW, or for any authoring — the role agents own those paths.`
- `agents/architect.md`: in its description replace `Inside /build-fleet:review its severity-calibrated lens runs on the read-only reviewer agent instead.` with `Inside /build-fleet:review its severity-calibrated lens runs on the read-only reviewer agent instead; in a verified review its findings must quote the spec and name a failing test.`
- `agents/qa.md`: replace `Inside /build-fleet:review its severity-calibrated testability lens runs on the read-only reviewer agent instead.` with `Inside /build-fleet:review its severity-calibrated testability lens runs on the read-only reviewer agent instead; in a verified review its findings must quote the spec and name a failing test.`

- [ ] **Step 6: `skills/sdd-protocol/SKILL.md`**

1. In `## PROGRESS.md schema`, after the `REVIEW_CYCLE_BUDGET` line, add:
   ```
   REVIEW_SHAPE: debate | verified   # optional — /build-fleet:review shape; absent ⇒ debate. --shape overrides per run.
   VERIFIER_MODEL: opus | sonnet | haiku   # optional — verified shape's panel model; absent ⇒ sonnet.
   VERIFY_BLOCKERS_SOLO: true | false      # optional — verified shape: one 3-verifier panel per blocker; absent ⇒ false.
   ```
2. In `## REVIEW.md entry format`, after the existing paragraph that ends `` `status:` is informational since v0.9. ``, add a paragraph: `In the verified shape (REVIEW_SHAPE: verified) each block's second line is "shape: verified" and blockers and majors carry quote:/absent:, test:, verdict: and verified: lines (format: the review-rubric skill and docs/history/2026-10-14-verified-review.md §3.2). The finalize gate recomputes the vote from the verdict lines and the cycle's quote-check event in .sdd/<slug>/EVENTS.jsonl; refuted-by: is not used.`
3. In the workspace layout block, add under `<feature>/`: `    EVENTS.jsonl         # build-fleet scripts only. Append-only event log (gate decisions, quote checks). Agents never write it.`

- [ ] **Step 7: Verify and commit**

```bash
bash scripts/rubric-drift.test.sh | tail -1     # passed=11 failed=0
bash scripts/lens-drift.test.sh | tail -1       # passed=3 failed=0
bash scripts/run-tests.sh 2>&1 | tail -1        # suites: 40, failed: 0
git add skills/review-rubric/SKILL.md agents/architect.md agents/qa.md agents/reviewer.md scripts/rubric-drift.test.sh skills/sdd-protocol/SKILL.md
git commit -m "docs(agents): verified-review rule mirrored and drift-checked; reviewer verify mode

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: One live verified review on a scratch feature (spec §5 "Once, live")

**Files:** none in the repo (a scratch project); findings go to the ledger and, if any, to a fix task.

- [ ] **Step 1: A scratch project with a small, flawed spec**

```bash
rm -rf /tmp/bf-live && mkdir -p /tmp/bf-live && cd /tmp/bf-live && git init -q
claude --plugin-dir ~/build-fleet-0.12
```
In the session: `/build-fleet:new-feature upload-retries` with the intent "a client that retries failed uploads", let it scaffold and draft the spec, then add `REVIEW_SHAPE: verified` to `.sdd/upload-retries/PROGRESS.md`.

- [ ] **Step 2: Run the review and wait for it**

`/build-fleet:review` → wait for the workflow to finish (`/workflows`).

- [ ] **Step 3: Check what landed**

```bash
cd /tmp/bf-live
sed -n '/^## Cycle 1/,$p' .sdd/upload-retries/REVIEW.md | head -60     # shape: verified, quote:/test:/verdict: lines
jq -c 'select(.source == "script:quote-check") | {checked, failures, revived, exempt}' .sdd/upload-retries/EVENTS.jsonl
bash ~/build-fleet-0.12/scripts/finalize-gate.sh upload-retries --report | sed 's/^[A-Z_]*: //' | jq '{shape, reasons, open: [.open[] | {id, why}]}'
```
Expected: one quote-check event exists (the hook fired); `shape` is `verified`; every `verdict:` line parses (`jq` raised no error); the run did not end `incomplete` because a reviewer omitted the `closures` array on cycle 1 (the schema requires it; if it did, make `closures` optional in `concernsSchemaFor` and default it to `[]` in the verified branch, with a harness case). Record in the ledger: findings raised, refuted, demoted; quote failures and whether they came from verifiers (paraphrase) or reviewers.

- [ ] **Step 4: Decide**

If more than a third of the quotes failed, the verifiers paraphrase: add an explicit "copy, do not retype" example to `verifierPrompt` and the lens grammar (Task 9's prompts), re-run Steps 2–3 on a fresh cycle, and commit the prompt change with `fix(review): …`. Otherwise record "live run clean" in the ledger and continue.

---

### Task 13: Release prep — stop before merge (spec §4)

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `ROADMAP.md`

- [ ] **Step 1: Confirm the version with Ray**

The roadmap put the lite profile at 0.11 and this protocol at 0.12, but this ships first. Ask Ray: ship as **0.11.0** (lite becomes 0.12) or **0.12.0** (skip 0.11)? Use the answer as `<VERSION>` below. Do not guess.

- [ ] **Step 2: `CLAUDE.md`**

1. Hard rules, **Hooks fail closed** bullet: append `The one deliberate exception is logging: `log_event` (hooks/scripts/_lib.sh) swallows its own failures, so writing the event log never changes a gate's decision.`
2. Layout block: `hooks/scripts/  # 12 gate scripts` → `# 14 gate scripts`; add `quote-check, review-carry` to the `scripts/` list and a line `scripts/lib/                  # shared verified-review rules (jq) and REVIEW.md block helpers`.

- [ ] **Step 3: `README.md`**

Update the component counts (hook scripts 12 → 14; the scripts list gains `quote-check.sh`, `review-carry.sh`), and add under the review description: `Optional verified review (REVIEW_SHAPE: verified): fresh verifiers judge every finding, a finding dies only on two quote-backed refutations, and every quote is checked against the spec before the gate counts it.`

- [ ] **Step 4: `CHANGELOG.md`**

Add at the top:
```
## [<VERSION>] — <date>

### Added
- **Verified review** (`REVIEW_SHAPE: verified`, opt-in; `debate` stays the default): findings carry a
  verbatim spec quote (or a named absence) and a failing test; a panel of three fresh verifiers judges
  each one; two quote-backed refutations kill a finding, one never does; severity is the median vote,
  lowered only with quoted evidence; open findings carry forward between cycles.
- `scripts/quote-check.sh`, run by a hook when the review's scribe finishes, checks every quote word for
  word and records the result in `.sdd/<slug>/EVENTS.jsonl`; a quote that is not found voids its vote.
- The finalize gate recomputes verified votes, refuses `quote-check-missing` and
  `spec-changed-since-review`, and gains `--report`.
- Event log essentials: `log_event`, and a guard that keeps agents from writing the log.

### Compatibility
- Nothing changes unless `REVIEW_SHAPE: verified` is set. Existing REVIEW.md files parse unchanged.
  `SDD_SCHEMA` stays 1. `.sdd/<slug>/EVENTS.jsonl` is new and committed with the rest of `.sdd/`.
```

- [ ] **Step 5: Contract docs**

- `docs/v0.2/CONTRACT.md` §8, in the "Success paths emit their command-specific signal" sentence, add `BUILD_FLEET_QUOTE_CHECK`, `BUILD_FLEET_FINALIZE_REPORT` and `BUILD_FLEET_REVIEW_CARRY`; after it add: `The finalize gate refuses with two further reasons in a verified review: quote-check-missing and spec-changed-since-review. /build-fleet:review refuses shape-changed-mid-feature and carry-unavailable.` In §6's workflow return object, add `shape` ("debate"|"verified"), `verification` (`{raised, verified, killed, closed, demoted, carried, solo_panels}` or null) and the `incomplete` reason `verifier-panel`.
- `docs/loops.md`: in the REVIEW internal row (line 22), change the stages cell to `fan-out → cross-examination → survival vote (debate) or verification panel → quote-backed vote (verified) → disposition → apply`.

- [ ] **Step 6: `plugin.json` and `ROADMAP.md`**

Set `"version": "<VERSION>"` in `.claude-plugin/plugin.json`. Append to `ROADMAP.md` a section for this release (what landed, the open measurement) and the approved roadmap order from the roadmap review (lite, prove the review, dashboard and receipt, launch).

- [ ] **Step 7: Suite, commit, and stop**

```bash
bash scripts/run-tests.sh 2>&1 | tail -1     # suites: 40, failed: 0
git add CLAUDE.md README.md CHANGELOG.md .claude-plugin/plugin.json ROADMAP.md docs/v0.2/CONTRACT.md docs/loops.md
git commit -m "release: v<VERSION> — verified review (opt-in)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
**Stop here.** Merging to main, tagging and pushing are Ray's call (main must equal the latest tag).

---

## Spec coverage map

| Spec section | Task |
|---|---|
| D1 scope, D2 selectable shape | 9 (args), 10 (settings), 11 (protocol) |
| D3 panel; option C | 9 (`runPanel`, `verify_blockers_solo`) |
| D4 checkable findings, §3.1 | 8 (`demoteUncheckable`), 9 (schema, prompt), 11 (rubric) |
| D5 kill on 2, D6 severity | 3 (jq), 8 (JS), parity |
| D7 hook on marker release, §3.4 | 4, 5 |
| D8 gate authority, §3.5 | 6 |
| D9 reviewer agent reused | 9, 11 |
| D10 carry-forward | 3 (`carried`), 4 (`off-roster-block-checked`), 6 (`carried-open`, `off-roster-raiser-carried-open`, `hosted-carried-stays-open`, `report-keeps-carried-origin`), 7 (`no-report-refuses`, `shape-read-from-any-block`), 8 (`materializeCarried`: `carry-relisted-keeps-record`, `carry-off-roster-hosted`), 9 |
| §3.2 REVIEW.md format | 8 (render), 3 (parse), 11 (docs) |
| §3.3 delta cycles, closures | 8, 9; 6 (`confirmed-closure-closes`) |
| §3.4 first event wins, exempt, budget | 4, 7, 9 (`effectiveBudget`), 10 (precondition) |
| §3.5 spec-changed-since-review | 3 (fingerprints), 6 |
| §3.6 commands, status, dependency on Part A | 2, 6, 10 |
| §3.7 agents and skills | 11 |
| §4 compatibility and release | 13 |
| §5 testing; once live | 2–9 harnesses; 12 |
| §6 measurement needs | 9 (settings + return `verification`), events (4, 6) |
| §7 success criteria | parity (8), `two-returned-kill-needs-both` (3), `invented-*` (4, 6), debate suites unchanged (6, 9) |
