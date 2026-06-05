#!/usr/bin/env bash
# Tests for hooks/scripts/block-source-before-finalized.sh.
# Locks in the forward FINALIZED gate (AC-17 — byte-identical pre-/post-M2) AND the
# v0.5 M2 bug-lane second unlock (AC-18).
# Run: bash hooks/scripts/block-source-before-finalized.test.sh   (exit 0 = all pass)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/block-source-before-finalized.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass=0; fail=0

dbody() {
  printf 'STATUS: %s\n\n# Bug: x\n\n## Symptom + reproduction steps\na\n\n## Root-cause hypothesis\nb\n\n## Blast radius\nc\n\n## Fix strategy\nd\n' "$1"
}
new_proj() { local p="$work/$1"; mkdir -p "$p/.sdd"; printf '%s' "$p"; }
check() {
  local name="$1" proj="$2" fp="$3" want="$4" rc=0
  ( cd "$proj" && printf '{"tool_input":{"file_path":"%s"}}' "$fp" | bash "$HOOK" >/dev/null 2>&1 ); rc=$?
  if [ "$rc" -eq "$want" ]; then pass=$((pass+1)); printf 'ok   %-36s rc=%s\n' "$name" "$rc"
  else fail=$((fail+1)); printf 'FAIL %-36s want=%s got=%s\n' "$name" "$want" "$rc"; fi
}

# --- forward feature (AC-17): byte-identical to pre-M2 behavior ---
p=$(new_proj f1); printf 'feat\n' > "$p/.sdd/ACTIVE"; mkdir -p "$p/.sdd/feat"; printf 'STATUS: DRAFT\n' > "$p/.sdd/feat/spec.md"
check "feature-draft-blocks-source" "$p" "src/app.py" 2
p=$(new_proj f2); printf 'feat\n' > "$p/.sdd/ACTIVE"; mkdir -p "$p/.sdd/feat"; printf 'STATUS: FINALIZED\n' > "$p/.sdd/feat/spec.md"
check "feature-finalized-allows-source" "$p" "src/app.py" 0
check "feature-sdd-write-always-ok" "$p" ".sdd/feat/spec.md" 0
p=$(new_proj f3); printf 'feat\n' > "$p/.sdd/ACTIVE"; mkdir -p "$p/.sdd/feat"   # spec.md absent → no STATUS
check "feature-missing-spec-blocks" "$p" "src/app.py" 2
p=$(new_proj f4); : > "$p/.sdd/ACTIVE"
check "no-active-allows-source" "$p" "src/app.py" 0

# --- bug lane (AC-18): the second unlock ---
p=$(new_proj b1); printf 'bug\n' > "$p/.sdd/ACTIVE"; mkdir -p "$p/.sdd/bug"; dbody CONFIRMED > "$p/.sdd/bug/diagnosis.md"
check "bug-confirmed-unlocks-source" "$p" "src/app.py" 0
p=$(new_proj b2); printf 'bug\n' > "$p/.sdd/ACTIVE"; mkdir -p "$p/.sdd/bug"; dbody DIAGNOSED > "$p/.sdd/bug/diagnosis.md"
check "bug-not-confirmed-blocks-source" "$p" "src/app.py" 2
p=$(new_proj b3); printf 'bug\n' > "$p/.sdd/ACTIVE"; mkdir -p "$p/.sdd/bug"; dbody REPORTED > "$p/.sdd/bug/diagnosis.md"
check "bug-reported-blocks-source" "$p" "src/app.py" 2
check "bug-sdd-write-always-ok" "$p" ".sdd/bug/diagnosis.md" 0
# AC-7: a bug's tests/ write is allowed BEFORE CONFIRMED (the reproducing test lands at
# REPRODUCE; blocking it would deadlock the lane against require-reproducing-test).
check "bug-tests-write-allowed-pre-confirmed" "$p" "tests/test_x.py" 0

# --- regression (fail-open guard): a status-less diagnosis.md / spec.md must BLOCK ---
# (exit 2), not fail open (exit 1) under bash 3.2's set -e + pipefail.
p=$(new_proj b4); printf 'bug\n' > "$p/.sdd/ACTIVE"; mkdir -p "$p/.sdd/bug"; printf '# Bug: no status line\n## Symptom + reproduction steps\na\n## Root-cause hypothesis\nb\n## Blast radius\nc\n## Fix strategy\nd\n' > "$p/.sdd/bug/diagnosis.md"
check "bug-statusless-diagnosis-blocks" "$p" "src/app.py" 2
p=$(new_proj f5); printf 'feat\n' > "$p/.sdd/ACTIVE"; mkdir -p "$p/.sdd/feat"; printf '# spec without status\n' > "$p/.sdd/feat/spec.md"
check "feature-statusless-spec-blocks" "$p" "src/app.py" 2

echo "-----"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
