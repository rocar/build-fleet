#!/usr/bin/env bash
# Parity: the verified-review rules exist twice — JS in workflows/review.js (the
# workflow's provisional result) and jq in scripts/lib/verified-review.jq (the gate's
# authoritative result). This renders fixtures with the JS (formatVerifiedFindingLines
# after applyVerifiedVote) and checks the jq rules reach the same final severity, kill
# and closure from the rendered REVIEW.md lines. Skips if node is absent. bash 3.2.
# Run: bash scripts/verified-vote-parity.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REVIEW="$DIR/../workflows/review.js"; RULES="$(cat "$DIR/lib/verified-review.jq")"
if ! command -v node >/dev/null 2>&1; then echo "ok   verified-vote-parity (SKIPPED: node not found; enforced in CI)"; exit 0; fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/vr-parity.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
awk '/LAYER1-PURE-HELPERS START/{f=1;next} /LAYER1-PURE-HELPERS END/{f=0;next} f' "$REVIEW" > "$TMP/helpers.js"
cat "$TMP/helpers.js" - > "$TMP/run.js" <<'JS'
const R = "The constraints section caps retries at three attempts explicitly.";
const q = { file: "spec.md", text: "Retries are capped at 3 attempts" };
const A = { kind: "quote", file: "spec.md", text: "xx yy zz ww" };
const v = (id, vote, severity, extra) => ({ verdicts: [{ id, vote, severity, ...(extra || {}) }] });
const fixtures = [
  ["killed-2of3", { id: "qa-c1-1", severity: "major", text: "a", anchor: A, test: "t" }, [v("qa-c1-1", "uphold", "major"), v("qa-c1-1", "refute", "minor", { reason: R, quote: q }), v("qa-c1-1", "refute", "minor", { reason: R, quote: q })]],
  ["one-refute-survives", { id: "qa-c1-2", severity: "blocker", text: "b", anchor: A, test: "t" }, [v("qa-c1-2", "refute", "minor", { reason: R, quote: q }), v("qa-c1-2", "uphold", "blocker"), v("qa-c1-2", "uphold", "major", { reason: "short" })]],
  ["lowered-with-evidence", { id: "qa-c1-3", severity: "blocker", text: "c", anchor: A, test: "t" }, [v("qa-c1-3", "uphold", "major", { reason: R, quote: q }), v("qa-c1-3", "uphold", "major", { reason: R, quote: q }), v("qa-c1-3", "uphold", "blocker")]],
  ["two-returned-even-median", { id: "qa-c1-4", severity: "blocker", text: "d", anchor: A, test: "t" }, [v("qa-c1-4", "uphold", "minor", { reason: R, quote: q }), null, v("qa-c1-4", "uphold", "blocker")]],
  ["test-invalid-majority", { id: "qa-c1-5", severity: "major", text: "e", anchor: A, test: "t" }, [v("qa-c1-5", "uphold", "major", { test_invalid: true, reason: "vacuous" }), v("qa-c1-5", "uphold", "major", { test_invalid: true, reason: "vacuous" }), v("qa-c1-5", "uphold", "major")]],
  ["closure-confirmed", { id: "qa-c1-6", severity: "major", text: "f", closure: { file: "spec.md", text: "Retries are capped at 3" } }, [v("qa-c1-6", "confirm", "major"), v("qa-c1-6", "confirm", "major"), v("qa-c1-6", "reject", "major", { reason: "no" })]],
  ["closure-rejected", { id: "qa-c1-7", severity: "blocker", text: "g", closure: { file: "spec.md", text: "Retries are capped at 3" } }, [v("qa-c1-7", "reject", "blocker", { reason: "no" }), v("qa-c1-7", "confirm", "blocker"), null]],
  ["carried", { id: "qa-c1-8", severity: "major", text: "h", anchor: A, test: "t", carried: { from_cycle: 1, reason: "not-addressed" } }, []],
  ["demoted-no-test", demoteUncheckable([{ id: "qa-c1-9", severity: "major", text: "i", anchor: A, test: "" }]).concerns[0], [v("qa-c1-9", "uphold", "major"), v("qa-c1-9", "uphold", "major"), v("qa-c1-9", "uphold", "major")]],
  ["raise-capped", { id: "qa-c1-10", severity: "major", text: "j", anchor: A, test: "t" }, [v("qa-c1-10", "uphold", "blocker"), v("qa-c1-10", "uphold", "blocker"), v("qa-c1-10", "uphold", "blocker")]],
];
console.log(JSON.stringify(fixtures.map(([name, f, panels]) => {
  const [c] = applyVerifiedVote([f], panels);
  return { name, js: { final: c.severity, killed: c.killed, closed: c.closed }, lines: formatVerifiedFindingLines(c, {}).join("\n") };
})));
JS
node "$TMP/run.js" > "$TMP/out.json" || { echo "FAIL node fixture run"; exit 1; }
jq -r "${RULES}"'.[] | . as $c | ($c.lines | vr_parse_block)[0] | vr_outcome([]) as $o
  | {final: $o.final, killed: $o.killed, closed: $o.closed} as $j
  | if $j == $c.js then "ok   parity-\($c.name)" else "FAIL parity-\($c.name) js=\($c.js|tojson) jq=\($j|tojson)" end' "$TMP/out.json" > "$TMP/res"
cat "$TMP/res"
f=$(grep -c '^FAIL' "$TMP/res"); p=$(grep -c '^ok' "$TMP/res")
echo "-----"; echo "passed=$p failed=$f"; [ "$f" -eq 0 ]
