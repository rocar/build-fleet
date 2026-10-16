#!/usr/bin/env bash
# Planted-bug smoke test for the troubleshoot-fix bug lane (v0.5).
#
# Drives a real planted bug (docs/v0.5/smoke/fixture/) through the lane's DETERMINISTIC
# backbone — the diagnosis.md validator and the two source-write gates — invoking the ACTUAL
# plugin hooks at every gate, plus the RED→GREEN transition and the VERIFY counterfactual.
# Runnable with NO plugin enabled; it exercises exactly the hooks a live run would fire.
# (The LLM-driven parts — the bug-mode classifier and diagnose.js confirmation — are NOT
# scriptable; WALKTHROUGH.md drives those with `claude --plugin-dir .`.)
#
# Run: bash docs/v0.5/smoke/smoke.sh        (exit 0 = every gate behaved correctly)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
HOOKS="$PLUGIN/hooks/scripts"
FIX="$HERE/fixture"
SLUG="bug-pagination-drops-last-page"

command -v python3 >/dev/null 2>&1 || { echo "smoke: python3 required"; exit 2; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cd "$work"

pass=0; fail=0
ok(){ pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no(){ fail=$((fail+1)); printf '  FAIL %s — %s\n' "$1" "$2"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected[$3] got[$2]"; fi; }

# --- hook helpers (cwd is the temp project, so hook path-resolution matches a real run) ---
hook_rc(){ local h="$1" fp="$2" rc=0; printf '{"tool_input":{"file_path":"%s"}}' "$fp" | bash "$HOOKS/$h" >/dev/null 2>&1 || rc=$?; printf '%s' "$rc"; }
# the source-write gate = BOTH PreToolUse hooks; BLOCKED if either exits 2.
gate(){ local fp="$1" b r; b=$(hook_rc block-source-before-finalized.sh "$fp"); r=$(hook_rc require-reproducing-test.sh "$fp"); if [ "$b" = 2 ] || [ "$r" = 2 ]; then printf 'BLOCKED'; else printf 'ALLOWED'; fi; }
validate_diag(){ hook_rc validate-diagnosis-status.sh "$work/.sdd/$SLUG/diagnosis.md"; }
red_green(){ if PYTHONPATH="$work" python3 tests/test_pagination.py >/dev/null 2>&1; then printf 'GREEN'; else printf 'RED'; fi; }

# diagnosis.md at a given STATUS (hypothesis/blast/fix filled once we reach DIAGNOSED+)
diag(){
  local status="$1" hyp="_(empty until DIAGNOSE)_"
  case "$status" in DIAGNOSED|CONFIRMED|FIXED) hyp="page_count uses floor division (total // per_page), truncating the final partial page.";; esac
  cat > ".sdd/$SLUG/diagnosis.md" <<EOF
STATUS: $status

# Bug: pagination drops the last partial page

## Symptom + reproduction steps
page_count(31, 10) returns 3, but 31 items at 10/page need 4 pages — the last item is unreachable.
Reproduced by tests/test_pagination.py::test_partial_last_page_is_counted.

## Root-cause hypothesis
$hyp

## Blast radius
Every caller of page_count(): page nav, "page N of M" displays. Off-by-one undercount; read-path only.

## Fix strategy
Ceiling division: (total_items + per_page - 1) // per_page. Minimal, local to page_count.
EOF
}
progress(){ cat > ".sdd/$SLUG/PROGRESS.md" <<EOF
FEATURE: $SLUG
PHASE: $1
LANE: bug
SEV: sev1
CYCLE: 0
FIX_CYCLE: 0
UPDATED: 2026-06-05T00:00:00Z
${2:-}
EOF
}
# the lite router's choice for `fix` at the current stage
lite(){ CLAUDE_PROJECT_DIR="$work" bash "$PLUGIN/scripts/lite-next.sh" fix | sed -n 's/.*"step":"\([^"]*\)".*/\1/p; s/.*"stop":"\([^"]*\)".*/stop:\1/p'; }

echo "Planted-bug smoke test — $SLUG"
echo "(plugin: $PLUGIN)"
echo

# ---------- REPORT (what /build-fleet:triage scaffolds) ----------
mkdir -p ".sdd/$SLUG" tests
cp "$FIX/pagination.py" pagination.py
printf '%s\n' "$SLUG" > .sdd/ACTIVE
diag REPORTED
progress REPORT
echo "[REPORT]"
check "router: REPORT → reproduce" "$(lite)" reproduce
check "validate-diagnosis accepts the REPORTED scaffold" "$(validate_diag)" 0
check "source write BLOCKED pre-CONFIRMED" "$(gate pagination.py)" BLOCKED

# ---------- REPRODUCE (qa writes the failing test) ----------
echo "[REPRODUCE]"
check "writing the reproduction under tests/ is ALLOWED" "$(gate tests/test_pagination.py)" ALLOWED
cp "$FIX/repro_check.py" tests/test_pagination.py
check "the reproduction is RED against the bug" "$(red_green)" RED
diag REPRODUCING
progress REPRODUCE
check "router: no hypothesis → action" "$(lite)" action:hypothesis
check "validate-diagnosis accepts REPRODUCING" "$(validate_diag)" 0
check "source still BLOCKED (test exists, not yet CONFIRMED)" "$(gate pagination.py)" BLOCKED

# ---------- DIAGNOSE (hypothesis recorded; diagnose.js confirms in a live run) ----------
echo "[DIAGNOSE]"
diag DIAGNOSED
progress DIAGNOSE
sed -i.bak '/^## Root-cause hypothesis$/a\
HYPOTHESIS_CYCLE: 1
' ".sdd/$SLUG/diagnosis.md" && rm -f ".sdd/$SLUG/diagnosis.md.bak"
check "validate-diagnosis accepts HYPOTHESIS_CYCLE" "$(validate_diag)" 0
check "router: hypothesis 1 → diagnose" "$(lite)" diagnose
check "validate-diagnosis accepts DIAGNOSED" "$(validate_diag)" 0
check "source still BLOCKED at DIAGNOSED" "$(gate pagination.py)" BLOCKED

# ---------- FIX (the gate flips diagnosis→CONFIRMED, unlocking source) ----------
echo "[FIX]"
diag CONFIRMED
progress FIX
check "router: FIX → apply-fix" "$(lite)" apply-fix
check "validate-diagnosis accepts CONFIRMED" "$(validate_diag)" 0
check "source write now ALLOWED (CONFIRMED + reproducing test)" "$(gate pagination.py)" ALLOWED
cp "$FIX/pagination.fixed.py" pagination.py
check "the fix turns the reproduction GREEN" "$(red_green)" GREEN
progress FIX "FIX_DONE_CYCLE: 0"
check "router: fix done → verify" "$(lite)" verify

# ---------- VERIFY (the counterfactual — red if the fix is reverted) ----------
echo "[VERIFY]"
cp "$FIX/pagination.py" pagination.py
check "counterfactual holds: reverted fix → RED" "$(red_green)" RED
cp "$FIX/pagination.fixed.py" pagination.py
check "restored fix → GREEN" "$(red_green)" GREEN
diag FIXED
progress HANDOFF
check "router: HANDOFF → ship-fix" "$(lite)" ship-fix

# ---------- HANDOFF (/ship-fix clears the lock) ----------
echo "[HANDOFF]"
: > .sdd/ACTIVE
check "router: shipped → nothing-to-do" "$(lite)" stop:nothing-to-do
check ".sdd/ACTIVE is cleared on ship" "$(cat .sdd/ACTIVE)" ""
check "with no active item, source writes are ALLOWED again" "$(gate pagination.py)" ALLOWED

# ---------- DRIFT (a built feature's criteria stay marked in its tests) ----------
echo "[DRIFT]"
mkdir -p .sdd/pager-totals
printf 'SDD_SCHEMA: 2\nFEATURE: pager-totals\nPHASE: HANDOFF\nBUILD_STATE: done\n' > .sdd/pager-totals/PROGRESS.md
printf 'STATUS: FINALIZED\n\n# pager-totals\n\n## Acceptance Criteria\n\n- **AC-1**: a partial last page is counted.\n- **AC-2**: an empty list has no pages.\n' > .sdd/pager-totals/spec.md
printf '\n# pager-totals/AC-1\ndef test_partial_marker(): pass\n# pager-totals/AC-2\ndef test_empty_marker(): pass\n' >> tests/test_pagination.py
drift(){ local rc=0; CLAUDE_PROJECT_DIR="$work" bash "$PLUGIN/scripts/drift-gate.sh" --all >/dev/null 2>&1 || rc=$?; printf '%s' "$rc"; }
check "drift gate: every criterion marked → pass" "$(drift)" 0
sed 's|# pager-totals/AC-2||' tests/test_pagination.py > tests/renamed.tmp && mv tests/renamed.tmp tests/test_pagination.py
check "drift gate: a criterion's marker removed → fail" "$(drift)" 2

echo
echo "-----"
echo "passed=$pass failed=$fail"
if [ "$fail" -eq 0 ]; then echo "SMOKE PASS — the bug-lane deterministic backbone is sound."; else echo "SMOKE FAIL"; fi
[ "$fail" -eq 0 ]
