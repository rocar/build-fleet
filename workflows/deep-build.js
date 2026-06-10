// SPDX-License-Identifier: MIT
// workflows/deep-build.js
//
// build-fleet v0.2 — M3 deep-build workflow (rewritten against the real Workflow
// API, grounded during Phase 6 against the Workflow tool's authoritative description).
//
// For features with file-ownership partitioning across multiple coders.
// Architect plans the partition; coders fan out in parallel against M2's
// pre-existing failing tests; in-workflow adversarial review catches gaps.
//
// CONTRACT: docs/v0.2/CONTRACT.md.
//
// @cost-ceiling {"input_tokens":400000,"output_tokens":100000}
//
// API NOTES — see workflows/review.js header. Same runtime contract:
//   agent(prompt, opts) → string, or validated object with opts.schema.
//   parallel(thunks: Array<() => Promise>) → barrier; errors → null.
//   phase(title) → void marker. No Date/Math.random — timestamps via args.now.

export const meta = {
  name: "build-fleet-deep-build",
  description: "Fan-out BUILD: architect plans partition, N coders implement in parallel, adversarial review",
  phases: [
    { title: "Plan partition", detail: "architect designs an N-way coder assignment" },
    { title: "Fan-out coders", detail: "coders implement assigned files against failing tests in parallel" },
    { title: "Adversarial review", detail: "architect (design) + qa (counterfactual) review the merged diff" },
    { title: "Apply", detail: "scribe aggregates into IMPL_NOTES + updates PROGRESS" },
  ],
};

// ---------- args ----------
// { feature, max_partitions?, partition_hint?, now }

// The Workflow runtime may deliver `args` as a JSON string rather than a parsed
// object (confirmed empirically during Phase 6 validation). Normalize.
const A = typeof args === "string" ? JSON.parse(args) : (args || {});

const feature = A.feature;
const maxPartitions = Math.min(A.max_partitions || 3, 8);
const partitionHint = A.partition_hint || null;
const now = A.now || "UNKNOWN_TIME";

if (!feature) {
  throw new Error(
    "BUILD_FLEET_WORKFLOW_ERROR: args must include {feature, now}. " +
    "Received args=" + JSON.stringify(args) + " (typeof=" + (typeof args) + ")"
  );
}

// ---------- schemas ----------

const PARTITION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["partition", "planner_notes"],
  properties: {
    planner_notes: { type: "string" },
    partition: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["label", "files", "acceptance_criteria", "tests", "notes"],
        properties: {
          label: { type: "string" },
          files: { type: "array", items: { type: "string" } },
          acceptance_criteria: { type: "array", items: { type: "string" } },
          tests: { type: "array", items: { type: "string" } },
          notes: { type: "string" },
        },
      },
    },
  },
};

const CODER_SUMMARY_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["label", "files_modified", "tests_passing", "tests_failing", "impl_notes"],
  properties: {
    label: { type: "string" },
    files_modified: { type: "array", items: { type: "string" } },
    tests_passing: { type: "integer" },
    tests_failing: { type: "integer" },
    impl_notes: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["kind", "text"],
        properties: {
          kind: { type: "string", enum: ["gap", "deviation", "todo"] },
          text: { type: "string" },
        },
      },
    },
  },
};

const BUILD_REVIEW_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["role", "status", "concerns"],
  properties: {
    role: { type: "string", enum: ["architect", "qa"] },
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

// ---------- Phase 1: plan partition ----------

phase("Plan partition");

let partitionPlan;
if (partitionHint) {
  partitionPlan = {
    partition: partitionHint,
    planner_notes: "Used caller-supplied partition_hint (M4 classifier or manual).",
  };
} else {
  partitionPlan = await agent(partitionPrompt(feature, maxPartitions), {
    label: "plan-partition",
    phase: "Plan partition",
    agentType: "build-fleet:architect",
    schema: PARTITION_SCHEMA,
  });
}

if (!partitionPlan || !Array.isArray(partitionPlan.partition) || partitionPlan.partition.length === 0) {
  await applyScribe(haltEnvelope(feature, now, {
    reason: "partition-planning-failed",
    detail: (partitionPlan && partitionPlan.planner_notes) || "Architect produced no valid partition.",
  }));
  return { verdict: "escalate", reason: "partition-planning-failed" };
}

const partitions = partitionPlan.partition;

// Correctness gate: detect file overlap BEFORE coder fan-out. Two coders racing
// on the same file would silently overwrite each other.
// VERIFY: exact string match; globs (containing '*') are checked literally.
{
  const seen = new Map();
  const overlaps = [];
  for (const p of partitions) {
    for (const f of p.files || []) {
      if (seen.has(f)) overlaps.push({ file: f, owners: [seen.get(f), p.label] });
      else seen.set(f, p.label);
    }
  }
  if (overlaps.length > 0) {
    await applyScribe(haltEnvelope(feature, now, {
      reason: "partition-file-overlap",
      detail: `Partition has overlapping files; coders would race: ${JSON.stringify(overlaps)}`,
    }));
    return { verdict: "escalate", reason: "partition-file-overlap" };
  }
}

log(`Partition plan: ${partitions.map((p) => p.label).join(", ")} (${partitions.length} coders)`);

// ---------- Phase 2: fan out coders ----------

phase("Fan-out coders");

const coderRaw = await parallel(
  partitions.map((p) => () =>
    agent(coderPrompt(p, feature), {
      label: `coder:${p.label}`,
      phase: "Fan-out coders",
      agentType: "build-fleet:coder",
      schema: CODER_SUMMARY_SCHEMA,
    })
  )
);

const coderResults = partitions.map((p, i) => ({ label: p.label, summary: coderRaw[i] }));
for (const cr of coderResults) {
  if (!cr.summary || typeof cr.summary !== "object") {
    await applyScribe(haltEnvelope(feature, now, {
      reason: "coder-payload-malformed",
      detail: `Partition '${cr.label}' returned no usable summary.`,
    }));
    return { verdict: "escalate", reason: "coder-payload-malformed", label: cr.label };
  }
}

// Post-hoc partition-violation detection: did any coder touch files outside its
// declared partition? Surfaced as a synthetic concern for the review phase.
const violations = [];
for (let i = 0; i < partitions.length; i++) {
  const declared = new Set(partitions[i].files || []);
  for (const f of coderResults[i].summary.files_modified || []) {
    if (!declared.has(f)) violations.push({ partition: partitions[i].label, file: f });
  }
}
if (violations.length > 0) {
  log(`WARNING: ${violations.length} partition-boundary violations: ${JSON.stringify(violations)}`);
}

// ---------- Phase 3: adversarial review ----------

phase("Adversarial review");

const reviewRaw = await parallel([
  () =>
    agent(archReviewPrompt(partitions, coderResults, feature, violations), {
      label: "build-review:architect",
      phase: "Adversarial review",
      agentType: "build-fleet:architect",
      schema: BUILD_REVIEW_SCHEMA,
    }),
  () =>
    agent(qaReviewPrompt(partitions, coderResults, feature), {
      label: "build-review:qa",
      phase: "Adversarial review",
      agentType: "build-fleet:qa",
      schema: BUILD_REVIEW_SCHEMA,
    }),
]);

const reviews = [
  { role: "architect", payload: reviewRaw[0] },
  { role: "qa", payload: reviewRaw[1] },
];
for (const r of reviews) {
  if (!r.payload || !Array.isArray(r.payload.concerns)) {
    await applyScribe(haltEnvelope(feature, now, {
      reason: "missing-reviewer-payload",
      detail: `Reviewer ${r.role} returned no usable concerns array.`,
    }));
    return { verdict: "escalate", reason: "missing-reviewer-payload", role: r.role };
  }
}

// Survival: 2 reviewers, no cross-examination peer. Concerns survive as raised.
// Add partition-violation concerns as synthetic majors.
const surviving = mergeConcerns(reviews);
for (const v of violations) {
  surviving.push({
    id: `violation-${v.partition}`,
    severity: "major",
    raised_by: "workflow",
    text: `Coder for partition '${v.partition}' modified out-of-partition file '${v.file}'.`,
  });
}
const survivingBlockers = surviving.filter((c) => c.severity === "blocker");
const verdict = survivingBlockers.length > 0 ? "needs-iteration" : "clean";

log(`Build review: ${surviving.length} concerns, ${survivingBlockers.length} blockers → ${verdict}`);

// ---------- Phase 4: apply via scribe ----------

phase("Apply");

const envelope = buildEnvelope({ feature, now, partitions, partitionPlan, coderResults, surviving, verdict });
await applyScribe(envelope);

return {
  verdict,
  feature,
  partitions: partitions.map((p) => p.label),
  surviving_concerns: surviving.length,
  surviving_blockers: survivingBlockers.length,
  violations: violations.length,
  next: envelope.next_legal_commands,
};

// ================= helpers =================

function partitionPrompt(feature, maxPartitions) {
  return `You are the architect planning a file partition for up to ${maxPartitions} coders to implement this feature IN PARALLEL against pre-existing failing tests.

Read yourself (you have Read/Grep/Glob):
- .sdd/${feature}/spec.md, acceptance.md, TEST_PLAN.md
- the tests/ directory (what test files exist)
- the project layout (top-level dirs suggesting package/module boundaries)

Design a partition where each entry is one coder's assignment. Partitions MUST NOT share
writable files (coders run in parallel and cannot coordinate — shared files cause races).
Every existing test file must be covered by at least one partition.

Return the structured object:
- partition: array of { label (kebab-case), files (specific paths, NOT globs), acceptance_criteria, tests, notes }
- planner_notes: one paragraph on how you chose the partitions and the tradeoffs.

Hard constraints: at most ${maxPartitions} partitions; no shared writable files; no orphan tests.
If the feature is genuinely single-package, return 1 partition — the orchestrator treats that
as a signal that deep-build was the wrong choice, which is fine.`;
}

function coderPrompt(partition, feature) {
  return `You are a coder in a deep-build fan-out. Your partition: '${partition.label}'.

Files you may write (ONLY these — other coders own the rest):
${JSON.stringify(partition.files, null, 2)}

Acceptance criteria you cover: ${JSON.stringify(partition.acceptance_criteria)}
Tests you must make pass (they EXIST and currently FAIL — qa wrote them under M2 ordering):
${JSON.stringify(partition.tests)}

Read .sdd/${feature}/spec.md and acceptance.md yourself for full context.
If .sdd/${feature}/SKILL_MANIFEST.md exists, load and apply the skills it lists
under the 'coder' role (per the skill-routing skill) before implementing; an
unavailable skill is a no-op — note it in your impl_notes and proceed.

Your job:
1. Run your partition's failing tests; confirm they fail initially.
2. Implement source ONLY in your assigned files until those tests pass.
3. Do NOT modify files outside your partition.
4. Record gap/deviation/todo notes for anything you couldn't resolve.

Return the structured object: { label, files_modified, tests_passing, tests_failing, impl_notes:[{kind,text}] }.`;
}

function archReviewPrompt(partitions, coderResults, feature, violations) {
  return `You are the architect reviewing a merged deep-build diff. ${partitions.length} coders worked in parallel.

Read .sdd/${feature}/spec.md, acceptance.md, DECISIONS.md yourself.

Partition plan: ${JSON.stringify(partitions, null, 2)}
Coder summaries: ${JSON.stringify(coderResults.map((r) => r.summary), null, 2)}
Detected partition-boundary violations (already flagged by the workflow): ${JSON.stringify(violations)}

Your lens: design adherence, scalability, failure modes, security, blast radius. Focus on the
SEAMS between partitions — single-partition correctness is easy; integration points (contracts,
error envelopes, type assumptions across partitions) are where parallel coding fails.

Return the structured object: { role:"architect", status, concerns:[{id,severity,text}] }.
Empty concerns + status "approved" if clean.`;
}

function qaReviewPrompt(partitions, coderResults, feature) {
  return `You are qa reviewing a merged deep-build diff. Lens: coverage gaps + the M2 counterfactual.

Read .sdd/${feature}/acceptance.md and TEST_PLAN.md yourself.

Partition plan + coder summaries: ${JSON.stringify({ partitions, summaries: coderResults.map((r) => r.summary) }, null, 2)}

Your job:
1. Each acceptance criterion → point at the test that exercises it. Missing → [blocker].
2. M2 counterfactual: would each test FAIL if its partition's source change were reverted?
   Tests that pass regardless of source are decorative → [blocker].
3. Failure paths covered? Missing → [major].
4. Integration tests spanning partitions — ownership gap → [major].

Return the structured object: { role:"qa", status, concerns:[{id,severity,text}] }.
Empty concerns + status "approved" if clean.`;
}

function mergeConcerns(reviews) {
  const out = [];
  for (const r of reviews) {
    for (const c of r.payload.concerns || []) {
      out.push({ id: c.id, severity: c.severity, raised_by: r.role, text: c.text });
    }
  }
  return out;
}

function buildEnvelope({ feature, now, partitions, partitionPlan, coderResults, surviving, verdict }) {
  const lines = [];
  lines.push(`## Deep-build run — ${now}`);
  lines.push(``);
  lines.push(`**Partitions:** ${partitions.map((p) => p.label).join(", ")}`);
  lines.push(`**Planner notes:** ${partitionPlan.planner_notes || "(none)"}`);
  lines.push(``);
  for (const cr of coderResults) {
    const s = cr.summary;
    lines.push(`### Partition '${cr.label}'`);
    lines.push(`- Files modified: ${JSON.stringify(s.files_modified || [])}`);
    lines.push(`- Tests passing/failing: ${s.tests_passing}/${s.tests_failing}`);
    for (const n of s.impl_notes || []) lines.push(`  - ${n.kind}: ${n.text}`);
    lines.push(``);
  }
  lines.push(`### In-workflow build review`);
  if (surviving.length === 0) lines.push(`(no surviving concerns)`);
  else for (const c of surviving) lines.push(`- [${c.severity}] (${c.raised_by}) ${c.text}`);
  lines.push(``);
  lines.push(`**Verdict:** ${verdict}`);

  const escalation_payload =
    verdict === "escalate" ? { reason: "deep-build-escalation", emitted_at: now } : null;

  return {
    build_fleet_version: "0.2",
    feature,
    workflow: "deep-build",
    phase: "BUILD",
    verdict,
    surviving_concerns: surviving,
    review_entries: [],
    impl_notes_appendix: lines.join("\n"),
    state_delta: {
      PHASE: verdict === "escalate" ? "ESCALATED" : "BUILD",
      BUILD_MODE: "deep-build",
      UPDATED: now,
    },
    next_legal_commands:
      verdict === "clean"
        ? ["/build-fleet:handoff"]
        : verdict === "escalate"
        ? []
        : ["/build-fleet:deep-build"],
    escalation_payload,
  };
}

function haltEnvelope(feature, now, payload) {
  return {
    build_fleet_version: "0.2",
    feature,
    workflow: "deep-build",
    phase: "BUILD",
    verdict: "escalate",
    surviving_concerns: [],
    review_entries: [],
    impl_notes_appendix: `## Deep-build halt — ${now}\n\nReason: ${payload.reason}\nDetail: ${payload.detail || "(none)"}\n`,
    state_delta: { PHASE: "ESCALATED", UPDATED: now },
    next_legal_commands: [],
    escalation_payload: { ...payload, emitted_at: now },
  };
}

async function applyScribe(envelope) {
  return await agent(
    `Apply this build-fleet workflow envelope to .sdd/${envelope.feature}/ exactly per agents/scribe.md.

ENVELOPE:
${JSON.stringify(envelope, null, 2)}`,
    { label: "scribe", phase: "Apply", agentType: "build-fleet:scribe" }
  );
}
