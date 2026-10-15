# Four Files per Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A forward feature is four files (`spec.md` with an acceptance section, `PROGRESS.md`, `DECISIONS.md`, `REVIEW.md`, plus `IMPL_NOTES.md` only when written); `acceptance.md`, `TEST_PLAN.md`, `SKILL_MANIFEST.md` and the `test-plan` skill are deleted from the plugin outright, the test plan lives in `<slug>/AC-n` markers in the tests, and the spec has a line budget.

**Architecture:** Gates first, test-first: a shared criteria helper, then the four hooks that change (`validate-acceptance-count`, `cap-spec-size`, `stop-tests`, `block-source-before-finalized`), the router, and a rewritten drift gate that scans markers. Then a static guard test that fails while any plugin file names a retired file — it is the RED for the prose tasks (commands, skills, agents, workflows, docs), which turn it green. Last, live runs and the review regression.

**Tech Stack:** bash 3.2 + BSD/GNU coreutils, awk (BWK on macOS, mawk/gawk on Linux), jq; markdown command/agent/skill files; JS workflows (isolated runtime).

**Spec:** `docs/history/2026-10-16-four-files.md` (approved 2026-10-16).

## Global Constraints

- No backward compatibility: every reference to `acceptance.md`, `TEST_PLAN.md`, `SKILL_MANIFEST.md` and the `test-plan` skill is deleted, not branched. The bug lane and `.sdd/_product/` are unchanged and stay `SDD_SCHEMA: 1`.
- New forward features are stamped `SDD_SCHEMA: 2`; an active forward feature with any other value is refused with reason `unsupported-schema`.
- bash 3.2 and BSD/GNU compatible: no `declare -A`, no `\b`, no `grep -P`; awk uses `index()`/`match()`/`RLENGTH` only; `find … -exec … {} +` (never `xargs` on possibly-empty input).
- Hooks fail closed (trap ERR → exit 2); deliberate allows are explicit `exit 0`.
- Signal lines are the machine contract; never document an exit-code table.
- No milestone jargon in command bodies, agent prompts or descriptions.
- A change to an agent's body means its `description:` is reviewed (CLAUDE.md). `rubric-drift`, `lens-drift`, `drift-wiring` and `agent-surface` must stay green; the severity tables and `## Review lens` text are untouched; the `verified-rule` block changes identically in `skills/review-rubric/SKILL.md`, `agents/architect.md`, `agents/qa.md`, `agents/reviewer.md`.
- Part D caps (agent body words): coder 894, qa 1433, architect 1359, product-owner 1411, classifier 1492, scribe 1571, devops 800, reviewer 800. Raise one only with a named reason in `agent-surface.test.sh`.
- TDD for gates: the failing test is written and seen failing first.
- Commit attribution line: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Work on `release/0.12.0` in `~/build-fleet-0.12`; never commit to main; no merge, tag or push. No version bump (the 0.12.0 release checklist is a separate step).

## Review Focus

1. **The Linux leg.** Every new awk (marker scan, criteria helper, line count) first meets mawk in CI. Expected: green on both legs. Pinned by CI's matrix; the marker scan uses only `index`, `substr`, `match`, `RLENGTH`.
2. **A spec whose acceptance heading is `## Acceptance Criteria` with `### ` subsections.** Expected: ids under the subsections count; a later `## ` heading ends the section. Test `criteria-subsections` (Task 1).
3. **CRLF spec and CRLF test files.** Expected: ids and markers read cleanly. Tests `criteria-crlf` (Task 1), `marker-crlf` (Task 5).
4. **A test root containing `node_modules/` with a vendored file that happens to contain `calc/AC-9`.** Expected: ignored. Test `skip-node-modules` (Task 5).
5. **An Edit that joins two lines of a spec at its budget.** Expected: allowed (the line count drops). Test `edit-join-lines-allowed` (Task 2).

**Rulings made while planning (from the spec):**
- R1: the `--all` schema exemption runs before the "built" check, so any forward feature with `SDD_SCHEMA` ≠ 2 is reported `unchecked` with `"schema"`, built or not.
- R2: `TEST_ROOTS:` with an empty value is treated as absent (the convention of every other PROGRESS field); empty *entries* (`a,,b`, `,a`, `a,`) are `bad-field`.
- R3: a `bad-field` from `TEST_ROOTS` returns at once, like `DRIFT_GATE` `bad-field`; `no-test-roots` marks every criterion `untested` (mirrors part C's `no-test-plan`).
- R4: the schema refusal in `lite-next.sh` sits in `route_active` on the feature branch, so it fires for every lite command including `status` (which calls `decide start`); `status` *reports* the stop and its `next` (`status park <reason>`) rather than being blocked, which is what the spec's exemption is for — the user can still read the state and park.
- R5: `stop-tests.sh` reads `.workflow-in-flight` as "non-empty" (`[ -s ]`), matching the scribe's release-by-emptying convention.
- R6: lines(text) is awk's `NR` at `END` — it counts a final unterminated line and gives 0 for empty input, which is exactly the spec's definition.
- R7: the retired-name scan also covers the bare skill name `test-plan` (D11 retires it); `docs/history/`, `CHANGELOG.md` and `*.test.sh` are excluded.

---

## File structure

| File | Responsibility | Task |
|---|---|---|
| `scripts/lib/criteria.sh` (new) | `spec_criteria <spec.md>` — the one criteria extractor | 1 |
| `hooks/scripts/validate-acceptance-count.sh` + test | AC_MAX on spec.md's section | 1 |
| `hooks/scripts/cap-spec-size.sh` + test | `SPEC_MAX_LINES` line projection | 2 |
| `hooks/scripts/stop-tests.sh` + test | window on `BUILD_STATE` / live workflow | 3 |
| `hooks/scripts/block-source-before-finalized.sh` + test, `scripts/lite-next.sh` + test | `unsupported-schema`; drop acceptance freshness | 4 |
| `scripts/drift-gate.sh` + test | marker scan | 5 |
| `scripts/lib/review-blocks.sh`, `scripts/fixtures/verified-review.sh`, `workflows/review.js`, `workflows/deep-build.js` + tests | quote sources without acceptance.md; no `status:` | 6 |
| `scripts/agent-surface.test.sh`, `docs/history/2026-10-16-lean-agents-RULES.md` | retired-name scan; `retired:` inventory form | 7 |
| `commands/*.md`, `skills/*` (delete `skills/test-plan/`) | prose | 8 |
| `agents/*.md` + RULES inventory | prose, caps, descriptions | 9 |
| `workflows/plan-review.js`, `workflows/diagnose.js`, remaining workflow prose | prose | 10 |
| `docs/v0.2/CONTRACT.md`, `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `docs/v0.5/smoke/smoke.sh`, `scripts/drift-wiring.test.sh` | docs, smoke, wiring | 11 |
| `docs/history/2026-10-16-four-files-EVAL.md` (new) | live runs, review regression, net lines | 12 |

---

### Task 1: Shared criteria helper; AC_MAX counts the spec's section

**Files:**
- Create: `scripts/lib/criteria.sh`
- Modify: `hooks/scripts/validate-acceptance-count.sh`
- Test: `hooks/scripts/validate-acceptance-count.test.sh`

**Interfaces:**
- Produces: `spec_criteria <path-to-spec.md>` — prints distinct `AC-<n>[a-z]` ids from the `## Acceptance…` section, one per line, `LC_ALL=C` sorted; prints nothing (rc 0) for a missing file or no section. Sourced by the hook as `. "$DIR/../../scripts/lib/criteria.sh"` and by `drift-gate.sh` as `. "$HERE/lib/criteria.sh"`.

- [ ] **Step 1: Read the current test harness** — `sed -n 1,60p hooks/scripts/validate-acceptance-count.test.sh` — and note its fixture helpers. Every fixture that writes `acceptance.md` is rewritten in step 2 to write the ids into `spec.md` under `## Acceptance Criteria`.

- [ ] **Step 2: Rewrite the harness's cases for the new trigger file.** Keep the harness's helper style; the cases (each a fresh fixture with `PROGRESS.md` holding `AC_MAX: 3`):

```bash
# spec <slug> — spec.md: STATUS line, a narrative section, then stdin as the acceptance body
spec() { mkdir -p "$P/.sdd/$1"; { printf 'STATUS: DRAFT\n\n# Spec\n\n## Behaviour\n\nSee AC-99 in prose.\n\n## Acceptance Criteria\n\n'; cat; } > "$P/.sdd/$1/spec.md"; }
```

| Case | spec body / setup | Expected |
|---|---|---|
| `under-cap-allows` | `- **AC-1** a` / `- **AC-2** b` | rc 0 |
| `over-cap-refuses` | AC-1..AC-4 | rc 2, stderr names `4 distinct` and `AC_MAX of 3` |
| `prose-ids-outside-section-ignored` | AC-1..AC-3 (the `AC-99` in `## Behaviour` must not count) | rc 0 |
| `criteria-subsections` | `### Import` / AC-1, AC-2 / `### Export` / AC-3, AC-4 | rc 2 (4 ids) |
| `later-section-ends-it` | AC-1, then `## Self-review notes` with AC-5..AC-8 | rc 0 |
| `criteria-crlf` | AC-1..AC-4 written with `\r\n` | rc 2, stderr `4 distinct` |
| `acceptance-md-not-a-trigger` | write `acceptance.md` with AC-1..AC-9 and hook payload naming it | rc 0 |
| `no-cap-field` | no `AC_MAX`, AC-1..AC-9 | rc 0 |
| `garbage-cap` | `AC_MAX: 3x` | rc 2 |
| `product-tier-exempt` | `.sdd/_product/spec.md` with 9 ids | rc 0 |

- [ ] **Step 3: Run it to verify it fails**

Run: `bash hooks/scripts/validate-acceptance-count.test.sh`
Expected: FAIL on `over-cap-refuses`, `criteria-subsections`, `criteria-crlf` (hook still triggers only on `acceptance.md`), and `acceptance-md-not-a-trigger` (it still fires there).

- [ ] **Step 4: Create the helper**

```bash
# scripts/lib/criteria.sh — acceptance criteria of a spec. Sourced, never run.
# The one extractor: hooks/scripts/validate-acceptance-count.sh and scripts/drift-gate.sh
# both call it, so the hook's count and the gate's set cannot disagree.
# bash 3.2 + BSD/GNU compatible.

# spec_criteria <spec.md> — distinct AC-<n>[a-z] ids in the `## Acceptance…` section
# (from that heading to the next `## ` heading; `### ` subsections stay inside), one per
# line, sorted. Nothing for a missing file or a spec with no such section.
spec_criteria() {
  [ -f "$1" ] || return 0
  awk '{ sub(/\r$/, "") } /^## /{ insec = ($0 ~ /^## Acceptance/); next } insec' "$1" \
    | { grep -oE 'AC-[0-9]+[a-z]?' || true; } | LC_ALL=C sort -u
}
```

- [ ] **Step 5: Change the hook.** In `validate-acceptance-count.sh`: header comment says it fires on `.sdd/<slug>/spec.md` and counts the acceptance section via `spec_criteria`; source the helper after `_lib.sh`:

```bash
# shellcheck source=../../scripts/lib/criteria.sh
. "$DIR/../../scripts/lib/criteria.sh"
```

replace the basename test with `[ "$(basename "$file_path")" = "spec.md" ] || exit 0`, replace the count line with

```bash
count=$(spec_criteria "$file_path" | grep -c . || true)
```

and in the refusal text replace "name in spec.md '## Self-review notes' which behaviours (and their criteria) move to a sibling backlog row, then cut them here." with "add a backlog row for the behaviours (and their criteria) that move out, record the split in DECISIONS.md, then cut them from this section." Change "The product tier has no acceptance.md." to "The product tier is exempt."

- [ ] **Step 6: Run it to verify it passes**

Run: `bash hooks/scripts/validate-acceptance-count.test.sh`
Expected: every case `ok`, `failed=0`.

- [ ] **Step 7: Commit**

```bash
git add scripts/lib/criteria.sh hooks/scripts/validate-acceptance-count.sh hooks/scripts/validate-acceptance-count.test.sh
git commit -m "feat(gates): AC_MAX counts the spec's acceptance section; shared criteria helper

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `cap-spec-size` counts lines (`SPEC_MAX_LINES`)

**Files:**
- Modify: `hooks/scripts/cap-spec-size.sh`
- Test: `hooks/scripts/cap-spec-size.test.sh`

**Interfaces:**
- Produces: PROGRESS field `SPEC_MAX_LINES: <int>` (absent/empty = no cap, `0` = disabled, non-integer = refused). `SPEC_MAX_KB` no longer read.

- [ ] **Step 1: Rewrite the harness cases** (`sed -n 1,60p` it first; keep its payload helpers). Fixture `PROGRESS.md` has `SPEC_MAX_LINES: 10`; `spec.md` starts at 8 lines (`printf 'l%s\n' 1 2 3 4 5 6 7 8`).

| Case | Payload | Expected |
|---|---|---|
| `write-under-allows` | Write, 10 lines | rc 0 |
| `write-over-refuses` | Write, 11 lines | rc 2, stderr `11 lines` and `10-line budget` |
| `write-unterminated-last-line-counts` | Write, `printf 'l%s\n' 1..10` + `x` (no newline) | rc 2 (11 lines) |
| `edit-add-lines-over` | Edit old `l8\n` → new `l8\na\nb\nc\n` | rc 2 (8+3) |
| `edit-add-lines-under` | Edit old `l8\n` → new `l8\na\nb\n` | rc 0 (10) |
| `edit-join-lines-allowed` | spec at 10 lines; Edit old `l1\nl2\n` → new `l1 l2\n` | rc 0 |
| `edit-replace-all-counts-occurrences` | spec 8 lines incl. 2× `X\n`; Edit `replace_all` `X\n` → `X\nY\n` | rc 0 (10); with 3× `X` and cap 10 → rc 2 |
| `no-field-no-cap` | no `SPEC_MAX_LINES`, Write 500 lines | rc 0 |
| `zero-disables` | `SPEC_MAX_LINES: 0`, Write 500 | rc 0 |
| `leading-zero-decimal` | `SPEC_MAX_LINES: 010`, Write 10 | rc 0 |
| `garbage-refuses` | `SPEC_MAX_LINES: 150L` | rc 2 |
| `kb-field-ignored` | `SPEC_MAX_KB: 1`, no lines field, Write 500 lines | rc 0 |
| `acceptance-md-not-capped` | Write `.sdd/f/acceptance.md`, 500 lines | rc 0 |
| `notebook-refused` | NotebookEdit on spec.md | rc 2 |
| `product-tier-exempt` | `.sdd/_product/spec.md` | rc 0 |
| `refusal-names-split-route` | the `write-over` stderr | contains `backlog row` and `DECISIONS.md`, not `Self-review notes` |

- [ ] **Step 2: Run it to verify it fails**

Run: `bash hooks/scripts/cap-spec-size.test.sh`
Expected: FAIL on every line-based case (the hook still reads `SPEC_MAX_KB`).

- [ ] **Step 3: Implement.** Replace the header's byte wording with lines and `SPEC_MAX_LINES`; path match becomes `.sdd/*/spec.md) ;;` only. Replace the budget/projection section with:

```bash
cap=$(read_progress_field "$slug" SPEC_MAX_LINES)
[ -n "$cap" ] || exit 0                             # absent: no cap
case "$cap" in
  *[!0-9]*)
    echo "build-fleet: cap-spec-size refused — SPEC_MAX_LINES is not an integer ('${cap}') — fix PROGRESS.md" >&2
    exit 2
    ;;
esac
cap=$((10#$cap))                                    # 010 → 10, not octal
[ "$cap" -gt 0 ] || exit 0                          # 0 disables the cap

# lines(text) = newline count, +1 for a non-empty unterminated last line = awk's NR.
lines_of() { awk 'END { print NR }'; }
nl_of() { tr -cd '\n' | wc -c | tr -d ' '; }
current=0
[ -f "$rel" ] && current=$(lines_of < "$rel")

case "$tool" in
  Write)
    projected=$(printf '%s' "$input" | jq -j '.tool_input.content // empty' | lines_of)
    ;;
  Edit)
    old=$(printf '%s' "$input" | jq -j '.tool_input.old_string // empty' | nl_of)
    new=$(printf '%s' "$input" | jq -j '.tool_input.new_string // empty' | nl_of)
    n=1
    # (keep the existing replace_all occurrence-counting block verbatim here; it sets n)
    projected=$(( current + (new - old) * n ))
    ;;
  NotebookEdit)
    echo "build-fleet: cap-spec-size refused — ${rel} is a spec file; NotebookEdit cannot be size-projected. Use Write or Edit." >&2
    exit 2
    ;;
  *) exit 0 ;;
esac

[ "$projected" -le "$cap" ] && exit 0

cat >&2 <<MSG
build-fleet: cap-spec-size refused — ${rel} would become ${projected} lines, over its ${cap}-line budget.

  current   : ${current} lines
  projected : ${projected} lines
  budget    : ${cap} lines (SPEC_MAX_LINES: ${cap} in ${progress})
  over by   : $(( projected - cap )) lines

A spec that cannot fit its budget is a feature that should be SPLIT, not compressed:
add a backlog row for the behaviours that move out, record the split in DECISIONS.md,
and cut them from ${base}. Move rationale to DECISIONS.md rather than the spec. Raising
SPEC_MAX_LINES in ${progress} is a deliberate, auditable decision — never edit it just
to land this write.
MSG
exit 2
```

(The existing `replace_all` block is reused unchanged: it counts occurrences of `old_string` in the file content and sets `n`.)

- [ ] **Step 4: Run it to verify it passes**

Run: `bash hooks/scripts/cap-spec-size.test.sh`
Expected: every case `ok`, `failed=0`.

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/cap-spec-size.sh hooks/scripts/cap-spec-size.test.sh
git commit -m "feat(gates): spec budget in lines (SPEC_MAX_LINES), newline-exact Edit projection

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `stop-tests` window keys on `BUILD_STATE`

**Files:**
- Modify: `hooks/scripts/stop-tests.sh:47-66`
- Test: `hooks/scripts/stop-tests.test.sh`

- [ ] **Step 1: Change the fixture and window cases.** `new_proj` writes `PHASE: BUILD\nBUILD_STATE: done\n` (so the existing red-suite cases still exercise the gate). Replace the TEST_PLAN/IMPL_NOTES window block (lines ~115-132) with:

```bash
# --- BUILD tests-first window: BUILD_STATE absent ⇒ coder not dispatched ⇒ red is expected ---
p=$(new_proj window 1); printf 'PHASE: BUILD\n' > "$p/.sdd/feat/PROGRESS.md"
run "$p"
assert "window-absent-build-state-allows" "[ $rc -eq 0 ]"
assert "window-absent-no-counter" "[ ! -f '$p/.sdd/feat/.stop-test-retries' ]"

# --- started + live workflow marker ⇒ a background deep-build is running ---
p=$(new_proj wf 1); printf 'PHASE: BUILD\nBUILD_STATE: started\n' > "$p/.sdd/feat/PROGRESS.md"
printf 'deep-build\n' > "$p/.sdd/feat/.workflow-in-flight"
run "$p"
assert "window-started-live-workflow-allows" "[ $rc -eq 0 ]"

# --- started + empty (released) marker ⇒ enforced ---
p=$(new_proj wf0 1); printf 'PHASE: BUILD\nBUILD_STATE: started\n' > "$p/.sdd/feat/PROGRESS.md"
: > "$p/.sdd/feat/.workflow-in-flight"
run "$p"
assert "started-released-marker-enforces" "[ $rc -eq 2 ]"

# --- started, no workflow ⇒ an interrupted coder run: enforced ---
p=$(new_proj st 1); printf 'PHASE: BUILD\nBUILD_STATE: started\n' > "$p/.sdd/feat/PROGRESS.md"
run "$p"
assert "started-no-workflow-enforces" "[ $rc -eq 2 ]"

# --- needs-iteration ⇒ enforced; IMPL_NOTES content is irrelevant now ---
p=$(new_proj ni 1); printf 'PHASE: BUILD\nBUILD_STATE: needs-iteration\n' > "$p/.sdd/feat/PROGRESS.md"
run "$p"
assert "needs-iteration-enforces" "[ $rc -eq 2 ]"

# --- CHANGE_REVIEW with BUILD_STATE absent ⇒ enforced (the window is BUILD only) ---
p=$(new_proj cr 1); printf 'PHASE: CHANGE_REVIEW\n' > "$p/.sdd/feat/PROGRESS.md"
run "$p"
assert "window-is-build-only" "[ $rc -eq 2 ]"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash hooks/scripts/stop-tests.test.sh`
Expected: FAIL `window-absent-build-state-allows` and `window-started-live-workflow-allows` (the hook still looks for TEST_PLAN.md).

- [ ] **Step 3: Implement.** Replace the comment block and the `has_content` window in `stop-tests.sh` with:

```bash
# Tests-first window inside BUILD: qa's failing suite IS the counterfactual, so a red
# suite is expected (a) before coder is dispatched — BUILD_STATE absent; implement sets
# `started` just before coder runs — and (b) while a deep-build workflow runs in the
# background (BUILD_STATE `started` and a non-empty .workflow-in-flight marker): its
# coders are mid-flight when the main session's turn ends. A standard build sets
# `done`/`needs-iteration` before its turn ends, so `started` with no live workflow is
# an interrupted coder run, and the gate enforces. Never skipped outside BUILD.
if [ "$phase" = "BUILD" ]; then
  bstate=$(read_progress_field "$slug" BUILD_STATE)
  if [ -z "$bstate" ]; then
    echo "build-fleet: '${slug}' is in the BUILD tests-first window — coder has not been dispatched (BUILD_STATE absent), so a red suite is the expected state. stop-tests gate skipped." >&2
    exit 0
  fi
  if [ "$bstate" = "started" ] && [ -s ".sdd/${slug}/.workflow-in-flight" ]; then
    echo "build-fleet: '${slug}' has a build workflow in flight — its coders are mid-run. stop-tests gate skipped." >&2
    exit 0
  fi
fi
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash hooks/scripts/stop-tests.test.sh`
Expected: every case `ok`, `failed=0`.

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/stop-tests.sh hooks/scripts/stop-tests.test.sh
git commit -m "feat(gates): stop-tests window keys on BUILD_STATE and a live build workflow

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `unsupported-schema` at the two entry points

**Files:**
- Modify: `hooks/scripts/block-source-before-finalized.sh` (after the bug-lane block, before `status=$(read_spec_status …)`)
- Modify: `scripts/lite-next.sh` (`route_active`, `route_feature`)
- Test: `hooks/scripts/block-source-before-finalized.test.sh`, `scripts/lite-next.test.sh`

- [ ] **Step 1: Stamp the fixtures.** In both harnesses, every forward-feature `PROGRESS.md` a helper writes gains `SDD_SCHEMA: 2` (bug-lane fixtures stay as they are). Then add:

`block-source-before-finalized.test.sh`:

| Case | Setup | Expected |
|---|---|---|
| `schema-1-source-refused` | FINALIZED spec, `SDD_SCHEMA: 1`, Write `src/a.py` | rc 2, stderr contains `older build-fleet` and `park` |
| `schema-absent-source-refused` | FINALIZED spec, no `SDD_SCHEMA` | rc 2 |
| `schema-1-sdd-write-allowed` | `SDD_SCHEMA: 1`, Write `.sdd/f/PROGRESS.md` | rc 0 |
| `schema-2-finalized-allowed` | FINALIZED, `SDD_SCHEMA: 2`, Write `src/a.py` | rc 0 |
| `bug-lane-schema-1-unaffected` | bug fixture (diagnosis CONFIRMED, `SDD_SCHEMA: 1`), Write `src/a.py` | rc 0 |

`lite-next.test.sh`:

| Case | Setup | Expected |
|---|---|---|
| `schema-1-feature-stops` | active feature, `SDD_SCHEMA: 1`, `lite-next.sh build` | `{"stop":"unsupported-schema","next":"status park <reason>"` |
| `schema-1-status-reports` | same, `lite-next.sh status` | line carries `"stop":"unsupported-schema"` (status reports it; rc 0) |
| `schema-1-bug-unaffected` | active bug, `SDD_SCHEMA: 1` | routes as before (not `unsupported-schema`) |
| `acceptance-md-not-freshness` | schema 2, reviewed (CYCLE 1), REVIEW.md newer than spec.md, a newer stray `acceptance.md` | not `"step":"review"` with "the spec changed" |

- [ ] **Step 2: Run both to verify they fail**

Run: `bash hooks/scripts/block-source-before-finalized.test.sh; bash scripts/lite-next.test.sh`
Expected: FAIL on the `schema-1-*`/`schema-absent-*` cases and `acceptance-md-not-freshness`.

- [ ] **Step 3: Implement the hook check** (forward lane only — it sits after the `resolve_lane … = bug` block, so the bug lane never reaches it, and after the `.sdd/` early allow):

```bash
# Schema: this plugin reads the four-file layout only (SDD_SCHEMA: 2). A forward feature
# scaffolded by an older build-fleet has acceptance.md/TEST_PLAN.md that nothing reads
# any more, so its gates would pass on nothing. Refuse source writes; .sdd/ stays
# writable above, so parking it by hand still works.
schema=$(read_progress_field "$slug" SDD_SCHEMA)
if [ "$schema" != "2" ]; then
  echo "build-fleet: active feature '${slug}' was started by an older build-fleet (SDD_SCHEMA=${schema:-<none>}; this version needs 2). Source writes are blocked — park it (/build-fleet:status park <reason>) and start it again." >&2
  echo "Refused write: ${file_path}" >&2
  exit 2
fi
```

- [ ] **Step 4: Implement the router check.** In `route_active`, replace the last line with:

```bash
  if [ "$lane" = bug ]; then route_bug "$slug" "$phase"; return; fi
  if [ "$(field "$p" SDD_SCHEMA)" != 2 ]; then
    S unsupported-schema "status park <reason>" "'$slug' was started by an older build-fleet; park it and start it again"; return
  fi
  route_feature "$c" "$slug" "$phase"
```

and in `route_feature` delete ` || newer "$d/acceptance.md" "$d/REVIEW.md"`. Add `unsupported-schema` to the header comment's stop list if it has one.

- [ ] **Step 5: Run both to verify they pass**

Run: `bash hooks/scripts/block-source-before-finalized.test.sh && bash scripts/lite-next.test.sh`
Expected: `failed=0` for both.

- [ ] **Step 6: Commit**

```bash
git add hooks/scripts/block-source-before-finalized.sh hooks/scripts/block-source-before-finalized.test.sh scripts/lite-next.sh scripts/lite-next.test.sh
git commit -m "feat(gates): refuse forward features from an older layout (unsupported-schema)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The drift gate scans `<slug>/AC-n` markers

**Files:**
- Modify (rewrite): `scripts/drift-gate.sh`
- Modify (rewrite): `scripts/drift-gate.test.sh`

**Interfaces:**
- Consumes: `spec_criteria` (Task 1).
- Produces: `BUILD_FLEET_DRIFT_GATE: {"feature":<s>,"pass":<bool>,"reasons":[…],"untested":[…],"unknown":[…]}`; `{"feature","pass":true,"unchecked":true}` for `DRIFT_GATE: off`; under `--all` also `{"feature","pass":true,"in_progress":true}` and `{"feature","pass":true,"unchecked":true,"schema":<s>}`; `BUILD_FLEET_DRIFT_GATE_SUMMARY: {"checked","unchecked","in_progress","failed"}`. Exit 0 pass / 2 fail / 1 bad usage. Reasons in order: `bad-field unsupported-schema no-criteria no-test-roots untested unknown-criterion`.

- [ ] **Step 1: Rewrite the harness.** Keep `proj`, `src`, `run`, `has`, `assert`; replace `feat`/`acc`/`plan` with:

```bash
# feat <slug> — PROGRESS.md: SDD_SCHEMA: 2, FEATURE, then stdin
feat() { mkdir -p "$P/.sdd/$1"; { printf 'SDD_SCHEMA: 2\nFEATURE: %s\n' "$1"; cat; } > "$P/.sdd/$1/PROGRESS.md"; }
# spec <slug> <ids…> — spec.md with the ids in its acceptance section
spec() { local s="$1"; shift; { printf 'STATUS: FINALIZED\n\n# %s\n\n## Acceptance Criteria\n\n' "$s"; for i in "$@"; do printf -- '- **%s**: behaviour %s.\n' "$i" "$i"; done; } > "$P/.sdd/$s/spec.md"; }
# base — feature f, criteria AC-1 AC-2, tests/test_f.py marking both
base() {
  proj; printf 'PHASE: BUILD\n' | feat f; spec f AC-1 AC-2
  src tests/test_f.py <<'T'
# f/AC-1
def test_one(): pass
def test_two(): pass  # f/AC-2
T
}
```

Cases (each `run f` unless noted):

| Case | Setup beyond `base` (or own) | Expected |
|---|---|---|
| `pass` | — | rc 0, `{"feature":"f","pass":true,"reasons":[],"untested":[],"unknown":[]}` |
| `gate-default-on` | own: feat with no DRIFT_GATE, spec AC-1, no marker, `tests/` exists | rc 2, `untested` |
| `unchecked-off` | `DRIFT_GATE: off` | rc 0, `"unchecked":true` |
| `explicit-on` | `DRIFT_GATE: on` | rc 0 |
| `bad-field-drift-gate` | `DRIFT_GATE: yes` | rc 2, `"reasons":["bad-field"]` |
| `unsupported-schema` | PROGRESS `SDD_SCHEMA: 1` | rc 2, `"reasons":["unsupported-schema"]` |
| `no-criteria` | spec with no ids | rc 2, `"reasons":["no-criteria"]` |
| `untested` | test file without the `f/AC-2` line | rc 2, `"untested":["AC-2"]` |
| `unknown-criterion` | add `# f/AC-7` to a test | rc 2, `"reasons":["unknown-criterion"]`, `"unknown":["AC-7"]` |
| `other-feature-markers-ignored` | add `# g/AC-7` and `# g/AC-1` (no g criteria involved) | rc 0 |
| `bare-id-not-a-marker` | tests mark `# AC-1`/`# AC-2` only | rc 2, untested AC-1, AC-2 |
| `no-match-AC-30` | spec AC-3; test `# f/AC-30` | rc 2, untested AC-3, unknown AC-30 |
| `no-match-AC-3a-for-AC-3` | spec AC-3; test `# f/AC-3a` | rc 2, untested AC-3, unknown AC-3a |
| `no-match-prefixed-slug` | spec AC-1; test `# old-f/AC-1` | rc 2, untested AC-1 (and nothing unknown) |
| `no-match-dot-prefix` | test `x.f/AC-1` | rc 2 untested AC-1 |
| `slash-comment-matches` | test `//f/AC-1` and `///f/AC-2` | rc 0 |
| `hash-no-space-matches` | test `#f/AC-1 #f/AC-2` | rc 0 |
| `not-a-criterion-shape` | add `f/AC-notes` | rc 0 (ignored) |
| `trailing-underscore-rejected` | spec AC-1; test `f/AC-1_x` | rc 2 untested AC-1 |
| `md-file-ignored` | markers only in `tests/README.md` | rc 2 untested both |
| `marker-crlf` | test file with `\r\n` lines | rc 0 |
| `default-roots-test-dir` | tests in `test/` not `tests/` | rc 0 |
| `default-roots-spec-dir` | tests in `spec/` | rc 0 |
| `default-roots-none` | no `tests`/`test`/`spec` dir | rc 2, `"reasons":["no-test-roots","untested"]`, untested both |
| `test-roots-csv` | `TEST_ROOTS: src, e2e` (spaces), markers split across `src/a.test.ts`, `e2e/b.spec.ts` | rc 0 |
| `test-roots-missing` | `TEST_ROOTS: nope` | rc 2, `no-test-roots` |
| `test-roots-empty-entry` | `TEST_ROOTS: tests,,src` | rc 2, `"reasons":["bad-field"]` |
| `test-roots-trailing-comma` | `TEST_ROOTS: tests,` | rc 2, `bad-field` |
| `test-roots-absolute` | `TEST_ROOTS: /tmp` | rc 2, `bad-field` |
| `test-roots-dotdot` | `TEST_ROOTS: ../x` | rc 2, `bad-field` |
| `test-roots-sdd` | `TEST_ROOTS: .sdd` | rc 2, `bad-field` |
| `test-roots-empty-value-is-absent` | `TEST_ROOTS:` | rc 0 (defaults to `tests`) |
| `skip-node-modules` | markers in tests/; `tests/node_modules/x.js` holds `f/AC-9` | rc 0 (AC-9 not unknown) |
| `skip-git-dir` | `tests/.git/x` holds `f/AC-9` | rc 0 |
| `path-with-spaces` | markers in `tests/my tests/t.py` | rc 0 |
| `bad-slug` | `run ../x` | rc 1 |
| `all-mixed` | own: f (built, `BUILD_STATE: done`, passes), g (built, untested), h (PHASE SPEC), o (`SDD_SCHEMA: 1`, built), bug b (`LANE: bug`); `run --all` | rc 2; o line `"unchecked":true,"schema":"1"`; h `"in_progress":true`; summary `{"checked":2,"unchecked":1,"in_progress":1,"failed":["g"]}` |
| `all-pass` | own: only f built and passing | rc 0, summary `"failed":[]` |

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/drift-gate.test.sh`
Expected: most cases FAIL (the gate still reads TEST_PLAN.md).

- [ ] **Step 3: Rewrite the gate**

```bash
#!/usr/bin/env bash
# scripts/drift-gate.sh — the drift gate: every acceptance criterion of a feature is named
# by at least one test marker. Static and model-free.
#
# Gated = PROGRESS.md's DRIFT_GATE is absent, empty or `on`; `off` = unchecked; any other
# value = bad-field. Criteria = distinct AC-<n>[a-z] ids in spec.md's `## Acceptance…`
# section (scripts/lib/criteria.sh). A marker is `<slug>/AC-<n>[a-z]` in a regular, non-.md
# file under the test roots, not preceded by [A-Za-z0-9_.-] and not followed by
# [A-Za-z0-9_-] — so `#calc/AC-3` and `//calc/AC-3` match, `calc/AC-30`, `old-calc/AC-3`
# and `calc/AC-3a` do not count for `calc/AC-3`. Other features' markers are ignored.
# Test roots = TEST_ROOTS (comma-separated, project-relative) if set, else whichever of
# tests, test, spec exist. .git/ and node_modules/ are skipped.
#
# Reasons, in this order: bad-field unsupported-schema no-criteria no-test-roots untested
# unknown-criterion.
#
# Usage: drift-gate.sh <slug> | drift-gate.sh --all
# Output (stdout): one `BUILD_FLEET_DRIFT_GATE: {…}` line per feature; --all adds one
#   `BUILD_FLEET_DRIFT_GATE_SUMMARY: {"checked","unchecked","in_progress","failed"}` line.
#   --all reports a forward feature whose SDD_SCHEMA is not 2 as unchecked (never failed).
# Exit: 0 = pass; 2 = fail; 1 = bad usage / unreadable workspace (CI keys off this).
# bash 3.2 + BSD/GNU compatible; read-only. Requires jq.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/criteria.sh
. "$HERE/lib/criteria.sh"

usage() { echo "usage: drift-gate.sh <slug> | drift-gate.sh --all" >&2; exit 1; }
[ $# -eq 1 ] || usage
command -v jq >/dev/null 2>&1 || { echo "drift-gate.sh: jq is required" >&2; exit 1; }
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 1

# field <file> <NAME> — the value of the first "NAME:" line, whitespace stripped
field() { { grep -m1 "^$2:" "$1" 2>/dev/null || true; } | sed -E "s/^$2:[[:space:]]*//" | tr -d '\r '; }
add() { eval "$1=\"\${$1}\${$1:+\$'\\n'}\$2\""; }
tojson() { if [ -z "$1" ]; then printf '[]'; else printf '%s\n' "$1" | jq -R . | jq -sc .; fi; }
js() { jq -n --arg s "$1" '$s'; }

# markers <slug> <root>… — distinct AC ids marked `<slug>/AC-…` under the roots, sorted
markers() {
  local slug="$1"; shift
  find "$@" \( -name .git -o -name node_modules \) -prune -o -type f ! -name '*.md' \
      -exec env SLUG="$slug" awk '
    BEGIN { pre = ENVIRON["SLUG"] "/AC-"; L = length(pre) }
    { line = $0; sub(/\r$/, "", line); off = 0
      while ((i = index(substr(line, off + 1), pre)) > 0) {
        p = off + i
        b = (p > 1) ? substr(line, p - 1, 1) : ""
        rest = substr(line, p + L)
        if (b !~ /[A-Za-z0-9_.-]/ && match(rest, /^[0-9]+[a-z]?/)) {
          id = substr(rest, 1, RLENGTH); a = substr(rest, RLENGTH + 1, 1)
          if (a !~ /[A-Za-z0-9_-]/) print "AC-" id
        }
        off = p
      } }' {} + 2>/dev/null | LC_ALL=C sort -u
}

emit() {  # emit <slug_json> <reasons> <untested> <unknown>
  local pass=true; [ -z "$2" ] || pass=false
  printf 'BUILD_FLEET_DRIFT_GATE: {"feature":%s,"pass":%s,"reasons":%s,"untested":%s,"unknown":%s}\n' \
    "$1" "$pass" "$(tojson "$2")" "$(tojson "$3")" "$(tojson "$4")"
  [ "$pass" = true ] && return 0 || return 2
}

# check_one <slug> — prints one gate line; returns 0 pass, 2 fail, 1 unreadable
check_one() {
  local slug="$1" d=".sdd/$1" sj gate crit tr e roots="" reasons="" untested="" unknown="" found="" id
  [ -f "$d/PROGRESS.md" ] || { echo "drift-gate.sh: $d/PROGRESS.md not found" >&2; return 1; }
  sj=$(js "$slug")
  gate=$(field "$d/PROGRESS.md" DRIFT_GATE)
  case "$gate" in
    off) printf 'BUILD_FLEET_DRIFT_GATE: {"feature":%s,"pass":true,"unchecked":true}\n' "$sj"; return 0 ;;
    ""|on) ;;
    *) emit "$sj" bad-field "" ""; return ;;
  esac
  [ "$(field "$d/PROGRESS.md" SDD_SCHEMA)" = 2 ] || { emit "$sj" unsupported-schema "" ""; return; }

  tr=$(field "$d/PROGRESS.md" TEST_ROOTS)
  if [ -n "$tr" ]; then
    case ",$tr," in *,,*) emit "$sj" bad-field "" ""; return ;; esac
    local oldifs="$IFS"; IFS=','; set -f
    for e in $tr; do
      case "$e" in /*|*..*|.sdd|.sdd/*) IFS="$oldifs"; set +f; emit "$sj" bad-field "" ""; return ;; esac
      add roots "$e"
    done
    IFS="$oldifs"; set +f
  else
    for e in tests test spec; do [ -d "$e" ] && add roots "$e"; done
  fi

  crit=$(spec_criteria "$d/spec.md")
  [ -n "$crit" ] || add reasons no-criteria

  local missing_root=""
  if [ -z "$roots" ]; then missing_root=1
  else
    while IFS= read -r e; do [ -d "$e" ] || missing_root=1; done <<EOF_R
$roots
EOF_R
  fi
  if [ -n "$missing_root" ]; then
    add reasons no-test-roots
  else
    local oldifs="$IFS"; IFS=$'\n'; set -f
    # shellcheck disable=SC2086
    found=$(markers "$slug" $roots)
    IFS="$oldifs"; set +f
  fi

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    printf '%s\n' "$found" | grep -qxF -- "$id" || add untested "$id"
  done <<EOF_C
$crit
EOF_C
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    printf '%s\n' "$crit" | grep -qxF -- "$id" || add unknown "$id"
  done <<EOF_F
$found
EOF_F
  [ -z "$untested" ] || add reasons untested
  [ -z "$unknown" ] || add reasons unknown-criterion
  emit "$sj" "$reasons" "$untested" "$unknown"
}

if [ "$1" != "--all" ]; then
  case "$1" in */*|..|.|-*|"") echo "drift-gate.sh: bad slug '$1'" >&2; exit 1 ;; esac
  check_one "$1"; exit $?
fi

checked=0; unchecked=0; in_progress=0; failed=""
for d in .sdd/*/; do
  [ -d "$d" ] || continue
  slug=$(basename "$d")
  [ "$slug" = _product ] && continue
  [ -f "$d/PROGRESS.md" ] || continue
  [ "$(field "$d/PROGRESS.md" LANE)" = bug ] && continue
  sch=$(field "$d/PROGRESS.md" SDD_SCHEMA)
  if [ "$sch" != 2 ]; then
    printf 'BUILD_FLEET_DRIFT_GATE: {"feature":%s,"pass":true,"unchecked":true,"schema":%s}\n' "$(js "$slug")" "$(js "$sch")"
    unchecked=$((unchecked+1)); continue
  fi
  bs=$(field "$d/PROGRESS.md" BUILD_STATE); ph=$(field "$d/PROGRESS.md" PHASE)
  built=false
  if [ "$bs" = done ]; then built=true
  elif [ -z "$bs" ]; then case "$ph" in CHANGE_REVIEW|HANDOFF) built=true ;; esac; fi
  if [ "$built" = false ]; then
    printf 'BUILD_FLEET_DRIFT_GATE: {"feature":%s,"pass":true,"in_progress":true}\n' "$(js "$slug")"
    in_progress=$((in_progress+1)); continue
  fi
  line=$(check_one "$slug"); rc=$?
  [ -n "$line" ] && printf '%s\n' "$line"
  case "$line" in *'"unchecked":true'*) unchecked=$((unchecked+1)) ;; *) checked=$((checked+1)) ;; esac
  [ $rc -eq 0 ] || add failed "$slug"
done
printf 'BUILD_FLEET_DRIFT_GATE_SUMMARY: {"checked":%s,"unchecked":%s,"in_progress":%s,"failed":%s}\n' "$checked" "$unchecked" "$in_progress" "$(tojson "$failed")"
[ -z "$failed" ] && exit 0 || exit 2
```

Note on `roots` word-splitting: roots are newline-separated and split with `IFS=newline` + `set -f`, so a root with a space (`TEST_ROOTS` cannot contain one — `field` strips spaces — but `tests/my tests` *inside* a root is reached by `find`) is safe.

- [ ] **Step 4: Run it to verify it passes**

Run: `bash scripts/drift-gate.test.sh`
Expected: every case `ok`, `failed=0`. If `all-mixed`'s `checked` count differs, recheck that the `o` feature is counted `unchecked` before the built test (R1).

- [ ] **Step 5: Commit**

```bash
git add scripts/drift-gate.sh scripts/drift-gate.test.sh
git commit -m "feat(drift-gate): criteria from the spec, coverage from <slug>/AC-n test markers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Review machinery: no `acceptance.md` source, no `status:` line

**Files:**
- Modify: `scripts/lib/review-blocks.sh:49-95`, `scripts/fixtures/verified-review.sh`, `workflows/review.js` (payload schema ~586-624, prompt ~1055, render ~1236, quote-file enums ~1010/1085/1110), `workflows/deep-build.js` (~182 and its render)
- Test: `scripts/quote-check.test.sh`, `scripts/finalize-gate.test.sh`, `scripts/change-review-gate.test.sh`, `scripts/workflow-review-*.test.sh` (whichever assert the rendered block)

- [ ] **Step 1: Failing tests.**
  - `quote-check.test.sh`: add `acceptance-md-not-a-source` — a quote `{"file":"acceptance.md","text":"<10+ chars present in a fixture acceptance.md>"}` must be rejected (not found / not an allowed source), and `spec-acceptance-section-quotable` — a quote of a criterion line from spec.md's acceptance section passes.
  - `finalize-gate.test.sh` and `change-review-gate.test.sh`: add `no-status-line-block` — a REVIEW.md block that is a heading plus findings with dispositions, no `status:` line, evaluates exactly as the same block with one (both pass, and an open blocker without `status:` still fails). This pins the spec's "no gate change" claim.
  - The workflow test that renders review blocks (find it: `/usr/bin/grep -ln "status:" scripts/workflow-*.test.sh scripts/verified-review-e2e.test.sh`): assert the rendered block has no `^status:` line.

- [ ] **Step 2: Run to verify they fail**

Run: `bash scripts/quote-check.test.sh; bash scripts/finalize-gate.test.sh; bash scripts/change-review-gate.test.sh` and the render test.
Expected: `acceptance-md-not-a-source` FAILS (still allow-listed) and the render test FAILS (still emits `status:`). The two `no-status-line-block` cases are expected to PASS already — they pin current behaviour; note it in the ledger.

- [ ] **Step 3: Implement.**
  - `review-blocks.sh`: the three `for k in spec.md acceptance.md DECISIONS.md _product/DECISIONS.md` loops become `for k in spec.md DECISIONS.md _product/DECISIONS.md`; delete the `acceptance.md)` case arms and the comment mentions.
  - `review.js`: delete `status` from the role payload `properties` and from both `required` arrays; delete the prompt line telling the role to set `status`; delete `lines.push(\`status: …\`)`; remove `"acceptance.md"` from every quote-file enum and from the read lists (`- .sdd/${feature}/acceptance.md` lines, "Read .sdd/${feature}/spec.md, .sdd/${feature}/acceptance.md and …" → "Read .sdd/${feature}/spec.md and …"); the architect lens text "what `acceptance.md`" → "what the spec's acceptance criteria".
  - `deep-build.js`: delete `status` from its review payload schema and render.
  - `scripts/fixtures/verified-review.sh`: drop the acceptance.md fixture file and any `status:` lines it writes.

- [ ] **Step 4: Run to verify they pass**

Run: `bash scripts/run-tests.sh > <scratch>/t6.log 2>&1; tail -5 <scratch>/t6.log` (`<scratch>` = the session scratchpad) and `node --check workflows/review.js workflows/deep-build.js` and `bash scripts/workflow-determinism-lint.sh workflows/*.js`
Expected: the suite's summary shows 0 failed suites except those owned by later tasks (`agent-surface` is not yet changed, so it is still green; nothing else may fail).

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/review-blocks.sh scripts/fixtures/verified-review.sh workflows/review.js workflows/deep-build.js scripts/*.test.sh
git commit -m "feat(review): findings-only blocks (no status line); spec.md is the only spec quote source

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The retired-name guard (RED for Tasks 8–11)

**Files:**
- Modify: `scripts/agent-surface.test.sh`

- [ ] **Step 1: Add the scan.** After the existing checks, before the summary:

```bash
# Retired layout: no shipped surface may name a file the four-file layout removed, or the
# retired test-plan skill. History, the changelog and test harnesses are exempt.
retired=$(cd "$ROOT" && /usr/bin/grep -rnE 'acceptance\.md|TEST_PLAN\.md|SKILL_MANIFEST\.md|`test-plan`|skills/test-plan' \
  agents commands skills workflows hooks scripts docs/v0.2 README.md CLAUDE.md 2>/dev/null \
  | /usr/bin/grep -v '\.test\.sh:' || true)
if [ -z "$retired" ]; then ok "no retired layout names"
else no "no retired layout names" "$(printf '%s\n' "$retired" | head -5) … ($(printf '%s\n' "$retired" | grep -c .) lines)"; fi
[ ! -d "$ROOT/skills/test-plan" ] && ok "test-plan skill removed" || no "test-plan skill removed" "skills/test-plan exists"
```

Also teach the inventory loop the retired form: in the `'- [x] '*)` arm, before extracting `q`:

```bash
        case "$line" in *'→ retired: '?*) continue ;; esac
```

(`n` is still incremented, so retired rules count as checked.)

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/agent-surface.test.sh`
Expected: FAIL `no retired layout names` (dozens of lines) and `test-plan skill removed`. This stays red until Task 11; the task is complete when the test is committed red (Ruling recorded in the ledger: "agent-surface red by design until Task 11").

- [ ] **Step 3: Commit**

```bash
git add scripts/agent-surface.test.sh
git commit -m "test(surface): fail while any shipped file names the retired layout

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Commands and skills

**Files:**
- Modify: `commands/new-feature.md`, `implement.md`, `handoff.md`, `finalize.md`, `revise.md`, `status.md`, `deep-build.md`, `dispatch.md`, `triage.md`, `verify.md`, `apply-fix.md`, `ship-fix.md` (only where they name a retired file)
- Modify: `skills/sdd-protocol/SKILL.md`, `skills/sdd-protocol/references/bug-lane.md`, `skills/sdd-spec-template/SKILL.md`, `skills/skill-routing/SKILL.md`, `skills/review-rubric/SKILL.md`
- Delete: `skills/test-plan/`

Edit rules (apply each; then the step-4 grep must be empty for these files):

- [ ] **Step 1: `new-feature.md`.**
  - Scaffold list: `spec.md` (header plus an empty `## Acceptance Criteria` section, from `sdd-spec-template`), `DECISIONS.md`. Delete the `acceptance.md`, `TEST_PLAN.md`, `IMPL_NOTES.md` and `REVIEW.md` scaffold lines; add one sentence: "`REVIEW.md` is created by the first review; `IMPL_NOTES.md` by its first writer."
  - PROGRESS block: `SDD_SCHEMA: 2`; delete `DRIFT_GATE: on`.
  - Size budget: `standard`: `SPEC_MAX_LINES: 150` and `AC_MAX: 15`; `large`: `SPEC_MAX_LINES: 400` and `AC_MAX: 30`; `trivial`: neither. Hook names unchanged; "acceptance.md" → "the spec's acceptance section".
  - Skill routing (step ~295): replace "write it to `.sdd/<slug>/SKILL_MANIFEST.md`" with "write `CODER_SKILLS: <csv>` and `QA_SKILLS: <csv>` into PROGRESS.md for each role whose `skills` list is non-empty (omit the line otherwise)". The `BUILD_FLEET_SKILL_MANIFEST:` signal line is unchanged.
- [ ] **Step 2: `implement.md`.**
  - Re-run guard (step 4): "If `BUILD_STATE` is present in PROGRESS.md, or any `<slug>/AC-` marker already exists under the test roots (`grep -rl -- '<slug>/AC-' <roots>`), refuse …" — same signal line and reason.
  - qa brief (step ~66) and repair brief (~115): drop "per the `test-plan` skill"; qa "tags every test with a `<slug>/AC-<n>` marker comment for each criterion it covers (on or above the test), then implements the failing suite under the test roots"; repair: "add or fix markers (or tests) so every criterion is marked".
  - Skill lines (~70, ~214): "If PROGRESS.md has `QA_SKILLS` (`CODER_SKILLS` for coder), first load and apply those skills …".
  - Every "acceptance.md" → "the spec's acceptance criteria"; every IMPL_NOTES mention that implies it exists → "`IMPL_NOTES.md` (create it if absent)" for writers, "if it exists" for readers.
- [ ] **Step 3: the other commands.** `handoff.md` pointer lists: `spec.md`, `DECISIONS.md`, `IMPL_NOTES.md` (if it exists). `finalize`, `revise`, `status`, `deep-build`, `dispatch`, `triage`: replace retired names with the spec's acceptance section / the skill fields. Bug-lane commands: only the retired-name mentions (`triage.md:48` lists files a bug never has — keep the sentence, name `spec.md` only).
- [ ] **Step 4: skills.**
  - `sdd-protocol/SKILL.md`: the `.sdd/` tree is the four-file layout (§3.1 of the spec, verbatim); PROGRESS block: `SDD_SCHEMA: 2`, `SPEC_MAX_LINES` replaces `SPEC_MAX_KB`, `DRIFT_GATE: on | off  # absent ⇒ on; off ⇒ unchecked (a feature with no tests)`, add `TEST_ROOTS: <csv>  # optional — drift gate test roots; absent ⇒ whichever of tests, test, spec exist`, `CODER_SKILLS`/`QA_SKILLS`; BUILD step 1 becomes "qa marks each test with `<slug>/AC-<n>` and writes the failing suite"; ownership line for IMPL_NOTES says "created on first write". Add the marker convention in three lines: format, placement (comment on or above the test), and "an untestable criterion is a spec defect product-owner fixes".
  - `references/bug-lane.md`: "no `spec.md`/`acceptance.md`" → "no `spec.md`".
  - `sdd-spec-template/SKILL.md`: the template ends with `## Acceptance Criteria` (the grammar the old acceptance file used: `- **AC-<n>**: <observable behaviour>`), and its guidance says criteria are the spec's last section and frozen with it.
  - `skill-routing/SKILL.md`: the persisted format section becomes the two PROGRESS fields; the "Where the manifest lives" diagram and the coder/qa read step name the fields; the classifier's JSON schema section is kept (it is the signal line's shape).
  - `review-rubric/SKILL.md` is **not** edited here: its `verified-rule` block is mirrored in three agents, so Task 9 edits all four in one commit and `rubric-drift` never goes red.
  - `git rm -r skills/test-plan`.
- [ ] **Step 5: Verify**

Run: `/usr/bin/grep -rnE 'acceptance\.md|TEST_PLAN\.md|SKILL_MANIFEST\.md|`test-plan`|skills/test-plan|SPEC_MAX_KB' commands skills | /usr/bin/grep -v '^skills/review-rubric/'`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add -A commands skills
git commit -m "docs(commands,skills): four-file layout; test markers; skill fields; retire test-plan

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Agents, rule inventory, caps, descriptions

**Files:**
- Modify: `agents/product-owner.md`, `qa.md`, `coder.md`, `scribe.md`, `architect.md`, `reviewer.md`, `devops.md`, `classifier.md`, `skills/review-rubric/SKILL.md`
- Modify: `docs/history/2026-10-16-lean-agents-RULES.md`, `scripts/agent-surface.test.sh` (`RULES_COUNT`, caps only if needed)

- [ ] **Step 1: List every affected line.** `/usr/bin/grep -nE 'acceptance|TEST_PLAN|SKILL_MANIFEST|IMPL_NOTES|test-plan|status:' agents/*.md > <scratch>/agent-lines.txt` and the inventory lines naming them: `/usr/bin/grep -nE 'acceptance\.md|TEST_PLAN|SKILL_MANIFEST|status:|test-plan' docs/history/2026-10-16-lean-agents-RULES.md`.
- [ ] **Step 2: Edit by these rules** (rules are never cut, only reworded — part D's D3a — except rules whose subject is gone, which are retired):
  - Ownership lists: drop `acceptance.md`, `TEST_PLAN.md`; product-owner owns "`spec.md`, including its acceptance criteria section".
  - product-owner: writes criteria as the spec's last section (`## Acceptance Criteria`), its self-review and PLAN_REVIEW criteria point there; an untestable criterion is its spec defect.
  - qa: replace the TEST_PLAN drafting rule (R44) and its `test-plan` skill references (lines 11-12, 80, 87) with: "Once spec is FINALIZED and PHASE=BUILD, mark each test with a `<slug>/AC-<n>` comment on or above it for every criterion it covers, then write the failing suite under the test roots. Every criterion needs at least one marker; the drift gate checks it." `skill-unavailable` lines go to `IMPL_NOTES.md` (create it if absent). Skills from `QA_SKILLS`.
  - coder: skills from `CODER_SKILLS`; "`IMPL_NOTES.md` (create it on first write) — gaps, deviations and TODOs"; review format block loses `status: concerns-raised | approved`.
  - scribe: drop `TEST_PLAN.md`/`acceptance.md` from its never-write list (they no longer exist); drop the `status:` render.
  - `skills/review-rubric/SKILL.md`, architect, reviewer, qa — in the `verified-rule` block, "`spec.md`, `acceptance.md`, `DECISIONS.md` or `_product/DECISIONS.md`" → "`spec.md`, `DECISIONS.md` or `_product/DECISIONS.md`", identically in all four; every review-format block loses the `status:` line and the sentence explaining it.
  - reviewer and architect read lists: `spec.md`, `DECISIONS.md` (no acceptance.md).
  - devops: never-write list without `acceptance.md`.
  - Every reader of IMPL_NOTES: "if it exists".
- [ ] **Step 3: Update the inventory.** For each reworded rule: `- [x] <agent> R<n>: "<old>" → "<new quote, verbatim from the new body>"`. Rewording is the default. A rule is retired only when its subject no longer exists — the `status:`-line rules (architect R34, reviewer R11) and a never-write clause whose only object was a deleted file: `- [x] <agent> R<n>: "<old>" → retired: <what> no longer exists`. Append any new rule as `- [x] <agent> R<next>: "(new)" → "<quote>"` and update `RULES_COUNT` in `agent-surface.test.sh`.
- [ ] **Step 4: Descriptions.** Re-read each changed agent's `description:`: qa's ("writing a test plan and failing suite from acceptance criteria") becomes "writing the failing suite, with criterion markers, from the spec's acceptance criteria"; keep one line, ≤40 words, "Do NOT use" kept.
- [ ] **Step 5: Verify**

Run: `bash scripts/agent-surface.test.sh; bash scripts/rubric-drift.test.sh; bash scripts/lens-drift.test.sh`
Expected: `rubric-drift` and `lens-drift` green; `agent-surface` green on caps, descriptions and inventory, still red only on `no retired layout names`, and only for files Tasks 10–11 own (workflows, hook/script comments, docs). `/usr/bin/grep -nE 'acceptance\.md|TEST_PLAN\.md|SKILL_MANIFEST\.md|`test-plan`' agents/*.md skills/review-rubric/SKILL.md` prints nothing. If an agent is over its cap, first cut narration (never a rule); raise the cap only with a named reason in the test.

- [ ] **Step 6: Commit**

```bash
git add agents skills/review-rubric docs/history/2026-10-16-lean-agents-RULES.md scripts/agent-surface.test.sh
git commit -m "docs(agents): four-file layout, test markers, skill fields, findings-only review blocks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Workflow prose

**Files:**
- Modify: `workflows/plan-review.js`, `workflows/diagnose.js`, `workflows/deep-build.js` (prompts), `workflows/review.js` (any prose Task 6 left)

- [ ] **Step 1:** `/usr/bin/grep -nE 'acceptance\.md|TEST_PLAN|SKILL_MANIFEST|IMPL_NOTES' workflows/*.js` and edit: read lists name `spec.md` and `DECISIONS.md`; deep-build's skill instruction "If PROGRESS.md has `CODER_SKILLS` (`QA_SKILLS`), load and apply those skills"; IMPL_NOTES readers "if it exists"; diagnose.js's comment "not spec.md/acceptance.md" → "not spec.md".
- [ ] **Step 2: Verify**

Run: `node --check workflows/*.js && bash scripts/workflow-determinism-lint.sh workflows/*.js && bash scripts/workflow-parse.test.sh && /usr/bin/grep -nE 'acceptance\.md|TEST_PLAN\.md|SKILL_MANIFEST\.md' workflows/*.js`
Expected: checks pass; grep prints nothing.

- [ ] **Step 3: Commit**

```bash
git add workflows
git commit -m "docs(workflows): four-file layout in workflow prompts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Contract, README, CLAUDE.md, CHANGELOG, smoke, wiring — guard goes green

**Files:**
- Modify: `docs/v0.2/CONTRACT.md`, `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `docs/v0.5/smoke/smoke.sh`, `scripts/drift-wiring.test.sh`, `hooks/scripts/*.sh` and `scripts/*.sh` comments that still name retired files, `hooks/hooks.json` description

- [ ] **Step 1: Smoke.** In `smoke.sh`'s `[DRIFT]` section: the gated feature gets `SDD_SCHEMA: 2`, its criteria in `spec.md`'s `## Acceptance Criteria`, and markers `# <slug>/AC-1` in the test file instead of a TEST_PLAN; the "gate fails" step removes one marker and expects `untested`. Add a `[LAYOUT]` assertion: after the smoke's `new-feature`-equivalent scaffold, `.sdd/<slug>/` contains no `acceptance.md`, `TEST_PLAN.md`, `SKILL_MANIFEST.md`.
- [ ] **Step 2: `drift-wiring.test.sh`** — replace TEST_PLAN/matrix wording assertions with the marker wording now in `implement.md` and `qa.md` (`<slug>/AC-`).
- [ ] **Step 3: Docs.**
  - `CONTRACT.md`: remove `status` from the review envelope; layout section = four files.
  - `README.md`: skills 7 → 6 (drop `test-plan`), the `.sdd/` layout, the drift-gate paragraph (markers, default on, `TEST_ROOTS`), budgets in lines.
  - `CLAUDE.md`: `skills/  # 6 skills: sdd-protocol (+references/), adr, review-rubric, sdd-spec-template, sdd-diagnosis-template, skill-routing`.
  - `CHANGELOG.md` under `[Unreleased] — 0.12.0 (lite)`: a **Changed** entry (four files per feature; test markers; findings-only review blocks; `SPEC_MAX_LINES`; drift gate on by default; skill fields) and a **Removed** entry (`acceptance.md`, `TEST_PLAN.md`, `SKILL_MANIFEST.md`, the `test-plan` skill, `SPEC_MAX_KB`, the review `status:` line), and a **Compatibility** line: "`SDD_SCHEMA: 2` for forward features. Breaking: a forward feature started before 0.12.0 is refused (`unsupported-schema`) — park it and start it again; `drift-gate.sh --all` reports it unchecked. Bug lane and product tier unchanged (schema 1)."
  - Comments in `hooks/scripts/*.sh`, `scripts/*.sh`, `hooks/hooks.json` naming retired files: reword.
- [ ] **Step 4: Verify the guard is green**

Run: `bash scripts/agent-surface.test.sh && bash scripts/run-tests.sh > <scratch>/t11.log 2>&1; tail -3 <scratch>/t11.log`
Expected: `agent-surface` `failed=0`; the full suite green (count = previous 48 suites, same count — no suite added or removed).

- [ ] **Step 5: Commit**

```bash
git add -A docs/v0.2 README.md CLAUDE.md CHANGELOG.md docs/v0.5/smoke scripts hooks
git commit -m "docs: four-file layout in contract, README, changelog; smoke and wiring on markers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Live runs, review regression, net lines

**Files:**
- Create: `docs/history/2026-10-16-four-files-EVAL.md`

- [ ] **Step 1: Fresh scratch repo.** `rm -rf /tmp/bf-four && mkdir /tmp/bf-four && cd /tmp/bf-four && git init -q`; a tiny Python package `calc.py` with `add`, `tests/test_calc.py`, `pytest` available. Run the lite flow headless:

```bash
cd /tmp/bf-four && env -u ANTHROPIC_API_KEY claude -p "/build-fleet:start add a multiply(a, b) function to calc" \
  --plugin-dir ~/build-fleet-0.12 --add-dir ~/build-fleet-0.12 --allowedTools=Read,Write,Edit,Bash,Grep,Glob,Skill,Task,Workflow
```

then `/build-fleet:build`, then `/build-fleet:ship`, the same way.
Expected (record each in the EVAL note): after start, `.sdd/<slug>/` = `spec.md` (with `## Acceptance Criteria`), `PROGRESS.md` (`SDD_SCHEMA: 2`, `SPEC_MAX_LINES`), `DECISIONS.md`, `REVIEW.md` (no `status:` lines); no retired file at any point; after build, `tests/` carries `<slug>/AC-n` markers for every criterion and `drift-gate.sh <slug>` passes; `IMPL_NOTES.md` exists only if something was written; ship completes.
- [ ] **Step 2: Planted missing marker.** Delete one marker line from the tests and run `bash ~/build-fleet-0.12/scripts/drift-gate.sh <slug>` and `--all`. Expected: `"reasons":["untested"]` naming that criterion; `--all` exits 2.
- [ ] **Step 3: Review regression.** Convert the csv-import planted-defect fixture used by part D (`/tmp/bf-lean-after`, or recreate from `docs/history/2026-10-16-lean-agents-EVAL.md`) to the four-file layout: fold its `acceptance.md` into `spec.md`'s `## Acceptance Criteria`, delete `acceptance.md`, set `SDD_SCHEMA: 2`. Run `/build-fleet:review` on it. Expected: D1 (AC-2/AC-3 contradiction), D2 (missing file), D3 (AC-4 untestable) all found, as in the part D baseline.
- [ ] **Step 4: Net lines.**

```bash
cd ~/build-fleet-0.12 && base=$(git log --format=%H -1 --grep='four files per feature — design' ) && \
git diff --numstat "$base"..HEAD -- agents commands skills workflows hooks scripts \
  | /usr/bin/grep -v '\.test\.sh' | awk '{a+=$1; d+=$2} END {print "added", a, "deleted", d, "net", a-d}'
```

Expected: net negative. Record the numbers in the EVAL note and the CHANGELOG entry.
- [ ] **Step 5: Commit**

```bash
git add docs/history/2026-10-16-four-files-EVAL.md CHANGELOG.md
git commit -m "docs(eval): four files per feature — live run, marker gate, review regression, net lines

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
