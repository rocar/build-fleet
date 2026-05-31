---
name: sdd-protocol
description: The canonical spec-driven development protocol for the build-fleet agent software house. Defines the SPEC → REVIEW → FINALIZE → BUILD → CHANGE-REVIEW → HANDOFF state machine, the .sdd/ workspace layout and file ownership, the deterministic phase gates, the bounded review-cycle and human-escalation policy, and the blocker/major/minor severity rubric. This is the single source of truth for how the fleet runs. Consult it whenever orchestrating a feature, transitioning phases, running a review, finalizing a spec, handing off to devops, or deciding whether to escalate — and any time a build-fleet command or role agent (product-owner, architect, coder, qa, devops) needs the workflow rules.
---

# SDD Protocol

This skill governs the runtime behaviour of the **build-fleet** software house. Commands
and role agents defer to it for the workflow, gates, and escalation rules. It is the
authority: where any agent prompt, command body, or stale CLAUDE.md disagrees with this
file, this file wins.

## Operating principles

- **Spec is the contract.** No source is written until the active spec is `FINALIZED`.
- **Gates are deterministic; judgments are adversarial.** Binary phase transitions are
  enforced by hooks (exit code 2 = block + feedback). Convergence judgments (e.g., "is
  the spec sound enough to finalize?") run as workflow cross-examination + survival vote
  (see REVIEW phase). The category error to avoid is hook-enforcing a judgment.
- **Filesystem is shared memory.** Subagent context is isolated and does not sync between
  roles. Everything that must cross roles lives as a file in `.sdd/<feature>/`. There is
  no per-agent persistent memory layer.
- **Escalate, don't loop forever.** Each review gate is bounded (default **3** cycles).
  In v0.2, one `/build-fleet:review` workflow run = one cycle. Cross-examination rounds
  inside a single workflow run do NOT bump the cycle counter. The 4th unresolved cycle
  writes `ESCALATION.md` and halts that phase for a human.
- **The orchestrator routes, it does not build.** The main session assigns work, runs
  gates, and synthesizes. It never writes production source itself.
- **One feature in flight.** `.sdd/ACTIVE` names the single active feature.

## Workspace layout and ownership

```
.sdd/
  ACTIVE                 # one line: the active feature slug. Empty = no active feature.
  <feature>/
    spec.md              # product-owner. STATUS line + spec body. Source of truth.
    acceptance.md        # product-owner. Testable acceptance criteria.
    DECISIONS.md         # architect. Append-only ADR log.
    TEST_PLAN.md         # qa. Test design mapped to acceptance criteria.
    IMPL_NOTES.md        # coder. Implementation notes and deviations.
    REVIEW.md            # reviewers. Append-only review log (see format below).
    PROGRESS.md          # orchestrator. Phase + cycle state (schema below).
    ESCALATION.md        # exists only when a gate has exhausted its cycles.
```

Write boundaries (enforced by hooks):
- `product-owner` writes `spec.md`, `acceptance.md`.
- `architect` and `qa` are reviewers: they may write **only inside `.sdd/<active>/`**
  (ADRs, REVIEW.md, TEST_PLAN.md). They never write source.
- `coder` writes source + `IMPL_NOTES.md`, only while `PHASE` is `BUILD`.
- `devops` writes CI/CD, IaC, release artifacts, only after CHANGE-REVIEW approval.

`.sdd/ACTIVE` empty (or absent) means no feature is active; all write-gating hooks then
allow operations through. Every hook resolves the active feature by reading this file —
never an environment variable.

## Product tier (v0.4 M0) — inherited context only

A repo may optionally carry a **product tier** above the flat feature dirs. It lives in a
reserved `.sdd/_product/` namespace (the underscore prevents collision with any feature
slug). A repo with no `.sdd/_product/` is a plain feature-first repo — the product tier is
**purely additive**; its absence changes nothing.

```
.sdd/
  _product/              # the product tier. Created by /build-fleet:new-product.
    vision.md            # product-owner. Overview/Goals (+ Non-goals/FAQ/OUTCOME for standard|large).
    backlog.md           # product-owner. Phased feature list + completion markers.
    STACK.md             # architect. The stack-of-record — inherited READ-ONLY by every feature.
    DECISIONS.md         # architect. Append-only product ADR log (the *why* behind STACK.md).
    PROGRESS.md          # orchestrator. PRODUCT / SIZE / UPDATED.
  ACTIVE                 # unchanged — the single active feature.
  <feature>/             # unchanged — features stay flat, NOT nested under _product/.
```

**M0 is inherited context only.** There is no product state machine, no product review
gate, no scribe, and no new hook. The files are plain DRAFT artifacts edited directly.
The outer PLAN → PLAN_REVIEW → PLAN_FINALIZE → DEVELOPING machine, CLAUDE.md generation,
and the phased build loop are later v0.4 milestones (see ROADMAP).

**Greenfield vs brownfield.** `/build-fleet:new-product` works on both. On a
greenfield repo the architect *ratifies* a new stack from the product description.
On a **brownfield** repo (real source/manifests already present) the architect
*infers and records the actual stack* from the code as the **binding
stack-of-record** (a `## Baseline (current)` section) — never hallucinating or
silently rewriting it. A forward/migration direction is allowed only as an
explicitly **`PROVISIONAL` (unreviewed)** section + ADRs tagged
`STATUS: PROVISIONAL`; because M0 has no product review gate, provisional forward
entries are strategy that **do not bind features** until ratified (M3 plan-review,
or an explicit human edit promoting the ADR). `/build-fleet:new-product` writes
only `.sdd/_product/`, never source, so it is safe to run against an existing
codebase; an existing root `CLAUDE.md` is untouched (M0 does not generate one —
that is M3).

**The inheritance contract:**
- `.sdd/_product/STACK.md` is the product's stack-of-record. When `/build-fleet:new-feature`
  runs and this file exists, it is read into the classifier + product-owner prompts as
  read-only context. Features inherit the **binding** stack (the `## Baseline (current)`
  on a brownfield product, or the ratified greenfield stack); any
  `## Forward direction (PROVISIONAL — unreviewed)` entries are advisory and do **not**
  constrain a feature until promoted. A feature's own `DECISIONS.md` must not contradict
  the binding product stack.
  A genuine need for a different stack is a signal to **revise the product tier** (edit
  STACK.md + append a product ADR), not a feature-local override. This is the fix for the
  latent bug where two features could independently pick conflicting stacks (feature-scoped
  `DECISIONS.md` has no cross-feature authority; product `DECISIONS.md` does).

**Hook interactions (M0):**
- `block-source-before-finalized` permits all `.sdd/_product/*` writes (any path under
  `.sdd/` is allowed; and it exits early when there is no active feature).
- `restrict-reviewer-writes` confines **all** writes to `.sdd/<active>/` while the active
  feature's `PHASE` is `REVIEW` or `CHANGE_REVIEW` (phase-based, not role-based). Therefore
  `/build-fleet:new-product` **refuses to run** while a feature is in those two phases —
  the product foundation is not reshaped mid-review. All other active-feature phases are
  fine; `/build-fleet:new-product` never touches `.sdd/ACTIVE`.
- No hook validates `vision.md`/`STACK.md` STATUS in M0 (`validate-spec-status` fires only
  on files named `spec.md`). Their STATUS lines are forward-compat for the M3 gate.

## PROGRESS.md schema

Exact field names; hooks and commands parse these lines:

```
FEATURE: <slug>
PHASE: SPEC | REVIEW | FINALIZE | BUILD | CHANGE_REVIEW | HANDOFF | ESCALATED
CYCLE: <int>          # spec-review cycles consumed (one increment per /build-fleet:review workflow run; cross-examination rounds inside a run do not bump CYCLE)
CHANGE_CYCLE: <int>   # change-review cycles consumed (one increment per /build-fleet:handoff invocation; still command-driven in v0.2 until M3 converts CHANGE_REVIEW to a workflow)
TIER: trivial | standard | large    # v0.2 M4 — set by the classifier subagent at /build-fleet:new-feature time. `trivial` opts into the REVIEW-skipping fast-path through finalize. `pending` until classifier runs.
BUILD_MODE: standard | deep-build   # v0.2 M3 — selects /build-fleet:finalize's BUILD orchestration. `standard` = sequential qa→coder via Task tool. `deep-build` = dispatch workflows/deep-build.js. M4's classifier sets this to `deep-build` for tier=large. `pending` until classifier runs.
UPDATED: <iso8601>
```

## spec.md STATUS line

The first line of `spec.md` is always:

```
STATUS: DRAFT | IN_REVIEW | FINALIZED | BLOCKED
```

`validate-spec-status` (PostToolUse on spec.md) rejects a write whose STATUS is missing or
not one of the four values, or whose required sections are absent.

## REVIEW.md entry format

Append-only. Reviewers add one block per cycle; never edit prior blocks. Resolution of a
concern is a *new* approving entry in a later cycle, not an edit.

```
## Cycle <N> — <role> — <iso8601>
- [blocker] <concern>
- [major]   <concern>
- [minor]   <concern>
status: concerns-raised | approved
```

`check-review-written` (SubagentStop) rejects a reviewer that stops without appending a
block attributed to it for the current cycle. In v0.2 workflow REVIEW: the workflow's
reviewer subagents return structured concerns payloads; the workflow script merges them
into the canonical REVIEW.md entries; the `scribe` subagent appends them in the final
phase. The hook skips its gate while `.sdd/<feature>/.workflow-in-flight` exists (the
workflow's envelope post-condition replaces it for workflow paths). Non-workflow paths
(CHANGE_REVIEW until M3) retain the hook's per-reviewer enforcement.

## Severity rubric

| Severity | Definition | Gate effect |
|---|---|---|
| `blocker` | Correctness, security, data loss, or a contradiction of the spec/acceptance. | Blocks FINALIZE and HANDOFF. |
| `major` | Scalability, maintainability, or missing acceptance coverage. | Must be resolved or explicitly accepted (as an ADR) before the gate opens. |
| `minor` | Style, wording, nits. | Advisory; never blocks a gate. |

The severity vocabulary is mirrored verbatim in each reviewer agent's prompt body for
non-workflow direct invocations and as belt-and-suspenders if `AgentDefinition.skills`
preload regresses. In v0.2 workflow REVIEW the orchestrator preloads `review-rubric` via
`AgentDefinition.skills`, so the in-body copy is the redundancy, not the primary source.

## State machine

```
SPEC ──► REVIEW ──► FINALIZE ──► BUILD ──► CHANGE_REVIEW ──► HANDOFF
          ▲  │                              ▲       │
          └──┘ (≤3 cycles, then ESCALATE)   └───────┘ (≤3 cycles, then ESCALATE)
```

**SPEC.** `/build-fleet:new-feature <slug>` scaffolds `.sdd/<slug>/`, runs the
classifier subagent (M4) to set `TIER` + `BUILD_MODE` in PROGRESS.md, and
delegates to product-owner to draft `spec.md` (STATUS=DRAFT) + `acceptance.md`.
For `TIER=trivial`, PO drafts a minimal skeleton spec from the classifier's
`skeleton_spec_hint`; for standard/large, PO drafts the full spec.

Exit: a non-empty spec with all required sections exists.

**M4 trivial fast-path.** Features classified `trivial` skip the REVIEW phase
entirely. The user invokes `/build-fleet:finalize` directly after PO drafts the
skeleton spec; finalize recognizes `TIER=trivial` and proceeds to BUILD without
requiring a completed review cycle. This saves the review tokens for changes
genuinely small enough that the gate cost exceeds the gate value (typo fixes,
dependency bumps, single-line bug fixes). See `agents/classifier.md` for the
criteria and disqualifiers; the classifier errs toward `standard` because
false-trivial is the dangerous miss (skips a review the change needed).

**REVIEW.** `/build-fleet:review` invokes the `workflows/review.js` dynamic workflow with
the current feature and cycle number (`args.feature`, `args.cycle`). The command writes
`.sdd/<feature>/.workflow-in-flight` before dispatch (a marker that makes the two
reviewer-gating hooks skip while a workflow is running); the scribe deletes it as the
workflow's final phase. The `scribe` is a workflow-internal Write-capable subagent (see
`agents/scribe.md`) — not a fleet role like architect/qa/coder, but the single canonical
writer of workflow-driven state mutations.

The workflow runs five phases internally:

1. **Read state** — a Read-only subagent collects spec.md, acceptance.md, prior REVIEW.md.
2. **Fan-out** — architect, qa, coder subagents review in parallel. Each returns a
   structured concerns payload `{role, status, concerns:[{id,severity,text}]}`. Their
   `AgentDefinition.tools` omits `Write`/`Edit`; their `AgentDefinition.skills` preloads
   `review-rubric` (replacing the v0.1 rubric duplication in agent prompt bodies).
3. **Cross-examination** — each reviewer is presented with peers' concerns and must
   refute or affirm each. A refutation must (a) be ≥40 characters, (b) cite a section
   of spec.md or acceptance.md as counter-evidence (regex: `(spec|acceptance)\.md\s*§|line\s+\d+`),
   (c) come from a different-role reviewer (self-refutation is filtered).
4. **Survival vote** — pure script logic. A concern survives unless refuted by a
   different-role reviewer with substantive reasoning. Survivors are the cycle's verdict.
5. **Apply via scribe** — the `scribe` subagent applies the structured envelope to
   PROGRESS.md (`state_delta`) and REVIEW.md (`review_entries`), writes ESCALATION.md
   when `escalation_payload` is non-null, and removes `.workflow-in-flight`.

Convergence rule (replaces v0.1 "all approved with zero blockers"):

> A concern survives unless explicitly refuted by another reviewer during
> cross-examination. The cycle is *clean* iff zero surviving `[blocker]` items.

Verdict semantics:
- `clean` — zero surviving blockers. Next command: `/build-fleet:finalize`.
- `revise` — surviving blockers; CYCLE < 3. Next command: `/build-fleet:review` after PO
  revises spec.md.
- `escalate` — surviving blockers; CYCLE >= 3. Workflow's scribe writes ESCALATION.md,
  sets PHASE=ESCALATED, halts.

The v0.1 cycle-3 agent-team fallback is retired entirely — workflow cross-examination
replaces it.

**FINALIZE.** `/finalize` runs the finalize gate. Permitted only when the most recent
review cycle is fully approved with no open blockers. On success: set STATUS=FINALIZED,
PHASE=BUILD. The source-write block lifts at this point and not before.

**BUILD.** Sequential, tests-first (v0.2 M2 ordering — replaces v0.1 parallel BUILD).
`/build-fleet:finalize`, on a successful gate, dispatches qa first then coder:

1. **qa drafts TEST_PLAN.md + writes failing tests.** Per the `test-plan` skill, qa
   builds the coverage matrix from acceptance.md and implements the test suite under
   `tests/`. Each test must initially FAIL — no source exists yet. qa signals the
   orchestrator with `BUILD_FLEET_QA_TESTS_READY: <count> failing tests in tests/` when done.
2. **coder implements to spec.** Coder refuses to begin until QA's failing tests exist
   in `tests/` and all fail (a passing test against an empty implementation isn't testing
   behavior). Coder iterates until every QA test passes. `gap:` / `deviation:` / `todo:`
   markers go in `IMPL_NOTES.md` per its prompt body.

coder refuses to start while STATUS ≠ FINALIZED (enforced by `block-source-before-finalized`).
coder also refuses if no failing tests exist in `tests/` (self-enforced per `agents/coder.md`;
the v0.1 hook layer does not gate this — Phase 5 hardening or M3 may add a hook).

Exit: implementation exists, every qa test passes, IMPL_NOTES.md lists any gaps/deviations.

### BUILD variants (v0.2 M3)

Two BUILD execution modes — selected by `PROGRESS.md`'s `BUILD_MODE` field. v0.2 M4
sets this automatically via the classifier at `/build-fleet:new-feature` time
(`tier=large` → `deep-build`; everything else → `standard`). Manual override is
possible via direct PROGRESS.md edit or by invoking `/build-fleet:deep-build`
explicitly:

- **`BUILD_MODE: standard`** — the M2 sequential qa-then-coder pattern described
  above. `/build-fleet:finalize` orchestrates it via the Task tool. v0.2 M4's
  classifier sets this for `tier=trivial` and `tier=standard`; manual override
  via direct PROGRESS.md edit is supported.
- **`BUILD_MODE: deep-build`** — for multi-file / multi-package features.
  `/build-fleet:finalize` runs qa first (same as standard), then routes the
  implementation phase to the `workflows/deep-build.js` workflow. The workflow's
  architect subagent designs a file partition; N coders (default 3, max 8) fan out
  in parallel against M2's pre-existing failing tests; an adversarial review
  sub-phase (architect for design, qa for coverage + counterfactual) catches gaps
  before BUILD is declared complete. The scribe aggregates results into
  `IMPL_NOTES.md` via the envelope's new `impl_notes_appendix` field.

  Until M4's classifier ships, `BUILD_MODE` is set manually (either by editing
  PROGRESS.md or by invoking `/build-fleet:deep-build [N]` directly, bypassing
  finalize's routing logic).

  Verdicts:
  - `clean` → next is `/build-fleet:handoff`.
  - `needs-iteration` → re-run `/build-fleet:deep-build` after addressing the
    surviving concerns recorded in IMPL_NOTES.md.
  - `escalate` → **M3 only emits this on workflow malfunction** (spec not
    finalized at workflow entry, no tests present, partition planning failed,
    or a reviewer/coder returned an unparseable payload). M3 does NOT track
    a cycle counter for deep-build; `needs-iteration` loops unbounded until
    the operator either runs `handoff` or manually writes ESCALATION.md to
    halt. Bounded-cycle escalation for deep-build is M3.1 / Phase 5 hardening.

Deep-build is fault-bounded by the workflow runtime's 16-concurrent and
1000-total-agent caps. Plan-approval for the partition happens at workflow launch
in interactive mode (the launch prompt shows the phase list including "Plan file
partition" and "Fan out N coders"); to halt mid-run after a bad partition is
planned, use `/workflows` to stop the workflow.

**CHANGE_REVIEW.** `/handoff` sets PHASE=CHANGE_REVIEW, increments `CHANGE_CYCLE`, and runs
architect + product-owner + qa against the diff:
- architect: design adherence and ADR compliance.
- product-owner: meets `acceptance.md`.
- qa: coverage gaps before handoff; verifies each test would FAIL if coder's source
  change were reverted (the v0.2 M2 counterfactual — a test that passes regardless of
  the source isn't testing behavior, it's decorative).
Exit (to HANDOFF): all three approve with no open blockers. Fail → back to BUILD (bounded
by `CHANGE_CYCLE` ≤ 3, then ESCALATE).

**HANDOFF.** devops takes the finalized, reviewed change → CI/CD, IaC, release notes.

## Hard gates (enforced by hooks)

1. No source write while the active spec STATUS ≠ FINALIZED.
   *(block-source-before-finalized, PreToolUse Write|Edit)*
2. architect/qa may not write outside `.sdd/<active>/`.
   *(restrict-reviewer-writes, PreToolUse Write|Edit — fires on non-workflow review
   paths; workflow REVIEW enforces via `AgentDefinition.tools` allowlists that omit
   `Write`/`Edit` on reviewer subagents. Hook skips while `.workflow-in-flight` marker exists.)*
3. spec.md always carries a valid STATUS line and required sections.
   *(validate-spec-status, PostToolUse Write|Edit on spec.md)*
4. A reviewer cannot stop without recording its review for the current cycle.
   *(check-review-written, SubagentStop — fires on non-workflow review paths; workflow
   REVIEW enforces via the workflow's envelope post-condition that halts the workflow if
   any reviewer returns an empty/malformed concerns payload. Hook skips while
   `.workflow-in-flight` marker exists.)*
5. A session cannot stop on a failing test/lint stack; if no recognized stack exists yet,
   the Stop hook is a silent no-op so bootstrap and empty repos don't deadlock.
   *(stop-tests, Stop)*

`TaskCompleted` and `TeammateIdle` (agent-teams-only) are intentionally **not** shipped.
v0.2 retires the agent-teams fallback entirely — workflow cross-examination replaces the
cycle-3 team debate path.

## Escalation

When a review gate exhausts its cycle budget with blockers still open, the responsible
command writes `.sdd/<feature>/ESCALATION.md` containing: the phase, the cycle count, the
unresolved blockers (verbatim from REVIEW.md), and the conflicting positions. It sets
PHASE=ESCALATED and stops. Escalation is a first-class outcome, not a failure — the human
decides how to break the deadlock.
