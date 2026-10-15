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

# --- a file named like an awk assignment; a name of only slashes ---
proj; printf 'DRIFT_GATE: on\n' | feat f; acc f AC-1 AC-2
src 'k=v' <<'T'
def test_one(): pass
T
src tests/t.py <<'T'
def test_two(): pass
T
plan f <<'T'
| AC-1 | `test_one` | unit | `k=v` |
| AC-2 | `test_two` | unit | `tests/t.py` |
T
run f
assert "file-named-like-assignment" "[ $rc -eq 0 ]"
base; plan f <<'T'
| AC-1 | `/` | unit | `tests/test_f.py` |
| AC-2 | `test_two` | unit | `tests/test_f.py` |
T
run f
assert "slash-only-name-fails" "[ $rc -eq 2 ] && has missing-test"

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
