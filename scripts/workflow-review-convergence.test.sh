#!/usr/bin/env bash
# Tests the v0.9 PURE convergence helpers of workflows/review.js — extracted VERBATIM
# from between the LAYER1-PURE-HELPERS markers (real source, never a copy) and run
# under node: cycle-total/next-adr-id normalization, the finding-id pattern,
# disposition coverage, ADR id assignment, finalize_ready, the verdict rule, ADR
# rendering and the REVIEW.md line grammar. Skips if node is absent. bash 3.2.
# Run: bash scripts/workflow-review-convergence.test.sh   (exit 0 = all pass)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
REVIEW="$ROOT/workflows/review.js"

if ! command -v node >/dev/null 2>&1; then
  echo "ok   workflow-review-convergence (SKIPPED: node not found; enforced in CI)"
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/wf-review-conv.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

awk '/LAYER1-PURE-HELPERS START/{f=1;next} /LAYER1-PURE-HELPERS END/{f=0;next} f' "$REVIEW" > "$TMP/helpers.js"
if [ ! -s "$TMP/helpers.js" ]; then
  echo "FAIL could not extract LAYER1-PURE-HELPERS region from $REVIEW"
  exit 1
fi

cat "$TMP/helpers.js" - > "$TMP/run.js" <<'EOF'
let pass = 0, fail = 0;
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function check(name, cond) { if (cond) { pass++; console.log("ok   " + name); } else { fail++; console.log("FAIL " + name); } }

// legacy helpers still present
check("roles-default", eq(normalizeRoles(undefined).roles, ["architect","qa","coder"]));
check("budget-default", normalizeCycleBudget(undefined).budget === 3);

// normalizeCycleTotal
check("cycle-total-absent-derives", normalizeCycleTotal(undefined, 3) === 2);
check("cycle-total-absent-cycle1", normalizeCycleTotal(null, 1) === 0);
check("cycle-total-explicit", normalizeCycleTotal(6, 1) === 6);
check("cycle-total-string", normalizeCycleTotal("4", 2) === 4);
check("cycle-total-malformed-falls-back", normalizeCycleTotal("x", 2) === 1);
check("cycle-total-negative-falls-back", normalizeCycleTotal(-1, 2) === 1);

// normalizeNextAdrId
check("adr-id-absent", normalizeNextAdrId(undefined) === 1);
check("adr-id-explicit", normalizeNextAdrId(7) === 7);
check("adr-id-zero-rejected", normalizeNextAdrId(0) === 1);
check("adr-id-string", normalizeNextAdrId("3") === 3);

// findingIdPattern
const re = new RegExp(findingIdPattern("architect"));
check("id-pattern-accepts", re.test("architect-c1-3"));
check("id-pattern-rejects-other-role", !re.test("qa-c1-3"));
check("id-pattern-rejects-legacy", !re.test("architect-3"));

// originCycle (fix round 1)
check("origin-cycle-parses", originCycle("architect-c3-2") === 3);
check("origin-cycle-legacy-null", originCycle("qa-1") === null);

// enforceDeltaSeverity (fix round 1)
let dsr = enforceDeltaSeverity([{ id: "qa-c1-1", severity: "major", raised_by: "qa", text: "m", refuted: false }], 1);
check("delta-severity-cycle1-passthrough", dsr.concerns[0].severity === "major" && eq(dsr.demoted, []));
dsr = enforceDeltaSeverity([{ id: "qa-c2-1", severity: "major", raised_by: "qa", text: "new major", refuted: false }], 2);
check(
  "delta-severity-demotes-new-major",
  dsr.concerns[0].severity === "minor" &&
    dsr.concerns[0].text === "[demoted from major: new majors are not permitted on a delta cycle] new major" &&
    eq(dsr.demoted, ["qa-c2-1"])
);
dsr = enforceDeltaSeverity([{ id: "qa-c1-4", severity: "major", raised_by: "qa", text: "re-raised", refuted: false }], 2);
check("delta-severity-keeps-reraised-major", dsr.concerns[0].severity === "major" && eq(dsr.demoted, []));
dsr = enforceDeltaSeverity(
  [
    { id: "qa-c2-9", severity: "blocker", raised_by: "qa", text: "b", refuted: false },
    { id: "qa-c2-8", severity: "minor", raised_by: "qa", text: "n", refuted: false },
  ],
  2
);
check(
  "delta-severity-keeps-blocker-and-minor",
  dsr.concerns[0].severity === "blocker" && dsr.concerns[1].severity === "minor" && eq(dsr.demoted, [])
);
dsr = enforceDeltaSeverity([{ id: "qa-c2-1", severity: "major", raised_by: "qa", text: "m", refuted: false }], undefined);
check("delta-severity-undefined-cycle-passthrough", dsr.concerns[0].severity === "major" && eq(dsr.demoted, []));

// enforceDeltaSeverity (fix round 2): demote ANY post-cycle-1 major, not only ===cycle —
// a major demoted at cycle 2 must not resurface as major at cycle 3.
dsr = enforceDeltaSeverity([{ id: "qa-c2-1", severity: "major", raised_by: "qa", text: "still open", refuted: false }], 3);
check(
  "delta-severity-demotes-post-cycle1-major-at-later-cycle",
  dsr.concerns[0].severity === "minor" &&
    dsr.concerns[0].text === "[demoted from major: new majors are not permitted on a delta cycle] still open" &&
    eq(dsr.demoted, ["qa-c2-1"])
);
dsr = enforceDeltaSeverity([{ id: "qa-c1-4", severity: "major", raised_by: "qa", text: "re-raised", refuted: false }], 3);
check("delta-severity-keeps-cycle1-major-at-cycle3", dsr.concerns[0].severity === "major" && eq(dsr.demoted, []));
dsr = enforceDeltaSeverity(
  [
    { id: "qa-c1-9", severity: "blocker", raised_by: "qa", text: "b1", refuted: false },
    { id: "qa-c3-9", severity: "blocker", raised_by: "qa", text: "b2", refuted: false },
  ],
  3
);
check(
  "delta-severity-blockers-never-demoted-any-origin",
  dsr.concerns[0].severity === "blocker" && dsr.concerns[1].severity === "blocker" && eq(dsr.demoted, [])
);

// fixtures
const S = [
  { id: "architect-c1-1", severity: "blocker", raised_by: "architect", text: "b", refuted: false },
  { id: "architect-c1-2", severity: "major", raised_by: "architect", text: "m1", refuted: false },
  { id: "qa-c1-1", severity: "major", raised_by: "qa", text: "m2", refuted: false },
  { id: "qa-c1-2", severity: "major", raised_by: "qa", text: "m3-refuted", refuted: true, refuted_by: "coder", refutation_reason: "r".repeat(45), refutation_citation: { file: "spec.md", locator: "§ X" } },
  { id: "coder-c1-1", severity: "minor", raised_by: "coder", text: "n", refuted: false },
];

// dispositionCoverage
let cov = dispositionCoverage(S, [{ id: "architect-c1-2", action: "adr" }]);
check("coverage-missing", eq(cov.missing, ["qa-c1-1"]) && eq(cov.extra, []));
cov = dispositionCoverage(S, [{ id: "architect-c1-2", action: "adr" }, { id: "qa-c1-1", action: "fix" }, { id: "qa-c1-2", action: "fix" }]);
check("coverage-extra-refuted-ignored", eq(cov.missing, []) && eq(cov.extra, ["qa-c1-2"]));
check("coverage-empty", eq(dispositionCoverage([], []), { missing: [], extra: [], duplicates: [], invalid: [] }));

// dispositionCoverage: duplicates/invalid computed ONLY over surviving-major ids (fix
// round 2) — an extra id (not a surviving major) never blocks, whatever its action,
// body, or repetition.
cov = dispositionCoverage(S, [{ id: "zzz", action: "adr", adr_body: "" }]);
check("coverage-extra-empty-body-not-invalid", eq(cov.invalid, []) && eq(cov.extra, ["zzz"]));
cov = dispositionCoverage(S, [{ id: "zzz", action: "adr", adr_body: "b" }, { id: "zzz", action: "adr", adr_body: "b" }]);
check("coverage-extra-duplicate-not-duplicates", eq(cov.duplicates, []));
cov = dispositionCoverage(S, [{ id: "qa-c1-1", action: "fix" }, { id: "qa-c1-1", action: "fix" }]);
check(
  "coverage-duplicate-real-major-not-in-missing",
  eq(cov.duplicates, ["qa-c1-1"]) && cov.missing.indexOf("qa-c1-1") === -1 && eq(cov.missing, ["architect-c1-2"])
);

// dispositionCoverage: invalid (fix round 1) — an "adr" whose body is empty/whitespace
cov = dispositionCoverage(S, [{ id: "architect-c1-2", action: "adr", adr_body: "  " }]);
check("coverage-invalid-empty-body", eq(cov.invalid, ["architect-c1-2"]));
cov = dispositionCoverage(S, [{ id: "architect-c1-2", action: "adr", adr_body: "### Context\nreal body" }]);
check("coverage-invalid-adr-with-body-ok", eq(cov.invalid, []));
cov = dispositionCoverage(S, [{ id: "qa-c1-1", action: "fix" }]);
check("coverage-invalid-fix-no-body-ok", eq(cov.invalid, []));

// assignAdrIds
const asg = assignAdrIds([{ id: "architect-c1-2", action: "adr", adr_title: "T", adr_body: "B" }, { id: "qa-c1-1", action: "fix", reason: "why" }, { id: "x", action: "adr" }], 4);
check("adr-ids-sequential", asg.map["architect-c1-2"].adr_id === 4 && asg.map["x"].adr_id === 5 && asg.next === 6);
check("adr-fix-null-id", asg.map["qa-c1-1"].adr_id === null && asg.map["qa-c1-1"].action === "fix");

// computeFinalizeReady
let r = computeFinalizeReady(S, asg.map);
check("ready-false-with-blocker", r.finalize_ready === false && r.openBlockers.length === 1 && eq(r.openMajors.map(c=>c.id), ["qa-c1-1"]));
const S2 = S.filter((c) => c.severity !== "blocker");
r = computeFinalizeReady(S2, { "architect-c1-2": { action: "adr", adr_id: 4 }, "qa-c1-1": { action: "adr", adr_id: 5 } });
check("ready-true-all-adr", r.finalize_ready === true && r.openMajors.length === 0);
r = computeFinalizeReady(S2, {});
check("ready-false-undispositioned-major-open", r.finalize_ready === false && r.openMajors.length === 2);
r = computeFinalizeReady(S2, { "architect-c1-2": { action: "adr", adr_id: 4 }, "qa-c1-1": { action: "fix", adr_id: null } });
check("ready-false-fix-major-open", r.finalize_ready === false && eq(r.openMajors.map(c=>c.id), ["qa-c1-1"]));

// decideVerdict
check("verdict-clean", decideVerdict(0, 0, 1, 3) === "clean");
check("verdict-clean-with-fix-majors-budget-left", decideVerdict(0, 2, 1, 3) === "clean");
check("verdict-revise", decideVerdict(1, 0, 2, 3) === "revise");
check("verdict-escalate-blockers", decideVerdict(1, 0, 3, 3) === "escalate");
check("verdict-escalate-fix-majors", decideVerdict(0, 1, 3, 3) === "escalate");
check("verdict-clean-at-budget-no-open", decideVerdict(0, 0, 3, 3) === "clean");
check("verdict-budget-1", decideVerdict(0, 1, 1, 1) === "escalate");

// formatAdr
const adr = formatAdr(4, "use token bucket", "### Context\nx\n### Decision\ny\n### Alternatives considered\nz\n### Consequences\nw", 2, "2026-09-03T10:12:41Z", "qa-c1-1", "qa");
check("adr-heading", adr.startsWith("## ADR-4: use token bucket\n"));
check("adr-date", adr.indexOf("- **Date:** 2026-09-03") > 0);
check("adr-cycle", adr.indexOf("- **Cycle:** 2") > 0);
check("adr-dispositions-line", adr.indexOf("- **Dispositions:** qa-c1-1 (raised by qa)") > 0);
check("adr-empty-title-fallback", formatAdr(1, "", "b", 1, "2026-01-01T00:00:00Z", "qa-c1-1", "qa").startsWith("## ADR-1: accept review finding qa-c1-1"));

// formatFindingLines
check("line-blocker", eq(formatFindingLines(S[0], {}), ["- [blocker] (architect-c1-1) b"]));
check("line-major-fix", eq(formatFindingLines(S[1], {}), ["- [major] (architect-c1-2) m1", "  disposition: fix"]));
check("line-major-adr", eq(formatFindingLines(S[1], { "architect-c1-2": { action: "adr", adr_id: 4 } }), ["- [major] (architect-c1-2) m1", "  disposition: adr ADR-4"]));
check("line-refuted", formatFindingLines(S[3], {})[1].startsWith("  refuted-by: coder — reason: ") && formatFindingLines(S[3], {})[1].endsWith("(cites spec.md § X)"));
check("line-minor-no-disposition", eq(formatFindingLines(S[4], {}), ["- [minor] (coder-c1-1) n"]));

console.log("-----"); console.log("passed=" + pass + " failed=" + fail); process.exit(fail > 0 ? 1 : 0);
EOF

node "$TMP/run.js"
