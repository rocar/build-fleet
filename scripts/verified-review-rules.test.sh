#!/usr/bin/env bash
# Tests for scripts/lib/verified-review.jq — the REVIEW_SHAPE: verified rules shared by
# quote-check.sh and finalize-gate.sh: block parsing, the vote, severity, demotion,
# closures, carried entries, quote checks, revival.
# Run: bash scripts/verified-review-rules.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES="$(cat "$DIR/lib/verified-review.jq")"
pass=0; fail=0
# t <name> <block-text> <jq-expression over $fs> <expected-compact-json>
t() {
  local got
  got=$(printf '%s' "$2" | jq -Rsc "${RULES} vr_parse_block as \$fs | $3" 2>&1)
  if [ "$got" = "$4" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$1"
  else fail=$((fail+1)); printf 'FAIL %s\n     want %s\n     got  %s\n' "$1" "$4" "$got"; fi
}
R='The constraints section caps retries at three attempts explicitly.'
Q='{"file":"spec.md","text":"Retries are capped at 3 attempts"}'
H='## Cycle 1 — qa — 2026-10-20T00:00:00Z
shape: verified'
up() { printf '  verdict: {"v":%s,"vote":"uphold","severity":"%s"}' "$1" "$2"; }
rf() { printf '  verdict: {"v":%s,"vote":"refute","severity":"%s","reason":"%s","quote":%s}' "$1" "$2" "$R" "$Q"; }
lo() { printf '  verdict: {"v":%s,"vote":"uphold","severity":"%s","reason":"%s","quote":%s}' "$1" "$2" "$R" "$Q"; }
OUT='[$fs[] | vr_outcome([]) | {id, final, killed}]'

t "parse-fields" "$H
- [major] (qa-c1-1) Claim text
  quote: {\"file\":\"spec.md\",\"text\":\"abc def ghi\"}
  ref: §Behavior, AC-3
  test: a test
  disposition: fix
status: concerns-raised" '[$fs[] | {id, severity, text, ref, test, disposition, q: .quote.text}]' \
  '[{"id":"qa-c1-1","severity":"major","text":"Claim text","ref":"§Behavior, AC-3","test":"a test","disposition":"fix","q":"abc def ghi"}]'
t "kill-on-two-valid-refutes" "$H
- [major] (qa-c1-1) c
$(up 1 major)
$(rf 2 minor)
$(rf 3 minor)" "$OUT" '[{"id":"qa-c1-1","final":"minor","killed":true}]'
# A verdict counts only from a numbered verifier (v = 1, 2 or 3): hand-written lines
# with no v, or a v outside the panel, never vote — they can neither kill nor demote.
nv() { printf '  verdict: {"vote":"refute","severity":"%s","reason":"%s","quote":%s}' "$1" "$R" "$Q"; }
t "unkeyed-verdicts-never-kill" "$H
- [blocker] (qa-c1-1) c
$(nv minor)
$(nv minor)
$(up 3 blocker)" "$OUT" '[{"id":"qa-c1-1","final":"blocker","killed":false}]'
t "out-of-panel-v-never-kills" "$H
- [blocker] (qa-c1-1) c
$(rf 7 minor)
$(rf 8 minor)
$(up 3 blocker)" "$OUT" '[{"id":"qa-c1-1","final":"blocker","killed":false}]'
t "out-of-panel-v-never-demotes" "$H
- [major] (qa-c1-1) c
$(up 1 major)
$(lo 4 minor)
$(lo 5 minor)" "$OUT" '[{"id":"qa-c1-1","final":"major","killed":false}]'
t "out-of-panel-closure-confirms-never-close" "$H
- [major] (qa-c1-1) c
  closure: {\"file\":\"spec.md\",\"text\":\"Retries are capped at 3 attempts\"}
  verdict: {\"v\":4,\"vote\":\"confirm\",\"severity\":\"major\",\"reason\":\"closed\"}
  verdict: {\"vote\":\"confirm\",\"severity\":\"major\",\"reason\":\"closed\"}" '[$fs[] | vr_outcome([]) | {id, closed}]' '[{"id":"qa-c1-1","closed":false}]'
t "one-refute-is-not-a-veto" "$H
- [blocker] (qa-c1-1) c
$(rf 1 minor)
$(up 2 blocker)
$(up 3 blocker)" "$OUT" '[{"id":"qa-c1-1","final":"blocker","killed":false}]'
t "refute-without-quote-ignored" "$H
- [major] (qa-c1-1) c
  verdict: {\"v\":1,\"vote\":\"refute\",\"severity\":\"minor\",\"reason\":\"$R\"}
$(rf 2 minor)
$(up 3 major)" "$OUT" '[{"id":"qa-c1-1","final":"major","killed":false}]'
t "refute-short-reason-ignored" "$H
- [major] (qa-c1-1) c
  verdict: {\"v\":1,\"vote\":\"refute\",\"severity\":\"minor\",\"reason\":\"too short\",\"quote\":$Q}
$(rf 2 minor)
$(up 3 major)" "$OUT" '[{"id":"qa-c1-1","final":"major","killed":false}]'
t "lower-severity-needs-evidence" "$H
- [blocker] (qa-c1-1) c
$(up 1 minor)
$(up 2 minor)
$(up 3 blocker)" "$OUT" '[{"id":"qa-c1-1","final":"blocker","killed":false}]'
t "lower-severity-with-evidence" "$H
- [blocker] (qa-c1-1) c
$(lo 1 major)
$(lo 2 major)
$(up 3 blocker)" "$OUT" '[{"id":"qa-c1-1","final":"major","killed":false}]'
t "severity-never-raised" "$H
- [major] (qa-c1-1) c
$(up 1 blocker)
$(up 2 blocker)
$(up 3 blocker)" "$OUT" '[{"id":"qa-c1-1","final":"major","killed":false}]'
t "even-count-takes-higher-middle" "$H
- [blocker] (qa-c1-1) c
$(lo 1 minor)
$(up 3 blocker)" "$OUT" '[{"id":"qa-c1-1","final":"blocker","killed":false}]'
t "two-returned-kill-needs-both" "$H
- [major] (qa-c1-1) c
$(rf 1 minor)
$(up 3 major)" "$OUT" '[{"id":"qa-c1-1","final":"major","killed":false}]'
t "malformed-verdict-never-kills" "$H
- [major] (qa-c1-1) c
  verdict: {broken
$(rf 2 minor)
$(up 3 major)" "$OUT" '[{"id":"qa-c1-1","final":"major","killed":false}]'
t "test-invalid-majority-demotes" "$H
- [major] (qa-c1-1) c
  verdict: {\"v\":1,\"vote\":\"uphold\",\"severity\":\"major\",\"test_invalid\":true}
  verdict: {\"v\":2,\"vote\":\"uphold\",\"severity\":\"major\",\"test_invalid\":true}
$(up 3 major)" '[$fs[] | vr_outcome([]) | {final, demoted_reason}]' '[{"final":"minor","demoted_reason":"test-invalid"}]'
t "demoted-line-demotes" "$H
- [major] (qa-c1-1) c
  demoted: {\"reason\":\"no-test\"}" '[$fs[] | vr_outcome([]) | {final, demoted_reason}]' '[{"final":"minor","demoted_reason":"no-test"}]'
t "anchor-quote-failure-demotes" "$H
- [major] (qa-c1-1) c
$(up 1 major)
$(up 2 major)" '[$fs[] | vr_outcome([{id:"qa-c1-1",where:"anchor"}]) | {final, demoted_reason}]' '[{"final":"minor","demoted_reason":"anchor-quote-failed"}]'
t "closure-majority-closes" "$H
- [major] (qa-c1-1) c
  closure: {\"file\":\"spec.md\",\"text\":\"abc def ghi jkl\"}
  verdict: {\"v\":1,\"vote\":\"confirm\",\"severity\":\"major\"}
  verdict: {\"v\":2,\"vote\":\"confirm\",\"severity\":\"major\"}
  verdict: {\"v\":3,\"vote\":\"reject\",\"severity\":\"major\",\"reason\":\"no\"}" \
  '[$fs[] | vr_outcome([]) | {closed}] + [$fs[] | vr_outcome([{id:"qa-c1-1",where:"closure"}]) | {closed, reopened_closure}]' \
  '[{"closed":true},{"closed":false,"reopened_closure":true}]'
t "carried-is-open-and-unchecked" "$H
- [major] (qa-c1-5) c
  quote: {\"file\":\"spec.md\",\"text\":\"gone from the spec\"}
  carried: {\"from_cycle\":1,\"reason\":\"not-addressed\"}" \
  '[$fs[] | vr_outcome([{id:"qa-c1-5",where:"anchor"}]) | {final, open: vr_open([])}] + [$fs | vr_quotes | length]' '[{"final":"major","open":"major"},0]'
t "open-adr-exists-closes" "$H
- [major] (qa-c1-1) c
  disposition: adr ADR-2" '[$fs[] | vr_outcome([]) | vr_open([2]), vr_open([1])]' '[null,"major-without-adr"]'
t "revived-by-failed-refute-quote" "$H
- [major] (qa-c1-1) c
$(up 1 major)
$(rf 2 minor)
$(rf 3 minor)" '$fs | vr_revived([{id:"qa-c1-1",where:"verdict",v:3}])' '["qa-c1-1"]'
t "revived-by-restored-severity" "$H
- [blocker] (qa-c1-1) c
$(lo 1 major)
$(lo 2 major)
$(up 3 blocker)" '$fs | vr_revived([{id:"qa-c1-1",where:"verdict",v:2}])' '["qa-c1-1"]'
DOCS='{"spec.md":"STATUS: DRAFT\n# Up\n## 3.1 Behavior\nThe *client* retries\nfailed uploads—always.\n"}'
t "check-normalises-markup-dashes-newlines" "$H" \
  "[{file:\"spec.md\",text:\"The client retries failed uploads-always\"}, {file:\"spec.md\",text:\"the client retries\"}] | map(vr_check($DOCS; \"feat\"))" '[true,false]'
t "check-bounds" "$H" \
  "[{file:\"spec.md\",text:\"retries\"}, {file:\"spec.md\",text:(\"x\" * 501)}] | map(vr_check($DOCS; \"feat\"))" '[false,false]'
t "check-allowlist" "$H" \
  "[{file:\"../spec.md\",text:\"The client retries\"}, {file:\"notes.md\",text:\"The client retries\"}] | map(vr_check($DOCS; \"feat\"))" '[false,false]'
t "check-workspace-paths-mapped" "$H" \
  "[{file:\".sdd/feat/spec.md\",text:\"The client retries\"}, {file:\"./spec.md\",text:\"The client retries\"}, {file:\".sdd/_product/DECISIONS.md\",text:\"The client retries\"}, {file:\".sdd/other/spec.md\",text:\"The client retries\"}] | map(vr_check($DOCS; \"feat\"))" '[true,true,false,false]'
t "check-absent-section" "$H" \
  "[{file:\"spec.md\",section:\"Behavior\"}, {file:\"spec.md\",section:\"§3.1 Behavior\"}, {file:\"spec.md\",section:\"Security\"}] | map(vr_check($DOCS; \"feat\"))" '[true,true,false]'
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
