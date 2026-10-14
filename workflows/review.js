// SPDX-License-Identifier: MIT
// workflows/review.js
//
// build-fleet v0.9 — convergent REVIEW workflow.
//
// SDD spec review with adversarial cross-examination, survival vote, and — new in
// v0.9 — an in-workflow DISPOSITION leg that classifies every surviving [major] as
// `adr` (a design trade-off, recorded by the scribe in the feature DECISIONS.md) or
// `fix` (the PO must close it in the spec). From cycle 2 the fan-out is a DELTA
// review: reviewers verify closure of their own prior `fix` findings and may raise
// new findings only at blocker severity, so the open-major set never grows after
// cycle 1. The return object carries `finalize_ready` (zero blockers AND zero `fix`
// majors) — the finalize gate's rule, computed here so the two never disagree.
//
// CONTRACT: docs/v0.2/CONTRACT.md §6.
//
// @cost-ceiling {"input_tokens":600000,"output_tokens":120000}
// (Cost ceiling lives in this header comment, NOT meta — meta must be a pure
// literal and the runtime ignores unknown meta fields. commands/review.md parses
// this line to emit BUILD_FLEET_COST_PREVIEW and to judge cost-runaway.
// Recalibrated 2026-09-06 from the live pilot run: full cycle 1 on a 49 KB
// spec ran 8 agents and spent 274,075 output tokens (733,827 subagent tokens
// total), so the v0.2-guess 30,000-output ceiling had commands/review.md's
// 3× cost-runaway trip at 90,000 — below the measured cost of a normal run.
// The new ceiling puts the runaway trip at 360,000.)
//
// API NOTES (confirmed against the Workflow tool description):
//   - agent(prompt, opts) → final text (string), or a validated object when
//     opts.schema is supplied. opts: {label, phase, schema, model, effort, agentType, isolation}.
//     There is NO opts.tools — reviewer isolation lives in agents/reviewer.md.
//   - parallel(thunks) → BARRIER. Errors → null in the result array.
//   - budget.spent() → output tokens spent this turn (main loop + workflows).
//   - NO Date.now()/Math.random()/new Date() — timestamps come via args.now.

export const meta = {
  name: "build-fleet-review",
  description: "SDD spec review: fan-out reviewers (delta review from cycle 2), then either adversarial cross-examination + survival vote (debate shape) or a panel of fresh verifiers + quote-backed majority vote (verified shape), architect disposition of surviving majors, scribe applies state",
  phases: [
    { title: "Fan-out review", detail: "read-only reviewer agents review the spec in parallel (roster configurable; default architect, qa, coder); cycle >= 2 is a delta review" },
    { title: "Cross-examination", detail: "each reviewer challenges peers' concerns, citing spec/acceptance/DECISIONS" },
    { title: "Survival vote", detail: "retain concerns not refuted by a different-role reviewer" },
    { title: "Verification panel", detail: "verified shape: 3 fresh verifiers judge every blocker/major and closure claim independently, quoting the spec" },
    { title: "Vote", detail: "verified shape: kill on 2 valid refutations; severity is the median vote, lowered only with quoted evidence" },
    { title: "Disposition", detail: "architect classifies each surviving major: adr (trade-off, ADR drafted) or fix (PO must close it in the spec)" },
    { title: "Apply", detail: "scribe writes PROGRESS + REVIEW + DECISIONS deltas" },
  ],
};

// ---------- args ----------
// { feature, cycle, now, run_id, roles?, cycle_budget?, cycle_total?, next_adr_id? }
// `cycle_total`  — cumulative review cycles BEFORE this run (never reset); absent ⇒ cycle - 1.
// `next_adr_id`  — next free feature ADR integer (scripts/adr-index.sh --next); absent ⇒ 1.
const A = typeof args === "string" ? JSON.parse(args) : (args || {});

const feature = A.feature;
const cycle = typeof A.cycle === "string" ? parseInt(A.cycle, 10) : A.cycle;
const now = A.now;
const runId = A.run_id || null;

// Output-token accounting: budget.spent() is a runtime global (absent on older
// runtimes — `typeof` guards the reference so the workflow never throws on it).
const spentAtStart = (typeof budget !== "undefined" && budget && typeof budget.spent === "function") ? budget.spent() : null;
function outputTokensSoFar() {
  return spentAtStart === null ? null : Math.max(0, budget.spent() - spentAtStart);
}

// Scribe result schema — declared ABOVE the first applyScribe() call site (TDZ;
// scripts/workflow-determinism-lint.sh's scribe-schema-tdz rule guards this).
const SCRIBE_RESULT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["ok", "error"],
  properties: {
    ok: { type: "boolean" },
    error: { type: ["string", "null"] },
  },
};

// --- LAYER1-PURE-HELPERS START — configurable roster + budget, and the v0.9 convergence helpers ---
// Extracted VERBATIM by scripts/workflow-review-config.test.sh and
// scripts/workflow-review-convergence.test.sh, so everything here MUST stay pure:
// no log()/agent()/args/budget, deterministic, side-effect-free.
const ALLOWED_REVIEW_ROLES = ["architect", "qa", "coder", "product-owner"];
const DEFAULT_REVIEW_ROLES = ["architect", "qa", "coder"];
const DEFAULT_CYCLE_BUDGET = 3;
const MAX_CYCLE_BUDGET = 3; // sdd-protocol ceiling — never exceed (escalate, don't loop forever)

function normalizeRoles(raw) {
  if (raw === undefined || raw === null) return { roles: DEFAULT_REVIEW_ROLES.slice(), error: null };
  if (!Array.isArray(raw) || raw.length === 0)
    return { roles: null, error: "roles: must be a non-empty array of reviewer roles" };
  const seen = [];
  for (const r of raw) {
    if (typeof r !== "string" || ALLOWED_REVIEW_ROLES.indexOf(r) === -1)
      return { roles: null, error: `roles: unknown reviewer role ${JSON.stringify(r)} (allowed: ${ALLOWED_REVIEW_ROLES.join(", ")})` };
    if (seen.indexOf(r) === -1) seen.push(r);
  }
  if (seen.length < 2)
    return { roles: null, error: "roles: need at least 2 distinct roles so cross-examination has a different-role refuter" };
  return { roles: seen, error: null };
}

function normalizeCycleBudget(raw) {
  if (raw === undefined || raw === null) return { budget: DEFAULT_CYCLE_BUDGET, error: null, clamped: false };
  const n = typeof raw === "string" ? parseInt(raw, 10) : raw;
  if (typeof n !== "number" || Number.isNaN(n) || !Number.isInteger(n))
    return { budget: null, error: "cycle_budget: must be an integer between 1 and " + MAX_CYCLE_BUDGET, clamped: false };
  if (n < 1)
    return { budget: null, error: "cycle_budget: must be >= 1", clamped: false };
  const budget = Math.min(n, MAX_CYCLE_BUDGET);
  return { budget, error: null, clamped: budget !== n };
}

// v0.9: cumulative cycle count BEFORE this run. Absent/malformed ⇒ derived from the
// cycle number (grandfathered PROGRESS files carry no CYCLE_TOTAL yet).
function normalizeCycleTotal(raw, cycle) {
  const fallback = Math.max(0, (Number.isInteger(cycle) ? cycle : 1) - 1);
  if (raw === undefined || raw === null) return fallback;
  const n = typeof raw === "string" ? parseInt(raw, 10) : raw;
  if (typeof n !== "number" || Number.isNaN(n) || !Number.isInteger(n) || n < 0) return fallback;
  return n;
}

// v0.9: next free feature ADR id. Absent/malformed ⇒ 1.
function normalizeNextAdrId(raw) {
  if (raw === undefined || raw === null) return 1;
  const n = typeof raw === "string" ? parseInt(raw, 10) : raw;
  if (typeof n !== "number" || Number.isNaN(n) || !Number.isInteger(n) || n < 1) return 1;
  return n;
}

// v0.9: finding ids are stable across cycles — "<role>-c<cycle>-<n>". A reviewer may
// only mint ids in its own namespace; a re-raised finding keeps its original id.
function findingIdPattern(role) {
  return "^" + role + "-c[0-9]+-[0-9]+$";
}

// v0.9 fix round 1: the cycle a stable finding id "<role>-c<n>-<k>" was FIRST raised
// in — the integer after "-c", or null when the id doesn't carry that shape.
function originCycle(id) {
  const m = typeof id === "string" ? id.match(/-c([0-9]+)-[0-9]+$/) : null;
  return m ? parseInt(m[1], 10) : null;
}

// v0.9 fix round 2: enforce in CODE what the cycle >= 2 prompt only asks for — ONLY a
// cycle-1 [major] may exist on a delta cycle. Any major whose originCycle(id) >= 2 is
// demoted, not only one minted THIS cycle: a major demoted at cycle 2 must not
// resurface as major at cycle 3 (originCycle(id) === cycle alone would let that
// through — fixed in this round). This holds the open-major set from growing after
// cycle 1 even if a reviewer ignores the instruction. Demoted concerns keep their id
// and raiser but drop to minor, with the reason visible in REVIEW.md text. Blockers
// and minors are NEVER demoted, regardless of origin cycle. Cycle 1 (or an
// undefined/non-delta cycle) is a full review — pass everything through.
function enforceDeltaSeverity(concerns, cycle) {
  if (!(typeof cycle === "number" && cycle >= 2)) return { concerns, demoted: [] };
  const demoted = [];
  const out = (concerns || []).map((c) => {
    const origin = originCycle(c.id);
    if (c.severity === "major" && origin !== null && origin >= 2) {
      demoted.push(c.id);
      return {
        ...c,
        severity: "minor",
        text: `[demoted from major: new majors are not permitted on a delta cycle] ${c.text}`,
      };
    }
    return c;
  });
  return { concerns: out, demoted };
}

// v0.9: disposition coverage — every surviving (unrefuted) major must be dispositioned
// exactly once, with a real ADR body when accepted as a trade-off. Returns the ids the
// leg missed, the ids it invented (`extra`), ids it listed more than once, and `adr`
// entries whose adr_body is empty/whitespace (an empty ADR would silently close a
// major). v0.9 fix round 2: `duplicates`/`invalid` are computed ONLY over entries whose
// id is a surviving major — i.e. after excluding `extra` ids — so a malformed `extra`
// entry (an id the leg invented, already reported via `extra`) never blocks apply.
function dispositionCoverage(surviving, dispositions) {
  const majors = surviving.filter((c) => c.severity === "major" && !c.refuted).map((c) => c.id);
  const list = dispositions || [];
  const given = list.map((d) => d.id);
  const missing = majors.filter((id) => given.indexOf(id) === -1);
  const extra = given.filter((id) => majors.indexOf(id) === -1);
  const covering = list.filter((d) => majors.indexOf(d.id) !== -1);
  const seen = {};
  const duplicates = [];
  for (const d of covering) {
    seen[d.id] = (seen[d.id] || 0) + 1;
    if (seen[d.id] === 2) duplicates.push(d.id);
  }
  const invalid = covering
    .filter((d) => d.action === "adr" && String(d.adr_body || "").trim() === "")
    .map((d) => d.id);
  return { missing, extra, duplicates, invalid };
}

// v0.9: assign sequential feature ADR ids to `adr` dispositions, in the order given.
// Returns { map: {id → {action, adr_id|null, ...}}, next: <next free id after assignment> }.
function assignAdrIds(dispositions, nextAdrId) {
  const map = {};
  let next = nextAdrId;
  for (const d of dispositions || []) {
    if (d.action === "adr") {
      map[d.id] = { action: "adr", adr_id: next, adr_title: d.adr_title || "", adr_body: d.adr_body || "", reason: d.reason || "" };
      next += 1;
    } else {
      map[d.id] = { action: "fix", adr_id: null, adr_title: "", adr_body: "", reason: d.reason || "" };
    }
  }
  return { map, next };
}

// v0.9: the finalize gate's rule, computed in-workflow so verdict and gate agree.
// finalize_ready ⇔ zero open blockers AND zero open (`fix` or undispositioned) majors.
function computeFinalizeReady(surviving, dispositionMap) {
  const openBlockers = surviving.filter((c) => c.severity === "blocker" && !c.refuted);
  const openMajors = surviving.filter((c) => {
    if (c.severity !== "major" || c.refuted) return false;
    const d = dispositionMap[c.id];
    return !d || d.action !== "adr";
  });
  return { finalize_ready: openBlockers.length === 0 && openMajors.length === 0, openBlockers, openMajors };
}

// v0.9: verdict keeps its blocker meaning; escalation fires on the exhausting cycle
// when blockers OR `fix` majors remain (escalate, don't loop forever).
function decideVerdict(openBlockerCount, openMajorCount, cycle, cycleBudget) {
  if (cycle >= cycleBudget && (openBlockerCount > 0 || openMajorCount > 0)) return "escalate";
  if (openBlockerCount > 0) return "revise";
  return "clean";
}

// v0.9 fix round 3 (C1): text that renders into a SINGLE REVIEW.md/DECISIONS.md
// line — finalize-gate.sh (and any hand-written legacy block) reads "the line
// after a [blocker]/[major] line" as its continuation (refuted-by / disposition),
// and an ADR heading must be one line. An embedded "\n" in agent-authored text
// (a finding's own text, a refutation reason, or an ADR title) would otherwise
// split that line and either be misread as its own continuation or break the
// "## ADR-N: title" heading grammar.
function flattenText(t) {
  return String(t == null ? "" : t).replace(/\s*\n\s*/g, " ").trim();
}

// v0.9: render one ADR block per the `adr` skill's entry format (feature scope).
// `nowIso` is the run's args.now; the date is its first 10 characters (no Date API).
function formatAdr(adrId, title, body, cycle, nowIso, findingId, raisedBy) {
  const date = String(nowIso || "").slice(0, 10);
  const cleanTitle = flattenText(title) || `accept review finding ${findingId}`;
  const cleanBody = String(body || "").trim();
  return [
    `## ADR-${adrId}: ${cleanTitle}`,
    "",
    `- **Date:** ${date}`,
    "- **Status:** accepted",
    `- **Cycle:** ${cycle}`,
    `- **Dispositions:** ${findingId} (raised by ${raisedBy}) — accepted as a trade-off at review cycle ${cycle}`,
    "",
    cleanBody,
  ].join("\n");
}

// v0.9: REVIEW.md line grammar — "- [sev] (id) text", then optional indented
// continuation lines: refuted-by (survival vote) and disposition (majors only).
function formatFindingLines(c, dispositionMap) {
  const lines = [`- [${c.severity}] (${c.id}) ${flattenText(c.text)}`];
  if (c.refuted) {
    const cite = c.refutation_citation ? ` (cites ${flattenText(c.refutation_citation.file)} ${flattenText(c.refutation_citation.locator)})` : "";
    lines.push(`  refuted-by: ${c.refuted_by} — reason: ${flattenText(c.refutation_reason)}${cite}`);
  } else if (c.severity === "major") {
    const d = dispositionMap[c.id];
    lines.push(d && d.action === "adr" ? `  disposition: adr ADR-${d.adr_id}` : "  disposition: fix");
  }
  return lines;
}
// REVIEW_SHAPE and its settings (verified review). Absent ⇒ today's behaviour.
const REVIEW_SHAPES = ["debate", "verified"];
const VERIFIER_MODELS = ["opus", "sonnet", "haiku"];

function normalizeShape(raw) {
  if (raw === undefined || raw === null) return { shape: "debate", error: null };
  if (REVIEW_SHAPES.indexOf(raw) === -1) return { shape: null, error: `shape: must be one of ${REVIEW_SHAPES.join(", ")}` };
  return { shape: raw, error: null };
}

function normalizeVerifierModel(raw) {
  if (raw === undefined || raw === null) return { model: "sonnet", error: null };
  if (VERIFIER_MODELS.indexOf(raw) === -1) return { model: null, error: `verifier_model: must be one of ${VERIFIER_MODELS.join(", ")}` };
  return { model: raw, error: null };
}

function normalizeFlag(raw, name) {
  if (raw === undefined || raw === null) return { value: false, error: null };
  if (raw === true || raw === "true") return { value: true, error: null };
  if (raw === false || raw === "false") return { value: false, error: null };
  return { value: null, error: `${name}: must be true or false` };
}

// Cycles of this review phase whose quote check reopened a finding (scripts/review-carry.sh);
// they do not count against the cycle budget.
function normalizeExemptCycles(raw) {
  if (raw === undefined || raw === null) return { value: 0, error: null };
  const n = typeof raw === "string" ? parseInt(raw, 10) : raw;
  if (typeof n !== "number" || Number.isNaN(n) || !Number.isInteger(n) || n < 0)
    return { value: null, error: "exempt_cycles: must be an integer >= 0" };
  return { value: n, error: null };
}

// The previous verified cycle's open set (finalize-gate.sh --report .open), carried forward.
function normalizeCarried(raw, shape) {
  if (raw === undefined || raw === null) return { carried: [], error: null };
  if (shape !== "verified") return { carried: null, error: "carried: only valid with shape verified" };
  if (!Array.isArray(raw)) return { carried: null, error: "carried: must be an array of finding objects" };
  for (const k of raw) {
    if (!k || typeof k.id !== "string" || typeof k.raised_by !== "string" || ["blocker", "major"].indexOf(k.severity) === -1)
      return { carried: null, error: "carried: each entry needs id, raised_by and severity blocker|major" };
  }
  return { carried: raw.slice(), error: null };
}

// --- VERIFIED-RULES START — REVIEW_SHAPE: verified. JS twin of scripts/lib/verified-review.jq;
// scripts/verified-vote-parity.test.sh renders findings with formatVerifiedFindingLines and
// checks the jq rules reach the same outcome. Pure: no log()/agent()/args/budget.
const VR_SEV = ["minor", "major", "blocker"];
function vrRank(s) { return s === "blocker" ? 2 : s === "major" ? 1 : s === "minor" ? 0 : -1; }

// A verdict's evidence counts: a quote {file,text} and a reason of at least 40 characters.
// (Whether the quote is real is checked after apply, by scripts/quote-check.sh.)
function vrEvidence(v) {
  return !!v && typeof v === "object" && !!v.quote && typeof v.quote === "object" &&
    typeof v.quote.file === "string" && v.quote.file.length > 0 &&
    typeof v.quote.text === "string" && v.quote.text.length > 0 &&
    typeof v.reason === "string" && v.reason.length >= 40;
}

// The schema requires anchor + test on every finding; a blocker/major whose anchor is
// kind "none" (or whose quote/section is empty) or whose test is empty is demoted to minor.
// Carried findings and closure claims are left alone: their evidence is the record's.
function demoteUncheckable(concerns) {
  const demoted = [];
  const out = (concerns || []).map((c) => {
    if (vrRank(c.severity) < 1 || c.carried || c.closure) return c;
    const a = c.anchor || {};
    const anchorOk = (a.kind === "quote" && typeof a.text === "string" && a.text.trim() !== "" && typeof a.file === "string" && a.file !== "") ||
      (a.kind === "absent" && typeof a.section === "string" && a.section.trim() !== "" && typeof a.file === "string" && a.file !== "");
    const testOk = typeof c.test === "string" && c.test.trim() !== "";
    if (anchorOk && testOk) return c;
    const reason = anchorOk ? "no-test" : "no-anchor";
    demoted.push(c.id);
    return { ...c, demoted: { reason } };
  });
  return { concerns: out, demoted };
}

// Verifier k sees the list rotated left by k (deterministic; the runtime has no randomness).
function rotateLeft(list, k) {
  const n = (list || []).length;
  if (n === 0) return [];
  const s = ((k % n) + n) % n;
  return list.slice(s).concat(list.slice(0, s));
}

// One finding (with .verdicts = [{v, vote, severity, reason?, quote?, test_invalid?}]) →
// {final, killed, closed, demoted_reason}. Mirrors vr_outcome with no failed quotes.
function verifiedOutcome(f) {
  const orig = vrRank(f.severity);
  // Only a panel verifier (v = 1, 2 or 3) votes, once (applyVerifiedVote numbers them).
  const seenV = {};
  const vs = (f.verdicts || []).filter((v) => v && typeof v === "object" && (v.v === 1 || v.v === 2 || v.v === 3) && !seenV[v.v] && (seenV[v.v] = true));
  const n = vs.length;
  if (f.carried) return { final: f.severity, killed: false, closed: false, demoted_reason: null };
  if (f.closure) {
    const c = vs.filter((v) => v.vote === "confirm").length;
    return { final: f.severity, killed: false, closed: n >= 2 && c * 2 > n, demoted_reason: null };
  }
  if (orig < 1) return { final: "minor", killed: false, closed: false, demoted_reason: null };
  const r = vs.filter((v) => v.vote === "refute" && vrEvidence(v)).length;
  const ranks = vs.map((v) => { const s = vrRank(v.severity); return s >= 0 && s < orig && vrEvidence(v) ? s : orig; }).sort((a, b) => a - b);
  const med = n < 2 ? orig : ranks[Math.floor(n / 2)];
  const ti = vs.filter((v) => v.test_invalid === true).length;
  const dem = f.demoted && typeof f.demoted === "object" ? (f.demoted.reason || "demoted")
    : n >= 2 && ti * 2 > n ? "test-invalid" : null;
  return { final: dem ? "minor" : VR_SEV[Math.min(med, orig)], killed: r >= 2, closed: false, demoted_reason: dem };
}

// Attach each verifier's verdict to its finding, numbered v = 1..3 in panel order.
// panels: [{verdicts:[{id,…}]}|null, …] (null = verifier failed). Returns findings with
// .verdicts filled and the outcome merged in; `refuted` = killed or closed (so the
// existing disposition/finalize helpers apply unchanged).
function applyVerifiedVote(findings, panels) {
  const byId = {};
  (panels || []).forEach((p, i) => {
    if (!p || !Array.isArray(p.verdicts)) return;
    const seen = {}; // one verdict per finding per verifier: a repeated id keeps its first
    for (const v of p.verdicts) {
      if (!v || typeof v.id !== "string" || seen[v.id]) continue;
      seen[v.id] = true;
      const { id, ...rest } = v;
      (byId[id] ||= []).push({ v: i + 1, ...rest });
    }
  });
  return (findings || []).map((f) => {
    const verdicts = f.carried || vrRank(f.severity) < 1 ? [] : (byId[f.id] || []);
    const withV = { ...f, verdicts };
    const o = verifiedOutcome(withV);
    const demoted = withV.demoted || (o.demoted_reason ? { reason: o.demoted_reason } : undefined);
    return { ...withV, ...o, ...(demoted ? { demoted } : {}), severity: o.final, severity_raised: f.severity, refuted: o.killed || o.closed };
  });
}

// Carried findings (from finalize-gate --report) stay open until a confirmed closure.
// A reviewer's re-listing of one is replaced by the carried record (original severity,
// text, anchor, ref and test; reason "re-listed"), so re-listing can never demote,
// re-verify or drop it; one the reviewer left out is added (reason "not-addressed").
// from_cycle keeps the cycle the finding was first carried from. A finding whose raiser
// is not in <roles> is written in roles[0]'s block (`host`): it stays open, and only its
// raiser can close it. Closure claims (entries with `closure`) pass through. Returns the
// full list, each id once.
function materializeCarried(concerns, carried, cycle, roles) {
  const byId = {};
  for (const k of carried || []) if (k && typeof k.id === "string") byId[k.id] = k;
  const record = (k, reason) => ({
    id: k.id, severity: k.severity, raised_by: k.raised_by, text: k.text,
    anchor: k.quote ? { kind: "quote", ...k.quote } : k.absent ? { kind: "absent", ...k.absent } : { kind: "none" },
    ref: k.ref || "", test: k.test || "",
    carried: { from_cycle: k.carried && Number.isInteger(k.carried.from_cycle) ? k.carried.from_cycle : cycle - 1, reason },
    ...(Array.isArray(roles) && roles.length > 0 && roles.indexOf(k.raised_by) === -1 ? { host: roles[0] } : {}),
  });
  const seen = {};
  const out = [];
  for (const c of concerns || []) {
    if (!c) continue;
    if (c.closure) { seen[c.id] = true; out.push(c); continue; }
    if (byId[c.id]) {
      if (!seen[c.id]) out.push(record(byId[c.id], "re-listed"));
      seen[c.id] = true;
      continue;
    }
    out.push(c);
  }
  for (const k of carried || []) {
    if (!k || typeof k.id !== "string" || seen[k.id]) continue;
    seen[k.id] = true;
    out.push(record(k, "not-addressed"));
  }
  return out;
}

// REVIEW.md lines for one verified finding. The header keeps the RAISED severity; the
// gate recomputes the final one from the verdict lines.
function formatVerifiedFindingLines(c, dispositionMap) {
  const j = (o) => JSON.stringify(o);
  const lines = [`- [${c.severity_raised || c.severity}] (${c.id}) ${flattenText(c.text)}`];
  const a = c.anchor || {};
  if (a.kind === "quote") lines.push(`  quote: ${j({ file: a.file, text: flattenText(a.text) })}`);
  else if (a.kind === "absent") lines.push(`  absent: ${j({ file: a.file, section: flattenText(a.section), missing: flattenText(a.missing) })}`);
  if (c.ref) lines.push(`  ref: ${flattenText(Array.isArray(c.ref) ? c.ref.join(", ") : c.ref)}`);
  if (c.test) lines.push(`  test: ${flattenText(c.test)}`);
  if (c.closure) lines.push(`  closure: ${j({ file: c.closure.file, text: flattenText(c.closure.text) })}`);
  for (const v of c.verdicts || []) {
    const out = { v: v.v, vote: v.vote, severity: v.severity };
    if (v.reason) out.reason = flattenText(v.reason);
    if (v.quote) out.quote = { file: v.quote.file, text: flattenText(v.quote.text) };
    if (v.test_invalid === true) out.test_invalid = true;
    lines.push(`  verdict: ${j(out)}`);
  }
  if (c.carried) lines.push(`  carried: ${j(c.carried)}`);
  if (c.demoted) lines.push(`  demoted: ${j(c.demoted)}`);
  if (c.verdicts && c.verdicts.length > 0) {
    const n = c.verdicts.length;
    const summary = c.closure ? `closure ${c.closed ? "confirmed" : "rejected"} (${c.verdicts.filter((v) => v.vote === "confirm").length}/${n})`
      : c.killed ? `refuted ${c.verdicts.filter((v) => v.vote === "refute").length}/${n}` : `upheld, severity ${c.final}`;
    lines.push(`  verified: ${summary}`);
  }
  if (!c.refuted && c.final === "major") {
    const d = dispositionMap[c.id];
    lines.push(d && d.action === "adr" ? `  disposition: adr ADR-${d.adr_id}` : "  disposition: fix");
  }
  return lines;
}
// --- VERIFIED-RULES END ---
// --- LAYER1-PURE-HELPERS END ---

// --- LENS START — reviewer lenses, injected into the read-only reviewer agent ---
// architect/qa/coder are VERBATIM copies of each role agent's "## Review lens"
// section (scripts/lens-drift.test.sh fails the suite if they drift). product-owner
// exists only here. Between the markers: a pure object literal, nothing else.
const LENS = {
  architect: `- **Correctness.** Does the proposal actually do what \`acceptance.md\`
  demands? Are there contradictions between spec sections, or between spec
  and code?
- **Failure modes.** What happens on partial failure, network loss, retries,
  concurrent callers, malformed input? Silence is a \`[major]\` when the failure
  would corrupt data or break an acceptance criterion, a \`[minor]\` otherwise.
- **Data integrity.** Schema migrations, write ordering, idempotency,
  transactional boundaries.
- **Security.** Auth, authz, input validation, secrets handling, blast
  radius of compromised credentials.
- **Scalability.** What breaks at 10× load? At 100×?
- **Blast radius.** If this change is wrong, what else breaks?
- **ADR compliance** (during CHANGE_REVIEW). Does the diff honor every ADR
  in \`DECISIONS.md\`? A silent override is a \`[blocker]\`.`,
  qa: `- **Testability.** For each acceptance criterion: could you write a test from it
  *alone*? A \`[major]\` only where a coder would have to guess at behaviour a test
  could fail on; cite the criterion. Prose that could be tighter is a \`[minor]\`.
- **Measurability.** "Fast", "robust", "user-friendly" with no number or observable
  check: a \`[major]\` inside an acceptance criterion, a \`[minor]\` in narrative text.
- **Coverage.** Spec behaviour with no acceptance criterion is a \`[major]\`. An
  acceptance criterion with no described behaviour is a \`[major]\` only if a coder
  would implement it blind, otherwise a \`[minor]\`.`,
  coder: `- **Interface contracts.** A signature, error envelope or data shape the spec
  leaves open is a \`[major]\` only when two reasonable implementations would fail
  different tests; otherwise state the assumption you would make as a \`[minor]\`.
- **Implementability.** An acceptance criterion that cannot be implemented as
  written, or that contradicts another, is a \`[blocker]\`.
- **Hidden dependencies.** An implicit dependency on infrastructure or a library
  the spec does not name is a \`[major]\` when it changes the stack or the deploy
  shape, a \`[minor]\` otherwise.`,
  "product-owner": `- Does the spec realize the inherited backlog intent, or has it drifted
  in scope without saying so in its Self-review notes?
- Is every acceptance criterion testable and mapped 1:1 to a described behavior?
- Are the Non-goals explicit enough that a reviewer cannot raise scope creep
  as a defect?`,
};
// --- LENS END ---

// Validation failures are NEVER a bare throw (a throw would strand the marker).
const rolesResult = normalizeRoles(A.roles);
const budgetResult = normalizeCycleBudget(A.cycle_budget);
const shapeResult = normalizeShape(A.shape);
const verifierModelResult = normalizeVerifierModel(A.verifier_model);
const soloResult = normalizeFlag(A.verify_blockers_solo, "verify_blockers_solo");
const exemptResult = normalizeExemptCycles(A.exempt_cycles);
const carriedResult = normalizeCarried(A.carried, shapeResult.shape);

const argErrors = [];
if (!feature || typeof feature !== "string") argErrors.push("feature: required non-empty string");
if (typeof cycle !== "number" || Number.isNaN(cycle)) argErrors.push("cycle: required integer");
if (!now || typeof now !== "string") argErrors.push("now: required iso8601 string (the dispatching command supplies it — the script cannot call Date)");
if (rolesResult.error) argErrors.push(rolesResult.error);
if (budgetResult.error) argErrors.push(budgetResult.error);
for (const r of [shapeResult, verifierModelResult, soloResult, exemptResult, carriedResult]) if (r.error) argErrors.push(r.error);
if (argErrors.length > 0) {
  log(`Invalid args: ${argErrors.join("; ")}. No state advanced.`);
  if (feature && typeof feature === "string") {
    await applyScribe(cleanupEnvelope(feature, typeof now === "string" ? now : null, runId));
  }
  return {
    verdict: "invalid-args",
    errors: argErrors,
    note: feature && typeof feature === "string"
      ? "Marker cleanup dispatched; PHASE/CYCLE unchanged. Fix the dispatch args and re-run /build-fleet:review."
      : "feature unknown — the dispatching command must delete .sdd/<slug>/.workflow-in-flight itself (only if its content matches the run_id it wrote).",
  };
}

const ROLES = rolesResult.roles;
const cycleBudget = budgetResult.budget;
const cycleTotalBefore = normalizeCycleTotal(A.cycle_total, cycle);
const nextAdrId = normalizeNextAdrId(A.next_adr_id);
const SHAPE = shapeResult.shape;
const VERIFIER_MODEL = verifierModelResult.model;
const VERIFY_BLOCKERS_SOLO = soloResult.value;
const CARRIED = carriedResult.carried;
// Cycles whose quote check reopened a finding do not count against the budget; added
// AFTER the MAX_CYCLE_BUDGET clamp so decideVerdict does not escalate the exempt cycle.
const effectiveBudget = cycleBudget + exemptResult.value;
log(`Review shape: ${SHAPE}${SHAPE === "verified" ? `; verifier model ${VERIFIER_MODEL}; per-blocker panels ${VERIFY_BLOCKERS_SOLO}; carried ${CARRIED.length}; exempt cycles ${exemptResult.value} (effective budget ${effectiveBudget})` : ""}.`);
log(`Reviewer roster: [${ROLES.join(", ")}]; cycle budget ${cycleBudget}; cumulative cycles before this run ${cycleTotalBefore}; next feature ADR id ${nextAdrId}.`);
if (budgetResult.clamped) {
  log(`cycle_budget requested ${JSON.stringify(A.cycle_budget)} exceeds the protocol ceiling — capped to ${MAX_CYCLE_BUDGET}.`);
}

// Per-role model: the architect lens and the disposition leg run on opus (today's
// cost profile); the read-only reviewer agent's own default is sonnet.
function modelFor(role) {
  return role === "architect" ? "opus" : undefined;
}

// ---------- schemas (structured agent output) ----------

function concernsSchemaFor(role, shape) {
  const base = {
    type: "object",
    additionalProperties: false,
    required: ["role", "status", "concerns"],
    properties: {
      role: { type: "string", enum: [role] },
      status: { type: "string", enum: ["concerns-raised", "approved"] },
      concerns: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["id", "severity", "text"],
          properties: {
            id: { type: "string", pattern: findingIdPattern(role) },
            severity: { type: "string", enum: ["blocker", "major", "minor"] },
            text: { type: "string" },
          },
        },
      },
    },
  };
  if (shape !== "verified") return base;
  // Verified shape: every finding carries an anchor and a test (a [minor] may use anchor
  // kind "none"); delta cycles return closure claims for carried findings.
  const item = base.properties.concerns.items;
  item.required = ["id", "severity", "text", "anchor", "test"];
  item.properties.anchor = {
    type: "object",
    additionalProperties: false,
    required: ["kind"],
    properties: {
      kind: { type: "string", enum: ["quote", "absent", "none"] },
      file: { type: "string" },
      text: { type: "string" },
      section: { type: "string" },
      missing: { type: "string" },
    },
  };
  item.properties.test = { type: "string" };
  item.properties.ref = { type: "string" };
  base.required = ["role", "status", "concerns", "closures"];
  base.properties.closures = {
    type: "array",
    items: {
      type: "object",
      additionalProperties: false,
      required: ["id", "closure"],
      properties: {
        id: { type: "string" },
        closure: {
          type: "object",
          additionalProperties: false,
          required: ["file", "text"],
          properties: { file: { type: "string" }, text: { type: "string" } },
        },
      },
    },
  };
  return base;
}

const REFUTATION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["role", "refutations"],
  properties: {
    role: { type: "string", enum: ROLES },
    refutations: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["concern_id", "verdict", "reason"],
        properties: {
          concern_id: { type: "string" },
          verdict: { type: "string", enum: ["refute", "affirm"] },
          reason: { type: "string" },
          citation: {
            type: "object",
            additionalProperties: false,
            required: ["file", "locator"],
            properties: {
              file: { type: "string" },
              locator: { type: "string" },
            },
          },
        },
      },
    },
  },
};

const VERIFICATION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["verdicts"],
  properties: {
    verdicts: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["id", "vote", "severity", "reason"],
        properties: {
          id: { type: "string" },
          vote: { type: "string", enum: ["uphold", "refute", "confirm", "reject"] },
          severity: { type: "string", enum: ["blocker", "major", "minor"] },
          reason: { type: "string" },
          quote: {
            type: "object",
            additionalProperties: false,
            required: ["file", "text"],
            properties: { file: { type: "string" }, text: { type: "string" } },
          },
          test_invalid: { type: "boolean" },
        },
      },
    },
  },
};

const DISPOSITION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["role", "dispositions"],
  properties: {
    role: { type: "string", enum: ["architect"] },
    dispositions: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["id", "action", "reason"],
        properties: {
          id: { type: "string" },
          action: { type: "string", enum: ["adr", "fix"] },
          reason: { type: "string" },
          adr_title: { type: "string" },
          adr_body: { type: "string" },
        },
      },
    },
  },
};

// ---------- Phase 1: fan-out review ----------

phase("Fan-out review");

const reviewerResults = await parallel(
  ROLES.map((role) => () =>
    agent(reviewPrompt(role, feature, cycle, LENS[role], SHAPE, CARRIED.filter((k) => k.raised_by === role)), {
      label: `review:${role}`,
      phase: "Fan-out review",
      agentType: "build-fleet:reviewer",
      ...(modelFor(role) ? { model: modelFor(role) } : {}),
      schema: concernsSchemaFor(role, SHAPE),
    })
  )
);

const reviews = ROLES.map((role, i) => ({ role, payload: reviewerResults[i] }));
for (const r of reviews) {
  if (!r.payload || !Array.isArray(r.payload.concerns)) {
    log(`Review incomplete: ${r.role} returned no usable concerns payload. Cleaning up without advancing state.`);
    const scribeResult = await applyScribe(cleanupEnvelope(feature, now, runId));
    return {
      verdict: "incomplete",
      reason: "missing-reviewer-payload",
      role: r.role,
      feature,
      cycle,
      scribe_apply: scribeResult.ok ? "applied" : "failed",
      scribe_error: scribeResult.error,
      note: "No REVIEW.md entries written; PHASE/CYCLE unchanged. Re-run /build-fleet:review.",
    };
  }
}

const enforced = enforceDeltaSeverity(mergeConcerns(reviews), cycle);
const allConcerns = enforced.concerns;
if (enforced.demoted.length > 0) {
  log(`Delta-severity enforcement demoted new major(s) to minor (not permitted on a delta cycle): ${enforced.demoted.join(", ")}.`);
}

let surviving;
let verification = null;

if (SHAPE === "verified") {
  // ---------- Phase 2 (verified): verification panel ----------
  // Closure claims count only for carried findings the claiming reviewer raised.
  const carriedById = {};
  for (const k of CARRIED) carriedById[k.id] = k;
  const closures = [];
  for (const r of reviews) {
    for (const cl of r.payload.closures || []) {
      const k = cl && carriedById[cl.id];
      if (!k || k.raised_by !== r.role || !cl.closure) {
        log(`Closure claim ignored (not a carried finding raised by ${r.role}): ${cl && cl.id}.`);
        continue;
      }
      closures.push({ id: k.id, severity: k.severity, raised_by: k.raised_by, text: k.text, closure: cl.closure });
    }
  }
  const closureIds = closures.map((c) => c.id);
  const offRoster = CARRIED.filter((k) => ROLES.indexOf(k.raised_by) === -1).map((k) => k.id);
  if (offRoster.length > 0) log(`Carried findings whose raiser is not in the roster are written in ${ROLES[0]}'s block and stay open until their raiser closes them: ${offRoster.join(", ")}.`);
  const dem = demoteUncheckable(materializeCarried(allConcerns.filter((c) => closureIds.indexOf(c.id) === -1).concat(closures), CARRIED, cycle, ROLES));
  if (dem.demoted.length > 0) log(`Demoted to minor (no anchor or no test): ${dem.demoted.join(", ")}.`);
  const findings = dem.concerns;
  const toVerify = findings.filter((f) => !f.carried && !f.demoted && (f.closure || vrRank(f.severity) >= 1));
  const verifyItem = (f) => f.closure
    ? { id: f.id, kind: "closure", severity: f.severity, text: f.text, closure: f.closure }
    : { id: f.id, kind: "finding", severity: f.severity, text: f.text, anchor: f.anchor, ref: f.ref || "", test: f.test };
  const soloIds = VERIFY_BLOCKERS_SOLO ? toVerify.filter((f) => !f.closure && f.severity === "blocker").map((f) => f.id) : [];
  const shared = toVerify.filter((f) => soloIds.indexOf(f.id) === -1).map(verifyItem);

  phase("Verification panel");

  const runPanel = (items, tag) =>
    parallel([0, 1, 2].map((k) => () =>
      agent(verifierPrompt(feature, cycle, rotateLeft(items, k)), {
        label: `verify:${tag}:${k + 1}`,
        phase: "Verification panel",
        agentType: "build-fleet:reviewer",
        model: VERIFIER_MODEL,
        schema: VERIFICATION_SCHEMA,
      })
    ));
  const returned = (ps) => (ps || []).filter((p) => p && Array.isArray(p.verdicts)).length;
  const sharedPanels = shared.length > 0 ? await runPanel(shared, "panel") : [];
  const soloPanels = {};
  for (const id of soloIds) {
    soloPanels[id] = await runPanel([verifyItem(toVerify.filter((f) => f.id === id)[0])], id);
  }
  const short = [];
  if (shared.length > 0 && returned(sharedPanels) < 2) short.push("shared panel");
  for (const id of soloIds) if (returned(soloPanels[id]) < 2) short.push(`panel for ${id}`);
  if (short.length > 0) {
    log(`Verifier panel incomplete (${short.join(", ")} returned fewer than 2 verdict sets). Cleaning up without advancing state.`);
    const scribeResult = await applyScribe(cleanupEnvelope(feature, now, runId));
    return {
      verdict: "incomplete",
      reason: "verifier-panel",
      panels: short,
      feature,
      cycle,
      scribe_apply: scribeResult.ok ? "applied" : "failed",
      scribe_error: scribeResult.error,
      note: "No REVIEW.md entries written; PHASE/CYCLE unchanged. Re-run /build-fleet:review.",
    };
  }

  // ---------- Phase 3 (verified): vote (pure JS; the gate recomputes it) ----------

  phase("Vote");

  surviving = findings.map((f) => applyVerifiedVote([f], soloIds.indexOf(f.id) !== -1 ? soloPanels[f.id] : sharedPanels)[0]);
  verification = {
    raised: findings.filter((f) => !f.carried && !f.closure).length,
    verified: toVerify.length,
    killed: surviving.filter((c) => c.killed).length,
    closed: surviving.filter((c) => c.closed).length,
    demoted: surviving.filter((c) => c.demoted).length,
    carried: surviving.filter((c) => c.carried).length,
    solo_panels: soloIds.length,
  };
  log(`Verification: ${verification.verified} judged, ${verification.killed} refuted, ${verification.closed} closures confirmed, ${verification.demoted} demoted, ${verification.carried} carried.`);
} else {
  // ---------- Phase 2: cross-examination ----------

  phase("Cross-examination");

  const xaResults = await parallel(
    ROLES.map((role) => () =>
      agent(crossExamPrompt(role, allConcerns, feature, cycle), {
        label: `cross-exam:${role}`,
        phase: "Cross-examination",
        agentType: "build-fleet:reviewer",
        ...(modelFor(role) ? { model: modelFor(role) } : {}),
        schema: REFUTATION_SCHEMA,
      })
    )
  );

  const refutationMap = mergeRefutations(ROLES, xaResults);

  // ---------- Phase 3: survival vote (pure JS) ----------

  phase("Survival vote");

  surviving = applySurvivalVote(allConcerns, refutationMap);
}

// ---------- Phase 4: disposition (architect, read-only; scribe writes the ADRs) ----------

phase("Disposition");

const survivingMajors = surviving.filter((c) => c.severity === "major" && !c.refuted);
let dispositionMap = {};
let decisionsAppendix = null;
let adrsWritten = 0;

if (survivingMajors.length === 0) {
  log("No surviving majors — disposition leg skipped.");
} else {
  const exhausting = cycle >= effectiveBudget;
  let dispo = null;
  try {
    dispo = await agent(dispositionPrompt(feature, cycle, survivingMajors, nextAdrId, exhausting), {
      label: "disposition:architect",
      phase: "Disposition",
      agentType: "build-fleet:reviewer",
      model: "opus",
      schema: DISPOSITION_SCHEMA,
    });
  } catch (e) {
    dispo = null;
    log(`Disposition agent errored: ${e && e.message ? e.message : String(e)}`);
  }
  const coverage = dispositionCoverage(surviving, dispo && dispo.dispositions);
  const dispositionBad =
    !dispo || !Array.isArray(dispo.dispositions) ||
    coverage.missing.length > 0 || coverage.duplicates.length > 0 || coverage.invalid.length > 0;
  if (dispositionBad) {
    const parts = [];
    if (coverage.missing.length > 0) parts.push(`missing ${coverage.missing.join(", ")}`);
    if (coverage.duplicates.length > 0) parts.push(`duplicate ids ${coverage.duplicates.join(", ")}`);
    if (coverage.invalid.length > 0) parts.push(`empty adr body for ${coverage.invalid.join(", ")}`);
    log(`Disposition incomplete: ${dispo ? parts.join("; ") : "no payload"}. Cleaning up without advancing state.`);
    const scribeResult = await applyScribe(cleanupEnvelope(feature, now, runId));
    return {
      verdict: "incomplete",
      reason: "disposition-incomplete",
      missing: coverage.missing,
      duplicates: coverage.duplicates,
      invalid: coverage.invalid,
      feature,
      cycle,
      scribe_apply: scribeResult.ok ? "applied" : "failed",
      scribe_error: scribeResult.error,
      note: "No REVIEW.md entries written; PHASE/CYCLE unchanged. Re-run /build-fleet:review.",
    };
  }
  if (coverage.extra.length > 0) {
    log(`Disposition named ids that are not surviving majors (ignored): ${coverage.extra.join(", ")}.`);
  }
  const kept = dispo.dispositions.filter((d) => coverage.extra.indexOf(d.id) === -1);
  const assigned = assignAdrIds(kept, nextAdrId);
  dispositionMap = assigned.map;
  const survivingById = {};
  for (const c of survivingMajors) survivingById[c.id] = c;
  const adrBlocks = [];
  for (const d of kept) {
    const disp = dispositionMap[d.id];
    const c = survivingById[d.id];
    if (disp && disp.action === "adr" && c) {
      adrBlocks.push(formatAdr(disp.adr_id, disp.adr_title, disp.adr_body, cycle, now, c.id, c.raised_by));
    }
  }
  adrsWritten = adrBlocks.length;
  decisionsAppendix = adrBlocks.length > 0 ? adrBlocks.join("\n\n") : null;
  log(`Disposition: ${adrsWritten} accepted via ADR, ${survivingMajors.length - adrsWritten} to fix.`);
}

const ready = computeFinalizeReady(surviving, dispositionMap);
const verdict = decideVerdict(ready.openBlockers.length, ready.openMajors.length, cycle, effectiveBudget);

log(
  `Cycle ${cycle}: ${surviving.length} concerns, ${ready.openBlockers.length} open blockers, ${ready.openMajors.length} open majors → verdict=${verdict}, finalize_ready=${ready.finalize_ready}`
);

// ---------- Phase 5: apply via scribe ----------

phase("Apply");

const outputTokens = outputTokensSoFar();
const envelope = buildEnvelope({
  feature, cycle, cycleBudget: effectiveBudget, cycleTotalBefore, now, reviews, surviving, dispositionMap,
  decisionsAppendix, ready, verdict, outputTokens, shape: SHAPE,
});
const scribeResult = await applyScribe(envelope);

return {
  verdict,
  shape: SHAPE,
  verification,
  finalize_ready: ready.finalize_ready,
  feature,
  cycle,
  cycle_total: cycleTotalBefore + 1,
  surviving_concerns: surviving.length,
  surviving_blockers: ready.openBlockers.length,
  open_majors: ready.openMajors.map((c) => c.id),
  adrs_written: adrsWritten,
  output_tokens: outputTokens,
  scribe_apply: scribeResult.ok ? "applied" : "failed",
  scribe_error: scribeResult.error,
  next: scribeResult.ok ? envelope.next_legal_commands : [],
  note: scribeResult.ok
    ? undefined
    : "SCRIBE APPLY FAILED after retry — REVIEW.md/PROGRESS.md/DECISIONS.md did NOT land and the .workflow-in-flight marker may remain. The dispatching command must report failure, not success.",
};

// ================= helpers =================

function reviewPrompt(role, feature, cycle, lens, shape, carried) {
  const files = `Read these files yourself (you have Read/Grep/Glob and NOTHING that writes):
- .sdd/${feature}/spec.md
- .sdd/${feature}/acceptance.md
- .sdd/${feature}/REVIEW.md      (the PREVIOUS cycle only — older cycles are archived in REVIEW-archive.md; do not read the archive)
- .sdd/${feature}/DECISIONS.md   (feature ADRs; may not exist on cycle 1)
Read product ADRs (.sdd/_product/DECISIONS.md) only for the specific ADR ids the spec cites — never the whole file.`;

  const rules = `Finding ids are STABLE across cycles and namespaced to you: "${role}-c<cycle>-<n>"
(e.g. "${role}-c${cycle}-1"). A finding you re-raise from an earlier cycle KEEPS its original id.

DECISIONS.md is dispositive. A [major] with "disposition: adr ADR-N" in REVIEW.md is CLOSED by that
ADR: do not re-raise it. If you believe the accepted trade-off is wrong, raise a NEW [blocker]
arguing against the ADR by id.

Do NOT write, edit, or create any file. Return only the structured object.`;

  const verified = shape === "verified";
  const verifiedRules = !verified ? "" : `
VERIFIED REVIEW. Every [blocker] and [major] must be checkable, or it is recorded as a [minor]:
- anchor: EITHER {"kind":"quote","file":"spec.md"|"acceptance.md"|"DECISIONS.md"|"_product/DECISIONS.md","text":"<10–500 characters copied VERBATIM from that file: no paraphrase, no ellipsis>"}
  OR {"kind":"absent","file":"spec.md","section":"<an existing heading of that file>","missing":"<what the spec should say there>"}.
  A [minor] may use {"kind":"none"}.
- test: one sentence naming a test that would FAIL if the finding is real.
- ref: optional, e.g. "§Behavior, AC-3".
Quotes are checked word for word against the files after this review; an invented quote demotes the finding.`;
  const carriedRules = !(verified && carried && carried.length > 0) ? "" : `
OPEN FINDINGS YOU RAISED, carried from the previous cycle. Handle EVERY one:
${JSON.stringify(carried.map((k) => ({ id: k.id, severity: k.severity, text: k.text, ...(k.quote ? { quote: k.quote } : {}), ...(k.absent ? { absent: k.absent } : {}), why_open: k.why || null })), null, 2)}
- Still open ⇒ leave it out of "concerns". It stays open exactly as recorded (severity, quote, test); re-listing it changes nothing.
- Closed by the revised spec ⇒ return it in "closures" as {"id": "<id>", "closure": {"file": "<file>", "text": "<verbatim text of the revised spec that closes it>"}}.
Only a closure the verifier panel confirms closes a carried finding.`;
  const cycleRules = verified && cycle > 1
    ? `This is cycle ${cycle}: a DELTA review. Two jobs, in order:
1. CLOSURE: the carried findings listed below.
2. NEW findings: [blocker] severity ONLY (correctness, security, data loss, or a contradiction
   of spec/acceptance, including a regression introduced by a fix). You may add [minor] notes
   (advisory). You may NOT raise a new [major]: the open-major set only shrinks after cycle 1.`
    : cycle <= 1
    ? `This is cycle 1: a FULL review of the spec through your lens.`
    : `This is cycle ${cycle}: a DELTA review. Two jobs, in order:
1. CLOSURE — for each of YOUR OWN findings from the previous cycle that carries "disposition: fix",
   and each of your own [blocker] findings, check whether the current spec/acceptance closes it.
   Still open ⇒ return it again with its ORIGINAL id (and the same severity). Closed ⇒ omit it.
2. NEW findings — [blocker] severity ONLY (correctness, security, data loss, or a contradiction
   of spec/acceptance — including a regression introduced by a fix). You may add [minor] notes
   (advisory). You may NOT raise a new [major]: the open-major set only shrinks after cycle 1.`;

  return `You are the ${role} reviewer. Cycle ${cycle}. Active feature: ${feature}.

${files}

Review through YOUR lens:
${lens}

The severity rubric (blocker / major / minor) is in your instructions — use those exact words.

${cycleRules}
${verifiedRules}
${carriedRules}

${rules}

Return the structured object:
- role: "${role}"
- status: "concerns-raised" if you hold any blocker/major, else "approved" (informational — the
  gate reads dispositions, not this line)
${verified
    ? `- concerns: array of { id, severity, text, anchor, test, ref? }. Empty array + "approved" when you have nothing.
- closures: array of { id, closure: { file, text } }. Empty array when you claim no closure.`
    : "- concerns: array of { id, severity, text }. Empty array + \"approved\" when you have nothing."}`;
}

function verifierPrompt(feature, cycle, items) {
  return `You are a VERIFIER in a build-fleet spec review, cycle ${cycle}. Active feature: ${feature}.
You did not raise these findings and you are not told who did. Judge each one ONLY against the files.

Read these files yourself (you have Read/Grep/Glob and NOTHING that writes):
- .sdd/${feature}/spec.md
- .sdd/${feature}/acceptance.md
- .sdd/${feature}/DECISIONS.md   (may not exist)
- .sdd/_product/DECISIONS.md     (only for an ADR id a finding or the spec cites)
Do NOT read REVIEW.md or REVIEW-archive.md. Do NOT write, edit, or create any file.

For each item of kind "finding":
- vote "refute" ONLY when the spec as written already answers the claim, and quote the text that answers it.
  Otherwise vote "uphold". When unsure, uphold.
- severity: blocker | major | minor, per the severity rubric in your instructions. A severity BELOW the
  finding's own counts only with a quote of the text that makes it less serious and a reason of at least
  40 characters; without them it counts as the finding's own severity.
- test_invalid: true, with a reason, when the finding's test is vacuous or could not exercise the claim.
  That is not a refutation.
For each item of kind "closure": vote "confirm" when the quoted text of the revised spec really closes the
finding, else "reject" with a reason.

Every quote is {"file": "spec.md"|"acceptance.md"|"DECISIONS.md"|"_product/DECISIONS.md", "text": "<10–500
characters copied VERBATIM from that file>"}. Quotes are checked word for word after this review; an
invented quote voids your vote.

Items (judge EVERY one, each on its own merits):
${JSON.stringify(items, null, 2)}

Return the structured object:
- verdicts: array of { id, vote, severity, reason, quote?, test_invalid? }, exactly one per item.`;
}

function crossExamPrompt(role, allConcerns, feature, cycle) {
  const peers = allConcerns.filter((c) => c.raised_by !== role);
  return `You are the ${role} reviewer in CROSS-EXAMINATION, cycle ${cycle}. Active feature: ${feature}.

Read .sdd/${feature}/spec.md, .sdd/${feature}/acceptance.md and .sdd/${feature}/DECISIONS.md
yourself if you need to cite them. An ADR that dispositions a peer's concern is a
substantive refutation — cite it by id. Do NOT write any file.

Below are concerns raised by OTHER reviewers (not your own). For each, decide whether to
REFUTE it (you believe it is not a real problem) or AFFIRM it (you agree it stands).

A refutation only counts if it is substantive: at least ~40 characters of reasoning AND a
structured citation pointing at the evidence. On every "refute" entry, set the citation
field to { file, locator } — e.g. { "file": "spec.md", "locator": "§ Constraints" } or
{ "file": "acceptance.md", "locator": "line 12" } or
{ "file": "DECISIONS.md", "locator": "ADR-7" }. A refute without a citation is
discarded by the script. If you cannot substantively refute, AFFIRM — that is the safe
default (no citation needed on an affirm).
You cannot refute your own concerns (the script filters self-refutation).

Peer concerns:
${JSON.stringify(peers, null, 2)}

Return the structured object:
- role: "${role}"
- refutations: array of { concern_id, verdict ("refute"|"affirm"), reason, citation? }.
  citation = { file, locator } and is REQUIRED when verdict is "refute".
  Include one entry per peer concern.`;
}

function dispositionPrompt(feature, cycle, majors, nextAdrId, exhausting) {
  const list = majors.map((c) => ({ id: c.id, raised_by: c.raised_by, text: c.text }));
  return `You are the architect, DISPOSITIONING the surviving [major] findings of review cycle ${cycle}
for feature ${feature}. Read .sdd/${feature}/spec.md, .sdd/${feature}/acceptance.md and
.sdd/${feature}/DECISIONS.md yourself. Do NOT write any file — the scribe records your ADRs.

For EVERY finding below, choose exactly one action:
- "adr" — the finding is a genuine design TRADE-OFF the spec should not absorb: the current
  choice is defensible, and the concern is a cost we accept. Supply adr_title (short imperative:
  what the decision IS, not what triggered it) and adr_body: the four sections of the ADR format
  below, WITHOUT the heading and metadata lines (the scribe adds "## ADR-N: title", Date, Status,
  Cycle). ADR ids are assigned sequentially from ADR-${nextAdrId} in the order you list them.
- "fix" — a missing behaviour, an unsatisfiable or untestable criterion, a contradiction, or
  an under-specification a coder would have to guess at. The product-owner must close it in the
  spec next cycle.
${exhausting ? `
This is the EXHAUSTING cycle of the budget: any "fix" you leave open ESCALATES the feature to a
human. Choose "fix" only where the spec genuinely cannot ship as written.` : ""}
Rule of thumb: if closing it would make the spec LONGER without making the system more correct,
it is an "adr". If a test could fail because of it, it is a "fix".

ADR body format (write these four sections, in this order, as markdown):
### Context
What forced the decision — name the finding id and who raised it.
### Decision
The decision in one or two sentences, stated as a positive choice.
### Alternatives considered
The rejected options with a one-line reason each.
### Consequences
What this makes easier, what harder, what now depends on it. Concrete.

Findings to disposition (cover EVERY id, exactly once):
${JSON.stringify(list, null, 2)}

Return the structured object:
- role: "architect"
- dispositions: array of { id, action ("adr"|"fix"), reason, adr_title?, adr_body? } — adr_title
  and adr_body are REQUIRED when action is "adr".`;
}

function mergeConcerns(reviews) {
  const out = [];
  for (const r of reviews) {
    for (const c of r.payload.concerns || []) {
      out.push({
        id: c.id,
        severity: c.severity,
        raised_by: r.role,
        text: c.text,
        ...(c.anchor ? { anchor: c.anchor } : {}),
        ...(c.ref ? { ref: c.ref } : {}),
        ...(typeof c.test === "string" ? { test: c.test } : {}),
        refuted: false,
        refuted_by: null,
        refutation_reason: null,
      });
    }
  }
  return out;
}

function mergeRefutations(roles, xaResults) {
  const map = {};
  roles.forEach((role, i) => {
    const payload = xaResults[i];
    if (!payload || !Array.isArray(payload.refutations)) return;
    for (const ref of payload.refutations) {
      (map[ref.concern_id] ||= []).push({
        role,
        verdict: ref.verdict,
        reason: ref.reason,
        citation: ref.citation || null,
      });
    }
  });
  return map;
}

function validCitation(c) {
  return !!c &&
    typeof c.file === "string" && c.file.trim().length > 0 &&
    typeof c.locator === "string" && c.locator.trim().length > 0;
}

function applySurvivalVote(concerns, refutationMap) {
  const MIN_REFUTATION_CHARS = 40;
  return concerns.map((c) => {
    const refs = (refutationMap[c.id] || []).filter(
      (r) =>
        r.verdict === "refute" &&
        r.role !== c.raised_by &&
        typeof r.reason === "string" &&
        r.reason.length >= MIN_REFUTATION_CHARS &&
        validCitation(r.citation)
    );
    if (refs.length === 0) return c;
    const r = refs[0];
    return { ...c, refuted: true, refuted_by: r.role, refutation_reason: r.reason, refutation_citation: r.citation };
  });
}

function buildEnvelope({ feature, cycle, cycleBudget, cycleTotalBefore, now, reviews, surviving, dispositionMap, decisionsAppendix, ready, verdict, outputTokens, shape }) {
  const reviewEntries = reviews.map((r) => {
    const own = surviving.filter((c) => (c.host || c.raised_by) === r.role);
    const lines = [`## Cycle ${cycle} — ${r.role} — ${now}`];
    if (shape === "verified") lines.push("shape: verified");
    for (const c of own) {
      const rendered = shape === "verified" ? formatVerifiedFindingLines(c, dispositionMap) : formatFindingLines(c, dispositionMap);
      for (const l of rendered) lines.push(l);
    }
    lines.push(`status: ${r.payload.status || "concerns-raised"}`);
    return lines.join("\n");
  });

  const escalation_payload =
    verdict === "escalate"
      ? {
          reason: "cycle-budget-exhausted-with-open-findings",
          cycle,
          cycle_budget: cycleBudget,
          surviving_blockers: ready.openBlockers,
          open_majors: ready.openMajors,
          emitted_at: now,
        }
      : null;

  const state_delta = {
    PHASE: verdict === "escalate" ? "ESCALATED" : "REVIEW",
    CYCLE: cycle,
    CYCLE_TOTAL: cycleTotalBefore + 1,
    UPDATED: now,
  };
  if (outputTokens !== null) state_delta.LAST_REVIEW_OUTPUT_TOKENS = outputTokens;

  return {
    build_fleet_version: "0.2",
    feature,
    run_id: runId,
    phase: "REVIEW",
    cycle,
    verdict,
    finalize_ready: ready.finalize_ready,
    surviving_concerns: surviving,
    review_entries: reviewEntries,
    decisions_appendix: decisionsAppendix,
    state_delta,
    next_legal_commands:
      verdict === "escalate" ? [] : ready.finalize_ready ? ["/build-fleet:finalize"] : ["/build-fleet:revise"],
    estimated_cost_actual: { input_tokens: null, output_tokens: outputTokens },
    escalation_payload,
  };
}

function cleanupEnvelope(feature, now, runId) {
  return {
    build_fleet_version: "0.2",
    feature,
    run_id: runId,
    phase: "REVIEW",
    cycle: 0,
    verdict: "incomplete",
    finalize_ready: false,
    surviving_concerns: [],
    review_entries: [],
    decisions_appendix: null,
    state_delta: now ? { UPDATED: now } : {},
    next_legal_commands: ["/build-fleet:review"],
    estimated_cost_actual: { input_tokens: null, output_tokens: null },
    escalation_payload: null,
  };
}

// ---------- verified scribe application ----------

async function applyScribe(envelope) {
  let lastError = "scribe returned no usable result";
  for (let attempt = 1; attempt <= 2; attempt++) {
    let res = null;
    try {
      res = await agent(
        `Apply this build-fleet workflow envelope to .sdd/${envelope.feature}/ exactly per your instructions in agents/scribe.md.

Marker ownership: RELEASE .sdd/${envelope.feature}/.workflow-in-flight by overwriting it with EMPTY content via the Write tool (you have no Bash; an empty marker counts as released and is reaped later) — ONLY if its current content matches the envelope's run_id${envelope.run_id ? ` ("${envelope.run_id}")` : " (null — legacy envelope: release unconditionally, best-effort)"}. If the content differs, leave the marker — it belongs to another run.

Append rules: append to REVIEW.md and DECISIONS.md with an Edit anchored on the file's final \`## \` block (its heading line through the last non-empty line), per agents/scribe.md — never rewrite a whole file. A state_delta key with no matching line in PROGRESS.md is APPENDED as a new line.

Return the structured object {ok, error}: ok=true when the WHOLE envelope landed (your SCRIBE_OK condition), with error=null. ok=false with error="<one-line reason>" otherwise (your SCRIBE_ERROR reason).

ENVELOPE:
${JSON.stringify(envelope, null, 2)}`,
        {
          label: attempt === 1 ? "scribe" : "scribe-retry",
          phase: "Apply",
          agentType: "build-fleet:scribe",
          effort: "low",
          schema: SCRIBE_RESULT_SCHEMA,
        }
      );
    } catch (e) {
      res = null;
      lastError = "scribe agent error: " + (e && e.message ? e.message : String(e));
    }
    if (res && res.ok === true) return { ok: true, error: null };
    if (res && typeof res.error === "string" && res.error) lastError = res.error;
    log(`Scribe apply attempt ${attempt}/2 failed: ${lastError}`);
  }
  return { ok: false, error: lastError };
}
