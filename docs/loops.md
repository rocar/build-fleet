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
| **REVIEW** (spec ⇄ review) | evaluator-optimizer + parallelization-with-voting | one `/build-fleet:review` run (REVIEW.md rotated to the previous cycle at each dispatch; cycle ≥2 is a delta review) | zero blockers & zero `fix` majors (`finalize_ready`) → `clean`; else `revise`/`escalate` at **≤3 cycles**, escalating on blockers **or** `fix` majors — plus a cumulative `CYCLE_TOTAL` bound across escalations | `workflows/review.js`, `SKILL.md` §REVIEW |
| **REVIEW internal** | 5-stage micro-loop | fan-out → cross-examination → survival vote → disposition → apply | pure-JS survival vote | `workflows/review.js` |
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
   grades its own work: fan-out runs every roster role as the read-only
   `build-fleet:reviewer` agent — Read/Grep/Glob by its own agent definition, no
   Write/Edit to grade with — and a concern only survives if a **different-role**
   reviewer fails to refute it (self-refutation is filtered). A surviving
   `[major]` then goes through a fifth, separate leg — **disposition**, run by the
   architect — before the gate's rule (`finalize_ready`) is computed, so the same
   role that classifies a trade-off as `adr`/`fix` never also voted it a pass.

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
     │    ESCALATION.md absent? per-escalation budget not exhausted?
     │    CYCLE_TOTAL_MAX not hit? last output within 3× the cost ceiling?
     │ 2. new_cycle = CYCLE + 1
     │ 3. rotate REVIEW.md → REVIEW-archive.md (review-rotate.sh);
     │    compute next_adr_id + cycle_total (adr-index.sh --next)
     │ 4. write .workflow-in-flight = run_id ──┐  (restrict-reviewer-writes +
     │ 5. emit COST_PREVIEW + REVIEW_CONFIG    │   check-review-written stand down
     │ 6. Workflow(scriptPath, args) ──────────┼──▶ Phase 1  Fan-out       while marker is live)
     │ 7. ◀── runId (async, returns at once)   │      parallel() ──▶ reviewer(architect) ┐ Read-only,
     │ 8. emit WORKFLOW_LAUNCHED               │                     reviewer(qa)        │ schema-validated
     │ 9. TaskGet once — run alive?            │                     reviewer(coder)     ┘ {role,status,concerns}
     │                                         │    Phase 2  Cross-examination
     │                                         │      parallel() ──▶ refute/affirm PEER concerns
     │                                         │    Phase 3  Survival vote (pure JS) → refuted vs. surviving
     │                                         │    Phase 4  Disposition (architect) → adr | fix per major
     │                                         │    Phase 5  buildEnvelope() ─────────────▶ apply:
     │                                         │                                            • state_delta → PROGRESS.md
     │                                         │                                              (+CYCLE_TOTAL, LAST_REVIEW_OUTPUT_TOKENS)
     │                                         │                                            • review_entries → REVIEW.md
     │                                         │                                            • decisions_appendix → DECISIONS.md
     │                                         │                                            • escalation_payload? → ESCALATION.md
     │                                         │                                            • release marker (if content==run_id)
     │ 10. ◀─ return {verdict, finalize_ready, scribe_apply, next} ◀──────────────────────┘
     │ 11. report verdict + next legal command (finalize | revise)
```

**Execution boundary.** Steps 1–11 are **static core** — the orchestrator running the
`commands/review.md` scaffold (Read/Write plus the `Workflow` launch, and the two
deterministic scripts in step 3). Phases 1–5 are the **dynamic workflow** `review.js`
in the isolated Workflow runtime: fan-out and cross-examination are `parallel()`
batches of `agent()` subagent calls, the survival vote (Phase 3) is deterministic JS
with **no** model call, disposition (Phase 4) is a single further `agent()` call that
only runs when a major survives, and the scribe apply (Phase 5) is itself a final
`agent()` call *from inside the script*. The script never touches the filesystem —
every state write is the scribe's.

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
   **v0.9 adds two more checks, before any cost is spent:** the cumulative
   `CYCLE_TOTAL` bound — refuse `cycle-total-exhausted` when `CYCLE_TOTAL_MAX` is
   not `0` and `CYCLE_TOTAL ≥ CYCLE_TOTAL_MAX` (`CYCLE_TOTAL` is scribe-written and
   never resets, not even across escalations or parks); and `cost-runaway` —
   refuse when `LAST_REVIEW_OUTPUT_TOKENS` exceeds 3× the `@cost-ceiling` header's
   `output_tokens` (override with `--override-cost`).
6. **Pick the new cycle**: `new_cycle = CYCLE + 1`.
7. **Rotate REVIEW.md and index the ADRs (v0.9).** `scripts/review-rotate.sh` moves
   every block older than the previous cycle's roster-sized run into
   `.sdd/<slug>/REVIEW-archive.md` (append-only) — bounding what the next fan-out
   has to read; idempotent, a no-op on cycle 0. `scripts/adr-index.sh --next`
   computes `next_adr_id` for the disposition leg's ADR numbering. `cycle_total` is
   read here too (`CYCLE_TOTAL`, or `CYCLE` when absent) — the count *before* this
   run.
8. **Drop the marker.** Compose `run_id = review-<slug>-c<new_cycle>-<now>` and write
   it as the single line of `.sdd/<slug>/.workflow-in-flight`. **This is the bypass
   token:** the `check-review-written` and `restrict-reviewer-writes` hooks stand
   down while the marker is live, because the workflow enforces those invariants
   structurally instead (Read-only reviewer tool allowlists + an envelope
   post-condition). The marker is *owned by this run* — only a scribe holding a
   matching `run_id` may release it.
9. **Emit the headless contract lines:** `BUILD_FLEET_COST_PREVIEW` (parsed from the
   `@cost-ceiling` header of `review.js`) and `BUILD_FLEET_REVIEW_CONFIG` (records
   the effective roster/budget and where each came from — a flag override isn't
   persisted, so this line is what makes it auditable).
10. **Invoke `Workflow`** with `args = {feature, cycle:new_cycle, now, run_id,
    cycle_total, next_adr_id}` (+ `roles`/`cycle_budget` only when non-default).
    `now` is supplied by the command because the workflow runtime has no `Date`.
    The call is **async** — it returns a `runId`/`taskId` immediately.
11. **Emit `BUILD_FLEET_WORKFLOW_LAUNCHED`** and poll `TaskGet` once. If the run died
    before any scribe wrote, the command releases the marker itself (only if the
    content still matches its `run_id`).

**Phase 1 — Fan-out — *dynamic workflow* (v0.9).** `parallel()` dispatches every
roster role at once, each as the read-only `build-fleet:reviewer` agent
(`Read`/`Grep`/`Glob` by its own agent definition, not a per-call tool/skill
override — the runtime's `agent()` has no `tools`/`skills` options; the severity
rubric is mirrored in the agent's prompt body) with that role's lens injected.
Cycle 1 is a full review; **cycle ≥ 2 is a delta review** — verify closure of prior
`fix` findings and blockers by id, new findings at blocker severity only, enforced
in code (a post-cycle-1 major is demoted to minor), not only asked for in the
prompt. Each reviewer reads `spec.md` + `acceptance.md` + prior `REVIEW.md` itself
and returns a schema-validated `{role, status, concerns:[{id, severity, text}]}` —
stable IDs shaped `<role>-c<cycle>-<n>` that persist across re-raises. A `null`
return (agent error / schema failure) is a **transient fault, not a review
outcome**: the workflow cleans up the marker and returns `incomplete` without
advancing state. v0.9 also inserts a fifth phase, **Disposition**, between the
survival vote and apply (fan-out → cross-examination → survival vote →
disposition → apply), and the gate's rule going forward is `finalize_ready` (zero
open blockers AND zero `fix`-dispositioned majors) rather than a bare `clean`
verdict.

**Phase 2 — Cross-examination.** Every concern is merged into one pool; each
reviewer is handed **only its peers'** concerns and must `refute` or `affirm` each.
A refutation only counts if it is *substantive*: **≥40 characters** of reasoning
**and** a structured `{file, locator}` citation against `spec.md`, `acceptance.md`
or `DECISIONS.md` (e.g. `{acceptance.md, "line 14"}` or `{DECISIONS.md, "ADR-7"}`
— citing an ADR by id is itself a substantive refutation). Affirm is the safe
default and needs no citation. Self-refutation is impossible — the pool excludes
your own concerns, and the vote filters same-role refutations anyway.

**Phase 3 — Survival vote (pure JS — no model).** A concern survives unless it is
refuted by a **different-role** reviewer with `verdict:"refute"`, ≥40 chars of
reason, and a valid citation (`applySurvivalVote`). A refutation renders as a
`  refuted-by:` continuation line under the finding in REVIEW.md and closes it
**regardless of severity** — a refuted blocker is exactly as closed as a refuted
major.

**Phase 4 — Disposition (architect, read-only reviewer).** Runs only when at least
one `[major]` survives the vote unrefuted. One architect leg classifies each
surviving major **exactly once**: `adr` (a design trade-off — an ADR title + body
is drafted, numbered from `next_adr_id`) or `fix` (a gap the PO must close in the
spec). Coverage is checked before anything is written — a missing id, a duplicate
id, or an `adr` disposition with an empty body fails the **whole run** as
`incomplete` (`disposition-incomplete`): nothing is written, re-run. The leg's
output becomes the envelope's `decisions_appendix` (the ADR blocks, verbatim), and
each dispositioned major's REVIEW.md line gets a `  disposition: adr ADR-N` or
`  disposition: fix` continuation.

Once every surviving major is dispositioned (or skipped, if none survived), the
gate's rule is computed:

```
openBlockers   = surviving.filter(severity==="blocker" && !refuted)
openMajors     = surviving.filter(severity==="major" && !refuted && disposition !== "adr")
finalize_ready = openBlockers.length === 0 && openMajors.length === 0
verdict = (cycle >= cycleBudget && (openBlockers.length > 0 || openMajors.length > 0))
            ? "escalate"
            : openBlockers.length > 0 ? "revise" : "clean"
```

**`finalize_ready`, not the bare `verdict`, is what `/build-fleet:finalize`'s gate
script (`scripts/finalize-gate.sh`) actually enforces.** A `clean` verdict with
`finalize_ready:false` (zero blockers, but an open `fix` major) routes to
`/build-fleet:revise`, not straight to finalize — the pre-v0.9 "clean → finalize
gate then refuses" trap can't happen anymore. Escalation now fires on the
exhausting cycle when **either** open blockers or open `fix` majors remain, not
blockers alone. `minor`s stay advisory and never block.

**Phase 5 — Apply via the scribe (`agents/scribe.md`).** `buildEnvelope()` produces
the one canonical envelope (schema: `docs/v0.2/CONTRACT.md §6`); the scribe — the
**only** state writer, holding `Read/Write/Edit` and **no Bash** — applies it
verbatim and atomically:

- **`state_delta` → `PROGRESS.md`**, in place, preserving field order:
  `PHASE = (escalate ? "ESCALATED" : "REVIEW")`, `CYCLE = cycle`,
  `CYCLE_TOTAL = cycle_total + 1` (cumulative, never reset), `LAST_REVIEW_OUTPUT_TOKENS`,
  `UPDATED = now`. A `clean` verdict still writes `PHASE: REVIEW`, **not**
  `FINALIZE` — the separate `/build-fleet:finalize` gate (or `/build-fleet:revise`
  when `finalize_ready` is false) advances the phase later.
- **`review_entries` → `REVIEW.md`**, appended verbatim, one block per role,
  **append-only** (a resolved concern is a new approving/refuting entry in a later
  cycle, never an edit) — ids are shaped `<role>-c<cycle>-<n>` and a re-raised
  finding keeps its original id across cycles.
- **`decisions_appendix` → `DECISIONS.md`** (v0.9) — the `adr`-dispositioned ADR
  blocks from Phase 4, appended verbatim, only when non-null.
- **`escalation_payload` → `ESCALATION.md`** only when non-null (i.e. `escalate`) —
  now lists both the open blockers **and** the open `fix` majors.
- **Release the marker**: overwrite `.workflow-in-flight` with empty content **iff**
  its content equals the envelope's `run_id`. An empty marker reads as absent, so the
  stood-down hooks re-engage immediately; the `reap-stale-workflow-markers` Stop hook
  deletes the empty file.

The scribe returns `{ok, error}`. The workflow retries once on `ok:false`; still
failing → the run carries `scribe_apply:"failed"` and the orchestrator must report
the run as **failed** (state did not land, marker may remain) — never advance.

### Verdict → what happens next

| Verdict | `finalize_ready` | PROGRESS after | Files written | Next legal command |
|---|---|---|---|---|
| `clean` | `true` | `PHASE:REVIEW`, `CYCLE:n`, `CYCLE_TOTAL:+1` | `REVIEW.md` (+approving/refuted entries), `DECISIONS.md` (any `adr` dispositions) | `/build-fleet:finalize` → `/build-fleet:build` |
| `clean` | `false` | `PHASE:REVIEW`, `CYCLE:n`, `CYCLE_TOTAL:+1` | `REVIEW.md` (open `fix` major(s)), `DECISIONS.md` (any `adr` dispositions) | `/build-fleet:revise` (hands the PO exactly the open items) → `/build-fleet:review` |
| `revise` | `false` | `PHASE:REVIEW`, `CYCLE:n`, `CYCLE_TOTAL:+1` | `REVIEW.md` (surviving blockers) | `/build-fleet:revise` → `/build-fleet:review` |
| `escalate` | `false` | `PHASE:ESCALATED`, `CYCLE:n`, `CYCLE_TOTAL:+1` | `REVIEW.md` + `ESCALATION.md` (blockers **and** open majors) | human: `/build-fleet:resolve-escalation` or `/build-fleet:park` |
| `incomplete` / `invalid-args` | — | **unchanged** | none (marker released) | re-run `/build-fleet:review` (transient fault, bad args, or `disposition-incomplete`) |

Cycle accounting: **one workflow run = one cycle**, against the per-escalation
`REVIEW_CYCLE_BUDGET` (default `3`). The internal fan-out / cross-exam /
disposition rounds do **not** bump that counter (`SKILL.md`, Operating principles).
The cycle that *exhausts* the budget with surviving blockers or open `fix` majors
**is** the escalation — there is no separate 4th cycle. **v0.9 adds a second,
cumulative counter**, `CYCLE_TOTAL`: every review cycle this feature has ever run,
never reset — not by `/build-fleet:resolve-escalation`, not by `/build-fleet:park`.
`/build-fleet:review` refuses to dispatch, before spending anything, when
`CYCLE_TOTAL_MAX` is not `0` and `CYCLE_TOTAL ≥ CYCLE_TOTAL_MAX`
(`cycle-total-exhausted`) — a backstop above the per-escalation budget, aimed at a
feature that keeps escalating, getting reset, and never converging.

### Worked example — cycle 1 of feature `api-client`, roster `[architect, qa, coder]`

**Phase 1 (fan-out)** produces three concerns:

- `architect-c1-1` **[blocker]** — "spec mandates retry-with-backoff but sets no
  max-retry bound; an outage triggers an unbounded retry storm."
- `qa-c1-2` **[major]** — "acceptance criterion AC-3 has no corresponding
  negative-path test."
- `coder-c1-3` **[minor]** — "naming: `fetchData` vs the spec's `fetch_data`."

**Phase 2 (cross-examination):**

- The **coder** refutes `qa-c1-2`: *"acceptance.md already enumerates the
  429/timeout negative path as a required case"* + citation
  `{acceptance.md, "line 14"}` (≥40 chars ✓, citation ✓, coder ≠ qa ✓).
- No one substantively refutes `architect-c1-1` (qa affirms it).
- `coder-c1-3` is a minor — irrelevant to the gate regardless.

**Phase 3 (survival vote):** `qa-c1-2` is killed — rendered as a
`refuted-by: coder — reason … (cites acceptance.md line 14)` continuation.
`architect-c1-1` survives unrefuted; no major is left standing.

**Phase 4 (disposition):** skipped — zero surviving majors, so the architect leg
never runs.

**Phase 5 (scribe):** `openBlockers = [architect-c1-1]`, `openMajors = []` →
`finalize_ready = false`. `cycle(1) < budget(3)` and a blocker is open →
**verdict = `revise`**. `PROGRESS.md` → `PHASE:REVIEW, CYCLE:1, CYCLE_TOTAL:1`;
`REVIEW.md` gets the cycle-1 block (architect's surviving blocker with no
continuation line; qa's major with the `refuted-by:` line above; coder's minor);
no `DECISIONS.md` appendix (disposition never ran); no `ESCALATION.md`; marker
released. **Next:** `/build-fleet:revise` hands the PO exactly `architect-c1-1` (a
max-retry bound to add to `spec.md`); then `/build-fleet:review` runs cycle 2 as a
**delta review** — the PO's fix is verified by id, and the roster may raise new
findings at `[blocker]` severity only (a new `[major]` would be demoted to
`[minor]` in code before the vote).

Had `architect-c1-1` also been refuted with a valid citation, zero blockers and
zero majors would survive → `finalize_ready = true`, **verdict = `clean`**, and
`/build-fleet:finalize` would be the next legal command. Had a `[major]` survived
instead of (or alongside) the blocker, Phase 4 would run: an `adr` disposition
drafts an ADR and closes that major (`openMajors` excludes it); a `fix`
disposition leaves it open (`finalize_ready:false`, next: `/build-fleet:revise`
regardless of the blocker's fate). Had `architect-c1-1` survived on **cycle 3**
instead of cycle 1 (the `REVIEW_CYCLE_BUDGET`), the same survival would yield
**`escalate`** — `ESCALATION.md` written (listing the open blocker and any open
majors), `PHASE:ESCALATED`, halt for a human — regardless of how large
`CYCLE_TOTAL` has grown by then.

---

## See also

- **Authority for all loop/gate semantics** — `skills/sdd-protocol/SKILL.md`
  (+ `references/product-tier.md`, `references/bug-lane.md`).
- **Envelope schema + headless signal contract** — `docs/v0.2/CONTRACT.md`.
- **Severity vocabulary** — `skills/review-rubric/SKILL.md`.
- **Doctrine assessment + the one gap** (autonomous multi-feature progression) —
  `docs/history/2026-06-20-loop-engineering-eval.md`.
