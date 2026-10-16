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
assert "adr-closes-missing-adr-refuses" "[ $rc -eq 2 ] && field .reasons | grep -q majors-without-adr && [ \"\$(field .majors_without_adr)\" = '[\"architect-c1-1\"]' ] && [ \"\$(field .open_majors)\" = '[]' ]"

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

# Final-review regressions.
p=$(vr_proj prev-no-event 2 2)
vr_block "$p" 1 qa; vr_block "$p" 1 architect
vr_block "$p" 2 qa '- [blocker] (qa-c2-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' "$(vr_up 1 blocker)" "$(vr_up 2 blocker)" "$(vr_up 3 blocker)"
vr_block "$p" 2 architect
qc "$p" 2; gate "$p"
assert "prev-cycle-without-event-keeps-blocker" "[ $rc -eq 2 ] && field .open_blockers | grep -q qa-c2-1"
gate "$p" --report
assert "report-json-without-prev-event" "field '.open | map(.id)' | grep -q qa-c2-1"

p=$(vr_proj dup-refute 1)
vr_block "$p" 1 qa '- [blocker] (qa-c1-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' "$(vr_up 1 blocker)" "$(vr_rf 2 'Retries are capped at 3 attempts')" "$(vr_rf 2 'Retries are capped at 3 attempts')" "$(vr_up 3 blocker)"
vr_block "$p" 1 architect
qc "$p" 1; gate "$p"
assert "one-verifier-twice-never-kills" "[ $rc -eq 2 ] && field .open_blockers | grep -q qa-c1-1"

p=$(vr_proj edited-after-check 1)
vr_block "$p" 1 architect
vr_block "$p" 1 qa '- [major] (qa-c1-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' "$(vr_up 1 major)" "$(vr_up 2 major)" '  disposition: fix'
qc "$p" 1
ln=$(grep -n '^  disposition: fix' "$p/.sdd/feat/REVIEW.md" | tail -1 | cut -d: -f1)
awk -v n="$ln" -v a="$(vr_rf 4 'Retries are capped at 3 attempts')" -v b="$(vr_rf 5 'Retries are capped at 3 attempts')" '{print} NR==n{print a; print b}' "$p/.sdd/feat/REVIEW.md" > "$p/r" && mv "$p/r" "$p/.sdd/feat/REVIEW.md"
gate "$p"
assert "review-edited-after-check-refuses" "[ $rc -eq 2 ] && field .reasons | grep -q review-changed-since-check"

p=$(vr_proj flag-role-gate 1)
vr_block "$p" 1 qa; vr_block "$p" 1 architect
vr_block "$p" 1 product-owner '- [blocker] (product-owner-c1-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' "$(vr_up 1 blocker)" "$(vr_up 2 blocker)" "$(vr_up 3 blocker)"
qc "$p" 1; gate "$p"
assert "flag-role-blocker-counted" "[ $rc -eq 2 ] && field .open_blockers | grep -q product-owner-c1-1"
# A free-form id (not <role>-c<N>-<k>) is raised by its block's role, so the raiser can close it.
p=$(vr_proj freeform 1)
vr_block "$p" 1 qa '- [major] (spec-gap) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t' "$(vr_up 1 major)" "$(vr_up 2 major)" "$(vr_up 3 major)"
vr_block "$p" 1 architect
qc "$p" 1; gate "$p" --report
assert "freeform-id-raised-by-block-role" "[ \"\$(field '.open[] | select(.id == \"spec-gap\") | .raised_by')\" = '\"qa\"' ]"
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
