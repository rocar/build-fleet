# The loops that actually run

A map of build-fleet's agentic loops — what iterates, what the iteration unit is,
and what makes each loop *stop*. Loop engineering is the architecture here, not a
feature of it: the plugin is a set of bounded, adversarial loops with engineered
stopping conditions.

> **This doc is a derived map, not an authority.** The canonical rulebook for every
> loop below is the **`sdd-protocol` skill** (`skills/sdd-protocol/SKILL.md` +
> `references/{product-tier,bug-lane}.md`). Where this file and the skill disagree,
> the skill wins. For the doctrine assessment (how these loops map onto Anthropic's
> published agent-loop guidance, and the one gap), see the research memo
> `docs/history/2026-06-20-loop-engineering-eval.md`.

---

## The loop catalog

| Loop | Shape (named pattern) | Iteration unit | Stopping condition | Where |
|---|---|---|---|---|
| **REVIEW** (spec ⇄ review) | evaluator-optimizer + parallelization-with-voting | one `/build-fleet:review` run | zero surviving blockers → `clean`; else `revise` until **≤3 cycles**, then `escalate` | `workflows/review.js`, `SKILL.md` §REVIEW |
| **REVIEW internal** | 3-stage micro-loop | fan-out → cross-examination → survival vote → scribe apply | pure-JS survival vote | `workflows/review.js:220-293` |
| **BUILD** (TDD) | generator/evaluator | coder iterates against qa's pre-written failing tests | every qa test passes | `SKILL.md:260-267` |
| **deep-build** | orchestrator-workers | architect partitions files → N coders fan out → adversarial review | `clean` / `needs-iteration` / `escalate`, bounded by `BUILD_CYCLE ≤3` | `workflows/deep-build.js`, `SKILL.md:283-287` |
| **CHANGE_REVIEW** | evaluator-optimizer | one `/build-fleet:handoff` pass | 3 approvals; fail → back to BUILD, `≤3 CHANGE_CYCLE` then `escalate` | `SKILL.md:289-300` |
| **Bug lane** | prompt-chaining + convergence | reproduce → diagnose → fix → verify | diagnose-confirm `CYCLE` + verify→fix `FIX_CYCLE`, both bounded | `references/bug-lane.md` |
| **stop-tests** (Stop hook) | loop-enforcement guard | each session-stop attempt | won't stop on a red suite; **3 red-strikes** → escalate + release | `hooks/scripts/stop-tests`, `SKILL.md:337` |
| **Product PLAN** | *deliberately non-converging* | PLAN → PLAN_REVIEW → ratify | interrogation surfaces risk; a **human** ratifies (never auto-converges) | `references/product-tier.md:58-118` |
| **DEVELOPING** | multi-feature outer loop | complete-N → arm-N+1 | derived "complete" when every backlog row is `[x]`; **surfaces, does not auto-start** | `references/product-tier.md:229-284` |

## Static core vs dynamic workflows

Every step above runs on one of two substrates:

- **Static core** — the deterministic backbone: slash-command prompt scaffolds the
  orchestrator executes step-by-step (`commands/*.md`), sequential/parallel
  **`Task`**-tool subagent dispatch, **hook** gate scripts (`hooks/scripts/*`), and
  **shell** helpers (`scripts/*`). Fixed code paths, no JS orchestration runtime.
  This is most of the plugin.
- **Dynamic workflows** — steps that run inside a **`Workflow`-tool JS script**
  (`workflows/*.js`): deterministic JS orchestration (`parallel()` fan-out + pure-JS
  logic) interleaved with `agent()` subagent calls, in an isolated runtime with **no
  Bash, no `Date`, no filesystem** (state writes go through the scribe). They are
  resumable (`resumeFromRunId`), shown in `/workflows`, and gated by the platform's
  plan-approval prompt.

> **Why "dynamic"?** It is easy to read a version-pinned `.js` as "static" — it is a
> fixed, deterministic file, and the `Workflow` tool exists precisely to make control
> flow deterministic *rather than* model-driven. But "dynamic workflow" is the Claude
> Code feature name, and it labels a different axis: the orchestration is a **program
> on the Workflow-tool runtime whose structure is computed at runtime** (roster size,
> fan-out count, loop-or-escalate-or-clean) instead of a hardcoded sequence. "Dynamic"
> here means neither *model-improvised* (each `agent()` dispatch is deterministic) nor
> *regenerated each run* (build-fleet **pins** its workflows —
> `/build-fleet:scaffold-workflow` generates one, then commits it). And "it's a `.js`"
> is not the test: `scripts/*.sh` are files on disk too, and they are static. The test
> is the **engine (the `Workflow` tool) plus runtime-computed control flow** — which is
> why the classification below keys off `allowed-tools`, not the file extension.

> **Generated on the fly vs pinned?** A dynamic workflow can be *generated inline* by
> Claude for a one-off task, or *pinned* as a saved `.js` and re-run — build-fleet's
> are all pinned. **At runtime there is no difference**: the engine executes both
> identically, and the `Workflow` tool persists an inline script to a file anyway, so
> "on the fly" becomes "a file on disk" the moment it runs. The difference is
> *lifecycle*. A pinned workflow is **reproducible, resumable, lintable, testable, and
> version-controlled**; a generated one is a fresh sample each time — fine for a genuine
> one-off, but its bytes shift, so cross-run `resumeFromRunId` cannot cache-match it
> (the one place the "no difference" claim needs an asterisk: a single run is identical,
> but resume/caching/testing all need a *stable* script). That is why build-fleet uses
> **generate-then-pin**: `/build-fleet:scaffold-workflow` generates a workflow, then
> lints → reviews → ratifies → **pins** it (into the target's `.claude/workflows/`)
> before it is trusted to run a gate. Generation is how a dynamic workflow is born;
> pinning is how it becomes load-bearing infrastructure.

There are **exactly four** dynamic workflows (authoritative list — `CLAUDE.md`):
`review.js`, `deep-build.js`, `diagnose.js`, `plan-review.js`, dispatched by the five
commands whose `allowed-tools` include `Workflow` (`/build-fleet:review`,
`/build-fleet:deep-build`, `/build-fleet:build` in deep-build mode,
`/build-fleet:diagnose`, `/build-fleet:plan-review`). **Everything else is static.**

| Loop / step | Substrate | Runtime engine |
|---|---|---|
| REVIEW — dispatch | static | `/build-fleet:review` scaffold + `Workflow` launch |
| REVIEW — phases 1–4 (fan-out, cross-exam, vote, apply) | **dynamic** | `workflows/review.js` |
| BUILD — standard TDD | static | `/build-fleet:build` → `Task` qa, then `Task` coder |
| BUILD — deep-build | static → **dynamic** | `Task` qa (suite must pre-exist), then `workflows/deep-build.js` |
| CHANGE_REVIEW | static | `/build-fleet:handoff` → 3× parallel `Task` reviewers + `Task` coder/devops |
| Bug lane — triage / reproduce / fix / verify / ship-fix | static | commands + `Task` |
| Bug lane — DIAGNOSE | **dynamic** | `workflows/diagnose.js` |
| Product — PLAN, PLAN_FINALIZE | static | `/build-fleet:new-product`, `/build-fleet:plan-finalize` + scripts |
| Product — PLAN_REVIEW | **dynamic** | `workflows/plan-review.js` |
| DEVELOPING — advance | static | `/build-fleet:handoff` steps 12a–d + `scripts/next-feature.sh` |
| All hard gates | static | `hooks/scripts/*` (PreToolUse / PostToolUse / SubagentStop / Stop) |

**The split isn't arbitrary.** The dynamic workflows are exactly the **adversarial
multi-agent fan-outs where deterministic JS must compute over subagent results** — a
survival vote (REVIEW), a file-partition + N-coder aggregation + adversarial
sub-review (deep-build), a diagnosis-confirmation vote (diagnose), an interrogation
consolidation (plan-review). Everything linear (TDD qa→coder), Bash-dependent
(CHANGE_REVIEW's `git diff` + counterfactual `git stash`, the DEVELOPING resolver),
and every gate stays static. The instructive case is **CHANGE_REVIEW: a parallel
adversarial review that stays static** — three `Task` reviewers, not a workflow —
because the orchestrator drives it with Bash the isolated runtime can't run, and it
needs no survival-vote machinery (a plain all-approve-or-bounce gate against the
3-cycle `CHANGE_CYCLE` budget).

## What makes them *engineered* loops

Four design decisions distinguish these from "the model just keeps going":

1. **Every loop is bounded with an explicit stopping condition.** The governing
   principle is *"Escalate, don't loop forever"* (`SKILL.md:33`). Cycle budgets are
   clamped to a hard ceiling of 3, **configurable downward only**
   (`review.js:117`, `MAX_CYCLE_BUDGET`). The run that exhausts the budget writes
   `ESCALATION.md`, sets `PHASE: ESCALATED`, and halts for a human. Escalation is a
   first-class outcome, not a failure.

2. **Generator and evaluator are separated by construction.** The builder never
   grades its own work: reviewer subagents run in fresh context with **no
   Write/Edit** (`review.js:222`), and a concern only survives if a
   **different-role** reviewer fails to refute it (`review.js:407` — self-refutation
   is filtered).

3. **Two opposite loop temperaments, on purpose.** Feature REVIEW is built to
   **converge** (the survival vote kills concerns refuted with a citation). The
   product PLAN machine is built to **not converge** — PLAN_REVIEW interrogates and
   surfaces risk with no survival vote, nothing auto-killed, and a human ratifies
   (`product-tier.md:58-87`). Same skeleton, inverted convergence: a spec is a
   contract to settle; a plan is a bet a human must own.

4. **Loop state lives outside the context window.** Each iteration reads/writes
   `.sdd/<feature>/` — `PROGRESS.md` carries `CYCLE`, `BUILD_CYCLE`, `CHANGE_CYCLE`
   counters. Loops are stateless-per-run and re-read state first, so they survive
   compaction and are (same-session) resumable.

---

## A full REVIEW cycle, end-to-end

The REVIEW loop is the reference implementation of everything above. One cycle spans
three actors — the **orchestrator** (dispatch), the **workflow** (`review.js`, the
adversarial middle), and the **scribe** (the single state writer) — plus the gate
hooks that stand down while the run is live.

### Sequence

```
orchestrator  /build-fleet:review        workflows/review.js         subagents          scribe
     │
     │ 1. preconditions: ACTIVE set? PHASE∈{SPEC,REVIEW}?
     │    ESCALATION.md absent? cycle budget not exhausted?
     │ 2. new_cycle = CYCLE + 1
     │ 3. write .workflow-in-flight = run_id ──┐  (restrict-reviewer-writes +
     │ 4. emit COST_PREVIEW + REVIEW_CONFIG    │   check-review-written stand down
     │ 5. Workflow(scriptPath, args) ──────────┼──▶ Phase 1  Fan-out       while marker is live)
     │ 6. ◀── runId (async, returns at once)   │      parallel() ──▶ architect ┐ Read-only,
     │ 7. emit WORKFLOW_LAUNCHED               │                     qa        │ schema-validated
     │ 8. TaskGet once — run alive?            │                     coder     ┘ {role,status,concerns}
     │                                         │    Phase 2  Cross-examination
     │                                         │      parallel() ──▶ refute/affirm PEER concerns
     │                                         │    Phase 3  Survival vote (pure JS) → verdict
     │                                         │    Phase 4  buildEnvelope() ─────────────▶ apply:
     │                                         │                                            • state_delta → PROGRESS.md
     │                                         │                                            • review_entries → REVIEW.md
     │                                         │                                            • escalation_payload? → ESCALATION.md
     │                                         │                                            • release marker (if content==run_id)
     │ 9. ◀──────── return {verdict, scribe_apply, next} ◀──────────────────────────────────┘
     │ 10. report verdict + next legal command
```

**Execution boundary.** Steps 1–10 are **static core** — the orchestrator running the
`commands/review.md` scaffold (Read/Write plus the `Workflow` launch). Phases 1–4 are
the **dynamic workflow** `review.js` in the isolated Workflow runtime: fan-out and
cross-examination are `parallel()` batches of `agent()` subagent calls, the survival
vote (Phase 3) is deterministic JS with **no** model call, and the scribe apply
(Phase 4) is itself a final `agent()` call *from inside the script*. The script never
touches the filesystem — every state write is the scribe's.

### Step by step

**Dispatch — `/build-fleet:review` (`commands/review.md`) — *static core*.** The command is a thin,
deterministic front door. It does **not** touch `PHASE`/`CYCLE`/`REVIEW.md` itself
(that would trip the hooks before the workflow could post its bypass marker). In
order:

1. **Verify the Workflow runtime** (Claude Code **v2.1.154+**, workflows enabled).
   Missing → `BUILD_FLEET_REFUSE {code:3, reason:"workflow-runtime-unavailable"}`.
   There is no non-workflow fallback for REVIEW.
2. **Resolve the active feature** from `.sdd/ACTIVE`. Empty → refuse
   `no-active-feature`.
3. **Check phase** in `PROGRESS.md`: must be `SPEC` or `REVIEW`, else refuse
   `wrong-phase`.
4. **Check for a prior escalation**: `ESCALATION.md` present → refuse
   `escalation-present` (resolve or park first).
5. **Resolve review config** — roster (default `architect, qa, coder`) and cycle
   budget (default `3`), a per-run flag winning over a `PROGRESS.md` default. The
   *workflow* is the authoritative validator; the command passes values straight
   through. Belt-and-suspenders: if `CYCLE ≥ effective_budget` and open blockers
   remain, refuse `cycle-budget-exhausted` (a further run could only escalate).
6. **Pick the new cycle**: `new_cycle = CYCLE + 1`.
7. **Drop the marker.** Compose `run_id = review-<slug>-c<new_cycle>-<now>` and write
   it as the single line of `.sdd/<slug>/.workflow-in-flight`. **This is the bypass
   token:** the `check-review-written` and `restrict-reviewer-writes` hooks stand
   down while the marker is live, because the workflow enforces those invariants
   structurally instead (Read-only reviewer tool allowlists + an envelope
   post-condition). The marker is *owned by this run* — only a scribe holding a
   matching `run_id` may release it.
8. **Emit the headless contract lines:** `BUILD_FLEET_COST_PREVIEW` (parsed from the
   `@cost-ceiling` header of `review.js`) and `BUILD_FLEET_REVIEW_CONFIG` (records
   the effective roster/budget and where each came from — a flag override isn't
   persisted, so this line is what makes it auditable).
9. **Invoke `Workflow`** with `args = {feature, cycle:new_cycle, now, run_id}` (+
   `roles`/`cycle_budget` only when non-default). `now` is supplied by the command
   because the workflow runtime has no `Date`. The call is **async** — it returns a
   `runId`/`taskId` immediately.
10. **Emit `BUILD_FLEET_WORKFLOW_LAUNCHED`** and poll `TaskGet` once. If the run died
    before any scribe wrote, the command releases the marker itself (only if the
    content still matches its `run_id`).

**Phase 1 — Fan-out (`review.js:220`) — *dynamic workflow*.** `parallel()` dispatches every roster role at
once, each as `agentType: build-fleet:<role>` whose `AgentDefinition.tools` **omit
Write/Edit** and whose `skills` preload `review-rubric`. Each reviewer reads
`spec.md` + `acceptance.md` + prior `REVIEW.md` itself and returns a
schema-validated `{role, status, concerns:[{id, severity, text}]}` — stable IDs like
`architect-1`. A `null` return (agent error / schema failure) is a **transient
fault, not a review outcome**: the workflow cleans up the marker and returns
`incomplete` without advancing state (`review.js:238-254`).

**Phase 2 — Cross-examination (`review.js:260`).** Every concern is merged into one
pool; each reviewer is handed **only its peers'** concerns and must `refute` or
`affirm` each. A refutation only counts if it is *substantive*: **≥40 characters** of
reasoning **and** a structured `{file, locator}` citation (e.g.
`{acceptance.md, "line 14"}`). Affirm is the safe default and needs no citation.
Self-refutation is impossible — the pool excludes your own concerns, and the vote
filters same-role refutations anyway.

**Phase 3 — Survival vote (`review.js:277`, pure JS — no model).** A concern survives
unless it is refuted by a **different-role** reviewer with `verdict:"refute"`, ≥40
chars of reason, and a valid citation (`applySurvivalVote`, `review.js:400`). Then:

```
survivingBlockers = surviving.filter(severity==="blocker" && !refuted)
verdict = survivingBlockers.length > 0
            ? (cycle >= cycleBudget ? "escalate" : "revise")
            : "clean"
```

Severity governs the gate: **only surviving `blocker`s decide the verdict.** `major`
items are recorded (must be fixed or ADR-accepted before FINALIZE); `minor`s are
advisory and never block.

**Phase 4 — Apply via the scribe (`review.js:290`, `agents/scribe.md`).**
`buildEnvelope()` produces the one canonical envelope (schema:
`docs/v0.2/CONTRACT.md §6`); the scribe — the **only** state writer, holding
`Read/Write/Edit` and **no Bash** — applies it verbatim and atomically:

- **`state_delta` → `PROGRESS.md`**, in place, preserving field order:
  `PHASE = (escalate ? "ESCALATED" : "REVIEW")`, `CYCLE = cycle`, `UPDATED = now`.
  Note a `clean` verdict writes `PHASE: REVIEW`, **not** `FINALIZE` — the separate
  `/build-fleet:finalize` gate flips `STATUS=FINALIZED, PHASE=BUILD` later.
- **`review_entries` → `REVIEW.md`**, appended verbatim, one block per role,
  **append-only** (a resolved concern is a new approving entry in a later cycle,
  never an edit).
- **`escalation_payload` → `ESCALATION.md`** only when non-null (i.e. `escalate`).
- **Release the marker**: overwrite `.workflow-in-flight` with empty content **iff**
  its content equals the envelope's `run_id`. An empty marker reads as absent, so the
  stood-down hooks re-engage immediately; the `reap-stale-workflow-markers` Stop hook
  deletes the empty file.

The scribe returns `{ok, error}`. The workflow retries once on `ok:false`; still
failing → the run carries `scribe_apply:"failed"` and the orchestrator must report
the run as **failed** (state did not land, marker may remain) — never advance.

### Verdict → what happens next

| Verdict | PROGRESS after | Files written | Next legal command |
|---|---|---|---|
| `clean` | `PHASE:REVIEW`, `CYCLE:n` | `REVIEW.md` (+approving entries) | `/build-fleet:finalize` → `/build-fleet:build` |
| `revise` | `PHASE:REVIEW`, `CYCLE:n` | `REVIEW.md` (surviving blockers) | `/build-fleet:review` again after PO revises `spec.md` |
| `escalate` | `PHASE:ESCALATED`, `CYCLE:n` | `REVIEW.md` + `ESCALATION.md` | human: `/build-fleet:resolve-escalation` or `/build-fleet:park` |
| `incomplete` / `invalid-args` | **unchanged** | none (marker released) | re-run `/build-fleet:review` (transient fault / bad args) |

Cycle accounting: **one workflow run = one cycle.** The internal fan-out /
cross-exam / vote rounds do **not** bump the counter (`SKILL.md:34`). The cycle that
*exhausts* the budget with surviving blockers **is** the escalation — there is no
separate 4th cycle.

### Worked example — cycle 1 of feature `api-client`, roster `[architect, qa, coder]`

**Phase 1 (fan-out)** produces three concerns:

- `architect-1` **[blocker]** — "spec mandates retry-with-backoff but sets no
  max-retry bound; an outage triggers an unbounded retry storm."
- `qa-1` **[major]** — "acceptance criterion AC-3 has no corresponding negative-path
  test."
- `coder-1` **[minor]** — "naming: `fetchData` vs the spec's `fetch_data`."

**Phase 2 (cross-examination):**

- The **coder** refutes `qa-1`: *"acceptance.md already enumerates the 429/timeout
  negative path as a required case"* + citation `{acceptance.md, "line 14"}`
  (≥40 chars ✓, citation ✓, coder ≠ qa ✓).
- No one substantively refutes `architect-1` (qa affirms it).
- `coder-1` is a minor — irrelevant to the gate regardless.

**Phase 3 (survival vote):** `qa-1` is killed (valid different-role refutation).
`architect-1` survives → `survivingBlockers = 1`. `1 > 0` and `cycle(1) <
budget(3)` → **verdict = `revise`**.

**Phase 4 (scribe):** `PROGRESS.md` → `PHASE:REVIEW, CYCLE:1`; `REVIEW.md` gets the
cycle-1 block (architect's surviving blocker with no refutation line; qa's major with
a `refuted-by: coder — reason … (cites acceptance.md line 14)` line; coder's minor);
no `ESCALATION.md`; marker released. **Next:** the PO adds a max-retry bound to
`spec.md`, then `/build-fleet:review` runs cycle 2.

Had `architect-1` also been refuted with a valid citation, zero blockers would
survive → **`clean`**, and the feature would move to `/build-fleet:finalize`. Had it
survived on **cycle 3** instead of cycle 1, the same survival would yield
**`escalate`** — `ESCALATION.md` written, `PHASE:ESCALATED`, halt for a human.

---

## See also

- **Authority for all loop/gate semantics** — `skills/sdd-protocol/SKILL.md`
  (+ `references/product-tier.md`, `references/bug-lane.md`).
- **Envelope schema + headless signal contract** — `docs/v0.2/CONTRACT.md`.
- **Severity vocabulary** — `skills/review-rubric/SKILL.md`.
- **Doctrine assessment + the one gap** (autonomous multi-feature progression) —
  `docs/history/2026-06-20-loop-engineering-eval.md`.
