#!/usr/bin/env bash
# End to end, no model: REVIEW.md blocks rendered by the workflow's own JS
# (applyVerifiedVote + formatVerifiedFindingLines) → the scribe's marker release fires
# hooks/scripts/check-review-quotes.sh → scripts/quote-check.sh records the event →
# scripts/finalize-gate.sh decides; then a delta cycle carries the open finding and
# scripts/review-carry.sh reports it. Skips if node is absent. bash 3.2.
# Run: bash scripts/verified-review-e2e.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
if ! command -v node >/dev/null 2>&1; then echo "ok   verified-review-e2e (SKIPPED: node not found; enforced in CI)"; exit 0; fi
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
. "$DIR/fixtures/verified-review.sh"
pass=0; fail=0
assert() { if eval "$2"; then pass=$((pass+1)); printf 'ok   %s\n' "$1"; else fail=$((fail+1)); printf 'FAIL %s (%s) out=%s\n' "$1" "$2" "${out:-}"; fi; }
awk '/LAYER1-PURE-HELPERS START/{f=1;next} /LAYER1-PURE-HELPERS END/{f=0;next} f' "$ROOT/workflows/review.js" > "$work/helpers.js"
render() { # render <js-expression yielding [findings, panels]> → block lines on stdout
  { cat "$work/helpers.js"; printf 'const [fs, panels] = %s;\nfor (const f of fs) for (const l of formatVerifiedFindingLines(applyVerifiedVote([f], panels)[0], {})) console.log(l);\n' "$1"; } > "$work/r.js"
  node "$work/r.js"
}
release() { ( cd "$1" && jq -cn --arg p "$1/.sdd/feat/.workflow-in-flight" '{tool_name:"Write", tool_input:{file_path:$p, content:""}}' \
  | CLAUDE_PROJECT_DIR="$1" bash "$ROOT/hooks/scripts/check-review-quotes.sh" ); }
gate() { out=$( cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$ROOT/scripts/finalize-gate.sh" feat "${@:2}" 2>/dev/null ); rc=$?; }
R="'$VR_REASON'"
F1='{ id: "qa-c1-1", severity: "major", raised_by: "qa", text: "Retry limit unspecified", anchor: { kind: "quote", file: "spec.md", text: "the client retries failed uploads" }, test: "a failing server stops the client within N attempts" }'

# Cycle 1: two verifiers refute with a REAL quote, one with an INVENTED one → the kill falls.
p=$(vr_proj e2e 1)
lines=$(render "[[ $F1 ], [
  { verdicts: [{ id: 'qa-c1-1', vote: 'uphold', severity: 'major', reason: 'ok' }] },
  { verdicts: [{ id: 'qa-c1-1', vote: 'refute', severity: 'minor', reason: $R, quote: { file: 'spec.md', text: 'Retries are capped at 3 attempts' } }] },
  { verdicts: [{ id: 'qa-c1-1', vote: 'refute', severity: 'minor', reason: $R, quote: { file: 'spec.md', text: 'Retries are capped at 9 attempts' } }] }]]")
assert "workflow-saw-a-kill" "printf '%s' \"\$lines\" | grep -q 'verified: refuted 2/3'"
vr_block "$p" 1 qa "$lines"; vr_block "$p" 1 architect
release "$p"
assert "hook-recorded-exempt-event" "jq -e 'select(.source == \"script:quote-check\") | .exempt == true and .revived == [\"qa-c1-1\"]' '$p/.sdd/feat/EVENTS.jsonl' >/dev/null"
gate "$p"
assert "gate-reopens-the-finding" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q '\"open_majors\":\\[\"qa-c1-1\"\\]'"
out=$( cd "$p" && CLAUDE_PROJECT_DIR="$p" bash "$ROOT/scripts/review-carry.sh" feat ); 
assert "carry-reports-it-and-exempts" "printf '%s' \"\$out\" | grep -q '\"open_count\":1,\"exempt_cycles\":1'"

# Cycle 2: the reviewer closes it with a quote of the revised spec; the panel confirms.
printf 'The client retries failed uploads at most 3 times.\n' >> "$p/.sdd/feat/spec.md"
sed -i.bak 's/^CYCLE: 1/CYCLE: 2/; s/^CYCLE_TOTAL: 1/CYCLE_TOTAL: 2/' "$p/.sdd/feat/PROGRESS.md"
lines=$(render "[[{ id: 'qa-c1-1', severity: 'major', raised_by: 'qa', text: 'Retry limit unspecified', closure: { file: 'spec.md', text: 'The client retries failed uploads at most 3 times.' } }], [
  { verdicts: [{ id: 'qa-c1-1', vote: 'confirm', severity: 'major', reason: 'ok' }] },
  { verdicts: [{ id: 'qa-c1-1', vote: 'confirm', severity: 'major', reason: 'ok' }] }, null]]")
vr_block "$p" 2 qa "$lines"; vr_block "$p" 2 architect
release "$p"; gate "$p"
assert "closed-in-cycle-2-passes" "[ $rc -eq 0 ]"
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
