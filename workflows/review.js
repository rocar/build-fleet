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
// @cost-ceiling {"input_tokens":120000,"output_tokens":30000}
// (Cost ceiling lives in this header comment, NOT meta — meta must be a pure
// literal and the runtime ignores unknown meta fields. commands/review.md parses
// this line to emit BUILD_FLEET_COST_PREVIEW and to judge cost-runaway.)
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
  description: "SDD spec review: fan-out reviewers (delta review from cycle 2), adversarial cross-examination, survival vote, architect disposition of surviving majors, scribe applies state",
  phases: [
    { title: "Fan-out review", detail: "read-only reviewer agents review the spec in parallel (roster configurable; default architect, qa, coder); cycle >= 2 is a delta review" },
    { title: "Cross-examination", detail: "each reviewer challenges peers' concerns, citing spec/acceptance/DECISIONS" },
    { title: "Survival vote", detail: "retain concerns not refuted by a different-role reviewer" },
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

// v0.9: render one ADR block per the `adr` skill's entry format (feature scope).
// `nowIso` is the run's args.now; the date is its first 10 characters (no Date API).
function formatAdr(adrId, title, body, cycle, nowIso, findingId, raisedBy) {
  const date = String(nowIso || "").slice(0, 10);
  const cleanTitle = String(title || "").trim() || `accept review finding ${findingId}`;
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
  const lines = [`- [${c.severity}] (${c.id}) ${c.text}`];
  if (c.refuted) {
    const cite = c.refutation_citation ? ` (cites ${c.refutation_citation.file} ${c.refutation_citation.locator})` : "";
    lines.push(`  refuted-by: ${c.refuted_by} — reason: ${c.refutation_reason}${cite}`);
  } else if (c.severity === "major") {
    const d = dispositionMap[c.id];
    lines.push(d && d.action === "adr" ? `  disposition: adr ADR-${d.adr_id}` : "  disposition: fix");
  }
  return lines;
}
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
  concurrent callers, malformed input? If the spec is silent, that is a
  finding.
- **Data integrity.** Schema migrations, write ordering, idempotency,
  transactional boundaries.
- **Security.** Auth, authz, input validation, secrets handling, blast
  radius of compromised credentials.
- **Scalability.** What breaks at 10× load? At 100×?
- **Blast radius.** If this change is wrong, what else breaks?
- **ADR compliance** (during CHANGE_REVIEW). Does the diff honor every ADR
  in \`DECISIONS.md\`? A silent override is a \`[blocker]\`.`,
  qa: `- For each acceptance criterion: could you write a test from this *alone*?
  If you have to invent assumptions, that's at minimum a \`[major]\`.
- Are non-functional requirements (performance, security, accessibility)
  testable as written? Or are they aspirational?
- Are the criteria measurable? "Fast", "robust", "user-friendly" are
  \`[blocker]\`-tier vagueness.
- Is there spec behavior with no acceptance coverage? Flag the gap.
- Are there acceptance criteria with no corresponding spec behavior? Flag
  the orphan — either spec is incomplete or the criterion is over-scope.`,
  coder: `- Missing or unclear interface contracts (signatures, error envelopes).
- Acceptance criteria that can't be implemented as written.
- Spec behavior with no corresponding acceptance coverage (you'll have to
  guess what "done" means).
- Implicit dependencies on infra or libraries the spec doesn't mention.`,
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

const argErrors = [];
if (!feature || typeof feature !== "string") argErrors.push("feature: required non-empty string");
if (typeof cycle !== "number" || Number.isNaN(cycle)) argErrors.push("cycle: required integer");
if (!now || typeof now !== "string") argErrors.push("now: required iso8601 string (the dispatching command supplies it — the script cannot call Date)");
if (rolesResult.error) argErrors.push(rolesResult.error);
if (budgetResult.error) argErrors.push(budgetResult.error);
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

function concernsSchemaFor(role) {
  return {
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
    agent(reviewPrompt(role, feature, cycle, LENS[role]), {
      label: `review:${role}`,
      phase: "Fan-out review",
      agentType: "build-fleet:reviewer",
      ...(modelFor(role) ? { model: modelFor(role) } : {}),
      schema: concernsSchemaFor(role),
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

const surviving = applySurvivalVote(allConcerns, refutationMap);

// ---------- Phase 4: disposition (architect, read-only; scribe writes the ADRs) ----------

phase("Disposition");

const survivingMajors = surviving.filter((c) => c.severity === "major" && !c.refuted);
let dispositionMap = {};
let decisionsAppendix = null;
let adrsWritten = 0;

if (survivingMajors.length === 0) {
  log("No surviving majors — disposition leg skipped.");
} else {
  const exhausting = cycle >= cycleBudget;
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
const verdict = decideVerdict(ready.openBlockers.length, ready.openMajors.length, cycle, cycleBudget);

log(
  `Cycle ${cycle}: ${surviving.length} concerns, ${ready.openBlockers.length} open blockers, ${ready.openMajors.length} open majors → verdict=${verdict}, finalize_ready=${ready.finalize_ready}`
);

// ---------- Phase 5: apply via scribe ----------

phase("Apply");

const outputTokens = outputTokensSoFar();
const envelope = buildEnvelope({
  feature, cycle, cycleBudget, cycleTotalBefore, now, reviews, surviving, dispositionMap,
  decisionsAppendix, ready, verdict, outputTokens,
});
const scribeResult = await applyScribe(envelope);

return {
  verdict,
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

function reviewPrompt(role, feature, cycle, lens) {
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

  const cycleRules = cycle <= 1
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

${rules}

Return the structured object:
- role: "${role}"
- status: "concerns-raised" if you hold any blocker/major, else "approved" (informational — the
  gate reads dispositions, not this line)
- concerns: array of { id, severity, text }. Empty array + "approved" when you have nothing.`;
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

function buildEnvelope({ feature, cycle, cycleBudget, cycleTotalBefore, now, reviews, surviving, dispositionMap, decisionsAppendix, ready, verdict, outputTokens }) {
  const reviewEntries = reviews.map((r) => {
    const own = surviving.filter((c) => c.raised_by === r.role);
    const lines = [`## Cycle ${cycle} — ${r.role} — ${now}`];
    for (const c of own) {
      for (const l of formatFindingLines(c, dispositionMap)) lines.push(l);
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

Append rules: append to REVIEW.md and DECISIONS.md with an Edit anchored on the file's final non-empty line — never rewrite a whole file. A state_delta key with no matching line in PROGRESS.md is APPENDED as a new line.

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
