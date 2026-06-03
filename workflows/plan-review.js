// workflows/plan-review.js
//
// build-fleet v0.4 — M3.1 product-tier PLAN_REVIEW workflow.
//
// FORK of workflows/review.js, deliberately diverged (the M3.0 decision: fork,
// don't parameterize). The product plan is a STRATEGIC BET, not a contract the
// machine can converge — so this workflow INTERROGATES (surfaces questions,
// risks, gaps from each role's lens) and never holds a survival vote. Nothing is
// auto-refuted; nothing auto-escalates. The output is an interrogation report
// appended to .sdd/_product/REVIEW.md and PHASE := PLAN_REVIEW. A human ratifies
// at /build-fleet:plan-finalize — the machine never votes a vision into being.
//
// Divergences from review.js:
//   - reviewers INTERROGATE product artifacts (vision/backlog/STACK/DECISIONS),
//     not spec.md/acceptance.md.
//   - roles are [product-owner, architect, qa] — product lenses, not [architect,qa,coder].
//     Self-interrogation is fine: the act surfaces risk, it does not vote.
//   - NO cross-examination phase. NO survival vote. Findings are consolidated by
//     pure JS (grouped + counted), never killed.
//   - verdict is informational ("interrogated"), never clean/revise/escalate.
//   - scribe writes the PRODUCT workspace via the envelope's workspace_dir.
//
// CONTRACT: docs/v0.2/CONTRACT.md §6 (envelope + workspace_dir).
//
// @cost-ceiling {"input_tokens":90000,"output_tokens":24000}
// (Cost ceiling lives in this header comment, NOT meta. commands/plan-review.md
// parses this line to emit BUILD_FLEET_COST_PREVIEW in headless mode.)

export const meta = {
  name: "build-fleet-plan-review",
  description: "Product-tier PLAN_REVIEW: interrogate the product plan from each role's lens, consolidate findings (no survival vote), scribe appends the report",
  phases: [
    { title: "Interrogate", detail: "product-owner, architect, qa interrogate vision/backlog/STACK in parallel" },
    { title: "Consolidate", detail: "group + count findings by severity — nothing is auto-killed" },
    { title: "Apply", detail: "scribe appends the interrogation report to _product/REVIEW.md and sets PHASE=PLAN_REVIEW" },
  ],
};

// ---------- args ----------
// { product: "<slug>", cycle: <int>, now: "<iso8601>" }
// `now` is supplied by the command because the script cannot call Date.

const A = typeof args === "string" ? JSON.parse(args) : (args || {});

const product = A.product;
const cycle = typeof A.cycle === "string" ? parseInt(A.cycle, 10) : A.cycle;
const now = A.now || "UNKNOWN_TIME";

if (!product || typeof cycle !== "number" || Number.isNaN(cycle)) {
  throw new Error(
    "BUILD_FLEET_WORKFLOW_ERROR: args must include {product, cycle, now}. " +
    "Received args=" + JSON.stringify(args) + " (typeof=" + (typeof args) + ")"
  );
}

const WORKSPACE = ".sdd/_product/";

// ---------- schema (structured interrogation output) ----------
//
// One object per interrogating role. `findings` is a flat list across the three
// kinds (question | risk | gap) so the role can weight its lens freely; `kind`
// distinguishes them for the report. No refutation/verdict fields — there is no
// vote here.

const INTERROGATION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["role", "findings"],
  properties: {
    role: { type: "string", enum: ["product-owner", "architect", "qa"] },
    findings: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["id", "kind", "severity", "text"],
        properties: {
          id: { type: "string" },
          kind: { type: "string", enum: ["question", "risk", "gap"] },
          severity: { type: "string", enum: ["blocker", "major", "minor"] },
          text: { type: "string" },
          artifact: { type: "string" }, // optional: vision.md | backlog.md | STACK.md | DECISIONS.md
        },
      },
    },
  },
};

const ROLES = ["product-owner", "architect", "qa"];

// ---------- Phase 1: fan-out interrogation ----------

phase("Interrogate");

const interrogations = await parallel(
  ROLES.map((role) => () =>
    agent(interrogatePrompt(role, product, cycle), {
      label: `interrogate:${role}`,
      phase: "Interrogate",
      agentType: `build-fleet:${role}`,
      schema: INTERROGATION_SCHEMA,
    })
  )
);

// Post-condition: every role must return a usable structured payload. Unlike the
// feature review, a missing payload does NOT escalate (there is no auto-escalate
// in plan-review) — it halts the workflow with an error the command surfaces, so
// the human re-runs. We never write a partial interrogation report.
const reports = ROLES.map((role, i) => ({ role, payload: interrogations[i] }));
for (const r of reports) {
  if (!r.payload || !Array.isArray(r.payload.findings)) {
    log(`Interrogation incomplete: ${r.role} returned no usable findings payload. Cleaning up without advancing state.`);
    // Do NOT write the report and do NOT advance PHASE/CYCLE — but we still must
    // remove the .workflow-in-flight marker the command dropped, or it orphans
    // until the reaper. The scribe is the only thing that can delete it (the
    // script has no filesystem access). A cleanup envelope whose state_delta
    // carries ONLY `UPDATED` leaves PHASE + CYCLE untouched (the scribe replaces
    // in place, key by key) while still triggering marker removal. Mirrors how
    // review.js always reaches its scribe on the missing-payload path.
    await applyScribe(cleanupEnvelope(product, now));
    return {
      verdict: "incomplete",
      reason: "missing-interrogator-payload",
      role: r.role,
      product,
      cycle,
      note: "No interrogation report written; PHASE/CYCLE unchanged. Re-run /build-fleet:plan-review.",
    };
  }
}

// ---------- Phase 2: consolidate (pure JS — nothing is killed) ----------

phase("Consolidate");

const allFindings = mergeFindings(reports);
const counts = countBySeverity(allFindings);

log(
  `Plan cycle ${cycle}: ${allFindings.length} findings interrogated ` +
  `(${counts.blocker} blocker, ${counts.major} major, ${counts.minor} minor). ` +
  `No survival vote — all findings surfaced for human ratification.`
);

// ---------- Phase 3: apply via scribe ----------

phase("Apply");

const envelope = buildEnvelope({ product, cycle, now, reports, allFindings, counts });
await applyScribe(envelope);

return {
  verdict: "interrogated",
  product,
  cycle,
  findings: allFindings.length,
  open_blockers: counts.blocker,
  next: envelope.next_legal_commands,
  note: counts.blocker > 0
    ? `${counts.blocker} blocker-severity finding(s) open. /build-fleet:plan-finalize will require 'ratify force' to override.`
    : "No blocker-severity findings. /build-fleet:plan-finalize ratify will pass.",
};

// ================= helpers =================

function interrogatePrompt(role, product, cycle) {
  const lens = LENS[role];
  return `You are the ${role}, INTERROGATING the product plan for "${product}". Plan-review cycle ${cycle}.

This is NOT a spec review and NOT a vote. You are surfacing what a strategic plan
must answer before a human commits to it. You cannot kill anyone's finding and no
finding kills the plan — everything you raise is recorded for the human to weigh.

**Do NOT write or edit any file** — even artifacts you normally own (vision/backlog).
This phase is read-only interrogation; you return findings only. The scribe is the
sole writer; the human revises the plan after reading your report.

Read these product artifacts yourself (you have Read/Grep/Glob):
- .sdd/_product/vision.md      (the product vision + goals; OUTCOME for standard/large)
- .sdd/_product/backlog.md     (phased feature backlog + dependencies)
- .sdd/_product/STACK.md       (the binding stack-of-record; brownfield has a Baseline + maybe PROVISIONAL forward)
- .sdd/_product/DECISIONS.md   (product ADRs — the why behind the stack)
- .sdd/_product/REVIEW.md      (prior interrogation cycles; may not exist on cycle 1)

Interrogate through YOUR lens:
${lens}

Honor the brownfield contract: a "## Forward direction (PROVISIONAL — unreviewed)"
section is strategy that does NOT yet bind. Interrogate whether the provisional
direction is justified — but do NOT treat the binding Baseline as a defect for
merely existing. Flag a stack concern as a finding to the human, never as a demand
to rewrite reality.

Return the structured object you are required to produce:
- role: "${role}"
- findings: array of { id, kind, severity, text, artifact? }
  - id: stable "${role}-1", "${role}-2", ...
  - kind: "question" (an unanswered decision the plan must resolve) |
          "risk" (a way this plan plausibly fails) |
          "gap" (something the plan should cover but omits)
  - severity: "blocker" (a human should not ratify until this is addressed) |
              "major" (should be resolved or consciously accepted) |
              "minor" (worth noting; not ratification-blocking)
  - artifact (optional): which file the finding is about.
  If the plan is sound from your lens, return an empty findings array — that is a
  legitimate signal (you found nothing ratification-relevant), not a failure.`;
}

const LENS = {
  "product-owner":
`- Is the vision coherent and falsifiable? For standard/large, is OUTCOME measurable?
- Is the backlog genuinely PHASED — each phase a shippable increment, not a dumping ground?
- Are depends-on edges real and acyclic? Does phase 1 stand alone?
- Is scope honest, or is this a roadmap that gets abandoned at feature 3? Flag over-ceremony.`,
  "architect":
`- Is the stack-of-record sound for the stated goals and scale? Any load-bearing gap?
- Is each ADR justified, or are there silent/unexplained choices?
- Brownfield: is the Baseline captured accurately? Is any PROVISIONAL forward direction
  incremental (migrate/wrap) rather than a rewrite, and is its risk named?
- What failure modes (data integrity, blast radius, coupling) does the plan not address?`,
  "qa":
`- Is the OUTCOME / are the goals actually measurable and testable as written?
- Does each backlog phase have a discernible acceptance shape, or is "done" undefined?
- What observability / verification is the plan silent on?
- Are there cross-feature integration risks the phasing hides?`,
};

function mergeFindings(reports) {
  const out = [];
  for (const r of reports) {
    for (const f of r.payload.findings || []) {
      out.push({
        id: f.id,
        kind: f.kind,
        severity: f.severity,
        raised_by: r.role,
        text: f.text,
        artifact: f.artifact || null,
      });
    }
  }
  return out;
}

function countBySeverity(findings) {
  const c = { blocker: 0, major: 0, minor: 0 };
  for (const f of findings) {
    if (c[f.severity] !== undefined) c[f.severity] += 1;
  }
  return c;
}

function buildEnvelope({ product, cycle, now, reports, allFindings, counts }) {
  // One REVIEW.md block per role, grouped by kind. Append-only; the scribe writes
  // .sdd/_product/REVIEW.md (workspace_dir below routes it there).
  const KIND_ORDER = ["question", "risk", "gap"];
  const KIND_LABEL = { question: "Open questions", risk: "Risks", gap: "Gaps" };

  const reviewEntries = reports.map((r) => {
    const own = allFindings.filter((f) => f.raised_by === r.role);
    const lines = [`## Plan Cycle ${cycle} — ${r.role} interrogation — ${now}`];
    if (own.length === 0) {
      lines.push("- (no ratification-relevant findings from this lens)");
    } else {
      for (const kind of KIND_ORDER) {
        const group = own.filter((f) => f.kind === kind);
        if (group.length === 0) continue;
        lines.push(`### ${KIND_LABEL[kind]}`);
        for (const f of group) {
          const where = f.artifact ? ` (${f.artifact})` : "";
          lines.push(`- [${f.severity}] ${f.text}${where}`);
        }
      }
    }
    return lines.join("\n");
  });

  // A consolidated summary block, last, so the human sees totals at the tail.
  reviewEntries.push(
    [
      `## Plan Cycle ${cycle} — interrogation summary — ${now}`,
      `- findings: ${allFindings.length} (blocker: ${counts.blocker}, major: ${counts.major}, minor: ${counts.minor})`,
      counts.blocker > 0
        ? `- ratification: BLOCKED by ${counts.blocker} open blocker-severity finding(s) — /build-fleet:plan-finalize requires 'ratify force' to override.`
        : `- ratification: no blocker-severity findings — /build-fleet:plan-finalize ratify will pass.`,
    ].join("\n")
  );

  return {
    build_fleet_version: "0.2",
    feature: product, // scribe uses this for SCRIBE_OK + any ESCALATION title; carries the product slug
    workspace_dir: WORKSPACE,
    phase: "PLAN_REVIEW",
    cycle,
    verdict: "interrogated", // informational — plan-review never votes
    surviving_concerns: [], // no survival vote in plan-review
    review_entries: reviewEntries,
    state_delta: {
      PHASE: "PLAN_REVIEW",
      CYCLE: cycle,
      UPDATED: now,
    },
    next_legal_commands: ["/build-fleet:plan-finalize", "/build-fleet:plan-review"],
    escalation_payload: null, // plan-review never auto-escalates — the human ratifies
  };
}

// Minimal envelope for the incomplete-interrogation path: removes the workflow
// marker and refreshes UPDATED only. state_delta deliberately OMITS PHASE/CYCLE so
// the scribe leaves them at their pre-run values (it only replaces keys present).
function cleanupEnvelope(product, now) {
  return {
    build_fleet_version: "0.2",
    feature: product,
    workspace_dir: WORKSPACE,
    phase: "PLAN_REVIEW",
    cycle: 0,
    verdict: "incomplete",
    surviving_concerns: [],
    review_entries: [], // nothing appended to REVIEW.md
    state_delta: { UPDATED: now }, // PHASE + CYCLE intentionally preserved
    next_legal_commands: ["/build-fleet:plan-review"],
    escalation_payload: null,
  };
}

async function applyScribe(envelope) {
  return await agent(
    `Apply this build-fleet workflow envelope to ${envelope.workspace_dir} exactly per your instructions in agents/scribe.md. Note the workspace_dir field — you write the PRODUCT workspace, not a feature dir.

ENVELOPE:
${JSON.stringify(envelope, null, 2)}`,
    {
      label: "scribe",
      phase: "Apply",
      agentType: "build-fleet:scribe",
    }
  );
}
