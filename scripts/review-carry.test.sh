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
