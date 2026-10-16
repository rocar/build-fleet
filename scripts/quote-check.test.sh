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
assert "event-fingerprint" "[ \"\$(ev '$p' '.files | keys')\" = '[\"DECISIONS.md\",\"spec.md\"]' ]"
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
# four-file layout: criteria are quoted from spec.md; acceptance.md is not a source
p=$(vr_proj ac-section 1)
vr_block "$p" 1 qa '- [major] (qa-c1-1) retry limit' "$(vr_q 'an upload against a failing server stops after 3 attempts')" '  test: t' "$(vr_up 1 major)" "$(vr_up 2 major)"
vr_block "$p" 1 architect
run "$p" 1
assert "spec-acceptance-section-quotable" "printf '%s' \"\$out\" | grep -q '\"failed\":0'"
p=$(vr_proj ac-file 1)
printf '# Acceptance\n- AC-1: only in the stray file\n' > "$p/.sdd/feat/acceptance.md"
vr_block "$p" 1 qa '- [major] (qa-c1-1) retry limit' '  quote: {"file":"acceptance.md","text":"only in the stray file"}' '  test: t' "$(vr_up 1 major)" "$(vr_up 2 major)"
vr_block "$p" 1 architect
run "$p" 1
assert "acceptance-md-not-a-source" "printf '%s' \"\$out\" | grep -q '\"failed\":1'"
# A --cycle that is not PROGRESS's CYCLE is skipped and records nothing: an event would
# shadow the real check of the current cycle (first event per cycle_total wins).
p=$(vr_proj stale 2)
vr_block "$p" 1 qa '- [major] (qa-c1-1) retry limit' "$(vr_q 'the client retries failed uploads')" '  test: t'
vr_block "$p" 1 architect
run "$p" 1
assert "stale-cycle-skipped" "[ $rc -eq 0 ] && printf '%s' \"\$out\" | grep -q '\"skipped\":\"stale-cycle\"'"
assert "stale-cycle-no-event" "! grep -q quote-check '$p/.sdd/feat/EVENTS.jsonl' 2>/dev/null"
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
