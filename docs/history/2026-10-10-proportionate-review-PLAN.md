# Proportionate Review (v0.10.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scale build-fleet's review effort to stakes — a classifier risk axis, tier-by-risk seeding of the review roster and budget, severity-calibrated review lenses, and a deterministic CHANGE_REVIEW gate with the v0.9 convergence rules — shipped as one additive v0.10.0 release, with the two-role versus three-role measurement on tap as the release gate.

**Architecture:** The classifier gains `risk` + `risk_reasons`; `new-feature` writes `RISK:` and rewrites `REVIEW_ROLES` / `REVIEW_CYCLE_BUDGET` from a tier-by-risk table (review.js is untouched except its `LENS` block — its roster floor of 2, the finalize gate and the rotation script already read the roster). The three review lenses move to the calibration `agents/reviewer.md` already states. CHANGE_REVIEW stays on Task reviewers but becomes two-stage (qa + product-owner, then architect) and exits on a new `scripts/change-review-gate.sh` that applies the finalize rule to `## Change-Cycle N` blocks, with ids, `disposition:` lines, closed-by-id and demotion of new majors at cycle ≥ 2. Everything is additive to the `.sdd/` schema (`SDD_SCHEMA` stays 1).

**Tech Stack:** bash 3.2 + GNU/BSD coreutils + jq (the gate script and its harness); plain JavaScript executed by the Claude Code Workflow runtime (the `LENS` block only — no `Date`, no filesystem); markdown agent / command / skill / docs files.

**Spec:** `docs/history/2026-10-10-proportionate-review.md` — read it first; every task cites the section it implements. Evidence: `docs/history/2026-10-10-orchestration-balance-research.md`.

## Global Constraints

- **Work in the release worktree only:** `~/build-fleet-0.10` on branch `release/0.10.0` (Task 1 creates it). Never edit `~/build-fleet` — tap sessions run from it via `--plugin-dir`, and Task 1's measurement depends on it staying at v0.9.0 until the merge. All paths below are relative to `~/build-fleet-0.10` unless they start with `~/Projects/tap`.
- **Tests first for the gate:** write the harness, run it red, write the script, run it green, run `bash scripts/run-tests.sh`, then commit. Baseline before this plan: `failed: 0` (note the `suites:` count on your first run; it goes up by exactly one when Task 2 lands).
- **Gate scripts fail closed** (CLAUDE.md): a finding the script cannot classify reads as OPEN; deliberate passes are explicit `exit 0`; unreadable workspace is `exit 1`, never a silent pass.
- **bash 3.2 + GNU-coreutils compatible**: no associative arrays, no `mapfile`, no `${var,,}`; in scripts never `sed -i` without a suffix. The harness runs on macOS (bash 3.2) and in CI's Linux job.
- **Workflows:** after the `LENS` edit run the wrapped parse check (Task 7 step 5 — a bare `node --check` rejects the file's legal top-level `return`) and `bash scripts/workflow-determinism-lint.sh workflows/review.js`.
- **Lenses are double-maintained:** each role's `## Review lens` bullets and the matching `LENS.<role>` string in `workflows/review.js` must be identical after whitespace normalisation; `scripts/lens-drift.test.sh` must stay green.
- **Severity table is quadruple-maintained:** never edit the `| Severity |` table text anywhere; `scripts/rubric-drift.test.sh` must stay green.
- **Any agent whose body changes gets a refreshed `description:`** (classifier, architect, qa, coder, product-owner). The exact new descriptions are in Tasks 4, 5 and 7.
- **Signal lines are the machine contract:** new line `BUILD_FLEET_CHANGE_REVIEW_GATE` (Task 2), new line `BUILD_FLEET_REVIEW_DEFAULTS` and new fields `risk`, `risk_reasons` on `BUILD_FLEET_CLASSIFICATION` and `risk_assigned` on `BUILD_FLEET_CLASSIFIER_FALLBACK` (Task 6); new fallback reason `risk-tier-conflict`. Never document an exit-code table.
- **No milestone jargon in user-facing text:** command bodies and agent prompts say what happens, never "v0.10" or "since 0.10". Version names belong in CHANGELOG, ROADMAP and `docs/`.
- **Commit messages** end with:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  ```
- **The verified drafts.** The gate script and its harness in Task 2 were run before this plan was written (31 cases, 0 failures, bash 3.2); the three lens texts in Task 7 were applied to a scratch copy and passed `lens-drift.test.sh`, the wrapped parse check and the determinism lint. Copy them verbatim.

## Review Focus

Inputs the spec implies but did not enumerate, most likely to bite first. Each has its test in the owning task.

1. **A product-owner finding id** (`product-owner-cc2-1`, a role name with a hyphen) must be demoted at change cycle 2 like any other; a regex that stops at the first hyphen would leave it open and bounce the feature. → Task 2 harness `hyphenated-role-id-demoted`.
2. **A blank line between a major and its `disposition:` line** (hand-wrapped by a human reviewer) ends the continuation run; the major must read OPEN, never silently closed. → Task 2 harness `blank-line-ends-run-fails-closed`.
3. **REVIEW.md absent** when handoff runs the gate (a scaffold that was never reviewed) must refuse with every role missing, not crash with an unreadable error. → Task 2 harness `no-review-file-refuses`.
4. **DECISIONS.md absent** while a major cites an ADR must read `majors-without-adr`, not pass. → Task 2 harness `no-decisions-file-refuses`.
5. **A classifier verdict that lacks `risk`** (an older cached agent body, or the model dropping the field) must take the fallback — `standard` + `elevated`, the historical roster — never a `low` default. → Task 6 step 3 (the fallback rule names `risk` as a required field) and Task 9 step 1's third preview, which must show `risk` present.

---

## File structure

| Path | Responsibility | Task |
|---|---|---|
| `docs/history/2026-10-10-proportionate-review-MEASUREMENT.md` (new) | The two-role vs three-role measurement record; its table is copied into the CHANGELOG | 1 |
| `scripts/change-review-gate.test.sh` (new) | Harness: 31 fixture cases for the gate | 2 |
| `scripts/change-review-gate.sh` (new) | Deterministic CHANGE_REVIEW gate: rubric rule over `## Change-Cycle N` blocks, two passes, closed-by-id, demotion | 2 |
| `commands/handoff.md` | PHASE HANDOFF resume; gate-based budget guard; two-stage fan-out; gate-based exit; refusal reasons | 3 |
| `agents/architect.md`, `agents/qa.md`, `agents/product-owner.md` | `## During CHANGE_REVIEW` sections: heading family, id grammar, `disposition:`, delta rule, architect's ADR-first closed-by-id; descriptions | 4 |
| `agents/classifier.md` | Risk axis: `risk`, `risk_reasons`, reason vocabulary, rules, cost asymmetry; description | 5 |
| `commands/new-feature.md` | Parse `risk`; coercion of trivial+elevated; `RISK:`; tier-by-risk seeding; `BUILD_FLEET_REVIEW_DEFAULTS`; user report | 6 |
| `commands/dispatch.md`, `commands/status.md` | Preview prints risk + would-seed roster; status prints TIER/RISK/roster and the change-review gate rule | 6 |
| `agents/architect.md`, `agents/qa.md`, `agents/coder.md`, `workflows/review.js` | Lens calibration (both copies); coder description | 7 |
| `skills/sdd-protocol/SKILL.md`, `skills/review-rubric/SKILL.md`, `README.md`, `docs/loops.md`, `docs/v0.2/CONTRACT.md`, `docs/PILOT.md` | Documentation of record | 8 |
| `CHANGELOG.md`, `.claude-plugin/plugin.json` | 0.10.0 entry with measurement + previews; version + description | 9 |

Tasks 2 to 5 do not depend on Task 1's result and may be implemented while the tap run executes. **Task 6 waits for Task 1**: its seeding table carries the row the measurement decides.

---

### Task 1: The release worktree, and the measurement that fixes the `standard` + `low` row (spec §5 step 1, §6, D9, D10)

**Files:**
- Create: `docs/history/2026-10-10-proportionate-review-MEASUREMENT.md`
- Read/modify (tap, Ray's repo): `~/Projects/tap/.sdd/fixture-and-harness/{PROGRESS.md,REVIEW.md,DECISIONS.md}`

**Interfaces:**
- Consumes: the uncommitted three-role cycle 1 already in tap's working tree (2026-09-06, v0.9.0).
- Produces: `MEASUREMENT.md` with the decision `KEEP two-role row` or `REVERT to three roles`, which Task 6 step 4 reads to fill the table, and whose table Task 9 copies into the CHANGELOG.

- [ ] **Step 1: Create the worktree and record the baseline**

```bash
cd ~/build-fleet && git worktree add ~/build-fleet-0.10 -b release/0.10.0
cd ~/build-fleet-0.10 && bash scripts/run-tests.sh | tail -3
```
Expected: last line `suites: <N>, failed: 0`. Write `<N>` down; Task 2 expects `<N>+1`.

- [ ] **Step 2: Copy the three-role arm aside (it is the uncommitted working tree)**

```bash
cd ~/Projects/tap
git status --short .sdd/fixture-and-harness        # expect: M DECISIONS.md, M PROGRESS.md, M REVIEW.md, ?? REVIEW-archive.md
mkdir -p ~/tap-measurement && cp -R .sdd/fixture-and-harness ~/tap-measurement/three-role
grep -c '^## Cycle 1 — ' ~/tap-measurement/three-role/REVIEW.md   # expect: 3
```

- [ ] **Step 3: Reconstruct the state the 2026-09-06 run started from, guarded**

Run this exactly; it aborts before changing anything if an anchor is not where the spec says.

```bash
(
cd ~/Projects/tap/.sdd/fixture-and-harness
r=$(grep -n '^## Cycle 1 — architect — 2026-09-06' REVIEW.md | head -1 | cut -d: -f1)
d=$(grep -n '^## ADR-7:' DECISIONS.md | head -1 | cut -d: -f1)
[ -n "$r" ] && [ -n "$d" ] || { echo "anchors not found; stop"; exit 1; }
[ "$(sed -n "$((r-1))p" REVIEW.md)" = "" ] || echo "note: line before Cycle 1 is not blank (fine)"
sed -i.bak "${r},\$d" REVIEW.md && sed -i.bak "${d},\$d" DECISIONS.md
sed -i.bak -e 's/^CYCLE: 1$/CYCLE: 0/' -e 's/^CYCLE_TOTAL: 6$/CYCLE_TOTAL: 5/' -e '/^LAST_REVIEW_OUTPUT_TOKENS:/d' PROGRESS.md
rm -f REVIEW.md.bak DECISIONS.md.bak PROGRESS.md.bak
grep -c '^## Cycle 1 — ' REVIEW.md; grep -c '^## ADR-7:' DECISIONS.md   # expect: 0 and 0
grep -E '^(CYCLE|CYCLE_TOTAL|CYCLE_TOTAL_MAX|REVIEW_ROLES|REVIEW_CYCLE_BUDGET|LAST_REVIEW_OUTPUT_TOKENS):' PROGRESS.md
)
```
The subshell keeps a failed anchor check from closing your shell. Expected last block: `CYCLE: 0`, `CYCLE_TOTAL: 5`, `CYCLE_TOTAL_MAX: 7`, `REVIEW_ROLES: architect, qa, coder`, `REVIEW_CYCLE_BUDGET: 3`, and no `LAST_REVIEW_OUTPUT_TOKENS` line. `REVIEW-archive.md` stays as is: reviewers never read it, so its presence does not change their inputs. One known small difference: the rotation at dispatch will run with `--roster 2` and archive one more legacy block (`## Cycle 2 — qa`) than the three-role run saw; legacy blocks cannot be re-raised by id, so this is noise, and it is recorded in step 6.

- [ ] **Step 3b: Check tap's local cycle-total guard before spending a run**

tap carries its own hooks in `~/Projects/tap/.claude/hooks/` (`cycle-total-cap.sh`,
`spec-size-cap.sh`, registered in `.claude/settings.json`) and a sidecar
`.sdd/fixture-and-harness/.cycle-total`. On 2026-09-02 that guard refused the scribe's
recording write after a full cycle's tokens were spent, so confirm it cannot fire here:

```bash
cat ~/Projects/tap/.sdd/fixture-and-harness/.cycle-total          # expect: 5 — matches the reconstructed CYCLE_TOTAL: 5
grep -E '^CYCLE_TOTAL_MAX:' ~/Projects/tap/.sdd/fixture-and-harness/PROGRESS.md   # expect: 7 — one cycle of headroom (5 + 1 < 7)
```
If the sidecar does not read `5`, write `5` into it (`printf '5' > …/.cycle-total`). This is
the same state the 2026-09-06 run started from and that run recorded cleanly. If the
guard still refuses the recording write during step 4, the fallback is to remove the
`cycle-total-cap.sh` entry from `~/Projects/tap/.claude/settings.json` for the run and
restore it afterwards; whichever you did goes into MEASUREMENT.md's Confounds.

- [ ] **Step 4: Run the two-role arm against main at v0.9.0**

In a **new** Claude Code session in tap, started with the main tree as the plugin (`cd ~/Projects/tap && claude --plugin-dir ~/build-fleet`), run:

```
/build-fleet:review --roles architect,qa --cycle-budget 2
```
Record from the command's output: the `BUILD_FLEET_REVIEW_CONFIG` line (must show `"roles":["architect","qa"]`, `"roles_source":"flag"`) and the wall-clock time of the `BUILD_FLEET_WORKFLOW_LAUNCHED` line. Wait for completion (`/workflows` shows progress). Record the completion time and the run's return object: `verdict`, `finalize_ready`, `open_majors`, `adrs_written`, `output_tokens`.

- [ ] **Step 5: Count the agents and the cross-examination yield**

Agents: count the workflow's agent labels in `/workflows` (or the transcript): `review:architect`, `review:qa`, `cross-exam:architect`, `cross-exam:qa`, `disposition:architect` (only if majors survived), `scribe`. Expected 5 or 6. Then:

```bash
cd ~/Projects/tap/.sdd/fixture-and-harness
grep -c '^## Cycle 1 — ' REVIEW.md                      # expect 2
awk '/^## Cycle 1 — /{f=1} f' REVIEW.md | grep -E '^- \[(blocker|major)\] ' > ~/tap-measurement/two-role-findings.txt
awk '/^## Cycle 1 — /{f=1} f' REVIEW.md | grep -c '^  refuted-by:'   # refutations that discarded a concern
awk '/^## Cycle 1 — /{f=1} f' ~/tap-measurement/three-role/REVIEW.md | grep -E '^- \[(blocker|major)\] ' > ~/tap-measurement/three-role-findings.txt
awk '/^## Cycle 1 — /{f=1} f' ~/tap-measurement/three-role/REVIEW.md | grep -c '^  refuted-by:'
```
Compare `two-role-findings.txt` and `three-role-findings.txt` **by content**, not by id: for each `[blocker]` or `disposition: fix` major in the three-role file, decide whether the two-role file raised the same defect under any id.

- [ ] **Step 6: Write the measurement record**

Create `~/build-fleet-0.10/docs/history/2026-10-10-proportionate-review-MEASUREMENT.md`:

```markdown
# Proportionate review — the two-role measurement

**Date run:** <date of step 4>  **Spec:** 2026-10-10-proportionate-review.md §6 (D9)
**Feature:** tap `fixture-and-harness`, cycle 1 from the reconstructed pre-run state.
**Plugin:** main at v0.9.0 for both arms (the roster is the only plugin-side difference).

| Arm | Roster | Agents | Wall-clock | output_tokens | Surviving blockers | Surviving `fix` majors | Refutations that discarded a concern |
|---|---|---|---|---|---|---|---|
| three-role (2026-09-06) | architect, qa, coder | 8 | 26.6 min | 274,075 | 0 | 9 | <from step 5> |
| two-role (<date>) | architect, qa | <5 or 6> | <min> | <n> | <n> | <n> | <n> |

## Findings the two-role arm lacked

<For each blocker or fix major in three-role-findings.txt with no content match in
two-role-findings.txt: the id, one line of its text, and Ray's call: real / not real.>

## Confounds

- One month of model drift between the arms.
- The rotation at dispatch ran with --roster 2 and archived one more legacy block
  (`## Cycle 2 — qa`); legacy blocks cannot be re-raised by id.

## Decision

<KEEP: the standard + low row seeds architect, qa with budget 2.
 or REVERT: the two-role arm lacked a real finding; the standard + low row seeds
 architect, qa, coder with budget 3. The risk axis and the seeding mechanism still ship.>
```
Fill every `<…>` from steps 4 and 5 before committing; the file must contain no angle-bracket fields when Task 9 copies it.

- [ ] **Step 7: Put the arm Ray continues from back into tap**

If continuing from the two-role arm, first (the flag was not persisted):
```bash
cd ~/Projects/tap/.sdd/fixture-and-harness
sed -i.bak -e 's/^REVIEW_ROLES: .*/REVIEW_ROLES: architect, qa/' -e 's/^REVIEW_CYCLE_BUDGET: .*/REVIEW_CYCLE_BUDGET: 2/' PROGRESS.md && rm -f PROGRESS.md.bak
```
If continuing from the three-role arm: `rm -rf ~/Projects/tap/.sdd/fixture-and-harness && cp -R ~/tap-measurement/three-role ~/Projects/tap/.sdd/fixture-and-harness`. tap's commits are Ray's; leave them to him.

- [ ] **Step 8: Commit the record**

```bash
cd ~/build-fleet-0.10
git add docs/history/2026-10-10-proportionate-review-MEASUREMENT.md
git commit -m "docs(measurement): two-role vs three-role review on tap fixture-and-harness

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: The deterministic CHANGE_REVIEW gate, test first (spec §3.5, §6, D6, D7)

**Files:**
- Create: `scripts/change-review-gate.test.sh`
- Create: `scripts/change-review-gate.sh`

**Interfaces:**
- Consumes: `.sdd/<slug>/PROGRESS.md` (`CHANGE_CYCLE`), `REVIEW.md` (`## Change-Cycle <N> — <role> — <iso>` blocks), `DECISIONS.md` (`## ADR-N:` headings). `CLAUDE_PROJECT_DIR` or the cwd as the project root.
- Produces: `bash scripts/change-review-gate.sh <slug> [--roster a,b,c]` → one stdout line `BUILD_FLEET_CHANGE_REVIEW_GATE: {"feature","change_cycle","pass","reasons":[],"open_blockers":[],"open_majors":[],"majors_without_adr":[],"demoted":[]}`; exit 0 pass / 2 refuse / 1 bad usage. `reasons` ⊆ {`missing-<role>`, `open-blockers`, `majors-open`, `majors-without-adr`}. Task 3 (handoff) calls it twice; Task 6 (status) narrates its rule.

- [ ] **Step 1: Write the harness**

Create `scripts/change-review-gate.test.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# Tests for scripts/change-review-gate.sh (rubric-only CHANGE_REVIEW gate). Builds a
# fixture workspace per case, asserts the BUILD_FLEET_CHANGE_REVIEW_GATE line + exit code.
# Run: bash scripts/change-review-gate.test.sh   (exit 0 = all pass)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$DIR/change-review-gate.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass=0; fail=0

# new_proj <name> <change_cycle> → fixture with feature 'feat' at CHANGE_CYCLE <n>
new_proj() {
  local p="$work/$1"
  mkdir -p "$p/.sdd/feat"
  printf 'PHASE: CHANGE_REVIEW\nCYCLE: 2\nCHANGE_CYCLE: %s\n' "$2" > "$p/.sdd/feat/PROGRESS.md"
  printf '# Architecture Decisions — feat\n\n## ADR-4: accept x\n\n- **Status:** accepted\n' > "$p/.sdd/feat/DECISIONS.md"
  printf '# Review Log — feat\n\nAppend-only.\n\n' > "$p/.sdd/feat/REVIEW.md"
  printf '%s' "$p"
}
# cblock <proj> <change_cycle> <role> <body-lines…>   (em-dash heading, the scribe/agent default)
cblock() { local p="$1" c="$2" r="$3"; shift 3; { printf '## Change-Cycle %s — %s — 2026-10-12T00:00:00Z\n' "$c" "$r"; for l in "$@"; do printf '%s\n' "$l"; done; printf 'status: concerns-raised\n\n'; } >> "$p/.sdd/feat/REVIEW.md"; }
# dblock <proj> <dash> <change_cycle> <role> <body-lines…>   (explicit dash variant)
dblock() { local p="$1" d="$2" c="$3" r="$4"; shift 4; { printf '## Change-Cycle %s %s %s %s 2026-10-12T00:00:00Z\n' "$c" "$d" "$r" "$d"; for l in "$@"; do printf '%s\n' "$l"; done; printf 'status: approved\n\n'; } >> "$p/.sdd/feat/REVIEW.md"; }
# sblock <proj> <cycle> <role> <body-lines…>   (a SPEC-review block, must never match)
sblock() { local p="$1" c="$2" r="$3"; shift 3; { printf '## Cycle %s — %s — 2026-10-12T00:00:00Z\n' "$c" "$r"; for l in "$@"; do printf '%s\n' "$l"; done; printf 'status: concerns-raised\n\n'; } >> "$p/.sdd/feat/REVIEW.md"; }
run() { out=$( cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$GATE" feat 2>/dev/null ); rc=$?; }
assert() { local name="$1" cond="$2"; if eval "$cond"; then pass=$((pass+1)); printf 'ok   %-48s\n' "$name"; else fail=$((fail+1)); printf 'FAIL %-48s (%s) out=%s\n' "$name" "$cond" "${out:-}"; fi; }

# --- pass: zero findings in all three roster blocks ---
p=$(new_proj zero 1); cblock "$p" 1 product-owner; cblock "$p" 1 qa; cblock "$p" 1 architect
run "$p"
assert "zero-findings-pass-rc0" "[ $rc -eq 0 ]"
assert "zero-findings-line" "printf '%s' \"\$out\" | grep -q '^BUILD_FLEET_CHANGE_REVIEW_GATE: {\"feature\":\"feat\",\"change_cycle\":1,\"pass\":true,\"reasons\":\\[\\]'"

# --- refuse: open blocker ---
p=$(new_proj blk 1); cblock "$p" 1 product-owner '- [blocker] (product-owner-cc1-1) AC-3 not met'; cblock "$p" 1 qa; cblock "$p" 1 architect
run "$p"
assert "blocker-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q open-blockers"

# --- refuse: fix major open, id listed ---
p=$(new_proj fix 1); cblock "$p" 1 product-owner; cblock "$p" 1 qa '- [major] (qa-cc1-1) failure path untested' '  disposition: fix'; cblock "$p" 1 architect
run "$p"
assert "fix-major-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q majors-open"
assert "fix-major-id-listed" "printf '%s' \"\$out\" | grep -q '\"open_majors\":\\[\"qa-cc1-1\"\\]'"

# --- pass: architect's own major accepted by an existing ADR ---
p=$(new_proj adr 1); cblock "$p" 1 product-owner; cblock "$p" 1 qa; cblock "$p" 1 architect '- [major] (architect-cc1-1) trade-off' '  disposition: adr ADR-4'
run "$p"
assert "adr-major-passes" "[ $rc -eq 0 ]"

# --- refuse: adr disposition citing an ADR that does not exist ---
p=$(new_proj noadr 1); cblock "$p" 1 product-owner; cblock "$p" 1 qa; cblock "$p" 1 architect '- [major] (architect-cc1-1) x' '  disposition: adr ADR-9'
run "$p"
assert "missing-adr-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q majors-without-adr"
assert "missing-adr-id-listed" "printf '%s' \"\$out\" | grep -q '\"majors_without_adr\":\\[\"architect-cc1-1\"\\]'"

# --- refuse: a roster role has no current-cycle block ---
p=$(new_proj miss 2); cblock "$p" 1 architect; cblock "$p" 2 product-owner; cblock "$p" 2 qa
run "$p"
assert "missing-role-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q missing-architect"

# --- pass: closed-by-id — qa's fix major is re-listed by the architect with an ADR ---
p=$(new_proj closedbyid 1)
cblock "$p" 1 product-owner
cblock "$p" 1 qa '- [major] (qa-cc1-2) retries not covered' '  disposition: fix'
cblock "$p" 1 architect '- [major] (qa-cc1-2) retries not covered: accepted, no retry path by design' '  disposition: adr ADR-4'
run "$p"
assert "closed-by-id-passes" "[ $rc -eq 0 ]"
assert "closed-by-id-open-majors-empty" "printf '%s' \"\$out\" | grep -q '\"open_majors\":\\[\\]'"

# --- pass + demoted: a NEW major at change cycle 2 (id originates at cycle 2) is advisory ---
p=$(new_proj demote 2); cblock "$p" 2 product-owner; cblock "$p" 2 qa '- [major] (qa-cc2-1) new maintainability nit in the fix' '  disposition: fix'; cblock "$p" 2 architect
run "$p"
assert "new-major-cycle2-passes" "[ $rc -eq 0 ]"
assert "new-major-cycle2-demoted-listed" "printf '%s' \"\$out\" | grep -q '\"demoted\":\\[\"qa-cc2-1\"\\]'"

# --- refuse: a RE-RAISED cycle-1 major at change cycle 2 stays open ---
p=$(new_proj reraise 2); cblock "$p" 2 product-owner; cblock "$p" 2 qa '- [major] (qa-cc1-1) still untested' '  disposition: fix'; cblock "$p" 2 architect
run "$p"
assert "reraised-major-cycle2-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q '\"open_majors\":\\[\"qa-cc1-1\"\\]'"

# --- refuse: a NEW blocker at change cycle 2 is never demoted ---
p=$(new_proj blk2 2); cblock "$p" 2 product-owner; cblock "$p" 2 qa '- [blocker] (qa-cc2-1) AC-7 test missing'; cblock "$p" 2 architect
run "$p"
assert "new-blocker-cycle2-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q open-blockers"

# --- no demotion at cycle 1 (K == 1 but cycle < 2) ---
p=$(new_proj nodemote1 1); cblock "$p" 1 product-owner; cblock "$p" 1 qa '- [major] (qa-cc1-1) x' '  disposition: fix'; cblock "$p" 1 architect
run "$p"
assert "cycle1-major-not-demoted" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q '\"demoted\":\\[\\]'"

# --- refuse: legacy block, no ids, undispositioned major is open ---
p=$(new_proj legacy 1); cblock "$p" 1 product-owner; cblock "$p" 1 qa '- [major] legacy text without id or disposition'; cblock "$p" 1 architect
run "$p"
assert "legacy-undispositioned-major-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q majors-open"

# --- pass: refuted-by continuation closes a blocker and a major (parity with finalize-gate) ---
p=$(new_proj refuted 1)
cblock "$p" 1 product-owner '- [blocker] (product-owner-cc1-1) refuted' '  refuted-by: architect — reason: AC-3 is satisfied by tests/test_x.py::test_ac3'
cblock "$p" 1 qa '- [major] (qa-cc1-1) refuted' '  refuted-by: architect — reason: covered by tests/test_y.py'
cblock "$p" 1 architect
run "$p"
assert "refuted-by-closes" "[ $rc -eq 0 ]"

# --- heading dash variants: en-dash, hyphen, em-dash all match ---
p=$(new_proj dashes 1); dblock "$p" '–' 1 product-owner; dblock "$p" '-' 1 qa; dblock "$p" '—' 1 architect
run "$p"
assert "dash-variants-match" "[ $rc -eq 0 ]"

# --- a same-numbered SPEC-review block with an open blocker is ignored ---
p=$(new_proj specblock 1); sblock "$p" 1 architect '- [blocker] (architect-c1-1) spec-review blocker, closed history'; cblock "$p" 1 product-owner; cblock "$p" 1 qa; cblock "$p" 1 architect
run "$p"
assert "spec-review-block-ignored" "[ $rc -eq 0 ]"

# --- status lines are ignored: concerns-raised with nothing open passes (covered above); approved with an open blocker still fails ---
p=$(new_proj status 1); dblock "$p" '—' 1 product-owner '- [blocker] (product-owner-cc1-1) approved-but-open'; cblock "$p" 1 qa; cblock "$p" 1 architect
run "$p"
assert "approved-status-not-trusted" "[ $rc -eq 2 ]"

# --- last block per role wins ---
p=$(new_proj last 1); cblock "$p" 1 product-owner; cblock "$p" 1 qa '- [blocker] (qa-cc1-1) early'; cblock "$p" 1 architect; cblock "$p" 1 qa
run "$p"
assert "last-block-per-role-wins" "[ $rc -eq 0 ]"

# --- roster override flag ---
p=$(new_proj roster 1); cblock "$p" 1 architect; cblock "$p" 1 qa
out=$( cd "$p" && CLAUDE_PROJECT_DIR="$p" bash "$GATE" feat --roster architect,qa 2>/dev/null ); rc=$?
assert "roster-flag-two-roles-pass" "[ $rc -eq 0 ]"

# --- bad input: non-integer CHANGE_CYCLE → exit 1 ---
p=$(new_proj badcycle 1); printf 'PHASE: CHANGE_REVIEW\nCHANGE_CYCLE: two\n' > "$p/.sdd/feat/PROGRESS.md"
run "$p"
assert "non-integer-cycle-exit-1" "[ $rc -eq 1 ]"

# --- bad input: missing PROGRESS → exit 1; flag-looking slug → exit 1 ---
p="$work/noprog"; mkdir -p "$p/.sdd/feat"
run "$p"
assert "no-progress-exit-1" "[ $rc -eq 1 ]"
out=$( bash "$GATE" --roster architect,qa 2>/dev/null ); rc=$?
assert "dash-slug-exit-1" "[ $rc -eq 1 ]"

# --- review focus: a product-owner id (role name with a hyphen) is demoted at cycle 2 like any other ---
p=$(new_proj poid 2); cblock "$p" 2 product-owner '- [major] (product-owner-cc2-1) wording of AC-9 could be tighter' '  disposition: fix'; cblock "$p" 2 qa; cblock "$p" 2 architect
run "$p"
assert "hyphenated-role-id-demoted" "[ $rc -eq 0 ] && printf '%s' \"\$out\" | grep -q '\"demoted\":\\[\"product-owner-cc2-1\"\\]'"

# --- review focus: a blank line between a major and its disposition ends the run; the major reads OPEN (fails closed) ---
p=$(new_proj blank 1); cblock "$p" 1 product-owner; cblock "$p" 1 qa; cblock "$p" 1 architect '- [major] (architect-cc1-1) x' '' '  disposition: adr ADR-4'
run "$p"
assert "blank-line-ends-run-fails-closed" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q majors-open"

# --- review focus: REVIEW.md absent → every role missing, exit 2, no crash ---
p=$(new_proj noreview 1); rm "$p/.sdd/feat/REVIEW.md"
run "$p"
assert "no-review-file-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q missing-architect && printf '%s' \"\$out\" | grep -q missing-qa"

# --- review focus: DECISIONS.md absent while a major cites an ADR → majors-without-adr ---
p=$(new_proj nodecisions 1); rm "$p/.sdd/feat/DECISIONS.md"; cblock "$p" 1 product-owner; cblock "$p" 1 qa; cblock "$p" 1 architect '- [major] (architect-cc1-1) x' '  disposition: adr ADR-4'
run "$p"
assert "no-decisions-file-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q majors-without-adr"

# --- review focus: CRLF PROGRESS.md still parses CHANGE_CYCLE ---
p=$(new_proj crlf 1); printf 'PHASE: CHANGE_REVIEW\r\nCHANGE_CYCLE: 1\r\n' > "$p/.sdd/feat/PROGRESS.md"; cblock "$p" 1 product-owner; cblock "$p" 1 qa; cblock "$p" 1 architect
run "$p"
assert "crlf-progress-parses" "[ $rc -eq 0 ]"

echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it red**

```bash
chmod +x scripts/change-review-gate.test.sh && bash scripts/change-review-gate.test.sh | tail -3
```
Expected: every case `FAIL` (the script does not exist, so `run` captures rc 127 and empty output), final line `passed=0 failed=31`, exit 1.

- [ ] **Step 3: Write the gate**

Create `scripts/change-review-gate.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# scripts/change-review-gate.sh — the deterministic CHANGE_REVIEW gate (rubric-only).
#
# /build-fleet:handoff calls this instead of evaluating REVIEW.md in prose, so the
# exit rule is testable and the budget guard and the post-review evaluation can
# never disagree.
#
# Rule, over the CURRENT change cycle's blocks (the LAST block per roster role whose
# heading is "## Change-Cycle <CHANGE_CYCLE> — <role> —"; a same-numbered spec-review
# "## Cycle <N>" block never matches):
#   - every roster role has a block                        else missing-<role>
#   - zero UNREFUTED "- [blocker]" lines                    else open-blockers
#   - every "- [major]" line is closed:
#       "  refuted-by: …"            in its continuation run  → closed
#       "  disposition: adr ADR-N"   in its run, ADR-N present in DECISIONS.md → closed
#       "  disposition: adr ADR-N"   in its run, ADR-N absent → majors-without-adr
#       id "<role>-cc<K>-<n>" with K == CHANGE_CYCLE and CHANGE_CYCLE >= 2 → DEMOTED
#                                    (a new major on a delta cycle is advisory; reported,
#                                     never blocks)
#       otherwise ("disposition: fix" or no disposition line)  → OPEN → majors-open
#   Two passes. Pass one records every major's state per id across all roster blocks.
#   Pass two resolves per id: an id closed by an ADR in ANY block is closed in every
#   block (the architect may accept a peer's major by re-listing its id with an ADR).
#   The continuation run is the indented lines after a finding; it ends at the first
#   line that is not indented ("- [", "status:", "## ", a blank line, or EOF).
#   `status:` lines are NOT evaluated.
#
# Usage: change-review-gate.sh <slug> [--roster a,b,c]
#   ROSTER defaults to architect,product-owner,qa (the CHANGE_REVIEW roster; there is
#   no PROGRESS field for it).
# Output (stdout, exactly one line):
#   BUILD_FLEET_CHANGE_REVIEW_GATE: {"feature","change_cycle","pass":bool,"reasons":[…],"open_blockers":[…],"open_majors":[…],"majors_without_adr":[…],"demoted":[…]}
# Exit: 0 = pass; 2 = refuse; 1 = bad usage / unreadable workspace.
# bash 3.2 + BSD/GNU compatible; read-only. Requires jq for JSON string escaping.
set -uo pipefail

slug="${1:-}"
[ -n "$slug" ] || { echo "usage: change-review-gate.sh <slug> [--roster a,b,c]" >&2; exit 1; }
case "$slug" in */*|..|.|-*) echo "change-review-gate.sh: bad slug '$slug'" >&2; exit 1 ;; esac
shift
roster_arg=""
if [ "${1:-}" = "--roster" ]; then roster_arg="${2:-}"; fi
command -v jq >/dev/null 2>&1 || { echo "change-review-gate.sh: jq is required" >&2; exit 1; }

cd "${CLAUDE_PROJECT_DIR:-.}"
dir=".sdd/${slug}"
progress="${dir}/PROGRESS.md"; review="${dir}/REVIEW.md"; decisions="${dir}/DECISIONS.md"
[ -f "$progress" ] || { echo "change-review-gate.sh: ${progress} not found" >&2; exit 1; }

field() { { grep -m1 "^$1:" "$progress" 2>/dev/null || true; } | sed -E "s/^$1:[[:space:]]*//" | tr -d '\r '; }
cycle=$(field CHANGE_CYCLE)
case "$cycle" in ''|*[!0-9]*) echo "change-review-gate.sh: CHANGE_CYCLE is not an integer ('${cycle}')" >&2; exit 1 ;; esac

roster="$roster_arg"
[ -n "$roster" ] || roster="architect,product-owner,qa"
roles=$(printf '%s' "$roster" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep . || true)

reasons=""; open_blockers=""; records=""
add() { eval "$1=\"\${$1}\${$1:+\$'\\n'}\$2\""; }

# ---- pass one: scan every roster block, record blockers and per-id major states ----
for role in $roles; do
  [ -f "$review" ] || { add reasons "missing-${role}"; continue; }
  start=$({ grep -nE "^##[[:space:]]+Change-Cycle[[:space:]]+${cycle}[[:space:]]+[—–-][[:space:]]+${role}[[:space:]]+[—–-]" "$review" || true; } | tail -1 | cut -d: -f1)
  if [ -z "$start" ]; then add reasons "missing-${role}"; continue; fi
  next=$({ tail -n +"$((start+1))" "$review" | grep -n '^## ' || true; } | head -1 | cut -d: -f1)
  if [ -n "$next" ]; then end=$((start+next-1)); else end=$(wc -l < "$review" | tr -d ' '); fi
  block=$(sed -n "${start},${end}p" "$review")

  n=$(printf '%s\n' "$block" | wc -l | tr -d ' ')
  k=1
  while [ $k -le $n ]; do
    line=$(printf '%s\n' "$block" | sed -n "${k}p")
    if printf '%s' "$line" | grep -qE '^-[[:space:]]+\[blocker\]'; then
      refuted=false
      j=$((k+1))
      while [ $j -le $n ]; do
        contl=$(printf '%s\n' "$block" | sed -n "${j}p")
        printf '%s' "$contl" | grep -qE '^[[:space:]]+' || break
        if printf '%s' "$contl" | grep -qE '^[[:space:]]+refuted-by:'; then refuted=true; break; fi
        j=$((j+1))
      done
      [ "$refuted" = true ] || add open_blockers "$line"
    elif printf '%s' "$line" | grep -qE '^-[[:space:]]+\[major\]'; then
      id=$(printf '%s' "$line" | sed -nE 's/^-[[:space:]]+\[major\][[:space:]]+\(([^)]+)\).*/\1/p')
      [ -n "$id" ] || id="$line"
      state="open"
      j=$((k+1))
      while [ $j -le $n ]; do
        contl=$(printf '%s\n' "$block" | sed -n "${j}p")
        printf '%s' "$contl" | grep -qE '^[[:space:]]+' || break
        if printf '%s' "$contl" | grep -qE '^[[:space:]]+refuted-by:'; then
          state="refuted"; break
        elif printf '%s' "$contl" | grep -qE '^[[:space:]]+disposition:[[:space:]]+adr[[:space:]]+ADR-0*[0-9]+'; then
          adr=$(printf '%s' "$contl" | sed -nE 's/.*ADR-0*([0-9]+).*/\1/p')
          if [ -f "$decisions" ] && grep -qE "^##[[:space:]]+ADR-0*${adr}:" "$decisions"; then state="adr-ok"; else state="adr-missing"; fi
          break
        fi
        j=$((j+1))
      done
      # delta rule: a major whose id ORIGINATES at this cycle (K == CHANGE_CYCLE >= 2)
      # is advisory. Blockers are never demoted; re-raised ids (K < cycle) stay open.
      if [ "$state" = "open" ] && [ "$cycle" -ge 2 ]; then
        korig=$(printf '%s' "$id" | sed -nE 's/^[a-z-]+-cc0*([0-9]+)-[0-9]+$/\1/p')
        if [ -n "$korig" ] && [ "$korig" -eq "$cycle" ]; then state="demoted"; fi
      fi
      add records "${state}"$'\t'"${id}"
    fi
    k=$((k+1))
  done
done

# ---- pass two: resolve per id (adr-ok anywhere wins; then adr-missing; then demoted; then open) ----
open_majors=""; without_adr=""; demoted=""
ids=$(printf '%s\n' "$records" | grep . | cut -f2- | awk '!seen[$0]++' || true)
if [ -n "$ids" ]; then
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    states=$(printf '%s\n' "$records" | awk -F'\t' -v want="$id" 'substr($0, length($1)+2) == want { print $1 }')
    if printf '%s\n' "$states" | grep -qx 'adr-ok'; then :
    elif printf '%s\n' "$states" | grep -qx 'adr-missing'; then add without_adr "$id"
    elif printf '%s\n' "$states" | grep -qx 'demoted'; then add demoted "$id"
    elif printf '%s\n' "$states" | grep -qx 'open'; then add open_majors "$id"
    fi
  done <<EOF_IDS
$ids
EOF_IDS
fi

[ -z "$open_blockers" ] || add reasons "open-blockers"
[ -z "$open_majors" ] || add reasons "majors-open"
[ -z "$without_adr" ] || add reasons "majors-without-adr"

tojson() { if [ -z "$1" ]; then printf '[]'; else printf '%s\n' "$1" | jq -R . | jq -sc .; fi; }
pass=true; [ -z "$reasons" ] || pass=false
slug_json=$(jq -n --arg s "$slug" '$s')
printf 'BUILD_FLEET_CHANGE_REVIEW_GATE: {"feature":%s,"change_cycle":%s,"pass":%s,"reasons":%s,"open_blockers":%s,"open_majors":%s,"majors_without_adr":%s,"demoted":%s}\n' \
  "$slug_json" "$cycle" "$pass" "$(tojson "$reasons")" "$(tojson "$open_blockers")" "$(tojson "$open_majors")" "$(tojson "$without_adr")" "$(tojson "$demoted")"
[ "$pass" = true ] && exit 0 || exit 2
```

- [ ] **Step 4: Run it green, then the whole suite**

```bash
chmod +x scripts/change-review-gate.sh
bash scripts/change-review-gate.test.sh | tail -2      # expect: passed=31 failed=0
bash scripts/finalize-gate.test.sh | tail -1            # unchanged, still green
bash scripts/run-tests.sh | tail -1                     # expect: suites: <N+1>, failed: 0
```

- [ ] **Step 5: Commit**

```bash
git add scripts/change-review-gate.sh scripts/change-review-gate.test.sh
git commit -m "feat(handoff): deterministic CHANGE_REVIEW gate — rubric rule over Change-Cycle blocks, closed-by-id, delta demotion

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: `commands/handoff.md` — resume at HANDOFF, gate-based guard and exit, two-stage fan-out (spec §3.6)

**Files:**
- Modify: `commands/handoff.md` (steps 2, 5, 7, 8; the Refusal cases list)

**Interfaces:**
- Consumes: `scripts/change-review-gate.sh` from Task 2 (its line, its `open_blockers` / `open_majors` arrays, exit 0/2).
- Produces: the orchestrator behaviour Task 4's agent sections and Task 8's docs describe. No new files.

- [ ] **Step 1: Step 2 accepts `PHASE: HANDOFF` as a resume**

Replace step 2 in full. Old:

```markdown
2. **Check phase.** Read PROGRESS.md. PHASE must be `BUILD` or
   `CHANGE_REVIEW`. If it's anything else (especially `SPEC` or `REVIEW`),
   refuse and tell the user to run `/build-fleet:finalize` then
   `/build-fleet:build` first.
```
New:

```markdown
2. **Check phase.** Read PROGRESS.md. PHASE must be `BUILD`, `CHANGE_REVIEW`
   or `HANDOFF`. If it's anything else (especially `SPEC` or `REVIEW`), refuse
   and tell the user to run `/build-fleet:finalize` then `/build-fleet:build`
   first. **`PHASE: HANDOFF` is a resume**: a previous run passed CHANGE_REVIEW
   and reached devops, and devops refused or failed (step 9 leaves `PHASE:
   HANDOFF` in that case). Run the gate to confirm the current change cycle
   still passes —
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/change-review-gate.sh" "<slug>"` — and
   on `"pass":true` skip straight to step 9. On `"pass":false` the workspace was
   edited by hand since; continue at step 3 as a normal run.
```

- [ ] **Step 2: Step 5 uses the gate, and the exhausting cycle's escalation lives in step 8**

Replace step 5 in full. Old:

```markdown
5. **Check the change-cycle budget.** Read `CHANGE_CYCLE:` from PROGRESS.md.
   The budget is 3 change-review cycles. If `CHANGE_CYCLE >= 3` AND the most
   recent CHANGE_REVIEW cycle in REVIEW.md still has open `[blocker]` items,
   the budget is exhausted with blockers surviving → write `ESCALATION.md`
   with the change-cycle context and unresolved blockers, set
   `PHASE: ESCALATED`, stop.
```
New:

````markdown
5. **Check the change-cycle budget.** Read `CHANGE_CYCLE:` from PROGRESS.md.
   The budget is 3 change-review cycles. If `CHANGE_CYCLE >= 3`, run the gate
   over the current cycle — never evaluate REVIEW.md in prose:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/change-review-gate.sh" "<slug>"
   ```
   Relay its `BUILD_FLEET_CHANGE_REVIEW_GATE:` line. On `"pass":true` the
   current cycle already passed (a previous run stopped before devops): skip to
   step 9. On `"pass":false` the budget is exhausted with findings open: write
   `ESCALATION.md` with the change-cycle context and the gate line's
   `open_blockers` and `open_majors` (both listed, verbatim), set
   `PHASE: ESCALATED`, stop. This guard exists for a workspace whose third cycle
   was recorded before the gate existed and bounced without escalating; a run
   that reaches step 8 on the exhausting cycle escalates there directly.
````

- [ ] **Step 3: Step 7 becomes two-stage with the finding grammar in every prompt**

Replace step 7 in full. Old: the step beginning `7. **Fan out CHANGE_REVIEW reviewers.** Use the Task tool to launch` and ending `... so they never collide in one REVIEW.md and the `check-review-written` hook enforces the right block).**`. New:

```markdown
7. **Run CHANGE_REVIEW in two stages.** The reviewers are `build-fleet:product-owner`,
   `build-fleet:qa` and `build-fleet:architect`. **Stage one:** launch product-owner
   and qa in parallel (two Task calls in a single message) and wait for both
   `## Change-Cycle <CHANGE_CYCLE>` blocks to exist in REVIEW.md. **Stage two:**
   launch the architect alone, pointing it at those two fresh blocks. The
   architect runs last so it can accept a peer's major by ADR in this same cycle
   (closed-by-id, below) instead of after a coder bounce. Agent count is
   unchanged; the cycle takes roughly one architect run longer.

   Every prompt includes:
   - The active feature slug and the current CHANGE_CYCLE number.
   - A pointer to the diff (the orchestrator runs `git diff` against the
     base if a git repo; otherwise describe the changed files).
   - A pointer to `spec.md`, `acceptance.md`, `DECISIONS.md`, `IMPL_NOTES.md`,
     `TEST_PLAN.md`.
   - The reviewer-specific lens:
     - architect: design adherence + ADR compliance.
     - product-owner: meets `acceptance.md`?
     - qa: coverage gaps before handoff.
   - The REVIEW.md entry format and severity rubric reminder. **CHANGE_REVIEW
     blocks are headed `## Change-Cycle <CHANGE_CYCLE> — <role> — <iso8601>`**
     (distinct from spec-review's `## Cycle N`, so they never collide in one
     REVIEW.md and the `check-review-written` hook enforces the right block).
   - **The finding grammar the gate reads.** Every finding carries a stable id
     `(<role>-cc<K>-<n>)` where `K` is the change cycle it was FIRST raised in; a
     re-raised finding keeps its id. Every `[major]` carries a continuation line
     `  disposition: fix` (the default — coder must close it) or
     `  disposition: adr ADR-N` (architect only, after appending ADR-N to
     DECISIONS.md). `status:` is informational; the gate ignores it.
   - **When `CHANGE_CYCLE >= 2`, the delta rule**, with a pointer to the previous
     cycle's `## Change-Cycle <CHANGE_CYCLE-1>` blocks: verify closure of your own
     prior blockers and `fix` majors against the new diff and re-raise by original
     id what is still open; new findings are `[blocker]` only, plus advisory
     `[minor]`s. A new `[major]` raised at this cycle is advisory — the gate
     reports it as demoted and it does not block.
   - **Architect only — closed-by-id.** Read the product-owner and qa blocks for
     this cycle (and, from cycle 2, the previous cycle's). For each open `fix`
     major that is a design trade-off rather than a defect: append the ADR to
     `DECISIONS.md` first, then list the peer's id under your own block with
     `  disposition: adr ADR-N`. The gate closes that id in every block. A defect
     stays `fix`.
```

- [ ] **Step 4: Step 8 evaluates with the gate**

Replace step 8 in full. Old: the step beginning `8. **Evaluate the cycle.** Once all three` and ending `CHANGE_REVIEW passes. Continue to step 9.`. New:

````markdown
8. **Evaluate the cycle with the gate.** Once the three `## Change-Cycle <CHANGE_CYCLE>`
   blocks exist, run — never evaluate REVIEW.md in prose:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/change-review-gate.sh" "<slug>"
   ```
   Relay its `BUILD_FLEET_CHANGE_REVIEW_GATE:` line verbatim. The rule is the
   rubric's: every roster role has a current-cycle block; zero unrefuted
   `[blocker]`s; every `[major]` closed by `disposition: adr ADR-N` (ADR present) or
   demoted as a new major on a delta cycle. `status:` lines are never evaluated.
   - `"pass":true` → CHANGE_REVIEW passes. Continue to step 9.
   - `"pass":false` and `CHANGE_CYCLE < 3` → delegate to `build-fleet:coder` with
     exactly the line's `open_blockers` and `open_majors` (ids and text) and a
     pointer to the blocks that raised them (PHASE returns to `BUILD`). Do not
     auto-loop; tell the user BUILD is open again and to re-run
     `/build-fleet:handoff` once coder is done. The `CHANGE_CYCLE` counter
     persists. **STOP here — do NOT continue to steps 9–12.** The feature is not
     shipped; `.sdd/ACTIVE` stays set.
   - `"pass":false` and `CHANGE_CYCLE >= 3` → the exhausting cycle escalates: write
     `ESCALATION.md` with the change-cycle context and the line's `open_blockers`
     and `open_majors` (both listed, verbatim), set `PHASE: ESCALATED`, stop.
   - `"demoted"` non-empty → mention the demoted ids to the user as advisory; they
     never block.
````

- [ ] **Step 5: Refusal cases name the gate's reasons**

Replace the final list. Old:

```markdown
- `CHANGE_CYCLE` budget exhausted with open blockers → write ESCALATION.md
  and stop.
```
New:

```markdown
- `CHANGE_CYCLE` budget exhausted with the gate failing (`open-blockers`,
  `majors-open` or `majors-without-adr` in its `reasons`) → write ESCALATION.md
  and stop.
- Gate failing below the budget → bounce to BUILD (not a refusal: coder is
  dispatched, the user re-runs handoff).
```

- [ ] **Step 6: Verify the old exit rule is gone and the gate is wired**

```bash
grep -c 'change-review-gate.sh' commands/handoff.md        # expect: 3 (steps 2, 5, 8)
grep -n 'all three are\|status: approved` with zero' commands/handoff.md   # expect: none (the old exit rule is gone)
grep -n 'three Task calls' commands/handoff.md             # expect: none
```

- [ ] **Step 7: Commit**

```bash
git add commands/handoff.md
git commit -m "feat(handoff): CHANGE_REVIEW exits on the gate, two-stage fan-out, resume at HANDOFF

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: The role agents in CHANGE_REVIEW — grammar, delta rule, architect's closed-by-id, descriptions (spec §3.7)

**Files:**
- Modify: `agents/architect.md` (frontmatter `description:`; `## During CHANGE_REVIEW`)
- Modify: `agents/qa.md` (frontmatter `description:`; the closing paragraph of `## During CHANGE_REVIEW`)
- Modify: `agents/product-owner.md` (frontmatter `description:`; `## During CHANGE_REVIEW`)

**Interfaces:**
- Consumes: the finding grammar the gate reads (Task 2) and the two-stage dispatch (Task 3).
- Produces: agent bodies whose `## During CHANGE_REVIEW` sections match Task 3's prompts word for word on grammar, so an agent dispatched directly behaves like one dispatched by handoff.

- [ ] **Step 1: `agents/architect.md` — description and CHANGE_REVIEW section**

Replace the `description:` line (line 3) with:

```yaml
description: Use this agent when reviewing code diffs for design soundness, scalability, failure modes, data integrity, security, and blast radius, and when authoring ADRs — the architect leg of /build-fleet:handoff (it runs after qa and product-owner and dispositions their open majors by ADR or fix), direct review invocations, and plan interrogation in /build-fleet:plan-review. Inside /build-fleet:review its severity-calibrated lens runs on the read-only reviewer agent instead. At the product tier (/build-fleet:new-product) it ratifies or infers the stack-of-record and records product ADRs. In the bug lane it refutes the root-cause hypothesis during /build-fleet:diagnose and reviews fix blast radius during /build-fleet:verify. Never writes source.
```

Replace the `## During CHANGE_REVIEW` section. Old:

```markdown
## During CHANGE_REVIEW

Your specific job: **design adherence + ADR compliance**. Walk the diff
against every ADR. If the diff introduces a new design decision not yet
recorded, append a new ADR before approving. If the diff contradicts an
existing ADR without justification, that's a `[blocker]`.
```
New:

````markdown
## During CHANGE_REVIEW

Your specific job: **design adherence + ADR compliance**. Walk the diff
against every ADR. If the diff introduces a new design decision not yet
recorded, append a new ADR before approving. If the diff contradicts an
existing ADR without justification, that's a `[blocker]`.

**You run last.** `/build-fleet:handoff` dispatches product-owner and qa first
and you after them, so their `## Change-Cycle <N>` blocks exist when you start.
Read them. The gate (`scripts/change-review-gate.sh`) closes a `[major]` only by
an ADR or by refutation, and an ADR in any block closes that id in every block —
so you are the one who can accept a peer's trade-off in this cycle:

- For each open `fix` major in a peer's block that is a design trade-off rather
  than a defect: append the ADR to `DECISIONS.md` **first**, then list the peer's
  id under your own block with `  disposition: adr ADR-N`. A defect stays `fix`
  for coder.
- Your own majors carry `  disposition: fix` or `  disposition: adr ADR-N` the
  same way.

Your block is headed `## Change-Cycle <N> — architect — <iso8601>`; every finding
carries a stable id `(architect-cc<K>-<n>)` where `K` is the change cycle it was
first raised in (a re-raised finding keeps its id):

```
## Change-Cycle 2 — architect — 2026-10-12T09:41:07Z
- [blocker] (architect-cc2-1) <text>
- [major] (qa-cc1-3) <qa's text>: accepted — <why it is a trade-off>
  disposition: adr ADR-5
- [major] (architect-cc1-2) <text, re-raised: still open>
  disposition: fix
- [minor] (architect-cc2-2) <text>
status: concerns-raised
```

**From change cycle 2, review the delta.** Verify closure of your own prior
blockers and `fix` majors against the new diff and re-raise by original id what
is still open. New findings are `[blocker]` only, plus advisory `[minor]`s; a new
`[major]` at this cycle is advisory (the gate reports it as demoted).
````

- [ ] **Step 2: `agents/qa.md` — description and the CHANGE_REVIEW closing paragraph**

Replace the `description:` line (line 3) with:

```yaml
description: Use this agent when designing or writing tests against acceptance.md (TEST_PLAN.md + the failing suite, before coder runs), or reviewing the diff for coverage gaps and running the counterfactual during /build-fleet:handoff (it runs in the first stage, before the architect; its majors carry disposition fix). Inside /build-fleet:review its severity-calibrated testability lens runs on the read-only reviewer agent instead. In the bug lane it authors the failing reproduction test for /build-fleet:reproduce and runs the revert-counterfactual for /build-fleet:verify. Do NOT use for implementing source, authoring specs, or writing ADRs.
```

In `## During CHANGE_REVIEW`, replace the closing paragraph. Old:

```markdown
Append your CHANGE_REVIEW block to REVIEW.md with severity-tagged items
and a final `status:` line. Approve only when coverage is complete.
```
New:

````markdown
Append your CHANGE_REVIEW block to REVIEW.md, headed
`## Change-Cycle <N> — qa — <iso8601>`, with severity-tagged items and a final
`status:` line. Every finding carries a stable id `(qa-cc<K>-<n>)` where `K` is the
change cycle it was first raised in; a re-raised finding keeps its id. Every
`[major]` carries the continuation `  disposition: fix` — you never write ADRs; the
architect, who runs after you, may accept a trade-off by listing your id with an
ADR. `status:` is informational: the gate (`scripts/change-review-gate.sh`) reads
blockers and dispositions.

```
## Change-Cycle 1 — qa — 2026-10-12T09:20:03Z
- [blocker] (qa-cc1-1) AC-7 has no test: <file + what is missing>
- [major] (qa-cc1-2) failure path <x> untested
  disposition: fix
status: concerns-raised
```

**From change cycle 2, review the delta.** Verify closure of your own prior
blockers and `fix` majors against the new diff and re-raise by original id what
is still open. New findings are `[blocker]` only, plus advisory `[minor]`s; a new
`[major]` at this cycle is advisory (the gate reports it as demoted).
````

- [ ] **Step 3: `agents/product-owner.md` — description and CHANGE_REVIEW section**

Replace the `description:` line (line 3) with:

```yaml
description: Use this agent when authoring a feature spec + acceptance criteria within the feature's size budget (/build-fleet:new-feature), closing the open blockers and fix-dispositioned majors of a review cycle (/build-fleet:revise), or signing off the change against acceptance.md at CHANGE_REVIEW (the PO leg of /build-fleet:handoff — first stage, before the architect; its majors carry disposition fix). At the product tier it authors the walking-skeleton vision and phased backlog (/build-fleet:new-product) and interrogates the plan in /build-fleet:plan-review. Never writes source, tests, or ADRs.
```

Replace the `## During CHANGE_REVIEW` section. Old:

```markdown
## During CHANGE_REVIEW

`/build-fleet:handoff` puts you alongside architect and qa against the
diff. Your specific job: **does the implementation meet `acceptance.md`?**
Walk every criterion, point at the code that satisfies it, and flag
anything missing. Append your block to `REVIEW.md` under
`## Cycle <N> — product-owner — <iso8601>` with severity-tagged items and
a final `status:` line.
```
New:

````markdown
## During CHANGE_REVIEW

`/build-fleet:handoff` dispatches you alongside qa in the first stage, before
the architect, against the diff. Your specific job: **does the implementation
meet `acceptance.md`?** Walk every criterion, point at the code that satisfies
it, and flag anything missing. Append your block to `REVIEW.md` under
`## Change-Cycle <N> — product-owner — <iso8601>` (the change-review heading
family — a `## Cycle N` heading here is rejected by the `check-review-written`
hook) with severity-tagged items and a final `status:` line. Every finding
carries a stable id `(product-owner-cc<K>-<n>)` where `K` is the change cycle it
was first raised in; a re-raised finding keeps its id. Every `[major]` carries the
continuation `  disposition: fix` — you never write ADRs; the architect, who runs
after you, may accept a trade-off by listing your id with an ADR. `status:` is
informational: the gate (`scripts/change-review-gate.sh`) reads blockers and
dispositions.

```
## Change-Cycle 1 — product-owner — 2026-10-12T09:20:03Z
- [blocker] (product-owner-cc1-1) AC-3 not met: <what the code does instead>
- [major] (product-owner-cc1-2) AC-9 met only for the happy path
  disposition: fix
status: concerns-raised
```

**From change cycle 2, review the delta.** Verify closure of your own prior
blockers and `fix` majors against the new diff and re-raise by original id what
is still open. New findings are `[blocker]` only, plus advisory `[minor]`s; a new
`[major]` at this cycle is advisory (the gate reports it as demoted).
````

- [ ] **Step 4: Drift tests stay green**

```bash
bash scripts/rubric-drift.test.sh | tail -1    # the severity tables were not touched
bash scripts/lens-drift.test.sh | tail -1      # the lens sections were not touched (Task 7 does that)
grep -n '## Cycle <N> — product-owner' agents/product-owner.md   # expect: none
```

- [ ] **Step 5: Commit**

```bash
git add agents/architect.md agents/qa.md agents/product-owner.md
git commit -m "feat(agents): CHANGE_REVIEW finding grammar, delta rule, architect closed-by-id; descriptions

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: The classifier's risk axis (spec §3.1, D1, D3, D4)

**Files:**
- Modify: `agents/classifier.md` (frontmatter `description:`; `### trivial` disqualifiers; new `## Risk` section; verdict JSON + rules; `## On being wrong`; `## Hard rules`)

**Interfaces:**
- Produces: the tier verdict gains `"risk": "low"|"elevated"` and `"risk_reasons": [<slug>…]` with the fixed vocabulary `auth`, `secrets`, `billing`, `data-migration`, `ci-release`, `new-dependency`, `review-requested`, `irreversible`, `public-contract`, `shared-module`. Rules: `elevated` ⇒ non-empty reasons and `tier ≠ trivial`; `low` ⇒ `[]`. Task 6 parses these; bug mode is unchanged.

- [ ] **Step 1: Description**

Replace the `description:` line (line 3) with:

```yaml
description: Use this agent when a feature request needs sizing and risk-rating — it classifies trivial / standard / large to set TIER + BUILD_MODE, and rates risk low / elevated (with reason slugs: reversibility, blast radius, the never-trivial list) to set RISK and seed the review roster, during /build-fleet:new-feature; previews both for /build-fleet:dispatch; and emits the skill manifest. Also runs in bug mode for /build-fleet:triage, emitting {severity, cause_known} for the troubleshoot-fix lane. Never modifies state — it emits a JSON verdict only. Do NOT use to draft specs or route work yourself.
```

- [ ] **Step 2: Elevated risk is a trivial disqualifier**

In `### trivial`, replace the disqualifier list. Old:

```markdown
Disqualifiers (force tier=standard even if trivial criteria fire):
- Touches authentication, authorization, secrets handling, billing, or data migrations — never trivial.
- Touches CI/CD, build config, or release tooling — never trivial.
- Introduces a new external dependency.
- The user explicitly asked for review ("can you have someone look at this?").
```
New:

```markdown
Disqualifiers (force tier=standard even if trivial criteria fire):
- Touches authentication, authorization, secrets handling, billing, or data migrations — never trivial (risk reasons `auth`, `secrets`, `billing`, `data-migration`).
- Touches CI/CD, build config, or release tooling — never trivial (`ci-release`).
- Introduces a new external dependency (`new-dependency`).
- The user explicitly asked for review ("can you have someone look at this?") (`review-requested`).
- **Any risk reason fires** (see "Risk" below): `risk=elevated` is never `trivial`.
```

- [ ] **Step 3: The risk section**

Insert this section immediately before `## What you do`:

```markdown
## Risk

Risk is a second axis, independent of size: a ten-line change to an auth check is
`standard` + `elevated`; a forty-file refactor behind a feature flag can be `large`
+ `low`. The orchestrator seeds the review roster and cycle budget from TIER and
RISK together, so this call decides how many reviewers the spec gets.

`risk` is `elevated` when at least one reason fires; `risk_reasons` lists the slugs
that fired (fixed vocabulary — emit these exact strings and nothing else):

| Group | Slug | Fires when |
|---|---|---|
| Never-trivial | `auth` | authentication or authorization logic changes |
| | `secrets` | secrets handling, key material, credential storage |
| | `billing` | payment, invoicing, pricing or entitlement logic |
| | `data-migration` | a schema migration or a backfill of persisted data |
| | `ci-release` | CI/CD, build config or release tooling |
| | `new-dependency` | a new external dependency is introduced |
| | `review-requested` | the user explicitly asked for review |
| Irreversibility | `irreversible` | the change deletes or transforms persisted data, or has external side effects that cannot be undone (sends, charges, third-party writes) |
| Blast radius | `public-contract` | a public API, wire format or storage format other code or systems depend on changes |
| | `shared-module` | a module imported across most of the repo changes behaviour |

Rules:
- `risk=elevated` ⇒ `risk_reasons` is non-empty and `tier` is not `trivial`.
- `risk=low` ⇒ `risk_reasons` is `[]`. Risk is low when no reason fires. Do not
  elevate on a hunch: name the reason or leave it low.
- `confidence` covers both axes.
```

- [ ] **Step 4: The verdict shape and its rules**

In `## What you do` step 4, replace the JSON block and the rules. Old JSON block ends with `"skill_manifest": null` and the rules list ends with the `skill_manifest` bullet. New JSON block:

```json
{
  "tier": "trivial|standard|large",
  "rationale": "<one paragraph: which criteria fired, which disqualifiers cleared, which risk reasons fired>",
  "skip_review": true|false,
  "build_mode": "standard|deep-build",
  "skeleton_spec_hint": "<for tier=trivial: a 3-5 sentence spec PO can use directly; null for standard/large>",
  "confidence": "high|medium|low",
  "skill_manifest": null,
  "risk": "low|elevated",
  "risk_reasons": []
}
```
Append two bullets to the rules list:

```markdown
   - `risk=elevated` → `risk_reasons` non-empty (slugs from the Risk table only) AND `tier` ≠ `trivial`.
   - `risk=low` → `risk_reasons=[]`.
```

- [ ] **Step 5: Cost asymmetry and hard rules**

Append to `## On being wrong`:

````markdown
The same asymmetry governs risk, and it is milder: a false `low` costs one
reviewer lens on a change that is still cross-examined, refuted by citation and
gated; a false `elevated` costs roughly three extra agent invocations. So name a
reason when one fires and otherwise leave risk low — but never let `low` pull a
disqualified change down to `trivial`.
```
In `## Hard rules`, replace the two fallback bullets with:

```markdown
- If you cannot read the project at all (no files exist yet), default to `standard` with `confidence=low` and rationale "no project context available", `skill_manifest=null`, `risk=low`, `risk_reasons=[]`.
- If the description is empty or nonsensical, default to `standard` with `confidence=low` and a rationale calling out the ambiguity, `skill_manifest=null`, `risk=low`, `risk_reasons=[]`.
````
(The orchestrator's own parse-failure fallback is `elevated`; the classifier's in-band low-confidence default stays `low` because `standard` + `low` still reviews with two roles and the finalize gate.)

- [ ] **Step 6: Verify**

```bash
grep -c '"risk"' agents/classifier.md            # expect: ≥ 1 (the JSON block)
grep -c 'risk_reasons' agents/classifier.md      # expect: ≥ 5
grep -n '^## Risk' agents/classifier.md          # expect: one heading, before "## What you do"
bash scripts/rubric-drift.test.sh | tail -1      # classifier carries no rubric table; still green
```

- [ ] **Step 7: Commit**

```bash
git add agents/classifier.md
git commit -m "feat(classifier): risk axis — low/elevated with reason slugs; elevated is never trivial

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: `new-feature` seeds by tier and risk; `dispatch` and `status` show it (spec §3.2, D2, D3)

**Waits for Task 1.** Step 4's table carries the row the measurement decided.

**Files:**
- Modify: `commands/new-feature.md` (step 3 PROGRESS block + paragraph; step 6 parse, fallback, signal; step 7; step 9)
- Modify: `commands/dispatch.md` (steps 3, 4, 5; Examples)
- Modify: `commands/status.md` (steps 2, 4)

**Interfaces:**
- Consumes: the classifier verdict fields `risk`, `risk_reasons` (Task 5); `MEASUREMENT.md`'s Decision (Task 1); the gate rule (Task 2) for status's narration.
- Produces: PROGRESS field `RISK: low | elevated | pending`; `REVIEW_ROLES` / `REVIEW_CYCLE_BUDGET` rewritten per the table; signal line `BUILD_FLEET_REVIEW_DEFAULTS: {"feature","tier","risk","roles":[…],"cycle_budget":n}`; `BUILD_FLEET_CLASSIFICATION` gains `"risk"`, `"risk_reasons"`; `BUILD_FLEET_CLASSIFIER_FALLBACK` gains `"risk_assigned":"elevated"` and the reason `risk-tier-conflict`.

- [ ] **Step 1: `new-feature` step 3 — the scaffold carries `RISK: pending` and says what step 7 does**

In the PROGRESS block, insert `RISK: pending` directly after `BUILD_MODE: pending`. Then replace the paragraph that begins `The last three are **optional per-feature config**` up to and including `Leaving them as-is reproduces the historical behavior.` with:

```markdown
   `REVIEW_ROLES`, `REVIEW_CYCLE_BUDGET` and `BUILD_CYCLE_BUDGET` are **optional
   per-feature config**, seeded here at the historical defaults so a classifier
   fallback or an interrupted run still leaves a working feature. **Step 7 rewrites
   `REVIEW_ROLES` and `REVIEW_CYCLE_BUDGET` from the classifier's tier and risk**
   (table there); `RISK` is `pending` until then. They stay discoverable and
   editable: `REVIEW_ROLES` is the `/build-fleet:review` roster — a ≥2 subset of
   architect, qa, coder, product-owner; the budgets are escalation budgets, 1–3,
   clamped to the 3-cycle ceiling. A command flag overrides these per run; the
   workflow validates them and falls back to its own defaults if absent.
```

- [ ] **Step 2: `new-feature` step 6 — parse the two new fields**

Replace:
````markdown
   Parse the classifier's JSON verdict. Extract `tier`, `build_mode`, `skip_review`,
   `skeleton_spec_hint`, `confidence`, `skill_manifest` (may be `null`).
```
with:
```markdown
   Parse the classifier's JSON verdict. Extract `tier`, `build_mode`, `skip_review`,
   `skeleton_spec_hint`, `confidence`, `skill_manifest` (may be `null`), `risk`
   (`low` | `elevated`) and `risk_reasons` (an array of slugs; `[]` when `risk` is
   `low`). `risk` is a required field: a verdict without it takes the fallback below.
````

- [ ] **Step 3: `new-feature` step 6 — the fallback is `standard` + `elevated`, and a contradictory verdict is coerced**

Replace the fallback paragraph and its signal. Old:
````markdown
   **Parse-failure fallback.** If the classifier returns malformed JSON or omits
   any of the required fields above, do NOT write `undefined` to PROGRESS.md.
   Instead, default to `tier=standard` / `build_mode=standard` / `skip_review=false`
   and emit:

   ```
   BUILD_FLEET_CLASSIFIER_FALLBACK: {"feature":"<slug>","reason":"<parse-error|missing-field|empty-output>","tier_assigned":"standard"}
   ```
````
New:
````markdown
   **Parse-failure fallback.** If the classifier returns malformed JSON or omits
   any of the required fields above (including `risk`), do NOT write `undefined`
   to PROGRESS.md. Instead, default to `tier=standard` / `build_mode=standard` /
   `skip_review=false` / `risk=elevated` / `risk_reasons=[]` — the historical
   three-role review — and emit:

   ```
   BUILD_FLEET_CLASSIFIER_FALLBACK: {"feature":"<slug>","reason":"<parse-error|missing-field|empty-output>","tier_assigned":"standard","risk_assigned":"elevated"}
   ```

   **Risk–tier coercion.** The classifier's rule forbids `tier=trivial` with
   `risk=elevated`, but a verdict is model output. If it arrives anyway, do NOT
   let it reach the trivial fast-path: set `tier=standard`, `build_mode=standard`,
   `skip_review=false`, ignore `skeleton_spec_hint`, keep `risk=elevated` and its
   reasons, and emit (before the classification line):

   ```
   BUILD_FLEET_CLASSIFIER_FALLBACK: {"feature":"<slug>","reason":"risk-tier-conflict","tier_assigned":"standard","risk_assigned":"elevated"}
   ```
````
Then replace the classification signal line:
```
   BUILD_FLEET_CLASSIFICATION: {"feature":"<slug>","tier":"<...>","build_mode":"<...>","skip_review":<bool>,"confidence":"<...>"}
```
with:
```
   BUILD_FLEET_CLASSIFICATION: {"feature":"<slug>","tier":"<...>","build_mode":"<...>","skip_review":<bool>,"confidence":"<...>","risk":"<low|elevated>","risk_reasons":[<slugs>]}
```

- [ ] **Step 4: `new-feature` step 7 — write `RISK` and seed the roster and budget**

After the bullet `- `BUILD_MODE:` ← classifier's `build_mode` …` insert:

```markdown
   - `RISK:` ← classifier's `risk` (`low` or `elevated`; `elevated` after a fallback or a
     coercion).
   - **Review roster and budget by tier and risk.** Rewrite `REVIEW_ROLES:` and
     `REVIEW_CYCLE_BUDGET:` from this table (the step-3 defaults are the
     `elevated` row, so a fallback changes nothing):

     | TIER | RISK | REVIEW_ROLES | REVIEW_CYCLE_BUDGET |
     |---|---|---|---|
     | standard | low | <ROW-FROM-MEASUREMENT> | <BUDGET-FROM-MEASUREMENT> |
     | standard | elevated | architect, qa, coder | 3 |
     | large | low or elevated | architect, qa, coder | 3 |
     | trivial | low | architect, qa | 2 |

     Two full-lens reviewers still cross-examine each other and the finalize gate
     still applies; what a smaller roster drops is the third fan-out lens. The
     trivial row only matters if TIER is later edited by hand — REVIEW is skipped
     for trivial features. A human overrides by editing these two lines or by
     passing `--roles` / `--cycle-budget` to `/build-fleet:review` for one run.
     Then emit exactly one line:

     ```
     BUILD_FLEET_REVIEW_DEFAULTS: {"feature":"<slug>","tier":"<...>","risk":"<...>","roles":["..."],"cycle_budget":<n>}
     ```
```
Fill `<ROW-FROM-MEASUREMENT>` / `<BUDGET-FROM-MEASUREMENT>` from `docs/history/2026-10-10-proportionate-review-MEASUREMENT.md` § Decision: `architect, qa` / `2` on KEEP, `architect, qa, coder` / `3` on REVERT. The committed command text must contain the literal values, not the angle-bracket tokens.

- [ ] **Step 5: `new-feature` step 9 — tell the user what was seeded**

Append one sentence to both the **standard** and **large** report bullets:

```markdown
     Also say: "Review roster seeded `<REVIEW_ROLES>` with cycle budget `<REVIEW_CYCLE_BUDGET>`
     (TIER=<tier>, RISK=<risk>); edit PROGRESS.md or pass `--roles` / `--cycle-budget` to
     change it."
```

- [ ] **Step 6: `dispatch` previews risk and the would-seed roster**

In step 3 replace `(`tier`, `rationale`, `skip_review`, `build_mode`, `skeleton_spec_hint`, `confidence`, `skill_manifest`)` with `(`tier`, `rationale`, `skip_review`, `build_mode`, `skeleton_spec_hint`, `confidence`, `skill_manifest`, `risk`, `risk_reasons`)`. In step 4 replace the signal line with:

```
   BUILD_FLEET_CLASSIFICATION: {"tier":"<...>","build_mode":"<...>","skip_review":<bool>,"confidence":"<...>","risk":"<low|elevated>","risk_reasons":[<slugs>]}
```
In step 5, after the `Confidence level.` bullet insert:

```markdown
   - Risk with its reasons, and the review roster + cycle budget
     `/build-fleet:new-feature` would seed for this tier and risk (the table in
     `commands/new-feature.md` step 7). A `trivial` + `elevated` verdict is shown
     as what new-feature would coerce it to: `standard` + `elevated`.
```
Replace the three Examples lines with:

```
/build-fleet:dispatch "fix typo in README"
→ BUILD_FLEET_CLASSIFICATION: {"tier":"trivial","build_mode":"standard","skip_review":true,"confidence":"high","risk":"low","risk_reasons":[]}

/build-fleet:dispatch "add --shout flag to greet CLI"
→ BUILD_FLEET_CLASSIFICATION: {"tier":"standard","build_mode":"standard","skip_review":false,"confidence":"high","risk":"low","risk_reasons":[]}

/build-fleet:dispatch "rotate the API signing key and add a key-version header to every response"
→ BUILD_FLEET_CLASSIFICATION: {"tier":"standard","build_mode":"standard","skip_review":false,"confidence":"high","risk":"elevated","risk_reasons":["secrets","public-contract"]}

/build-fleet:dispatch "rewrite greet to support multiple languages with i18n loader and locale dispatch across cli, core, and api packages"
→ BUILD_FLEET_CLASSIFICATION: {"tier":"large","build_mode":"deep-build","skip_review":false,"confidence":"high","risk":"low","risk_reasons":[]}
```

- [ ] **Step 7: `status` prints the new fields and narrates the change-review gate**

In step 2, after `- PHASE.` insert:

```markdown
   - TIER and RISK (`pending` when the classifier has not run; absent RISK on a
     feature scaffolded before this field existed prints as `unset`).
   - REVIEW_ROLES and REVIEW_CYCLE_BUDGET (the seeded review roster and budget).
```
In step 4, after the `finalize_ready` bullet insert:

```markdown
   - `change_review_ready` (change-review territory only): yes iff the rule of
     `scripts/change-review-gate.sh` holds over the current `CHANGE_CYCLE` blocks —
     every roster role (architect, product-owner, qa) has a block, zero unrefuted
     `[blocker]` lines, and every `[major]` is closed by `disposition: adr ADR-N`
     with that ADR in DECISIONS.md (an architect ADR closes a peer's id in every
     block) or is a new major on cycle ≥ 2 (advisory, "demoted"). `status:` lines
     are not evaluated.
```

- [ ] **Step 8: Verify**

```bash
grep -c 'RISK' commands/new-feature.md                      # expect: ≥ 4
grep -c 'BUILD_FLEET_REVIEW_DEFAULTS' commands/new-feature.md   # expect: 1
grep -n '<ROW-FROM-MEASUREMENT>\|<BUDGET-FROM-MEASUREMENT>' commands/new-feature.md   # expect: none
grep -c 'risk_reasons' commands/dispatch.md                 # expect: ≥ 5
grep -c 'change_review_ready' commands/status.md            # expect: 1
```

- [ ] **Step 9: Commit**

```bash
git add commands/new-feature.md commands/dispatch.md commands/status.md
git commit -m "feat(new-feature): RISK field and tier-by-risk review seeding; dispatch/status show risk and the change-review gate rule

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Lens calibration in both copies (spec §3.3, D5)

**Files:**
- Modify: `agents/architect.md` (`## Review lens`: one bullet; intro line)
- Modify: `agents/qa.md` (`## Review lens`: the bullet list)
- Modify: `agents/coder.md` (frontmatter `description:`; `## Review lens`: intro + the bullet list)
- Modify: `workflows/review.js` (the `LENS` object, between `// --- LENS START` and `// --- LENS END`)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: identical bullet text in each agent's `## Review lens` and in `LENS.<role>`; `scripts/lens-drift.test.sh` is the contract.

- [ ] **Step 1: `agents/architect.md`**

Replace the intro line `When reviewing a spec or a diff, hunt for:` with `When reviewing a spec or a diff, judge these — at the severity the rubric gives them, not higher:`. Replace the failure-modes bullet. Old:

```markdown
- **Failure modes.** What happens on partial failure, network loss, retries,
  concurrent callers, malformed input? If the spec is silent, that is a
  finding.
```
New:

```markdown
- **Failure modes.** What happens on partial failure, network loss, retries,
  concurrent callers, malformed input? Silence is a `[major]` when the failure
  would corrupt data or break an acceptance criterion, a `[minor]` otherwise.
```

- [ ] **Step 2: `agents/qa.md`**

Replace the whole bullet list under `## Review lens` (five bullets, from `- For each acceptance criterion: could you write a test from this *alone*?` to `the orphan — either spec is incomplete or the criterion is over-scope.`) with:

```markdown
- **Testability.** For each acceptance criterion: could you write a test from it
  *alone*? A `[major]` only where a coder would have to guess at behaviour a test
  could fail on; cite the criterion. Prose that could be tighter is a `[minor]`.
- **Measurability.** "Fast", "robust", "user-friendly" with no number or observable
  check: a `[major]` inside an acceptance criterion, a `[minor]` in narrative text.
- **Coverage.** Spec behaviour with no acceptance criterion is a `[major]`. An
  acceptance criterion with no described behaviour is a `[major]` only if a coder
  would implement it blind, otherwise a `[minor]`.
```

- [ ] **Step 3: `agents/coder.md`**

Replace the `description:` line (line 3) with:

```yaml
description: Use this agent when implementing source to a FINALIZED spec during BUILD (after qa's failing suite exists), when closing the open blockers and fix majors a CHANGE_REVIEW gate hands back, or — in the bug lane — when refuting a hypothesis during /build-fleet:diagnose and implementing the confirmed fix strategy during /build-fleet:fix. Inside /build-fleet:review its severity-calibrated implementer lens runs on the read-only reviewer agent instead. Do NOT use for writing specs, tests, ADRs, or review verdicts, and never before the spec is FINALIZED (bug lane: never before the diagnosis is CONFIRMED with a reproducing test in place).
```
Replace the lens intro `agent — `scripts/lens-drift.test.sh` fails the suite if the two drift.) Common findings:` with `agent — `scripts/lens-drift.test.sh` fails the suite if the two drift.) Rate what you find by these rules:`. Replace the bullet list (four bullets, from `- Missing or unclear interface contracts` to `- Implicit dependencies on infra or libraries the spec doesn't mention.`) with:

```markdown
- **Interface contracts.** A signature, error envelope or data shape the spec
  leaves open is a `[major]` only when two reasonable implementations would fail
  different tests; otherwise state the assumption you would make as a `[minor]`.
- **Implementability.** An acceptance criterion that cannot be implemented as
  written, or that contradicts another, is a `[blocker]`.
- **Hidden dependencies.** An implicit dependency on infrastructure or a library
  the spec does not name is a `[major]` when it changes the stack or the deploy
  shape, a `[minor]` otherwise.
```
(The old coverage bullet is gone on purpose: it duplicated qa's and produced paired findings.)

- [ ] **Step 4: `workflows/review.js` — the same three texts, backticks escaped**

Inside the `LENS` object, replace the architect failure-modes bullet with (note the escaped backticks):

```javascript
- **Failure modes.** What happens on partial failure, network loss, retries,
  concurrent callers, malformed input? Silence is a \`[major]\` when the failure
  would corrupt data or break an acceptance criterion, a \`[minor]\` otherwise.
```
Replace the whole `qa:` entry with:

```javascript
  qa: `- **Testability.** For each acceptance criterion: could you write a test from it
  *alone*? A \`[major]\` only where a coder would have to guess at behaviour a test
  could fail on; cite the criterion. Prose that could be tighter is a \`[minor]\`.
- **Measurability.** "Fast", "robust", "user-friendly" with no number or observable
  check: a \`[major]\` inside an acceptance criterion, a \`[minor]\` in narrative text.
- **Coverage.** Spec behaviour with no acceptance criterion is a \`[major]\`. An
  acceptance criterion with no described behaviour is a \`[major]\` only if a coder
  would implement it blind, otherwise a \`[minor]\`.`,
```
Replace the whole `coder:` entry with:

```javascript
  coder: `- **Interface contracts.** A signature, error envelope or data shape the spec
  leaves open is a \`[major]\` only when two reasonable implementations would fail
  different tests; otherwise state the assumption you would make as a \`[minor]\`.
- **Implementability.** An acceptance criterion that cannot be implemented as
  written, or that contradicts another, is a \`[blocker]\`.
- **Hidden dependencies.** An implicit dependency on infrastructure or a library
  the spec does not name is a \`[major]\` when it changes the stack or the deploy
  shape, a \`[minor]\` otherwise.`,
```
The `architect:` entry's other seven bullets and the `"product-owner":` entry are untouched.

- [ ] **Step 5: Verify — drift, parse, lint, suite**

```bash
bash scripts/lens-drift.test.sh | tail -4        # expect: ok lens-matches-architect / qa / coder; passed=3 failed=0
bash scripts/rubric-drift.test.sh | tail -1      # still green
# Parse check in the form the Workflow runtime executes (a bare `node --check` rejects the
# file's legal top-level `return`, before AND after this edit):
{ echo '(async function(){'; sed 's/^export const meta/const meta/' workflows/review.js; echo '})'; } > /tmp/review-wrapped.js && node --check /tmp/review-wrapped.js && echo "parse ok"
bash scripts/workflow-determinism-lint.sh workflows/review.js   # expect: BUILD_FLEET_LINT_PASS
bash scripts/run-tests.sh | tail -1                              # expect: failed: 0
```

- [ ] **Step 6: Commit**

```bash
git add agents/architect.md agents/qa.md agents/coder.md workflows/review.js
git commit -m "feat(review): calibrate the architect, qa and coder lenses to the reviewer discipline (both copies)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Documentation of record (spec §3.8)

**Files:**
- Modify: `skills/sdd-protocol/SKILL.md` (PROGRESS schema; SPEC paragraph; CHANGE_REVIEW paragraph)
- Modify: `skills/review-rubric/SKILL.md` (`## How a major becomes an ADR`)
- Modify: `README.md` (state diagram label; classifier sentence; handoff row; PROGRESS schema block)
- Modify: `docs/loops.md` (CHANGE_REVIEW catalog row; the "stays static" passage)
- Modify: `docs/v0.2/CONTRACT.md` (§8 success-signal sentence)
- Modify: `docs/PILOT.md` (the `/build-fleet:review` comment)

**Interfaces:**
- Consumes: every behaviour from Tasks 2–7, and the `standard` + `low` row from Task 6.

- [ ] **Step 1: `skills/sdd-protocol/SKILL.md` — PROGRESS schema**

In the forward-feature schema block, insert after the `BUILD_MODE:` line:

```
RISK: low | elevated                 # set by the classifier at /build-fleet:new-feature (reversibility, blast radius, the never-trivial list). `pending` until it runs. With TIER it selects the seeded review roster and budget.
```
Replace the two comment lines:
```
REVIEW_ROLES: <csv>         # optional — /build-fleet:review roster (>=2 of architect,qa,coder,product-owner). Default architect,qa,coder. A --roles flag overrides per-run.
REVIEW_CYCLE_BUDGET: <int>  # optional — /build-fleet:review escalation budget (1..3, clamped to the ceiling). Default 3. A --cycle-budget flag overrides per-run.
```
with:
```
REVIEW_ROLES: <csv>         # optional — /build-fleet:review roster (>=2 of architect,qa,coder,product-owner). Seeded by new-feature from TIER + RISK (standard+low: architect,qa; else architect,qa,coder); absent ⇒ architect,qa,coder. A --roles flag overrides per-run.
REVIEW_CYCLE_BUDGET: <int>  # optional — /build-fleet:review escalation budget (1..3, clamped to the ceiling). Seeded with the roster (standard+low: 2; else 3); absent ⇒ 3. A --cycle-budget flag overrides per-run.
```
(If Task 1 decided REVERT, write `standard+low: architect,qa,coder` and `standard+low: 3` instead, matching Task 6.)

- [ ] **Step 2: `skills/sdd-protocol/SKILL.md` — SPEC and CHANGE_REVIEW paragraphs**

In the **SPEC** paragraph, replace `runs the\nclassifier subagent to set `TIER` + `BUILD_MODE` in PROGRESS.md,` with `runs the\nclassifier subagent to set `TIER`, `RISK` + `BUILD_MODE` in PROGRESS.md and to seed\n`REVIEW_ROLES` / `REVIEW_CYCLE_BUDGET` from tier and risk (`commands/new-feature.md` step 7),`.

Replace the **CHANGE_REVIEW** paragraph's last two sentences. Old:
```markdown
Exit (to HANDOFF): all three approve with no open blockers. Fail → back to BUILD,
bounded by the 3-cycle `CHANGE_CYCLE` budget, then ESCALATE.
```
New:
```markdown
The fan-out is two-stage: product-owner and qa in parallel, then the architect,
who reads their blocks. Findings carry ids `<role>-cc<K>-<n>` (`K` = the change
cycle first raised); every `[major]` carries `disposition: fix` or, architect only,
`disposition: adr ADR-N` after the ADR is appended — and the architect may close a
peer's open major by re-listing its id with an ADR (closed-by-id). From change
cycle 2 each reviewer re-raises its own open findings by id and raises new findings
at `[blocker]` only; a new `[major]` is advisory (demoted).

Exit (to HANDOFF): `scripts/change-review-gate.sh` passes — every roster role has a
current-cycle block, zero unrefuted `[blocker]`s, every `[major]` closed by an ADR
present in DECISIONS.md or demoted. `status:` is informational. Fail below the
budget → back to BUILD with exactly the open items; fail on the exhausting cycle
(`CHANGE_CYCLE` 3) → ESCALATE with blockers and `fix` majors both listed.
```

- [ ] **Step 3: `skills/review-rubric/SKILL.md` — the non-workflow ADR path**

Replace the `## How a major becomes an ADR` section body (from `This describes the non-workflow paths` to `elevated to `[blocker]` for lack of audit trail.`) with:

```markdown
This describes the non-workflow paths (CHANGE_REVIEW and direct invocation). In
workflow REVIEW the architect disposition leg records the ADR — see "Delta review
and disposition (v0.9)" below.

In CHANGE_REVIEW the same grammar applies, read by `scripts/change-review-gate.sh`:

- Ids `<role>-cc<K>-<n>`, `K` the change cycle the finding was first raised in; a
  re-raised finding keeps its id.
- Every `[major]` carries `disposition: fix` (the default; coder closes it) or
  `disposition: adr ADR-N` (architect only, ADR appended first).
- **Closed-by-id.** The architect runs after product-owner and qa and may accept a
  peer's open major as a trade-off by listing the peer's id under its own block with
  an ADR disposition. An id closed by an ADR in any block is closed in every block.
- **Delta rule.** From change cycle 2, new findings are `[blocker]` only; a new
  `[major]` is advisory (the gate reports it as demoted). Blockers are never demoted,
  and qa's change-review lens rates a missing acceptance test as a blocker, so
  demotion touches maintainability-class findings in fix code only.

A `[major]` that gets quietly dropped between cycles without a fix or an ADR is a
finding the next reviewer should re-raise by id — same content, elevated to
`[blocker]` for lack of audit trail.
```

- [ ] **Step 4: `README.md`**

Four edits:
1. In the state diagram (the `SPEC[…] --> REVIEW([…])` line), replace `architect · qa · coder` with `roster by tier and risk`.
2. In the agents section, replace `The classifier sizes\nincoming work and routes domain skills;` with `The classifier sizes\nincoming work, rates its risk (reversibility, blast radius) — which seeds the\nreview roster — and routes domain skills;`.
3. In the command table, replace the `/build-fleet:handoff` row's description with: `product-owner + qa review the diff, then architect (who may accept a peer's major by ADR); exits on the deterministic change-review gate; refuses if tests are missing/failing. On pass devops ships, the backlog flips, and the loop advances.`
4. In the PROGRESS schema block, insert `RISK:    low | elevated | pending` after the `BUILD_MODE:` line and replace the two comments `# optional — review roster (default architect,qa,coder)` / `# optional — review budget 1..3 (default 3)` with `# seeded by tier + risk (standard+low: architect,qa; else architect,qa,coder)` / `# seeded with the roster (standard+low: 2; else 3)`. Then replace the sentence `(The three optional config fields are seeded by `/build-fleet:new-feature` and read\nwith-default by their commands; a `--roles` / `--cycle-budget` flag overrides per run.` with `(The three optional config fields are seeded by `/build-fleet:new-feature` — the review\npair from the classifier's tier and risk — and read with-default by their commands; a\n`--roles` / `--cycle-budget` flag overrides per run.`. Apply the REVERT variant if Task 1 decided so.

- [ ] **Step 5: `docs/loops.md`**

Replace the CHANGE_REVIEW catalog row's stopping-condition cell `3 approvals; fail → back to BUILD, `≤3 CHANGE_CYCLE` then `escalate`` with `change-review gate passes (zero blockers, every major ADR'd or demoted — `scripts/change-review-gate.sh`); fail → back to BUILD, `≤3 CHANGE_CYCLE` then `escalate``. Replace the passage sentence `and it\nneeds no survival-vote machinery (a plain all-approve-or-bounce gate against the\n3-cycle `CHANGE_CYCLE` budget).` with `and it\nneeds no survival-vote machinery: a two-stage fan-out (product-owner + qa, then the\narchitect, who dispositions their majors) and a deterministic rubric gate\n(`scripts/change-review-gate.sh`) against the 3-cycle `CHANGE_CYCLE` budget.`.

- [ ] **Step 6: `docs/v0.2/CONTRACT.md` and `docs/PILOT.md`**

In CONTRACT §8 replace `Success paths emit their command-specific signal (`BUILD_FLEET_WORKFLOW_LAUNCHED`,\n`BUILD_FLEET_FINALIZE_PASS`, `BUILD_FLEET_PLAN_FINALIZE_PASS`, …).` with `Success paths emit their command-specific signal (`BUILD_FLEET_WORKFLOW_LAUNCHED`,\n`BUILD_FLEET_FINALIZE_PASS`, `BUILD_FLEET_PLAN_FINALIZE_PASS`, `BUILD_FLEET_CHANGE_REVIEW_GATE`,\n`BUILD_FLEET_REVIEW_DEFAULTS`, …). `BUILD_FLEET_CLASSIFICATION` carries `risk` and\n`risk_reasons`; `BUILD_FLEET_CLASSIFIER_FALLBACK` carries `risk_assigned` and may name\nthe reason `risk-tier-conflict`.`

In PILOT.md replace `/build-fleet:review      # adversarial review workflow — architect, qa, coder` with `/build-fleet:review      # adversarial review workflow — roster seeded by tier + risk`.

- [ ] **Step 7: Verify and commit**

```bash
grep -c 'RISK' skills/sdd-protocol/SKILL.md README.md          # expect: ≥ 2 each
grep -n 'all three approve\|3 approvals\|all-approve-or-bounce' skills/sdd-protocol/SKILL.md docs/loops.md README.md   # expect: none
bash scripts/run-tests.sh | tail -1                            # failed: 0
git add skills/sdd-protocol/SKILL.md skills/review-rubric/SKILL.md README.md docs/loops.md docs/v0.2/CONTRACT.md docs/PILOT.md
git commit -m "docs: risk axis, tier-by-risk seeding and the change-review gate in protocol, rubric, README, loops, contract, pilot

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Release v0.10.0 — classifier previews, CHANGELOG, bump, merge, tag (spec §4, §5 step 6, §6)

**Files:**
- Modify: `CHANGELOG.md`, `.claude-plugin/plugin.json`
- Check only: `.claude-plugin/marketplace.json`, `README.md` counts

**Interfaces:**
- Consumes: `MEASUREMENT.md` (Task 1); every earlier commit on `release/0.10.0`.

- [ ] **Step 1: Classifier previews on tap from the worktree**

In a new session, `cd ~/Projects/tap && claude --plugin-dir ~/build-fleet-0.10`, run the three previews and record each `BUILD_FLEET_CLASSIFICATION` line:

```
/build-fleet:dispatch "tighten the login check so a disabled account cannot obtain a session token"
/build-fleet:dispatch "fix the typo 'recieve' in docs/README.md"
/build-fleet:dispatch "add a position_history table and backfill it from the positions table across the ingest and export packages"
```
Expected: first → `standard`, `risk":"elevated"`, reasons include `auth`; second → `trivial`, `low`, `[]`; third → `large`, reasons include `data-migration`. Every line must contain `"risk"` (Review Focus 5). If any expectation fails, fix the classifier text (Task 5) before continuing; a wrong preview is a wrong seeding.

- [ ] **Step 2: CHANGELOG entry**

Insert directly under the `## Compatibility` section (above `## [0.9.0] — 2026-09-06`), with `<date>` = `date -u +%F` on the day of the release commit and the table and previews pasted from Task 1's MEASUREMENT.md and step 1:

```markdown
## [0.10.0] — <date>

The **proportionate review** release. Review effort now scales with stakes: the
classifier rates risk on a second axis, `new-feature` seeds the review roster and
cycle budget from tier and risk, the three review lenses are calibrated to the
reviewer discipline, and CHANGE_REVIEW exits on a deterministic rubric gate with the
v0.9 convergence rules (ids, dispositions, closed-by-id, delta demotion). Design:
`docs/history/2026-10-10-proportionate-review.md`; evidence:
`docs/history/2026-10-10-orchestration-balance-research.md`. Measured on the tap
pilot before tagging (`docs/history/2026-10-10-proportionate-review-MEASUREMENT.md`):

<paste the measurement table and its Decision line>

Classifier previews on tap (`/build-fleet:dispatch`): <paste the three signal lines>.

### Added
- **Classifier risk axis** — `risk: low | elevated` + `risk_reasons` (slugs: `auth`, `secrets`, `billing`, `data-migration`, `ci-release`, `new-dependency`, `review-requested`, `irreversible`, `public-contract`, `shared-module`). Elevated is never `trivial`. PROGRESS gains `RISK:`.
- **Tier-by-risk review seeding** in `new-feature` step 7 (`standard` + `low` → <roster>, budget <n>; everything else → architect, qa, coder, budget 3), recorded by the new `BUILD_FLEET_REVIEW_DEFAULTS` line. A `trivial` + `elevated` verdict is coerced to `standard` (`BUILD_FLEET_CLASSIFIER_FALLBACK` reason `risk-tier-conflict`). `dispatch` previews risk and the would-seed roster; `status` prints TIER, RISK and the roster.
- **`scripts/change-review-gate.sh`** (+ harness, 31 cases) — the CHANGE_REVIEW exit `/build-fleet:handoff` now computes: every roster role has a `## Change-Cycle N` block, zero unrefuted blockers, every major closed by an ADR present in DECISIONS.md or demoted; two passes so an architect ADR closes a peer's id in every block. One signal line, `BUILD_FLEET_CHANGE_REVIEW_GATE`.

### Changed
- **CHANGE_REVIEW is two-stage**: product-owner and qa in parallel, then the architect, who reads their blocks and may accept a peer's major by ADR (closed-by-id). Findings carry ids `<role>-cc<K>-<n>` and `disposition:` lines; from change cycle 2 the delta rule applies and a new major is advisory. The budget guard and the exit both call the gate, so they cannot disagree; the exhausting cycle escalates directly with blockers and `fix` majors both listed.
- **`handoff` resumes at devops when `PHASE: HANDOFF`** (a previous run's devops refusal) instead of refusing the phase it told the user to re-run from.
- **Lenses calibrated**: qa's "invent assumptions ⇒ major" and "vague words ⇒ blocker-tier" and coder's gap list move to "a major only where a coder would guess at behaviour a test could fail on; vagueness is a major inside an acceptance criterion and a minor elsewhere"; the coder lens drops its coverage bullet (qa's duplicate); the architect's failure-modes bullet is severity-rated. Both copies (agent + `review.js` LENS); descriptions refreshed (classifier, architect, qa, coder, product-owner).

### Fixed
- `agents/product-owner.md` named a `## Cycle <N>` heading for its CHANGE_REVIEW block, which `check-review-written.sh` rejects in that phase; now `## Change-Cycle <N>`.

**Compatibility.** `SDD_SCHEMA` stays `1`. Additive PROGRESS field `RISK` (read-with-default; absent prints `unset`). Signal grammar: new lines `BUILD_FLEET_CHANGE_REVIEW_GATE`, `BUILD_FLEET_REVIEW_DEFAULTS`; new fields `risk`, `risk_reasons` on `BUILD_FLEET_CLASSIFICATION`, `risk_assigned` on `BUILD_FLEET_CLASSIFIER_FALLBACK`; new fallback reason `risk-tier-conflict`. REVIEW.md Change-Cycle lines gain `(id)` and `disposition:`; old blocks still parse — an undispositioned legacy major reads as open and bounces to the coder once, after which reviewers re-raise with ids. A feature seeded before 0.10.0 keeps its three-role roster; edit `REVIEW_ROLES` / `REVIEW_CYCLE_BUDGET` by hand to adopt the table. No migration required.
```
Fill `<roster>` / `<n>` from the Decision (`architect, qa` / `2` on KEEP; `architect, qa, coder` / `3` on REVERT, in which case also say the row reverted and why).

- [ ] **Step 3: Manifest**

In `.claude-plugin/plugin.json` set `"version": "0.10.0"` and, in `description`, replace `and a convergent bounded review loop (delta review, in-workflow ADR disposition, rubric-only finalize gate, spec/criteria/cycle caps).` with `a convergent bounded review loop (delta review, in-workflow ADR disposition, rubric-only finalize gate, spec/criteria/cycle caps), and risk-proportionate review: a classifier risk axis seeds the review roster and budget by tier and risk, and CHANGE_REVIEW exits on a deterministic rubric gate.` Confirm `marketplace.json` carries no version field and its description needs no change:

```bash
jq -r .version .claude-plugin/plugin.json                 # 0.10.0
grep -c version .claude-plugin/marketplace.json           # 0 — nothing to bump there
grep -n -E 'twelve|Eight role|Four dynamic|seven craft' README.md   # counts unchanged: no hook, agent, workflow or skill was added
```

- [ ] **Step 4: Full suite, then commit the release**

```bash
bash scripts/run-tests.sh | tail -1     # suites: <N+1>, failed: 0
git add CHANGELOG.md .claude-plugin/plugin.json
git commit -m "release: v0.10.0 — proportionate review

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

- [ ] **Step 5: Merge to main, tag, clean up**

```bash
cd ~/build-fleet && git merge --no-ff release/0.10.0 -m "merge: release/0.10.0 — proportionate review

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
bash scripts/run-tests.sh | tail -1     # failed: 0 on main
git tag v0.10.0 && git log --oneline -1 && git describe --tags   # main == v0.10.0
git worktree remove ~/build-fleet-0.10 && git branch -d release/0.10.0
```
Ray pushes `main` and the tag; CI's `release-channel` job asserts the tag matches `plugin.json`. The tap sessions that run from `~/build-fleet` pick up 0.10.0 on their next start; `~/Projects/tap`'s `fixture-and-harness` keeps whichever arm Task 1 step 7 restored.

---

## Spec coverage map

| Spec section | Task |
|---|---|
| §3.1 Classifier risk axis | 5 |
| §3.2 PROGRESS `RISK`, seeding table, signals, dispatch, status | 6 |
| §3.3 Lens alignment (both copies, descriptions) | 7 (coder description), 4 (architect/qa descriptions) |
| §3.4 Change-review finding grammar | 3 (prompts), 4 (agents), 8 (rubric) |
| §3.5 The gate | 2 |
| §3.6 handoff: resume at HANDOFF, gate guard, two-stage, gate exit, refusals | 3 |
| §3.7 Role agents in CHANGE_REVIEW, PO heading fix | 4 |
| §3.8 Documentation | 8 |
| §4 Compatibility and release checklist | 9 |
| §5 Order (measurement first, worktree) | 1, then 2–9 |
| §6 Gate harness, drift/lint, classifier previews, measurement, success criteria | 2, 7, 9 step 1, 1 |
| §7 Out of scope | nothing to implement — do not add a roles-of-one path, a PO self-review change, a critic verdict, a change-review roster field, a change-review workflow or command namespacing |
