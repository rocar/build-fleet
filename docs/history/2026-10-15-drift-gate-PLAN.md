# Drift Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A model-free gate that proves every acceptance criterion of a gated feature maps to a named test that exists, wired into `implement` (before and after coder), `handoff`, the lite router, and the user's CI.

**Architecture:** One read-only script, `scripts/drift-gate.sh <slug> | --all`, prints `BUILD_FLEET_DRIFT_GATE:` lines. The flow commands call it and act on its line; a new PROGRESS field `QA_FAIL: drift` carries a failure across runs, and the router reads it. Docs and qa's prompt teach the matrix grammar the gate reads.

**Tech Stack:** bash 3.2 + BSD/GNU coreutils, awk (BWK awk on macOS, mawk/gawk on Linux), jq; markdown command/agent/skill files.

**Spec:** `docs/history/2026-10-15-drift-gate.md` (approved 2026-10-15).

## Global Constraints

- bash 3.2 and BSD/GNU compatible: no `declare -A`, no `\b` in grep patterns, no `grep -F -w` together; fixed-string matching uses `grep -F`, whole-word matching uses awk.
- jq is required; the gate exits 1 without it.
- Signal lines are the machine contract. Commands never document an exit-code table; the script's exit code exists for CI only.
- Hooks and gates fail closed; an unreadable matrix row fails the gate (`unparsed`).
- No milestone jargon in command bodies, agent prompts or descriptions.
- A change to an agent's body changes its `description:` (hard rule). `scripts/rubric-drift.test.sh` and `scripts/lens-drift.test.sh` must stay green: do not touch any `| Severity |` table or `## Review lens` text.
- TDD for gates: the failing test is written and seen failing first.
- Commit attribution line: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Work on `release/0.12.0` in `~/build-fleet-0.12`; never commit to main; no merge, tag or push.

## Review Focus

1. **The Linux leg.** The drafts below ran on macOS (bash 3.2, BWK awk) only; mawk on Ubuntu is first exercised by CI. Expected: every suite green on both legs. (Pinned by CI's existing matrix; no new test.)
2. **A matrix with a trailing Notes column** — qa often adds one. Expected: parses; column 4 stays the location. Test `five-column-matrix` (Task 1).
3. **A test path with spaces** (`tests/my tests/test_s.py`). Expected: found. Test `path-with-spaces` (Task 1).
4. **A CRLF `acceptance.md`** (Windows checkouts). Expected: ids read cleanly, nothing untested. Test `crlf-acceptance` (Task 1).
5. **A renamed matrix heading** (`## Coverage matrix (draft)`). Expected: fail closed (every criterion untested), never a silent pass. Test `renamed-matrix-heading-fails-closed` (Task 1); the skill states the exact heading (Task 4).

**Rulings made while planning (from the spec):**
- R1: the spec's "`## Acceptance` section of spec.md" matches any heading that starts with `## Acceptance`, because the spec template's heading is `## Acceptance Criteria`.
- R2: "contains `..`" is matched literally (`*..*`): fail closed; a file name such as `a..b.py` is refused too.
- R3: a gate that prints no line (exit 1) is a refusal with its own reason, `drift-gate-error`, in `implement` and `handoff` (the spec names no reason for it).
- R4: the repair brief after coder ends with `BUILD_FLEET_QA_TESTS_READY: <count> tests in tests/` (the same tag, "failing" dropped) because the suite is green there.
- R5: the smoke test is the bug lane's; the gated feature is added as a `[DRIFT]` section on the same temp project, reusing its test file.

---

## File structure

| File | Responsibility | Task |
|---|---|---|
| `scripts/drift-gate.sh` (new) | the gate: parse criteria and matrix, check, print one line per feature; `--all` for CI | 1 |
| `scripts/drift-gate.test.sh` (new) | hermetic harness, one fixture per case | 1 |
| `scripts/lite-next.sh`, `scripts/lite-next.test.sh` | router reads `QA_FAIL` | 2 |
| `commands/new-feature.md`, `commands/implement.md`, `commands/handoff.md` | the firing points and repair mode | 3 |
| `scripts/drift-wiring.test.sh` (new) | asserts the wiring text exists where the spec puts it | 3, 4 |
| `agents/qa.md`, `skills/test-plan/SKILL.md`, `skills/sdd-protocol/SKILL.md`, `docs/v0.2/CONTRACT.md`, `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `docs/v0.5/smoke/smoke.sh` | docs, qa's prompt, smoke | 4 |
| — | live run on `/tmp/bf-lite` | 5 |

---

### Task 1: The gate script

**Files:**
- Create: `scripts/drift-gate.sh`
- Test: `scripts/drift-gate.test.sh`

**Interfaces:**
- Produces:
  - `bash scripts/drift-gate.sh <slug>` → exactly one stdout line
    `BUILD_FLEET_DRIFT_GATE: {"feature","pass","reasons","untested","unknown","missing":[{"criterion","test","location","why"}],"unparsed","gaps_open"}`;
    unchecked: `{"feature","pass":true,"unchecked":true}`. Exit 0 pass, 2 fail, 1 usage/unreadable (no line).
  - `bash scripts/drift-gate.sh --all` → one line per visited feature (built: the above; not built: `{"feature","pass":true,"in_progress":true}`), then
    `BUILD_FLEET_DRIFT_GATE_SUMMARY: {"checked","unchecked","in_progress","failed":[…]}`. Exit 2 if any failed.
  - Both honour `CLAUDE_PROJECT_DIR` (default `.`).

- [ ] **Step 1: Write the failing test harness**

Create `scripts/drift-gate.test.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# Tests for scripts/drift-gate.sh (the drift gate: every acceptance criterion maps to a
# named test that exists). One fixture project per case; asserts the
# BUILD_FLEET_DRIFT_GATE line(s) and the exit code.
# Run: bash scripts/drift-gate.test.sh   (exit 0 = all pass)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$DIR/drift-gate.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass=0; fail=0; n=0

# proj — a fresh project; sets $P
proj() { n=$((n+1)); P="$work/p$n"; mkdir -p "$P/.sdd"; }
# feat <slug> — PROGRESS.md fields on stdin (DRIFT_GATE etc.)
feat() { mkdir -p "$P/.sdd/$1"; { printf 'SDD_SCHEMA: 1\nFEATURE: %s\n' "$1"; cat; } > "$P/.sdd/$1/PROGRESS.md"; }
# acc <slug> <ids…> — acceptance.md naming each id
acc() { local s="$1"; shift; { printf '# Acceptance — %s\n\n' "$s"; for i in "$@"; do printf -- '- **%s**: behaviour %s.\n' "$i" "$i"; done; } > "$P/.sdd/$s/acceptance.md"; }
# plan <slug> — TEST_PLAN.md body on stdin (matrix rows and any sections after it)
plan() { { printf '# Test Plan — %s\n\n## Coverage matrix\n\n| Criterion | Test name | Type | Location |\n|---|---|---|---|\n' "$1"; cat; } > "$P/.sdd/$1/TEST_PLAN.md"; }
# src <path> — a source/test file with stdin as its content
src() { mkdir -p "$P/$(dirname "$1")"; cat > "$P/$1"; }
run() { out=$( cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$GATE" "$@" 2>/dev/null ); rc=$?; }
has() { printf '%s' "$out" | grep -qF -- "$1"; }
assert() { local name="$1" cond="$2"; if eval "$cond"; then pass=$((pass+1)); printf 'ok   %-52s\n' "$name"; else fail=$((fail+1)); printf 'FAIL %-52s (%s) out=%s\n' "$name" "$cond" "${out:-}"; fi; }

# a passing baseline: AC-1, AC-2 mapped to tests that exist
base() {
  proj; printf 'DRIFT_GATE: on\n' | feat f; acc f AC-1 AC-2
  src tests/test_f.py <<'T'
def test_one():
    pass
def test_two():
    pass
T
}

# --- pass ---
base; plan f <<'T'
| AC-1 | `test_one` | unit | `tests/test_f.py::test_one` |
| AC-2 | `test_two` | unit | `tests/test_f.py::test_two` |
T
run f
assert "pass-rc0" "[ $rc -eq 0 ]"
assert "pass-line" "has 'BUILD_FLEET_DRIFT_GATE: {\"feature\":\"f\",\"pass\":true,\"reasons\":[]'"

# --- unchecked: no field, empty, off ---
proj; printf 'PHASE: BUILD\n' | feat f; run f
assert "unchecked-absent" "[ $rc -eq 0 ] && has 'BUILD_FLEET_DRIFT_GATE: {\"feature\":\"f\",\"pass\":true,\"unchecked\":true}'"
proj; printf 'DRIFT_GATE:\n' | feat f; run f
assert "unchecked-empty" "[ $rc -eq 0 ] && has '\"unchecked\":true'"
proj; printf 'DRIFT_GATE: off\n' | feat f; run f
assert "unchecked-off" "[ $rc -eq 0 ] && has '\"unchecked\":true'"

# --- bad-field ---
proj; printf 'DRIFT_GATE: yes\n' | feat f; run f
assert "bad-field" "[ $rc -eq 2 ] && has '\"reasons\":[\"bad-field\"]'"

# --- no-test-plan (criteria then all untested) ---
proj; printf 'DRIFT_GATE: on\n' | feat f; acc f AC-1; run f
assert "no-test-plan" "[ $rc -eq 2 ] && has '\"reasons\":[\"no-test-plan\",\"untested\"]' && has '\"untested\":[\"AC-1\"]'"

# --- no-criteria ---
proj; printf 'DRIFT_GATE: on\n' | feat f; printf '# Acceptance\n\nnone yet\n' > "$P/.sdd/f/acceptance.md"
src tests/t.py <<'T'
def test_one(): pass
T
plan f <<'T'
T
run f
assert "no-criteria" "[ $rc -eq 2 ] && has '\"reasons\":[\"no-criteria\"]'"

# --- untested ---
base; plan f <<'T'
| AC-1 | `test_one` | unit | `tests/test_f.py::test_one` |
T
run f
assert "untested" "[ $rc -eq 2 ] && has '\"reasons\":[\"untested\"]' && has '\"untested\":[\"AC-2\"]'"

# --- unknown-criterion ---
base; plan f <<'T'
| AC-1 | `test_one` | unit | `tests/test_f.py::test_one` |
| AC-2, AC-9 | `test_two` | unit | `tests/test_f.py::test_two` |
T
run f
assert "unknown-criterion" "[ $rc -eq 2 ] && has '\"reasons\":[\"unknown-criterion\"]' && has '\"unknown\":[\"AC-9\"]'"

# --- missing-file ---
base; plan f <<'T'
| AC-1 | `test_one` | unit | `tests/test_f.py::test_one` |
| AC-2 | `test_two` | unit | `tests/nope.py::test_two` |
T
run f
assert "missing-file" "[ $rc -eq 2 ] && has '\"reasons\":[\"missing-file\"]' && has '\"why\":\"missing-file\"'"

# --- missing-test ---
base; plan f <<'T'
| AC-1 | `test_one` | unit | `tests/test_f.py::test_one` |
| AC-2 | `test_three` | unit | `tests/test_f.py::test_three` |
T
run f
assert "missing-test" "[ $rc -eq 2 ] && has '\"reasons\":[\"missing-test\"]' && has '{\"criterion\":\"AC-2\",\"test\":\"test_three\",\"location\":\"tests/test_f.py::test_three\",\"why\":\"missing-test\"}'"

# --- gaps-open (bullet) vs None. ---
base; plan f <<'T'
| AC-1 | `test_one` | unit | `tests/test_f.py::test_one` |
| AC-2 | `test_two` | unit | `tests/test_f.py::test_two` |

## Gaps

- AC-2: cannot test the clock — recommendation: add infra.
T
run f
assert "gaps-open" "[ $rc -eq 2 ] && has '\"reasons\":[\"gaps-open\"]' && has '\"gaps_open\":true'"
base; plan f <<'T'
| AC-1 | `test_one` | unit | `tests/test_f.py::test_one` |
| AC-2 | `test_two` | unit | `tests/test_f.py::test_two` |

## Gaps

None.
T
run f
assert "gaps-none-passes" "[ $rc -eq 0 ]"

# --- unparsed ---
base; plan f <<'T'
| AC-1 | `test_one` | unit | `tests/test_f.py::test_one` |
| AC-2 | `test_two` | unit |
| see above | `test_two` | unit | `tests/test_f.py::test_two` |
T
run f
assert "unparsed" "[ $rc -eq 2 ] && has '\"unparsed\"' && has '\"reasons\":[\"untested\",\"unparsed\"]'"

# --- reasons keep table order ---
base; plan f <<'T'
| AC-9 | `test_one` | unit | `tests/nope.py::x` |
| broken |
T
run f
assert "reasons-order" "has '\"reasons\":[\"untested\",\"unknown-criterion\",\"missing-file\",\"unparsed\"]'"

# --- spec.md fallback (## Acceptance Criteria section only) ---
proj; printf 'DRIFT_GATE: on\n' | feat f
printf 'STATUS: FINALIZED\n\n## Behavior\n\nSee AC-7 later.\n\n## Acceptance Criteria\n\n- AC-1: x\n\n## Risks\n\nAC-8 is a risk id, not a criterion.\n' > "$P/.sdd/f/spec.md"
src tests/t.py <<'T'
def test_one(): pass
T
plan f <<'T'
| AC-1 | `test_one` | unit | `tests/t.py::test_one` |
T
run f
assert "spec-fallback" "[ $rc -eq 0 ]"

# --- multi-id cell with spaces; (failure) suffix inside and outside backticks ---
base; plan f <<'T'
| AC-1 ,  AC-2 | `test_one` (failure) | unit | `tests/test_f.py::test_one` |
| AC-2 | `test_two (failure)` | unit | `tests/test_f.py::test_two` |
T
run f
assert "multi-id-and-failure-suffix" "[ $rc -eq 0 ]"
base; plan f <<'T'
| AC-1, AC-2 | `test_gone` | unit | `tests/test_f.py::test_gone` |
T
run f
assert "missing-entry-per-id" "has '\"criterion\":\"AC-1\",\"test\":\"test_gone\"' && has '\"criterion\":\"AC-2\",\"test\":\"test_gone\"'"

# --- backticked vs bare location; location with no :: ---
base; plan f <<'T'
| AC-1 | test_one | unit | tests/test_f.py::test_one |
| AC-2 | `test_two` | unit | `tests/test_f.py` |
T
run f
assert "bare-cells-and-no-colons" "[ $rc -eq 0 ]"

# --- aligned separators and two tables under one heading ---
base; { printf '# Test Plan — f\n\n## Coverage matrix\n\n### Unit\n\n| Criterion | Test name | Type | Location |\n| :--- | --- | :---: | ---: |\n'
  printf '| AC-1 | `test_one` | unit | `tests/test_f.py::test_one` |\n\n### Integration\n\n'
  printf '| Criterion | Test name | Type | Location |\n| --- | --- | --- | --- |\n| AC-2 | `test_two` | integration | `tests/test_f.py::test_two` |\n'; } > "$P/.sdd/f/TEST_PLAN.md"
run f
assert "aligned-separators-two-tables" "[ $rc -eq 0 ]"

# --- whole word vs substring ---
proj; printf 'DRIFT_GATE: on\n' | feat f; acc f AC-1
src tests/t.py <<'T'
def test_retry_backoff():
    pass
T
plan f <<'T'
| AC-1 | `test_retry` | unit | `tests/t.py::test_retry` |
T
run f
assert "whole-word-no-prefix-match" "[ $rc -eq 2 ] && has missing-test"
proj; printf 'DRIFT_GATE: on\n' | feat f; acc f AC-1 AC-2
src tests/t.test.js <<'T'
it("retries 3 times (with backoff)", () => {});
test('parses a*b [x]', () => {});
T
plan f <<'T'
| AC-1 | `retries 3 times (with backoff)` | unit | `tests/t.test.js` |
| AC-2 | `parses a*b [x]` | unit | `tests/t.test.js` |
T
run f
assert "substring-with-regex-chars" "[ $rc -eq 0 ]"

# --- parametrize suffix; Go subtest ---
proj; printf 'DRIFT_GATE: on\n' | feat f; acc f AC-1 AC-2
src tests/test_p.py <<'T'
@pytest.mark.parametrize("case", ["a"])
def test_eval(case): pass
T
src pkg/x_test.go <<'T'
func TestProcess(t *testing.T) {
	t.Run("invalid_input", func(t *testing.T) {})
}
T
plan f <<'T'
| AC-1 | `test_eval[case1]` | unit | `tests/test_p.py::test_eval[case1]` |
| AC-2 | `TestProcess/invalid_input` | unit | `pkg/x_test.go::TestProcess/invalid_input` |
T
run f
assert "parametrize-and-go-subtest" "[ $rc -eq 0 ]"
proj; printf 'DRIFT_GATE: on\n' | feat f; acc f AC-1
src pkg/x_test.go <<'T'
func TestProcess(t *testing.T) {}
T
plan f <<'T'
| AC-1 | `TestProcess/invalid_input` | unit | `pkg/x_test.go` |
T
run f
assert "go-subtest-missing-segment" "[ $rc -eq 2 ] && has missing-test"

# --- refused locations ---
for loc in '../outside.py' '/etc/hosts' '.sdd/f/acceptance.md' 'README.md'; do
  base; printf '# AC-1 test_one\n' > "$P/README.md"
  printf '| AC-1 | `test_one` | unit | `%s` |\n| AC-2 | `test_two` | unit | `tests/test_f.py` |\n' "$loc" | plan f
  run f
  assert "refused-location $loc" "[ $rc -eq 2 ] && has '\"why\":\"missing-file\"'"
done

# --- CRLF test plan still parses ---
base; printf '| AC-1 | `test_one` | unit | `tests/test_f.py` |\r\n| AC-2 | `test_two` | unit | `tests/test_f.py` |\r\n' | plan f
run f
assert "crlf-rows" "[ $rc -eq 0 ]"


# --- review focus: shapes qa writes in the wild ---
base; plan f <<'T'
| AC-1 | `test_one` | unit | `tests/test_f.py::test_one` | happy path |
| AC-2 | `test_two` | unit | `tests/test_f.py::test_two` | |
T
run f
assert "five-column-matrix" "[ $rc -eq 0 ]"
proj; printf 'DRIFT_GATE: on\n' | feat f; acc f AC-1
src 'tests/my tests/test_s.py' <<'T'
def test_spaced(): pass
T
plan f <<'T'
| AC-1 | `test_spaced` | unit | `tests/my tests/test_s.py::test_spaced` |
T
run f
assert "path-with-spaces" "[ $rc -eq 0 ]"
base; printf '# Acceptance\r\n\r\n- AC-1: x\r\n- AC-2: y\r\n' > "$P/.sdd/f/acceptance.md"
plan f <<'T'
| AC-1 | `test_one` | unit | `tests/test_f.py` |
| AC-2 | `test_two` | unit | `tests/test_f.py` |
T
run f
assert "crlf-acceptance" "[ $rc -eq 0 ] && has '\"untested\":[]'"
base; { printf '# Test Plan — f\n\n## Coverage matrix (draft)\n\n| Criterion | Test name | Type | Location |\n|---|---|---|---|\n'
  printf '| AC-1 | `test_one` | unit | `tests/test_f.py` |\n| AC-2 | `test_two` | unit | `tests/test_f.py` |\n'; } > "$P/.sdd/f/TEST_PLAN.md"
run f
assert "renamed-matrix-heading-fails-closed" "[ $rc -eq 2 ] && has '\"untested\":[\"AC-1\",\"AC-2\"]'"

# --- usage and unreadable workspace ---
proj; run; assert "no-args-usage" "[ $rc -eq 1 ]"
proj; run ../x; assert "bad-slug" "[ $rc -eq 1 ]"
proj; run ghost; assert "no-progress-rc1" "[ $rc -eq 1 ]"

# --- --all ---
proj
printf 'DRIFT_GATE: on\nBUILD_STATE: done\nPHASE: BUILD\n' | feat a-pass; acc a-pass AC-1
printf '| AC-1 | `test_a` | unit | `tests/t.py` |\n' | plan a-pass
printf 'DRIFT_GATE: on\nPHASE: HANDOFF\n' | feat b-fail; acc b-fail AC-1
printf '| AC-1 | `test_gone` | unit | `tests/t.py` |\n' | plan b-fail
printf 'DRIFT_GATE: on\nPHASE: SPEC\n' | feat c-spec; acc c-spec AC-1
printf 'DRIFT_GATE: on\nBUILD_STATE: started\nPHASE: BUILD\n' | feat d-mid
printf 'PHASE: HANDOFF\n' | feat e-old
printf 'LANE: bug\nPHASE: VERIFY\nBUILD_STATE: done\nDRIFT_GATE: on\n' | feat f-bug
mkdir -p "$P/.sdd/_product"; printf 'PHASE: BACKLOG\n' > "$P/.sdd/_product/PROGRESS.md"
mkdir -p "$P/.sdd/g-noprogress"
src tests/t.py <<'T'
def test_a(): pass
T
run --all
assert "all-rc2-on-failure" "[ $rc -eq 2 ]"
assert "all-summary" "has 'BUILD_FLEET_DRIFT_GATE_SUMMARY: {\"checked\":2,\"unchecked\":1,\"in_progress\":2,\"failed\":[\"b-fail\"]}'"
assert "all-in-progress-line" "has '{\"feature\":\"c-spec\",\"pass\":true,\"in_progress\":true}'"
assert "all-skips-bug-and-product" "! has f-bug && ! has _product && ! has g-noprogress"
assert "all-one-line-per-feature" "[ \$(printf '%s\n' \"\$out\" | grep -c '^BUILD_FLEET_DRIFT_GATE: ') -eq 5 ]"
rm -rf "$P/.sdd/b-fail"; run --all
assert "all-rc0-when-clean" "[ $rc -eq 0 ] && has '\"failed\":[]'"
proj; rmdir "$P/.sdd"; run --all
assert "all-no-sdd" "[ $rc -eq 0 ] && has '{\"checked\":0,\"unchecked\":0,\"in_progress\":0,\"failed\":[]}'"

printf '\npassed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/drift-gate.test.sh | tail -3`
Expected: most cases `FAIL` (the script does not exist yet; `run` gets exit 127) and a final `passed=<few> failed=<many>` with failed > 0. The three `usage` cases may pass by accident (127 ≠ 1, so they fail too — any non-zero failed count is the expected RED).

- [ ] **Step 3: Write the implementation**

Create `scripts/drift-gate.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# scripts/drift-gate.sh — the drift gate: every acceptance criterion of a gated feature
# maps to a named test that exists in the repo. Static and model-free.
#
# Gated = PROGRESS.md carries `DRIFT_GATE: on` (absent, empty or `off` = unchecked; any
# other value = bad-field). Criteria = distinct AC-<n>[a-z] ids in acceptance.md, else in
# spec.md's `## Acceptance…` section (same id pattern as validate-acceptance-count.sh).
# Matrix = the table rows under TEST_PLAN.md's `## Coverage matrix`:
#   | AC-1, AC-2 | `test_name` | unit | `tests/file.py::test_name` |
# Each cell is trimmed of whitespace and one pair of backticks. Separator rows and
# header rows (first cell `Criterion`) are skipped. Column 2 is the name as declared in
# source; a trailing ` (failure)` and then a trailing `[…]` parametrize id are stripped.
# Column 4 before the first `::` is the file, relative to the project root.
#
# Reasons, in this order: bad-field no-test-plan no-criteria untested unknown-criterion
# missing-file missing-test gaps-open unparsed.
#
# Usage: drift-gate.sh <slug> | drift-gate.sh --all
# Output (stdout): one `BUILD_FLEET_DRIFT_GATE: {…}` line per feature; --all adds one
#   `BUILD_FLEET_DRIFT_GATE_SUMMARY: {"checked","unchecked","in_progress","failed"}` line.
# Exit: 0 = pass; 2 = fail; 1 = bad usage / unreadable workspace (CI keys off this).
# bash 3.2 + BSD/GNU compatible; read-only. Requires jq.
set -uo pipefail

usage() { echo "usage: drift-gate.sh <slug> | drift-gate.sh --all" >&2; exit 1; }
[ $# -eq 1 ] || usage
command -v jq >/dev/null 2>&1 || { echo "drift-gate.sh: jq is required" >&2; exit 1; }
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 1

# field <file> <NAME> — the value of the first "NAME:" line, whitespace stripped
field() { { grep -m1 "^$2:" "$1" 2>/dev/null || true; } | sed -E "s/^$2:[[:space:]]*//" | tr -d '\r '; }
add() { eval "$1=\"\${$1}\${$1:+\$'\\n'}\$2\""; }
tojson() { if [ -z "$1" ]; then printf '[]'; else printf '%s\n' "$1" | jq -R . | jq -sc .; fi; }

# has_word <file> <name> — name occurs with no [A-Za-z0-9_] on either side
has_word() {
  WANT="$2" awk 'BEGIN { w = ENVIRON["WANT"]; L = length(w) }
    { line = $0; off = 0
      while ((i = index(substr(line, off + 1), w)) > 0) {
        p = off + i
        b = (p > 1) ? substr(line, p - 1, 1) : ""
        a = substr(line, p + L, 1)
        if (b !~ /[A-Za-z0-9_]/ && a !~ /[A-Za-z0-9_]/) { found = 1; exit }
        off = p
      } }
    END { exit found ? 0 : 1 }' "$1"
}
# has_name <file> <name> — the whole-word / per-segment / substring rule of the spec
has_name() {
  local f="$1" n="$2" seg rest
  case "$n" in
    */*)
      rest="$n"
      while [ -n "$rest" ]; do
        seg="${rest%%/*}"
        if [ "$seg" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
        [ -n "$seg" ] || continue
        has_name "$f" "$seg" || return 1
      done
      return 0 ;;
  esac
  if printf '%s' "$n" | grep -qE '^[A-Za-z0-9_]+$'; then has_word "$f" "$n"
  else grep -qF -- "$n" "$f"; fi
}

# matrix_rows <TEST_PLAN.md> — one tab-separated record per (id,row):
#   R <id> <name> <location> <file>     or     U <row text>
matrix_rows() {
  awk -F'|' '
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function tick(s) { if (length(s) >= 2 && substr(s, 1, 1) == "`" && substr(s, length(s), 1) == "`") s = substr(s, 2, length(s) - 2); return trim(s) }
    function cell(s) { return tick(trim(s)) }
    /^## / { insec = ($0 ~ /^## Coverage matrix[ \t\r]*$/); next }
    !insec { next }
    { row = $0; sub(/\r$/, "", row) }
    row !~ /^[ \t]*\|/ { next }
    row ~ /^[ \t|:-]+$/ { next }
    {
      line = row; sub(/^[ \t]*\|/, "", line); sub(/\|[ \t]*$/, "", line)
      nc = split(line, c, "|")
      if (cell(c[1]) == "Criterion") next
      if (nc < 4) { print "U\t" row; next }
      name = trim(c[2]); sub(/[ \t]*\(failure\)$/, "", name); name = tick(name)
      sub(/[ \t]*\(failure\)$/, "", name); sub(/\[[^]]*\]$/, "", name); name = trim(name)
      loc = cell(c[4]); file = loc; k = index(file, "::"); if (k) file = substr(file, 1, k - 1)
      file = trim(file)
      n = split(cell(c[1]), ids, ","); good = (n > 0)
      for (j = 1; j <= n; j++) { ids[j] = trim(ids[j]); if (ids[j] !~ /^AC-[0-9]+[a-z]?$/) good = 0 }
      if (!good || name == "" || file == "") { print "U\t" row; next }
      for (j = 1; j <= n; j++) print "R\t" ids[j] "\t" name "\t" loc "\t" file
    }' "$1"
}

# check_one <slug> — prints one gate line; returns 0 pass, 2 fail, 1 unreadable
check_one() {
  local slug="$1" d=".sdd/$1" gate crit rows reasons="" untested="" unknown="" missing="" unparsed=""
  local f_untested="" f_unknown="" f_file="" f_test="" covered="" gaps=false tp
  local kind id name loc file rest
  [ -f "$d/PROGRESS.md" ] || { echo "drift-gate.sh: $d/PROGRESS.md not found" >&2; return 1; }
  local slug_json; slug_json=$(jq -n --arg s "$slug" '$s')
  gate=$(field "$d/PROGRESS.md" DRIFT_GATE)
  case "$gate" in
    ""|off) printf 'BUILD_FLEET_DRIFT_GATE: {"feature":%s,"pass":true,"unchecked":true}\n' "$slug_json"; return 0 ;;
    on) ;;
    *) printf 'BUILD_FLEET_DRIFT_GATE: {"feature":%s,"pass":false,"reasons":["bad-field"],"untested":[],"unknown":[],"missing":[],"unparsed":[],"gaps_open":false}\n' "$slug_json"; return 2 ;;
  esac

  if [ -f "$d/acceptance.md" ]; then
    crit=$({ grep -oE 'AC-[0-9]+[a-z]?' "$d/acceptance.md" || true; } | LC_ALL=C sort -u)
  elif [ -f "$d/spec.md" ]; then
    crit=$(awk '/^## /{ insec = ($0 ~ /^## Acceptance/); next } insec' "$d/spec.md" | { grep -oE 'AC-[0-9]+[a-z]?' || true; } | LC_ALL=C sort -u)
  else crit=""; fi

  tp="$d/TEST_PLAN.md"
  if [ -f "$tp" ]; then
    rows=$(matrix_rows "$tp")
    if awk '/^## /{ insec = ($0 ~ /^## Gaps[ \t\r]*$/); next } insec && /^[ \t]*- / { found = 1 } END { exit found ? 0 : 1 }' "$tp"; then gaps=true; fi
  else rows=""; add reasons no-test-plan; fi
  [ -n "$crit" ] || add reasons no-criteria

  while IFS="$(printf '\t')" read -r kind id name loc file; do
    case "$kind" in
      U) rest="$id${name:+	$name}${loc:+	$loc}${file:+	$file}"; add unparsed "$rest"; continue ;;
      R) ;;
      *) continue ;;
    esac
    add covered "$id"
    if ! printf '%s\n' "$crit" | grep -qxF -- "$id"; then
      printf '%s\n' "$unknown" | grep -qxF -- "$id" || add unknown "$id"
      f_unknown=1
    fi
    case "$file" in
      /*|*..*|.sdd/*|*/.sdd/*|*.md) add missing "$id	$name	$loc	missing-file"; f_file=1; continue ;;
    esac
    if [ ! -f "$file" ]; then add missing "$id	$name	$loc	missing-file"; f_file=1; continue; fi
    has_name "$file" "$name" || { add missing "$id	$name	$loc	missing-test"; f_test=1; }
  done <<EOF_ROWS
$rows
EOF_ROWS

  if [ -n "$crit" ]; then
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      printf '%s\n' "$covered" | grep -qxF -- "$id" || { add untested "$id"; f_untested=1; }
    done <<EOF_CRIT
$crit
EOF_CRIT
  fi

  [ -z "$f_untested" ] || add reasons untested
  [ -z "$f_unknown" ] || add reasons unknown-criterion
  [ -z "$f_file" ] || add reasons missing-file
  [ -z "$f_test" ] || add reasons missing-test
  [ "$gaps" = false ] || add reasons gaps-open
  [ -z "$unparsed" ] || add reasons unparsed

  local pass=true missing_json
  [ -z "$reasons" ] || pass=false
  if [ -z "$missing" ]; then missing_json='[]'
  else missing_json=$(printf '%s\n' "$missing" | jq -R 'split("\t") | {criterion: .[0], test: .[1], location: .[2], why: .[3]}' | jq -sc .); fi
  printf 'BUILD_FLEET_DRIFT_GATE: {"feature":%s,"pass":%s,"reasons":%s,"untested":%s,"unknown":%s,"missing":%s,"unparsed":%s,"gaps_open":%s}\n' \
    "$slug_json" "$pass" "$(tojson "$reasons")" "$(tojson "$untested")" "$(tojson "$unknown")" "$missing_json" "$(tojson "$unparsed")" "$gaps"
  [ "$pass" = true ] && return 0 || return 2
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
  bs=$(field "$d/PROGRESS.md" BUILD_STATE); ph=$(field "$d/PROGRESS.md" PHASE)
  built=false
  if [ "$bs" = done ]; then built=true
  elif [ -z "$bs" ]; then case "$ph" in CHANGE_REVIEW|HANDOFF) built=true ;; esac; fi
  if [ "$built" = false ]; then
    printf 'BUILD_FLEET_DRIFT_GATE: {"feature":%s,"pass":true,"in_progress":true}\n' "$(jq -n --arg s "$slug" '$s')"
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

- [ ] **Step 4: Run the harness to verify it passes**

Run: `bash scripts/drift-gate.test.sh | tail -1`
Expected: `passed=44 failed=0`

- [ ] **Step 5: Mutation check (the harness can fail)**

Apply each mutation to a copy, run the harness, restore. Each must turn at least the named case red:

| Mutation (in `drift-gate.sh`) | Case that must fail |
|---|---|
| `then has_word "$f" "$n"` → `then grep -qF -- "$n" "$f"` | `whole-word-no-prefix-match` |
| `insec = ($0 ~ /^## Acceptance/)` → `insec = 1` | `spec-fallback` |
| delete the line `row ~ /^[ \t|:-]+$/ { next }` | `aligned-separators-two-tables` |
| `\|*.md)` → `)` in the refused-location case | `refused-location README.md` |
| `function cell(s) { return tick(trim(s)) }` → `function cell(s) { return trim(s) }` | `pass-rc0` |
| `insec && /^[ \t]*- / { found = 1 }` → `insec && NF { found = 1 }` | `gaps-none-passes` |

```bash
cp scripts/drift-gate.sh /tmp/dg.orig
perl -0pi -e 's/then has_word "\$f" "\$n"/then grep -qF -- "\$n" "\$f"/' scripts/drift-gate.sh
bash scripts/drift-gate.test.sh | grep '^FAIL'      # expect whole-word-no-prefix-match
cp /tmp/dg.orig scripts/drift-gate.sh               # restore; repeat per row
```

Expected: every row's case appears under `FAIL`; after the last restore the harness is `passed=44 failed=0`.

- [ ] **Step 6: Commit**

```bash
git add scripts/drift-gate.sh scripts/drift-gate.test.sh
git commit -m "feat(gate): drift gate — every acceptance criterion maps to a named test

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The router reads `QA_FAIL`

**Files:**
- Modify: `scripts/lite-next.sh` (`route_feature`)
- Test: `scripts/lite-next.test.sh`

**Interfaces:**
- Consumes: the PROGRESS field `QA_FAIL: drift` (written by Task 3's commands).
- Produces: `lite-next.sh build` with `QA_FAIL: drift` (spec FINALIZED) → `{"step":"implement","args":"","why":"repair the test plan"}` at every BUILD_STATE; `lite-next.sh ship` with `QA_FAIL: drift` → `{"stop":"drift","next":"/build-fleet:build","why":"the test plan has drifted; build repairs it"}`.

- [ ] **Step 1: Write the failing tests**

In `scripts/lite-next.test.sh`, insert immediately before the line `rc=0; bash "$ROUTER" bogus >/dev/null 2>&1 || rc=$?`:

```bash
# ---- drift repair: QA_FAIL: drift sends build to implement, stops ship ----
for bs in unset started needs-iteration done; do
  proj; { printf 'PHASE: BUILD\nQA_FAIL: drift\n'; [ "$bs" = unset ] || printf 'BUILD_STATE: %s\n' "$bs"; } | feature f FINALIZED
  check "build-drift-repair-$bs" '"step":"implement","args":"","why":"repair the test plan"' build
done
proj; feature f FINALIZED <<'EOF'
PHASE: HANDOFF
BUILD_STATE: done
QA_FAIL: drift
EOF
check ship-drift '"stop":"drift","next":"/build-fleet:build"' ship

```

- [ ] **Step 2: Run to verify they fail**

Run: `bash scripts/lite-next.test.sh | grep -E '^FAIL|passed'`
Expected: `FAIL build-drift-repair-unset`, `-started`, `-needs-iteration`, `-done`, `FAIL ship-drift`; `lite-next: 74 passed, 5 failed`.

- [ ] **Step 3: Implement**

In `scripts/lite-next.sh`, `route_feature`:

1. Change `  local c="$1" slug="$2" phase="$3" d=".sdd/$2" st tier cyc bs` to
   `  local c="$1" slug="$2" phase="$3" d=".sdd/$2" st tier cyc bs qf`.
2. After the line `  cyc=$(num "$(field "$d/PROGRESS.md" CYCLE)"); bs=$(field "$d/PROGRESS.md" BUILD_STATE)` add:
   ```bash
     qf=$(field "$d/PROGRESS.md" QA_FAIL)
   ```
3. In the `build)` branch, immediately before `      case "$bs" in` (after the `if [ "$st" != FINALIZED ]; then … return; fi` block), add:
   ```bash
         # a test plan that failed the drift gate: implement runs only its qa repair pass
         if [ "$qf" = drift ]; then T implement "" "repair the test plan"; return; fi
   ```
4. Immediately after the line `    ship)`, add:
   ```bash
         if [ "$qf" = drift ]; then S drift "build" "the test plan has drifted; build repairs it"; return; fi
   ```

- [ ] **Step 4: Run to verify they pass**

Run: `bash scripts/lite-next.test.sh | tail -1`
Expected: `lite-next: 79 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add scripts/lite-next.sh scripts/lite-next.test.sh
git commit -m "feat(router): QA_FAIL: drift routes build to the repair pass and stops ship

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Firing points in the flow

**Files:**
- Modify: `commands/new-feature.md` (step 3 PROGRESS template)
- Modify: `commands/implement.md` (precondition 4, new steps b2 and e2, step e's "coder completed" branch)
- Modify: `commands/handoff.md` (step 2, step 4, Refusal cases)
- Create: `scripts/drift-wiring.test.sh`

**Interfaces:**
- Consumes: Task 1's `scripts/drift-gate.sh` and its line; Task 2's `QA_FAIL` routing.
- Produces: the PROGRESS fields `DRIFT_GATE: on` (new-feature) and `QA_FAIL: drift` (implement, handoff); the signals `BUILD_FLEET_QA_VERIFY_FAIL` reasons `drift` / `drift-gate-error`, `BUILD_FLEET_BUILD_INCOMPLETE` reason `drift-repair`, and the new `BUILD_FLEET_HANDOFF_REFUSE` (reasons `drift`, `drift-gate-error`). Task 4 documents them.

- [ ] **Step 1: Write the failing wiring test**

Create `scripts/drift-wiring.test.sh`:

```bash
#!/usr/bin/env bash
# Wiring for the drift gate (docs/history/2026-10-15-drift-gate.md §3.3–3.4): asserts
# each firing point, field and signal is written where the spec puts it, so a later
# edit cannot drop one silently. Run: bash scripts/drift-wiring.test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
# want <name> <file> <fixed string> [min count]
want() {
  local c; c=$(grep -cF -- "$3" "$ROOT/$2" 2>/dev/null || true)
  if [ "${c:-0}" -ge "${4:-1}" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$1"
  else fail=$((fail+1)); printf 'FAIL %s — %s lacks [%s] (x%s, found %s)\n' "$1" "$2" "$3" "${4:-1}" "${c:-0}"; fi
}

# ---- flow (§3.3) ----
want new-feature-field     commands/new-feature.md '   DRIFT_GATE: on'
want implement-calls-gate  commands/implement.md   'scripts/drift-gate.sh'
want implement-b2          commands/implement.md   'b2. **Drift gate (before coder).**'
want implement-e2          commands/implement.md   'e2. **Drift gate (after coder).**'
want implement-repair-mode commands/implement.md   '**Repair mode.**'
want implement-fail-line   commands/implement.md   'BUILD_FLEET_QA_VERIFY_FAIL: {"feature":"<slug>","reason":"drift","gate":'
want implement-qa-fail     commands/implement.md   'QA_FAIL: drift' 3
want implement-incomplete  commands/implement.md   '"reason":"drift-repair"'
want handoff-calls-gate    commands/handoff.md     'scripts/drift-gate.sh'
want handoff-refuse        commands/handoff.md     'BUILD_FLEET_HANDOFF_REFUSE: {"feature":"<slug>","code":2,"reason":"drift","gate":'
want handoff-resume        commands/handoff.md     'run the drift gate (step 4) and, if it passes, skip straight to step 9'
want handoff-refusal-case  commands/handoff.md     '- The drift gate fails'

printf '\npassed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash scripts/drift-wiring.test.sh | tail -1`
Expected: `passed=0 failed=12`

- [ ] **Step 3: `commands/new-feature.md`** — in step 3's PROGRESS template, replace

```
   CYCLE_TOTAL_MAX: 6
   UPDATED: <iso8601>
```

with

```
   CYCLE_TOTAL_MAX: 6
   DRIFT_GATE: on
   UPDATED: <iso8601>
```

- [ ] **Step 4: `commands/implement.md`, precondition 4** — after the line `   suite and is resumable), or `/build-fleet:handoff` if BUILD completed.` add:

```

   **Repair mode.** If PROGRESS.md carries `QA_FAIL: drift`, an earlier run stopped on
   the drift gate. The guard admits this run whatever the BUILD_STATE, and the run is a
   repair: skip step a (qa's authoring pass) and go straight to the repair pass.
   - `BUILD_STATE` absent → the repair pass of step b2 (the suite must be red). On a
     pass, continue to step c and coder as a normal build.
   - `BUILD_STATE` `started`, `needs-iteration` or `done` → the repair pass of step e2
     (the suite must be green). Coder is not dispatched.
```

- [ ] **Step 5: `commands/implement.md`, step b2** — after the paragraph ending `refuse via the precondition-4 re-run guard.` (the last paragraph of step b) and before `c. **Mark the build started.**`, add:

````
b2. **Drift gate (before coder).** Run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/drift-gate.sh" "<slug>"` and relay its
   `BUILD_FLEET_DRIFT_GATE:` line. `"pass":true` (an unchecked feature included) →
   step c. No line at all (exit 1) → emit
   `BUILD_FLEET_QA_VERIFY_FAIL: {"feature":"<slug>","reason":"drift-gate-error"}` with
   its stderr and stop. `"pass":false` → the **repair pass**, once. Use the Task tool
   to invoke `build-fleet:qa` with:

   > PHASE=BUILD for feature `<slug>`. The drift gate failed: `<the gate line>`. Fix
   > `.sdd/<slug>/TEST_PLAN.md`, or add or rename tests under `tests/`, so every
   > acceptance criterion maps to a named test, per the `test-plan` skill's matrix
   > grammar. Write no source. Every test must still FAIL. End with exactly:
   > `BUILD_FLEET_QA_TESTS_READY: <count> failing tests in tests/` giving the new count.

   Verify the suite against that count by step b's rules (a failure there emits step
   b's line and stops), then run the gate again.
   - Pass → remove `QA_FAIL` from PROGRESS.md if present; step c.
   - Still failing → set `QA_FAIL: drift` in PROGRESS.md, emit
     ```
     BUILD_FLEET_QA_VERIFY_FAIL: {"feature":"<slug>","reason":"drift","gate":<the gate line's JSON>}
     ```
     and stop. Coder is not dispatched and `BUILD_STATE` stays absent. The user fixes
     the rows the gate names; `/build-fleet:build` then re-enters in repair mode.

````

- [ ] **Step 6: `commands/implement.md`, step e** — in "**Branch — coder completed.**", replace

```
   been written, run the test suite one final time. If all tests pass, emit:
```

with

```
   been written, run the test suite one final time. If all tests pass, run step e2;
   when it passes, emit:
```

Then, after that branch's last paragraph (the one ending `STATUS stays FINALIZED,\n   PHASE stays BUILD.` that follows `BUILD_FLEET_BUILD_INCOMPLETE`), and before `## Hard rules`, add:

````

e2. **Drift gate (after coder).** Before `BUILD_STATE: done`, run the gate as in step
   b2 (no line → step b2's `drift-gate-error` line). `"pass":true` → emit
   `BUILD_FLEET_BUILD_COMPLETE` and set `BUILD_STATE: done` as above. `"pass":false` →
   the repair pass, once, with this brief:

   > PHASE=BUILD for feature `<slug>`; the source is built. The drift gate failed:
   > `<the gate line>`. Restore or rename tests under `tests/`, or fix
   > `.sdd/<slug>/TEST_PLAN.md`, so every acceptance criterion maps to a named test.
   > Write no source. The suite must stay green. End with exactly:
   > `BUILD_FLEET_QA_TESTS_READY: <count> tests in tests/`.

   Then run the suite and the gate again:
   - Suite green, gate passes → remove `QA_FAIL` if present, emit
     `BUILD_FLEET_BUILD_COMPLETE`, set `BUILD_STATE: done`.
   - Suite red (a restored test fails: behaviour is missing) → remove `QA_FAIL` if
     present, set `BUILD_STATE: needs-iteration`, emit
     `BUILD_FLEET_BUILD_INCOMPLETE: {"feature":"<slug>","failing_tests":<N>,"reason":"drift-repair"}`
     and stop. The next `/build-fleet:build` resumes coder through deep-build.
   - Gate still failing → set `QA_FAIL: drift`, emit step b2's `drift` line, stop.
````

- [ ] **Step 7: `commands/handoff.md`** — three edits.

(a) Step 2: replace `   on `"pass":true` skip straight to step 9.` with
`   on `"pass":true` run the drift gate (step 4) and, if it passes, skip straight to step 9.`
(re-wrap the paragraph's following line if it now runs long; keep the rest of the sentence).

(b) Step 4: after the bullet ending `     catching it here gives a clearer error.`, add:

```
   - Run the drift gate: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/drift-gate.sh" "<slug>"`,
     and relay its `BUILD_FLEET_DRIFT_GATE:` line. This runs before the change-cycle
     budget and before `CHANGE_CYCLE` moves, so a failure never spends a review cycle.
     `"pass":true` (an unchecked feature included) → continue. `"pass":false` → set
     `QA_FAIL: drift` in PROGRESS.md, emit
     `BUILD_FLEET_HANDOFF_REFUSE: {"feature":"<slug>","code":2,"reason":"drift","gate":<the gate line's JSON>}`
     and stop; `/build-fleet:build` repairs the test plan. No line at all (exit 1) →
     emit `BUILD_FLEET_HANDOFF_REFUSE: {"feature":"<slug>","code":2,"reason":"drift-gate-error"}`
     with its stderr and stop.
```

(c) Refusal cases: after `- No tests, or test command fails → refuse with the failing output.` add:

```
- The drift gate fails, or prints no line → `BUILD_FLEET_HANDOFF_REFUSE` with reason
  `drift` (and `QA_FAIL: drift` set) or `drift-gate-error`.
```

- [ ] **Step 8: Run to verify the wiring test passes, and nothing else broke**

Run: `bash scripts/drift-wiring.test.sh | tail -1 && bash scripts/run-tests.sh 2>&1 | tail -1`
Expected: `passed=12 failed=0`, then `suites: 47, failed: 0` (45 before this plan + `drift-gate` + `drift-wiring`).

- [ ] **Step 9: Commit**

```bash
git add commands/new-feature.md commands/implement.md commands/handoff.md scripts/drift-wiring.test.sh
git commit -m "feat(flow): drift gate fires before and after coder and at handoff; repair mode

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: qa's prompt, skills, contract, docs and smoke

**Files:**
- Modify: `agents/qa.md` (description + body after line 105)
- Modify: `skills/test-plan/SKILL.md` (new section before `## Discipline rules`)
- Modify: `skills/sdd-protocol/SKILL.md` (PROGRESS schema; BUILD section)
- Modify: `docs/v0.2/CONTRACT.md` (lite surface: stop reasons; new signals)
- Modify: `README.md`, `CLAUDE.md`, `CHANGELOG.md`
- Modify: `docs/v0.5/smoke/smoke.sh`
- Modify: `scripts/drift-wiring.test.sh` (doc assertions)

**Interfaces:**
- Consumes: the names fixed in Tasks 1–3 (`drift-gate.sh`, `DRIFT_GATE`, `QA_FAIL`, the four signals, stop `drift`).

- [ ] **Step 1: Extend the wiring test (failing)**

In `scripts/drift-wiring.test.sh`, before the final `printf '\npassed=…` line, add:

```bash
# ---- docs and qa's prompt (§3.4) ----
want qa-description   agents/qa.md                  'and its repair pass when the drift gate fails'
want qa-body          agents/qa.md                  'The drift gate (`scripts/drift-gate.sh`)'
want skill-section    skills/test-plan/SKILL.md     '## The drift gate'
want skill-name-rule  skills/test-plan/SKILL.md     'as declared in source'
want protocol-gate    skills/sdd-protocol/SKILL.md  'DRIFT_GATE: on | off'
want protocol-qafail  skills/sdd-protocol/SKILL.md  'QA_FAIL: drift'
want protocol-build   skills/sdd-protocol/SKILL.md  '**Drift gate.**'
want contract-line    docs/v0.2/CONTRACT.md         'BUILD_FLEET_DRIFT_GATE: {'
want contract-summary docs/v0.2/CONTRACT.md         'BUILD_FLEET_DRIFT_GATE_SUMMARY: {'
want contract-refuse  docs/v0.2/CONTRACT.md         'BUILD_FLEET_HANDOFF_REFUSE: {'
want contract-stop    docs/v0.2/CONTRACT.md         '`drift` (the test plan failed the drift gate'
want readme-ci        README.md                     'scripts/drift-gate.sh --all'
want claude-md        CLAUDE.md                     'drift-gate'
want changelog        CHANGELOG.md                  '`scripts/drift-gate.sh`'
want smoke            docs/v0.5/smoke/smoke.sh      'echo "[DRIFT]"'
```

Run: `bash scripts/drift-wiring.test.sh | tail -1`
Expected: `passed=12 failed=15`

- [ ] **Step 2: `agents/qa.md`**

Description (line 3): replace `(TEST_PLAN.md + the failing suite, before coder runs)` with
`(TEST_PLAN.md + the failing suite, before coder runs, and its repair pass when the drift gate fails)`.

Body: after the paragraph ending `coverage type (unit / integration / e2e). Then implement the tests.` add:

```

The drift gate (`scripts/drift-gate.sh`) checks your matrix with no model: before coder
starts, after coder finishes, and at handoff. Every criterion needs a row, and every
row's test name must appear in the file its location names. Write the name as declared
in source (the function name, or a test's description string without the `it(` call or
its quotes), per the `test-plan` skill's matrix grammar. When the gate fails you get one
repair pass with its line: fix the plan or the test names (after coder: restore or rename
tests), write no source, and end with your ready signal and the new count.
```

- [ ] **Step 3: `skills/test-plan/SKILL.md`** — before `## Discipline rules`, add:

````
## The drift gate

`scripts/drift-gate.sh` enforces the coverage matrix for every feature whose
PROGRESS.md carries `DRIFT_GATE: on` (new features get it). It reads:

- **Criteria:** the distinct `AC-<n>` / `AC-<n><letter>` ids in `acceptance.md` (or,
  without one, in spec.md's `## Acceptance…` section).
- **The matrix:** table rows under the exact heading `## Coverage matrix`, up to the
  next `## ` heading. Several tables under it are fine; header and separator rows are
  skipped.
  - Column 1: one or more ids, comma-separated.
  - Column 2: the test name **as declared in source**: `test_retry`, or a description
    string without the runner call or quotes (`retries 3 times`, not
    `it('retries 3 times')`). A ` (failure)` suffix and a `[…]` parametrize id are
    ignored. A Go subtest is `TestParent/child`.
  - Column 4: `path/to/file::name` or a bare path, relative to the project root; not
    under `.sdd/`, not a `.md` file.
- **Gaps:** any `- ` bullet under `## Gaps` fails the gate; `None.` does not.

It fails when a criterion has no row, a row names an unknown id, the file is missing,
the name is not in the file (whole word for `[A-Za-z0-9_]` names, exact text
otherwise), a gap is open, or a row cannot be read. It runs before coder, after
coder and at handoff, and `drift-gate.sh --all` runs it in CI over every built
feature. It proves the test exists, not that it tests the criterion; that stays
your review.
````

- [ ] **Step 4: `skills/sdd-protocol/SKILL.md`**

(a) PROGRESS schema: after the line starting `LAST_REVIEW_OUTPUT_TOKENS:` add:

```
DRIFT_GATE: on | off        # drift gate (scripts/drift-gate.sh): on ⇒ every AC-n must map to a named test. new-feature writes on; absent/empty/off ⇒ unchecked
QA_FAIL: drift              # the drift gate failed and the test plan still needs repair; /build-fleet:implement's repair mode clears it
```

(b) BUILD section: before the paragraph starting `Both roles first load any skills routed to them`, add:

```
**Drift gate.** `scripts/drift-gate.sh` proves every acceptance criterion maps to a
named test in TEST_PLAN.md's coverage matrix. `/build-fleet:implement` runs it after
qa's suite is verified (before coder) and again before `BUILD_STATE: done`; each failure
gets one qa repair pass, then sets `QA_FAIL: drift` and stops. `/build-fleet:handoff`
runs it before the change-cycle budget; a failure sets `QA_FAIL: drift` and refuses.
With `QA_FAIL: drift` set, `/build-fleet:build` routes to implement's repair mode.
```

- [ ] **Step 5: `docs/v0.2/CONTRACT.md`** (lite surface section)

(a) Stop reasons: replace `` `spec-not-ready`, `not-built`; and `status`, used only by `lite-next.sh status` when the``
with `` `spec-not-ready`, `not-built`, `drift` (the test plan failed the drift gate; `next` is `build`, which repairs it); and `status`, used only by `lite-next.sh status` when the``.

(b) After the paragraph ending `` `scripts/lite-next.test.sh` pins one case per row.``, add:

````

### The drift gate

`scripts/drift-gate.sh <slug>` prints one line; `--all` prints one per feature and a
summary (it gates only built features: `BUILD_STATE: done`, or no BUILD_STATE at
`CHANGE_REVIEW`/`HANDOFF`; it skips bugs and `_product`):

```
BUILD_FLEET_DRIFT_GATE: {"feature":"<slug>","pass":<bool>,"reasons":[…],"untested":[…],"unknown":[…],"missing":[{"criterion","test","location","why"}],"unparsed":[…],"gaps_open":<bool>}
BUILD_FLEET_DRIFT_GATE: {"feature":"<slug>","pass":true,"unchecked":true}
BUILD_FLEET_DRIFT_GATE: {"feature":"<slug>","pass":true,"in_progress":true}
BUILD_FLEET_DRIFT_GATE_SUMMARY: {"checked":N,"unchecked":M,"in_progress":K,"failed":[…]}
```

Reasons: `bad-field`, `no-test-plan`, `no-criteria`, `untested`, `unknown-criterion`,
`missing-file`, `missing-test`, `gaps-open`, `unparsed`. The script's exit status (2 on
any failure) exists for CI; inside the flow, read the line. The steps that run it add:

```
BUILD_FLEET_QA_VERIFY_FAIL: {"feature":"<slug>","reason":"drift","gate":{…}}       # implement; also "drift-gate-error"
BUILD_FLEET_BUILD_INCOMPLETE: {"feature":"<slug>","failing_tests":<N>,"reason":"drift-repair"}
BUILD_FLEET_HANDOFF_REFUSE: {"feature":"<slug>","code":2,"reason":"drift","gate":{…}}  # also "drift-gate-error"
```
````

- [ ] **Step 6: `README.md`** — after the bullet `- Every gate fails closed: an unexpected state blocks rather than allows.` add:

````
- Every acceptance criterion maps to a named test that exists, checked before and
  after the build and at ship. Run the same check in your CI:

  ```bash
  bash <path-to-build-fleet>/scripts/drift-gate.sh --all   # exit 2 on drift
  ```
````

- [ ] **Step 7: `CLAUDE.md`** — in the layout block replace
`                              #   lite-next — the lite commands' router)` with
`                              #   lite-next — the lite commands' router, drift-gate)`.

- [ ] **Step 8: `CHANGELOG.md`** — under `## [Unreleased] — 0.12.0 (lite)` → `### Added`, after the `scripts/workflow-parse.test.sh` bullet (two lines), add:

```
- **Drift gate** — `scripts/drift-gate.sh` proves every acceptance criterion of a gated feature
  (`DRIFT_GATE: on`, written by `new-feature`) maps to a named test that exists. It runs before
  and after coder and at `handoff`; a failure gets one qa repair pass, then `QA_FAIL: drift` and
  `build` repairs it. `drift-gate.sh --all` runs it in CI over every built feature.
```

- [ ] **Step 9: `docs/v0.5/smoke/smoke.sh`** — insert before the final block (the line `echo` that precedes `echo "-----"`):

```bash
# ---------- DRIFT (a built feature's criteria stay mapped to named tests) ----------
echo "[DRIFT]"
mkdir -p .sdd/pager-totals
printf 'FEATURE: pager-totals\nPHASE: HANDOFF\nBUILD_STATE: done\nDRIFT_GATE: on\n' > .sdd/pager-totals/PROGRESS.md
printf '# Acceptance Criteria — pager-totals\n\n- AC-1: a partial last page is counted.\n- AC-2: an empty list has no pages.\n' > .sdd/pager-totals/acceptance.md
printf '# Test Plan — pager-totals\n\n## Coverage matrix\n\n| Criterion | Test name | Type | Location |\n|---|---|---|---|\n| AC-1 | `test_partial_last_page_is_counted` | unit | `tests/test_pagination.py::test_partial_last_page_is_counted` |\n| AC-2 | `test_empty_has_no_pages` | unit | `tests/test_pagination.py::test_empty_has_no_pages` |\n' > .sdd/pager-totals/TEST_PLAN.md
drift(){ local rc=0; CLAUDE_PROJECT_DIR="$work" bash "$PLUGIN/scripts/drift-gate.sh" --all >/dev/null 2>&1 || rc=$?; printf '%s' "$rc"; }
check "drift gate: every criterion mapped → pass" "$(drift)" 0
sed 's/def test_empty_has_no_pages/def test_renamed_away/' tests/test_pagination.py > tests/renamed.tmp && mv tests/renamed.tmp tests/test_pagination.py
check "drift gate: a mapped test renamed away → fail" "$(drift)" 2

```

- [ ] **Step 10: Run everything**

Run: `bash scripts/drift-wiring.test.sh | tail -1; bash docs/v0.5/smoke/smoke.sh | tail -3; bash scripts/rubric-drift.test.sh | tail -1; bash scripts/lens-drift.test.sh | tail -1; bash scripts/run-tests.sh 2>&1 | tail -1`
Expected: `passed=27 failed=0`; smoke `passed=25 failed=0` + `SMOKE PASS …`; rubric-drift and lens-drift green; `suites: 47, failed: 0`.

- [ ] **Step 11: Commit**

```bash
git add agents/qa.md skills/test-plan/SKILL.md skills/sdd-protocol/SKILL.md docs/v0.2/CONTRACT.md README.md CLAUDE.md CHANGELOG.md docs/v0.5/smoke/smoke.sh scripts/drift-wiring.test.sh
git commit -m "docs(gate): drift gate in qa's prompt, the test-plan grammar, the contract and the smoke test

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Live run

**Files:** none in the repo (scratch: `/tmp/bf-lite`). Findings that need a change go through TDD in the owning task's files and are committed as fixes.

- [ ] **Step 1: A fresh feature through the lite commands**

```bash
cd /tmp/bf-lite && git status --short | head      # the earlier live-run repo; leave its old features
env -u ANTHROPIC_API_KEY claude -p --plugin-dir ~/build-fleet-0.12 --permission-mode acceptEdits \
  --allowedTools=Bash,Read,Write,Edit,Task,Skill,Workflow \
  "/build-fleet:start add a --dry-run flag that prints the upload plan without sending" > /tmp/bf-lite/run-start.log 2>&1
```

Then `build` and `ship` the same way (`run-build.log`, `run-ship.log`), answering any clarifying question in a follow-up `-p` with `--continue`.

Expected:
- `.sdd/<slug>/PROGRESS.md` has `DRIFT_GATE: on`.
- `run-build.log` contains `BUILD_FLEET_DRIFT_GATE:` twice (before and after coder), both `"pass":true`, or a repair pass that ends in a pass.
- `run-ship.log` contains `BUILD_FLEET_DRIFT_GATE:` with `"pass":true` before the change review, and ends `BUILD_FLEET_LITE_DONE: {"stop":"shipped"}`.
- `CLAUDE_PROJECT_DIR=/tmp/bf-lite bash ~/build-fleet-0.12/scripts/drift-gate.sh --all` exits 0 and counts the new feature as checked.

- [ ] **Step 2: Drift after ship**

Rename one mapped test in the new feature's test file, then:
- `drift-gate.sh --all` exits 2 and names the criterion.
- `CLAUDE_PROJECT_DIR=/tmp/bf-lite bash ~/build-fleet-0.12/scripts/lite-next.sh ship` → after setting `QA_FAIL: drift` by hand (what handoff would write), `{"stop":"drift","next":"/build-fleet:build",…}`.
- `claude -p … "/build-fleet:build"` → repair mode: qa restores the name, the gate passes, `QA_FAIL` is gone, `BUILD_STATE: done`.

- [ ] **Step 3: Record and finish**

Run: `bash scripts/run-tests.sh 2>&1 | tail -1`
Expected: `suites: 47, failed: 0`. Record the live-run outcome (pass, or each finding and its fix commit) for the final report.
