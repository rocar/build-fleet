// SPDX-License-Identifier: MIT
// workflows/diagnose.js
//
// build-fleet v0.5 (troubleshoot-fix lane) — DIAGNOSE confirmation workflow.
//
// An INVERTED fork of review.js. Where review.js runs a survival vote on reviewer
// *concerns* (a concern survives unless refuted), diagnose.js runs the dual: a single
// root-cause *hypothesis* (recorded in diagnosis.md) is CONFIRMED iff it is NOT refuted
// by a substantive, different-role, reproduction-citing refutation. The "concern" set is
// the reviewers' refutations of the hypothesis; the hypothesis survives confirmation iff
// none of those refutations survives cross-examination.
//
// Reviewer roles are [architect, coder] (the product-owner drops out of the bug lane).
// Evidence is the REPRODUCTION (the failing test / diagnosis.md reproduction steps), not
// spec.md/acceptance.md — so the substantive-refutation citation regex is retargeted.
//
// CONTRACT: docs/v0.2/CONTRACT.md (the scribe envelope is reused unchanged).
//
// @cost-ceiling {"input_tokens":90000,"output_tokens":24000}
//
// API NOTES (same as review.js): agent(prompt, opts) → text or validated object with
// opts.schema; parallel(thunks) is a BARRIER (errors → null); phase(title) groups agents;
// args may arrive as a JSON string; NO Date.now()/Math.random()/new Date() — now comes via args.

export const meta = {
  name: "build-fleet-diagnose",
  description: "Bug-lane diagnosis confirmation: reviewers try to refute the root-cause hypothesis citing the reproduction; the hypothesis is CONFIRMED iff no substantive refutation survives cross-examination",
  phases: [
    { title: "Refute", detail: "architect + coder attempt to refute the root-cause hypothesis, citing the reproduction" },
    { title: "Cross-examination", detail: "each reviewer challenges the other's refutation" },
    { title: "Survival vote", detail: "the hypothesis is CONFIRMED unless a refutation survives" },
    { title: "Apply", detail: "scribe writes REVIEW + PROGRESS deltas" },
  ],
};

// ---------- args: { slug, cycle, now } ----------
const A = typeof args === "string" ? JSON.parse(args) : (args || {});
const slug = A.slug;
const cycle = typeof A.cycle === "string" ? parseInt(A.cycle, 10) : A.cycle;
const now = A.now || "UNKNOWN_TIME";

if (!slug || typeof cycle !== "number" || Number.isNaN(cycle)) {
  throw new Error(
    "BUILD_FLEET_WORKFLOW_ERROR: args must include {slug, cycle, now}. " +
    "Received args=" + JSON.stringify(args) + " (typeof=" + (typeof args) + ")"
  );
}

const ROLES = ["architect", "coder"];

// ---------- schemas ----------

// Phase 1: each reviewer attempts to refute the single recorded hypothesis.
const REFUTE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["role", "verdict", "reason"],
  properties: {
    role: { type: "string", enum: ["architect", "coder"] },
    verdict: { type: "string", enum: ["refute", "affirm"] },
    reason: { type: "string" },
  },
};

// Phase 2: each reviewer defends-or-concedes the OTHER's refutation (cross-exam).
const CROSSEXAM_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["role", "responses"],
  properties: {
    role: { type: "string", enum: ["architect", "coder"] },
    responses: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["challenge_id", "verdict", "reason"],
        properties: {
          challenge_id: { type: "string" },
          // "refute" = this peer refutation is itself unsound (defends the hypothesis);
          // "affirm" = the peer's refutation stands.
          verdict: { type: "string", enum: ["refute", "affirm"] },
          reason: { type: "string" },
        },
      },
    },
  },
};

// ---------- Phase 1: refute the hypothesis ----------

phase("Refute");

const refuteResults = await parallel(
  ROLES.map((role) => () =>
    agent(refutePrompt(role, slug, cycle), {
      label: `refute:${role}`,
      phase: "Refute",
      agentType: `build-fleet:${role}`,
      schema: REFUTE_SCHEMA,
    })
  )
);

// Post-condition (mirrors review.js): every reviewer must return a usable payload.
const refutals = ROLES.map((role, i) => ({ role, payload: refuteResults[i] }));
for (const r of refutals) {
  if (!r.payload || typeof r.payload.verdict !== "string") {
    await applyScribe(haltEnvelope(slug, cycle, now, {
      reason: "missing-reviewer-payload",
      detail: `Reviewer ${r.role} returned no usable refutation payload.`,
    }));
    return { verdict: "escalate", reason: "missing-reviewer-payload", role: r.role };
  }
}

// A refutation becomes a live "challenge" only if it is substantive: verdict=refute,
// >=40 chars, and cites the reproduction. (Same substantiveness floor as review.js, with
// the evidence target retargeted from spec/acceptance to the reproduction.)
const challenges = toChallenges(refutals);

// ---------- Phase 2: cross-examination ----------

phase("Cross-examination");

let crossMap = {};
if (challenges.length > 0) {
  const xResults = await parallel(
    ROLES.map((role) => () =>
      agent(crossExamPrompt(role, challenges, slug, cycle), {
        label: `cross-exam:${role}`,
        phase: "Cross-examination",
        agentType: `build-fleet:${role}`,
        schema: CROSSEXAM_SCHEMA,
      })
    )
  );
  crossMap = mergeCrossExam(ROLES, xResults);
}

// ---------- Phase 3: survival vote (pure JS) ----------

phase("Survival vote");

const judged = applyHypothesisVote(challenges, crossMap);
const survivingRefutations = judged.filter((c) => !c.refuted);
const verdict =
  survivingRefutations.length > 0 ? (cycle >= 3 ? "escalate" : "refuted") : "confirmed";

log(
  `Cycle ${cycle}: ${challenges.length} substantive refutation(s), ` +
  `${survivingRefutations.length} surviving → verdict=${verdict}`
);

// ---------- Phase 4: apply via scribe ----------

phase("Apply");

const envelope = buildEnvelope({ slug, cycle, now, refutals, judged, verdict });
await applyScribe(envelope);

return {
  verdict,
  slug,
  cycle,
  substantive_refutations: challenges.length,
  surviving_refutations: survivingRefutations.length,
  next: envelope.next_legal_commands,
};

// ================= helpers =================

function refutePrompt(role, slug, cycle) {
  return `You are the ${role} reviewer in DIAGNOSIS CONFIRMATION, cycle ${cycle}. Active bug: ${slug}.

Read these yourself (you have Read/Grep/Glob):
- .sdd/${slug}/diagnosis.md   (the recorded root-cause hypothesis, blast radius, and fix strategy)
- the reproduction: the failing test(s) under tests/, and the "Symptom + reproduction steps" section

Your job is ADVERSARIAL: try to REFUTE the recorded root-cause hypothesis. A diagnosis is
confirmed only by surviving attack, so default to suspicion. ${role === "architect"
    ? "Lens: does the hypothesis actually explain the reproduced behavior? Is the blast radius honest? Is there a more likely cause the reproduction points to?"
    : "Lens: is the fix strategy feasible and does it address THIS root cause? Does the reproduction's actual failure match the claimed mechanism?"}

A refutation only counts if it is substantive: at least ~40 characters of reasoning AND it
cites the reproduction as counter-evidence — e.g. "diagnosis.md § Symptom", "tests/test_login.py",
or "line 42". If you cannot substantively refute the hypothesis citing the reproduction, AFFIRM
it (that is the honest outcome when the diagnosis holds).

Return the structured object:
- role: "${role}"
- verdict: "refute" (the hypothesis is unsound) or "affirm" (it withstands your attack)
- reason: your reasoning. If refuting, cite the reproduction.`;
}

function crossExamPrompt(role, challenges, slug, cycle) {
  const peers = challenges.filter((c) => c.raised_by !== role);
  return `You are the ${role} reviewer in CROSS-EXAMINATION, cycle ${cycle}. Active bug: ${slug}.

Read .sdd/${slug}/diagnosis.md and the reproduction (failing test(s) under tests/) yourself.

Below are refutations of the root-cause hypothesis raised by the OTHER reviewer. For each,
decide whether to REFUTE it (you believe the refutation itself is unsound — i.e. the hypothesis
actually still holds against the reproduction) or AFFIRM it (the refutation stands; the
hypothesis is genuinely in doubt).

A refutation-of-a-refutation only counts if substantive: at least ~40 characters AND it cites
the reproduction (e.g. "diagnosis.md § Fix strategy", "tests/...", "line N"). If you cannot
substantively defend the hypothesis, AFFIRM the peer's refutation (the safe default — an
unsupported hypothesis should not be confirmed).

Peer refutations:
${JSON.stringify(peers.map((c) => ({ challenge_id: c.id, raised_by: c.raised_by, reason: c.text })), null, 2)}

Return the structured object:
- role: "${role}"
- responses: array of { challenge_id, verdict ("refute"|"affirm"), reason }. One entry per peer refutation.`;
}

// Phase-1 refutations → live challenges (substantive refute verdicts only).
function toChallenges(refutals) {
  const REPRO_REF = /(diagnosis\.md\s*§|tests?\/|line\s+\d+)/i;
  const MIN = 40;
  const out = [];
  for (const r of refutals) {
    const p = r.payload;
    if (
      p && p.verdict === "refute" &&
      typeof p.reason === "string" && p.reason.length >= MIN && REPRO_REF.test(p.reason)
    ) {
      out.push({
        id: `${r.role}-refutation`,
        severity: "blocker",   // a surviving refutation blocks CONFIRMED (renders in ESCALATION.md)
        raised_by: r.role,
        text: p.reason,
        refuted: false,
        refuted_by: null,
        refutation_reason: null,
      });
    }
  }
  return out;
}

function mergeCrossExam(roles, xResults) {
  const map = {};
  roles.forEach((role, i) => {
    const payload = xResults[i];
    if (!payload || !Array.isArray(payload.responses)) return;
    for (const resp of payload.responses) {
      (map[resp.challenge_id] ||= []).push({
        role,
        verdict: resp.verdict,
        reason: resp.reason,
      });
    }
  });
  return map;
}

// A challenge (refutation of the hypothesis) is itself REFUTED — i.e. the hypothesis is
// defended — only by a substantive, different-role, reproduction-citing response. A
// challenge that survives means the hypothesis is genuinely in doubt.
function applyHypothesisVote(challenges, crossMap) {
  const REPRO_REF = /(diagnosis\.md\s*§|tests?\/|line\s+\d+)/i;
  const MIN = 40;
  return challenges.map((c) => {
    const defenses = (crossMap[c.id] || []).filter(
      (d) =>
        d.verdict === "refute" &&
        d.role !== c.raised_by &&
        typeof d.reason === "string" &&
        d.reason.length >= MIN &&
        REPRO_REF.test(d.reason)
    );
    if (defenses.length === 0) return c;
    const d = defenses[0];
    return { ...c, refuted: true, refuted_by: d.role, refutation_reason: d.reason };
  });
}

function buildEnvelope({ slug, cycle, now, refutals, judged, verdict }) {
  const reviewEntries = refutals.map((r) => {
    const p = r.payload;
    const lines = [`## Cycle ${cycle} — ${r.role} — ${now}`];
    lines.push(`- verdict: ${p.verdict}`);
    lines.push(`  ${(p.reason || "").replace(/\n+/g, " ")}`);
    const own = judged.find((c) => c.raised_by === r.role);
    if (own && own.refuted) {
      lines.push(`  refutation-overturned-by: ${own.refuted_by} — ${own.refutation_reason}`);
    }
    return lines.join("\n");
  });

  const escalation_payload =
    verdict === "escalate"
      ? {
          // field name `surviving_blockers` matches the reused scribe's ESCALATION renderer
          reason: "diagnosis-not-confirmed-cycle-budget-exhausted",
          cycle,
          surviving_blockers: judged.filter((c) => !c.refuted),
          emitted_at: now,
        }
      : null;

  // PHASE advance (the scribe writes PROGRESS PHASE, like review.js — it never writes the
  // diagnosis.md body): `confirmed` advances to FIX; the /build-fleet:fix gate then flips
  // diagnosis.md STATUS → CONFIRMED (the content write the scribe must not do, mirroring how
  // /build-fleet:finalize flips spec.md after review). `refuted` stays at DIAGNOSE for a
  // re-run; `escalate` is terminal.
  return {
    build_fleet_version: "0.5",
    feature: slug,            // scribe targets .sdd/<feature>/ — here the bug slug
    phase: "DIAGNOSE",
    cycle,
    verdict,
    surviving_concerns: judged,
    review_entries: reviewEntries,
    state_delta: {
      PHASE: verdict === "escalate" ? "ESCALATED" : verdict === "confirmed" ? "FIX" : "DIAGNOSE",
      CYCLE: cycle,
      UPDATED: now,
    },
    next_legal_commands:
      verdict === "confirmed"
        ? ["/build-fleet:fix"]
        : verdict === "escalate"
        ? []
        : ["/build-fleet:diagnose"],
    escalation_payload,
  };
}

function haltEnvelope(slug, cycle, now, payload) {
  return {
    build_fleet_version: "0.5",
    feature: slug,
    phase: "DIAGNOSE",
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
