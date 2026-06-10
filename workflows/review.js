// SPDX-License-Identifier: MIT
// workflows/review.js
//
// build-fleet v0.2 — M1 review workflow (rewritten against the real Workflow API,
// grounded during Phase 6 against the Workflow tool's authoritative description).
//
// SDD spec review with adversarial cross-examination and survival vote.
// Replaces v0.1's parallel-Task fan-out + agent-teams cycle-3 fallback.
//
// CONTRACT: docs/v0.2/CONTRACT.md.
//
// @cost-ceiling {"input_tokens":120000,"output_tokens":30000}
// (Cost ceiling lives in this header comment, NOT meta — meta must be a pure
// literal and the runtime ignores unknown meta fields. commands/review.md parses
// this line to emit BUILD_FLEET_COST_PREVIEW in headless mode.)
//
// API NOTES (confirmed against the Workflow tool description):
//   - agent(prompt, opts) → returns final text (string), OR a validated object
//     when opts.schema is supplied. opts: {label, phase, schema, model, agentType, isolation}.
//   - parallel(thunks) → thunks is an Array<() => Promise>. BARRIER. Errors → null in result array.
//   - phase(title) → void marker; subsequent agent() calls group under it.
//   - args → the Workflow `args` input, verbatim.
//   - NO Date.now()/Math.random()/new Date() — they throw. Timestamps come via args.now.
//   - Scripts are plain JS, not TS. No filesystem/Node API from the script itself.

export const meta = {
  name: "build-fleet-review",
  description: "SDD spec review: fan-out reviewers, adversarial cross-examination, survival vote, scribe applies state",
  phases: [
    { title: "Fan-out review", detail: "architect, qa, coder review the spec in parallel" },
    { title: "Cross-examination", detail: "each reviewer challenges peers' concerns" },
    { title: "Survival vote", detail: "retain concerns not refuted by a different-role reviewer" },
    { title: "Apply", detail: "scribe writes PROGRESS + REVIEW deltas" },
  ],
};

// ---------- args ----------
// { feature: "<slug>", cycle: <int>, now: "<iso8601>" }
// `now` is supplied by the command because the script cannot call Date.

// The Workflow runtime may deliver `args` as a JSON string rather than a parsed
// object (confirmed empirically during Phase 6 validation). Normalize.
const A = typeof args === "string" ? JSON.parse(args) : (args || {});

const feature = A.feature;
const cycle = typeof A.cycle === "string" ? parseInt(A.cycle, 10) : A.cycle;
const now = A.now || "UNKNOWN_TIME";

if (!feature || typeof cycle !== "number" || Number.isNaN(cycle)) {
  throw new Error(
    "BUILD_FLEET_WORKFLOW_ERROR: args must include {feature, cycle, now}. " +
    "Received args=" + JSON.stringify(args) + " (typeof=" + (typeof args) + ")"
  );
}

// ---------- schemas (structured agent output) ----------

const CONCERNS_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["role", "status", "concerns"],
  properties: {
    role: { type: "string", enum: ["architect", "qa", "coder"] },
    status: { type: "string", enum: ["concerns-raised", "approved"] },
    concerns: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["id", "severity", "text"],
        properties: {
          id: { type: "string" },
          severity: { type: "string", enum: ["blocker", "major", "minor"] },
          text: { type: "string" },
        },
      },
    },
  },
};

const REFUTATION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["role", "refutations"],
  properties: {
    role: { type: "string", enum: ["architect", "qa", "coder"] },
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
        },
      },
    },
  },
};

const ROLES = ["architect", "qa", "coder"];

// ---------- Phase 1: fan-out review ----------

phase("Fan-out review");

const reviewerResults = await parallel(
  ROLES.map((role) => () =>
    agent(reviewPrompt(role, feature, cycle), {
      label: `review:${role}`,
      phase: "Fan-out review",
      agentType: `build-fleet:${role}`,
      schema: CONCERNS_SCHEMA,
    })
  )
);

// Post-condition (replaces the retired check-review-written hook for workflow REVIEW):
// every reviewer must return a usable structured payload. A null (agent error /
// skipped) or missing concerns array halts the workflow into escalation.
const reviews = ROLES.map((role, i) => ({ role, payload: reviewerResults[i] }));
for (const r of reviews) {
  if (!r.payload || !Array.isArray(r.payload.concerns)) {
    await applyScribe(haltEnvelope(feature, cycle, now, {
      reason: "missing-reviewer-payload",
      detail: `Reviewer ${r.role} returned no usable concerns payload.`,
    }));
    return { verdict: "escalate", reason: "missing-reviewer-payload", role: r.role };
  }
}

const allConcerns = mergeConcerns(reviews);

// ---------- Phase 2: cross-examination ----------

phase("Cross-examination");

const xaResults = await parallel(
  ROLES.map((role) => () =>
    agent(crossExamPrompt(role, allConcerns, feature, cycle), {
      label: `cross-exam:${role}`,
      phase: "Cross-examination",
      agentType: `build-fleet:${role}`,
      schema: REFUTATION_SCHEMA,
    })
  )
);

const refutationMap = mergeRefutations(ROLES, xaResults);

// ---------- Phase 3: survival vote (pure JS) ----------

phase("Survival vote");

const surviving = applySurvivalVote(allConcerns, refutationMap);
const survivingBlockers = surviving.filter((c) => c.severity === "blocker" && !c.refuted);
const verdict =
  survivingBlockers.length > 0 ? (cycle >= 3 ? "escalate" : "revise") : "clean";

log(
  `Cycle ${cycle}: ${surviving.length} concerns, ${survivingBlockers.length} surviving blockers → verdict=${verdict}`
);

// ---------- Phase 4: apply via scribe ----------

phase("Apply");

const envelope = buildEnvelope({ feature, cycle, now, reviews, surviving, verdict });
await applyScribe(envelope);

return {
  verdict,
  feature,
  cycle,
  surviving_concerns: surviving.length,
  surviving_blockers: survivingBlockers.length,
  next: envelope.next_legal_commands,
};

// ================= helpers =================

function reviewPrompt(role, feature, cycle) {
  return `You are the ${role} reviewer. Cycle ${cycle}. Active feature: ${feature}.

Read these files yourself (you have Read/Grep/Glob):
- .sdd/${feature}/spec.md
- .sdd/${feature}/acceptance.md
- .sdd/${feature}/REVIEW.md   (prior cycles; may not exist on cycle 1)

Review the spec through your role's lens. The review-rubric skill is preloaded —
use it for severity definitions (blocker / major / minor).

Return your review as the structured object you are required to produce:
- role: "${role}"
- status: "concerns-raised" if you have any blocker/major items, else "approved"
- concerns: array of { id, severity, text }. Use stable IDs "${role}-1", "${role}-2", ...
  If you have no findings, return an empty concerns array and status "approved".`;
}

function crossExamPrompt(role, allConcerns, feature, cycle) {
  const peers = allConcerns.filter((c) => c.raised_by !== role);
  return `You are the ${role} reviewer in CROSS-EXAMINATION, cycle ${cycle}. Active feature: ${feature}.

Read .sdd/${feature}/spec.md and .sdd/${feature}/acceptance.md yourself if you need to cite them.

Below are concerns raised by OTHER reviewers (not your own). For each, decide whether to
REFUTE it (you believe it is not a real problem) or AFFIRM it (you agree it stands).

A refutation only counts if it is substantive: at least ~40 characters of reasoning AND it
cites a specific section of the spec or acceptance (e.g. "spec.md § Constraints" or
"acceptance.md line 12"). If you cannot substantively refute, AFFIRM — that is the safe default.
You cannot refute your own concerns (the script filters self-refutation).

Peer concerns:
${JSON.stringify(peers, null, 2)}

Return the structured object:
- role: "${role}"
- refutations: array of { concern_id, verdict ("refute"|"affirm"), reason }.
  Include one entry per peer concern.`;
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
      });
    }
  });
  return map;
}

function applySurvivalVote(concerns, refutationMap) {
  const SECTION_REF = /(spec|acceptance)\.md\s*§|line\s+\d+/i;
  const MIN_REFUTATION_CHARS = 40;
  return concerns.map((c) => {
    const refs = (refutationMap[c.id] || []).filter(
      (r) =>
        r.verdict === "refute" &&
        r.role !== c.raised_by &&
        typeof r.reason === "string" &&
        r.reason.length >= MIN_REFUTATION_CHARS &&
        SECTION_REF.test(r.reason)
    );
    if (refs.length === 0) return c;
    const r = refs[0];
    return { ...c, refuted: true, refuted_by: r.role, refutation_reason: r.reason };
  });
}

function buildEnvelope({ feature, cycle, now, reviews, surviving, verdict }) {
  const reviewEntries = reviews.map((r) => {
    const own = surviving.filter((c) => c.raised_by === r.role);
    const lines = [`## Cycle ${cycle} — ${r.role} — ${now}`];
    for (const c of own) {
      lines.push(`- [${c.severity}] ${c.text}`);
      if (c.refuted) {
        lines.push(`  refuted-by: ${c.refuted_by} — reason: ${c.refutation_reason}`);
      }
    }
    lines.push(`status: ${r.payload.status || "concerns-raised"}`);
    return lines.join("\n");
  });

  const escalation_payload =
    verdict === "escalate"
      ? {
          reason: "cycle-budget-exhausted-with-open-blockers",
          cycle,
          surviving_blockers: surviving.filter(
            (c) => c.severity === "blocker" && !c.refuted
          ),
          emitted_at: now,
        }
      : null;

  return {
    build_fleet_version: "0.2",
    feature,
    phase: "REVIEW",
    cycle,
    verdict,
    surviving_concerns: surviving,
    review_entries: reviewEntries,
    state_delta: {
      PHASE: verdict === "escalate" ? "ESCALATED" : "REVIEW",
      CYCLE: cycle,
      UPDATED: now,
    },
    next_legal_commands:
      verdict === "clean"
        ? ["/build-fleet:finalize"]
        : verdict === "escalate"
        ? []
        : ["/build-fleet:review"],
    escalation_payload,
  };
}

function haltEnvelope(feature, cycle, now, payload) {
  return {
    build_fleet_version: "0.2",
    feature,
    phase: "REVIEW",
    cycle,
    verdict: "escalate",
    surviving_concerns: [],
    review_entries: [],
    state_delta: { PHASE: "ESCALATED", CYCLE: cycle, UPDATED: now },
    next_legal_commands: [],
    escalation_payload: { ...payload, emitted_at: now },
  };
}

async function applyScribe(envelope) {
  return await agent(
    `Apply this build-fleet workflow envelope to .sdd/${envelope.feature}/ exactly per your instructions in agents/scribe.md.

ENVELOPE:
${JSON.stringify(envelope, null, 2)}`,
    {
      label: "scribe",
      phase: "Apply",
      agentType: "build-fleet:scribe",
    }
  );
}
