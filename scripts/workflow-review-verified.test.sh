#!/usr/bin/env bash
# Tests the verified-shape PURE helpers of workflows/review.js — extracted VERBATIM from
# between the LAYER1-PURE-HELPERS markers and run under node: the shape/settings
# normalizers, demoteUncheckable, rotateLeft, verifiedOutcome, applyVerifiedVote,
# materializeCarried and formatVerifiedFindingLines. Skips if node is absent. bash 3.2.
# Run: bash scripts/workflow-review-verified.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REVIEW="$DIR/../workflows/review.js"
if ! command -v node >/dev/null 2>&1; then echo "ok   workflow-review-verified (SKIPPED: node not found; enforced in CI)"; exit 0; fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wf-review-ver.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
awk '/LAYER1-PURE-HELPERS START/{f=1;next} /LAYER1-PURE-HELPERS END/{f=0;next} f' "$REVIEW" > "$TMP/helpers.js"
[ -s "$TMP/helpers.js" ] || { echo "FAIL could not extract LAYER1-PURE-HELPERS region"; exit 1; }
cat "$TMP/helpers.js" - > "$TMP/run.js" <<'JS'
let pass = 0, fail = 0;
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function check(name, cond) { if (cond) { pass++; console.log("ok   " + name); } else { fail++; console.log("FAIL " + name); } }
const R = "The constraints section caps retries at three attempts explicitly.";
const Q = { file: "spec.md", text: "Retries are capped at 3 attempts" };

check("shape-default-debate", normalizeShape(undefined).shape === "debate");
check("shape-verified", normalizeShape("verified").shape === "verified");
check("shape-bad", normalizeShape("vote").error !== null);
check("verifier-model-default-sonnet", normalizeVerifierModel(null).model === "sonnet");
check("verifier-model-bad", normalizeVerifierModel("gpt").error !== null);
check("flag-default-false", normalizeFlag(undefined, "x").value === false);
check("flag-string-true", normalizeFlag("true", "x").value === true);
check("flag-bad", normalizeFlag("yes", "x").error !== null);
check("exempt-default-0", normalizeExemptCycles(undefined).value === 0);
check("exempt-bad", normalizeExemptCycles(-1).error !== null);
check("carried-default-empty", eq(normalizeCarried(undefined, "verified").carried, []));
check("carried-debate-rejected", normalizeCarried([{ id: "qa-c1-1", raised_by: "qa", severity: "major" }], "debate").error !== null);
check("carried-minor-rejected", normalizeCarried([{ id: "qa-c1-1", raised_by: "qa", severity: "minor" }], "verified").error !== null);

const dm = demoteUncheckable([
  { id: "qa-c1-1", severity: "major", text: "a", anchor: { kind: "quote", file: "spec.md", text: "abc def ghij" }, test: "t" },
  { id: "qa-c1-2", severity: "major", text: "b", anchor: { kind: "none" }, test: "t" },
  { id: "qa-c1-3", severity: "blocker", text: "c", anchor: { kind: "absent", file: "spec.md", section: "Security", missing: "x" }, test: " " },
  { id: "qa-c1-4", severity: "minor", text: "d", anchor: { kind: "none" }, test: "" },
]);
check("demote-no-anchor-and-no-test", eq(dm.demoted, ["qa-c1-2", "qa-c1-3"]) && dm.concerns[1].demoted.reason === "no-anchor" && dm.concerns[2].demoted.reason === "no-test");
check("demote-minor-untouched", !dm.concerns[3].demoted);

check("rotate-0", eq(rotateLeft([1, 2, 3], 0), [1, 2, 3]));
check("rotate-1", eq(rotateLeft([1, 2, 3], 1), [2, 3, 1]));
check("rotate-wraps", eq(rotateLeft([1, 2], 3), [2, 1]));
check("rotate-empty", eq(rotateLeft([], 2), []));

const f = { id: "qa-c1-1", severity: "major", raised_by: "qa", text: "a", anchor: { kind: "quote", file: "spec.md", text: "abc def ghij" }, test: "t" };
const panels = [
  { verdicts: [{ id: "qa-c1-1", vote: "uphold", severity: "major", reason: "ok" }] },
  { verdicts: [{ id: "qa-c1-1", vote: "refute", severity: "minor", reason: R, quote: Q }] },
  { verdicts: [{ id: "qa-c1-1", vote: "refute", severity: "minor", reason: R, quote: Q }] },
];
let [c] = applyVerifiedVote([f], panels);
check("vote-kill", c.killed && c.refuted && c.verdicts.length === 3 && eq(c.verdicts.map((v) => v.v), [1, 2, 3]));
[c] = applyVerifiedVote([f], [panels[0], panels[1], null]);
check("vote-one-refute-of-two-survives", !c.killed && c.severity === "major" && eq(c.verdicts.map((v) => v.v), [1, 2]));
[c] = applyVerifiedVote([f], [panels[0], { verdicts: [panels[1].verdicts[0], panels[1].verdicts[0]] }, panels[0]]);
check("vote-duplicate-verdict-counts-once", !c.killed && eq(c.verdicts.map((v) => v.v), [1, 2, 3]));
[c] = applyVerifiedVote([{ ...f, carried: { from_cycle: 1, reason: "not-addressed" } }], panels);
check("vote-carried-not-verified", c.verdicts.length === 0 && !c.refuted && c.severity === "major");
[c] = applyVerifiedVote([{ ...f, closure: { file: "spec.md", text: "Retries are capped at 3 attempts" } }],
  [{ verdicts: [{ id: "qa-c1-1", vote: "confirm", severity: "major", reason: "ok" }] }, { verdicts: [{ id: "qa-c1-1", vote: "confirm", severity: "major", reason: "ok" }] }, null]);
check("vote-closure-confirmed-refuted", c.closed && c.refuted);
[c] = applyVerifiedVote([f], [
  { verdicts: [{ id: "qa-c1-1", vote: "uphold", severity: "major", test_invalid: true, reason: "vacuous" }] },
  { verdicts: [{ id: "qa-c1-1", vote: "uphold", severity: "major", test_invalid: true, reason: "vacuous" }] },
  { verdicts: [{ id: "qa-c1-1", vote: "uphold", severity: "major", reason: "ok" }] },
]);
check("vote-test-invalid-demotes-with-line", c.severity === "minor" && c.demoted && c.demoted.reason === "test-invalid");

const K1 = { id: "qa-c1-1", raised_by: "qa", severity: "major", text: "a", quote: { file: "spec.md", text: "abc def ghij" }, test: "t" };
const K9 = { id: "qa-c1-9", raised_by: "qa", severity: "blocker", text: "z", absent: { file: "spec.md", section: "Security", missing: "auth" }, test: "t" };
const KA = { id: "architect-c1-2", raised_by: "architect", severity: "blocker", text: "y", quote: { file: "spec.md", text: "abc def ghij" }, test: "t", carried: { from_cycle: 1, reason: "not-addressed" } };
// qa re-lists qa-c1-1 badly (lower severity, no anchor) and twice; leaves qa-c1-9 out.
let mc = materializeCarried([{ id: "qa-c1-1", severity: "minor", raised_by: "qa", text: "again", anchor: { kind: "none" }, test: "" },
  { id: "qa-c1-1", severity: "major", raised_by: "qa", text: "dup", anchor: { kind: "none" }, test: "" }], [K1, K9], 2, ["qa", "coder"]);
check("carry-adds-omitted", eq(mc.map((x) => x.id), ["qa-c1-1", "qa-c1-9"]) && eq(mc[1].carried, { from_cycle: 1, reason: "not-addressed" }) && mc[1].anchor.kind === "absent");
check("carry-relisted-keeps-record", mc[0].severity === "major" && mc[0].text === "a" && eq(mc[0].anchor, { kind: "quote", file: "spec.md", text: "abc def ghij" }) && mc[0].test === "t" && eq(mc[0].carried, { from_cycle: 1, reason: "re-listed" }));
mc = materializeCarried([{ id: "qa-c1-1", severity: "major", raised_by: "qa", text: "a", closure: { file: "spec.md", text: "closed" } }], [K1, KA], 3, ["qa", "coder"]);
check("carry-closure-claim-untouched", mc[0].closure && !mc[0].carried && mc.length === 2);
check("carry-off-roster-hosted", mc[1].id === "architect-c1-2" && mc[1].host === "qa" && mc[1].raised_by === "architect");
check("carry-keeps-origin-cycle", eq(mc[1].carried, { from_cycle: 1, reason: "not-addressed" }));
const dm2 = demoteUncheckable([{ ...mc[0] }, { id: "qa-c1-7", severity: "major", raised_by: "qa", text: "c", anchor: { kind: "none" }, carried: { from_cycle: 1, reason: "not-addressed" } }]);
check("demote-skips-closure-and-carried", eq(dm2.demoted, []));

[c] = applyVerifiedVote([f], panels);
let lines = formatVerifiedFindingLines(c, {});
check("render-header-keeps-raised-severity", lines[0] === "- [major] (qa-c1-1) a");
check("render-quote-line", lines[1] === '  quote: {"file":"spec.md","text":"abc def ghij"}');
check("render-verdicts-and-summary", lines.filter((l) => l.startsWith("  verdict: ")).length === 3 && lines.indexOf("  verified: refuted 2/3") !== -1);
check("render-killed-no-disposition", !lines.some((l) => l.startsWith("  disposition:")));
[c] = applyVerifiedVote([f], [panels[0], panels[0], null]);
lines = formatVerifiedFindingLines(c, { "qa-c1-1": { action: "adr", adr_id: 4 } });
check("render-upheld-major-disposition", lines[lines.length - 1] === "  disposition: adr ADR-4");
console.log("-----\npassed=" + pass + " failed=" + fail);
process.exit(fail === 0 ? 0 : 1);
JS
node "$TMP/run.js"
