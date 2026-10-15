#!/usr/bin/env bash
# Tests for scripts/drift-gate.sh (the drift gate: every acceptance criterion in the spec
# is named by a `<slug>/AC-n` marker in a test file). One fixture project per case;
# asserts the BUILD_FLEET_DRIFT_GATE line(s) and the exit code.
# Run: bash scripts/drift-gate.test.sh   (exit 0 = all pass)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$DIR/drift-gate.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass=0; fail=0; n=0

# proj — a fresh project; sets $P
proj() { n=$((n+1)); P="$work/p$n"; mkdir -p "$P/.sdd"; }
# feat <slug> — PROGRESS.md: SDD_SCHEMA: 2, FEATURE, then stdin
feat() { mkdir -p "$P/.sdd/$1"; { printf 'SDD_SCHEMA: 2\nFEATURE: %s\n' "$1"; cat; } > "$P/.sdd/$1/PROGRESS.md"; }
# spec <slug> <ids…> — spec.md with the ids in its acceptance section
spec() { local s="$1"; shift; { printf 'STATUS: FINALIZED\n\n# %s\n\n## Acceptance Criteria\n\n' "$s"; for i in "$@"; do printf -- '- **%s**: behaviour %s.\n' "$i" "$i"; done; } > "$P/.sdd/$s/spec.md"; }
# src <path> — a file with stdin as its content
src() { mkdir -p "$P/$(dirname "$1")"; cat > "$P/$1"; }
run() { out=$( cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$GATE" "$@" 2>/dev/null ); rc=$?; }
has() { printf '%s' "$out" | grep -qF -- "$1"; }
assert() { local name="$1" cond="$2"; if eval "$cond"; then pass=$((pass+1)); printf 'ok   %-44s\n' "$name"; else fail=$((fail+1)); printf 'FAIL %-44s (%s) out=%s\n' "$name" "$cond" "${out:-}"; fi; }
# base [fields] — feature f, criteria AC-1 AC-2, tests/test_f.py marking both
base() {
  proj; printf 'PHASE: BUILD\n%s' "${1:-}" | feat f; spec f AC-1 AC-2
  src tests/test_f.py <<'T'
# f/AC-1
def test_one(): pass
def test_two(): pass  # f/AC-2
T
}
# only <path> — replace the test tree with one file (content on stdin)
only() { rm -rf "$P/tests"; src "$1"; }

# --- pass, default-on, off, explicit on, bad field ---
base; run f
assert "pass" "[ $rc -eq 0 ] && has 'BUILD_FLEET_DRIFT_GATE: {\"feature\":\"f\",\"pass\":true,\"reasons\":[],\"untested\":[],\"unknown\":[]}'"
proj; printf 'PHASE: BUILD\n' | feat f; spec f AC-1; mkdir -p "$P/tests"; run f
assert "gate-default-on" "[ $rc -eq 2 ] && has '\"untested\":[\"AC-1\"]'"
base 'DRIFT_GATE: off
'; run f
assert "unchecked-off" "[ $rc -eq 0 ] && has '{\"feature\":\"f\",\"pass\":true,\"unchecked\":true}'"
base 'DRIFT_GATE: on
'; run f
assert "explicit-on" "[ $rc -eq 0 ] && has '\"pass\":true'"
base 'DRIFT_GATE: yes
'; run f
assert "bad-field-drift-gate" "[ $rc -eq 2 ] && has '\"reasons\":[\"bad-field\"]'"

# --- schema, criteria ---
base; sed -i.bak 's/^SDD_SCHEMA: 2$/SDD_SCHEMA: 1/' "$P/.sdd/f/PROGRESS.md"; run f
assert "unsupported-schema" "[ $rc -eq 2 ] && has '\"reasons\":[\"unsupported-schema\"]'"
base; spec f; run f
assert "no-criteria" "[ $rc -eq 2 ] && has '\"reasons\":[\"no-criteria\",\"unknown-criterion\"]'"
base; rm "$P/.sdd/f/spec.md"; only tests/t.py </dev/null; run f
assert "no-spec-is-no-criteria" "[ $rc -eq 2 ] && has '\"reasons\":[\"no-criteria\"]'"

# --- coverage ---
base; only tests/test_f.py <<'T'
def test_one(): pass  # f/AC-1
T
run f
assert "untested" "[ $rc -eq 2 ] && has '\"reasons\":[\"untested\"]' && has '\"untested\":[\"AC-2\"]'"
base; printf '# f/AC-7\n' >> "$P/tests/test_f.py"; run f
assert "unknown-criterion" "[ $rc -eq 2 ] && has '\"reasons\":[\"unknown-criterion\"]' && has '\"unknown\":[\"AC-7\"]'"
base; printf '# g/AC-7\n# g/AC-1\n' >> "$P/tests/test_f.py"; run f
assert "other-feature-markers-ignored" "[ $rc -eq 0 ]"
base; only tests/t.py <<'T'
# AC-1
# AC-2
T
run f
assert "bare-id-not-a-marker" "[ $rc -eq 2 ] && has '\"untested\":[\"AC-1\",\"AC-2\"]'"
proj; printf 'PHASE: BUILD\n' | feat f; spec f AC-3; src tests/t.py <<'T'
# f/AC-30
T
run f
assert "no-match-AC-30" "[ $rc -eq 2 ] && has '\"untested\":[\"AC-3\"]' && has '\"unknown\":[\"AC-30\"]'"
proj; printf 'PHASE: BUILD\n' | feat f; spec f AC-3; src tests/t.py <<'T'
# f/AC-3a
T
run f
assert "no-match-AC-3a-for-AC-3" "[ $rc -eq 2 ] && has '\"untested\":[\"AC-3\"]' && has '\"unknown\":[\"AC-3a\"]'"
proj; printf 'PHASE: BUILD\n' | feat f; spec f AC-1; src tests/t.py <<'T'
# old-f/AC-1
T
run f
assert "no-match-prefixed-slug" "[ $rc -eq 2 ] && has '\"untested\":[\"AC-1\"],\"unknown\":[]'"
proj; printf 'PHASE: BUILD\n' | feat f; spec f AC-1; src tests/t.py <<'T'
x.f/AC-1
T
run f
assert "no-match-dot-prefix" "[ $rc -eq 2 ] && has '\"untested\":[\"AC-1\"]'"
base; only tests/t.ts <<'T'
//f/AC-1
///f/AC-2
T
run f
assert "slash-comment-matches" "[ $rc -eq 0 ]"
base; only tests/t.py <<'T'
#f/AC-1 #f/AC-2
T
run f
assert "hash-no-space-matches" "[ $rc -eq 0 ]"
base; printf '# see f/AC-notes\n' >> "$P/tests/test_f.py"; run f
assert "not-a-criterion-shape" "[ $rc -eq 0 ]"
proj; printf 'PHASE: BUILD\n' | feat f; spec f AC-1; src tests/t.py <<'T'
# f/AC-1_x
T
run f
assert "trailing-underscore-rejected" "[ $rc -eq 2 ] && has '\"untested\":[\"AC-1\"]'"
base; only tests/README.md <<'T'
f/AC-1 f/AC-2
T
run f
assert "md-file-ignored" "[ $rc -eq 2 ] && has '\"untested\":[\"AC-1\",\"AC-2\"]'"
base; rm -rf "$P/tests"; mkdir -p "$P/tests"; printf '# f/AC-1\r\ndef t(): pass  # f/AC-2\r\n' > "$P/tests/t.py"; run f
assert "marker-crlf" "[ $rc -eq 0 ]"

# --- test roots ---
base; mv "$P/tests" "$P/test"; run f
assert "default-roots-test-dir" "[ $rc -eq 0 ]"
base; mv "$P/tests" "$P/spec"; run f
assert "default-roots-spec-dir" "[ $rc -eq 0 ]"
base; rm -rf "$P/tests"; run f
assert "default-roots-none" "[ $rc -eq 2 ] && has '\"reasons\":[\"no-test-roots\",\"untested\"]' && has '\"untested\":[\"AC-1\",\"AC-2\"]'"
base 'TEST_ROOTS: src, e2e
'; rm -rf "$P/tests"; src src/a.test.ts <<'T'
// f/AC-1
T
src e2e/b.spec.ts <<'T'
// f/AC-2
T
run f
assert "test-roots-csv" "[ $rc -eq 0 ]"
base 'TEST_ROOTS: nope
'; run f
assert "test-roots-missing" "[ $rc -eq 2 ] && has '\"no-test-roots\"'"
base 'TEST_ROOTS: tests,nope
'; run f
assert "test-roots-one-missing" "[ $rc -eq 2 ] && has '\"no-test-roots\"'"
base 'TEST_ROOTS: tests,,src
'; run f
assert "test-roots-empty-entry" "[ $rc -eq 2 ] && has '\"reasons\":[\"bad-field\"]'"
base 'TEST_ROOTS: tests,
'; run f
assert "test-roots-trailing-comma" "[ $rc -eq 2 ] && has '\"reasons\":[\"bad-field\"]'"
base 'TEST_ROOTS: ,tests
'; run f
assert "test-roots-leading-comma" "[ $rc -eq 2 ] && has '\"reasons\":[\"bad-field\"]'"
base 'TEST_ROOTS: /tmp
'; run f
assert "test-roots-absolute" "[ $rc -eq 2 ] && has '\"reasons\":[\"bad-field\"]'"
base 'TEST_ROOTS: ../x
'; run f
assert "test-roots-dotdot" "[ $rc -eq 2 ] && has '\"reasons\":[\"bad-field\"]'"
base 'TEST_ROOTS: .sdd
'; run f
assert "test-roots-sdd" "[ $rc -eq 2 ] && has '\"reasons\":[\"bad-field\"]'"
base 'TEST_ROOTS: .sdd/f
'; run f
assert "test-roots-under-sdd" "[ $rc -eq 2 ] && has '\"reasons\":[\"bad-field\"]'"
base 'TEST_ROOTS:
'; run f
assert "test-roots-empty-value-is-absent" "[ $rc -eq 0 ]"
base; src tests/node_modules/x.js <<'T'
// f/AC-9
T
run f
assert "skip-node-modules" "[ $rc -eq 0 ]"
base; src tests/.git/x <<'T'
f/AC-9
T
run f
assert "skip-git-dir" "[ $rc -eq 0 ]"
base; only "tests/my tests/t.py" <<'T'
# f/AC-1 f/AC-2
T
run f
assert "path-with-spaces" "[ $rc -eq 0 ]"

# --- usage ---
proj; run ../x
assert "bad-slug" "[ $rc -eq 1 ]"
proj; run nope
assert "missing-workspace" "[ $rc -eq 1 ]"

# --- --all ---
proj
printf 'PHASE: HANDOFF\nBUILD_STATE: done\n' | feat f; spec f AC-1
printf 'PHASE: HANDOFF\nBUILD_STATE: done\n' | feat g; spec g AC-1
printf 'PHASE: SPEC\n' | feat h; spec h AC-1
mkdir -p "$P/.sdd/o"; printf 'SDD_SCHEMA: 1\nPHASE: HANDOFF\nBUILD_STATE: done\n' > "$P/.sdd/o/PROGRESS.md"
mkdir -p "$P/.sdd/b"; printf 'SDD_SCHEMA: 1\nLANE: bug\nPHASE: HANDOFF\n' > "$P/.sdd/b/PROGRESS.md"
src tests/t.py <<'T'
# f/AC-1
T
run --all
assert "all-mixed-rc" "[ $rc -eq 2 ]"
assert "all-mixed-old-schema-unchecked" "has '{\"feature\":\"o\",\"pass\":true,\"unchecked\":true,\"schema\":\"1\"}'"
assert "all-mixed-in-progress" "has '{\"feature\":\"h\",\"pass\":true,\"in_progress\":true}'"
assert "all-mixed-bug-skipped" "! has '\"feature\":\"b\"'"
assert "all-mixed-summary" "has 'BUILD_FLEET_DRIFT_GATE_SUMMARY: {\"checked\":2,\"unchecked\":1,\"in_progress\":1,\"failed\":[\"g\"]}'"
proj
printf 'PHASE: HANDOFF\nBUILD_STATE: done\n' | feat f; spec f AC-1
src tests/t.py <<'T'
# f/AC-1
T
run --all
assert "all-pass" "[ $rc -eq 0 ] && has '\"failed\":[]'"

echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
