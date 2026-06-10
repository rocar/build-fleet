---
description: Run a product-tier PLAN_REVIEW on .sdd/_product/ — interrogate the plan (vision, backlog, stack) from each role's lens, consolidate findings, apply via scribe. No survival vote; the human ratifies at /build-fleet:plan-finalize.
argument-hint: ""
allowed-tools: Read, Write, Edit, Workflow
---

# /build-fleet:plan-review

You are the **orchestrator**. The runtime rulebook is the `sdd-protocol` skill
(**Product tier → PLAN state machine**). The product PLAN_REVIEW phase runs as a
Claude Code [dynamic workflow](https://code.claude.com/docs/en/workflows). This
command validates preconditions, normalizes the product PROGRESS, drops the
workflow marker, and dispatches `workflows/plan-review.js`. The workflow does the
interrogation, consolidation, and state-mutation-via-scribe.

**This is interrogation, not a verdict.** Unlike `/build-fleet:review`, plan-review
holds **no survival vote** and **never auto-escalates**. It surfaces questions,
risks, and gaps for a human to weigh, sets `PHASE: PLAN_REVIEW`, and stops. Strategy
is ratified at `/build-fleet:plan-finalize`, not auto-decided here.

## Workflow runtime requirement

The `Workflow` tool must be available (Claude Code v2.1.154+, workflows enabled,
`Workflow` in `allowedTools`). If absent, refuse with exit code 3 and tell the
user how to enable workflows — there is no v0.1-style fallback.

## What you do

1. **Verify the workflow runtime.** If the `Workflow` tool is unavailable, refuse:
   > `BUILD_FLEET_REFUSE: workflow runtime unavailable. Plan-review requires Claude Code v2.1.154+ with workflows enabled. Exit 3.`

2. **Resolve the product.** Read `.sdd/PRODUCT` (fall back to the `PRODUCT:` field of
   `.sdd/_product/PROGRESS.md`). If there is no product tier, refuse:
   > `BUILD_FLEET_REFUSE: no product tier. Run /build-fleet:new-product first. Exit 2.`

3. **Refuse while a feature is mid-review (hook-confinement guard).** Read `.sdd/ACTIVE`;
   if non-empty, read `.sdd/<active>/PROGRESS.md` `PHASE`. If it is `REVIEW` or
   `CHANGE_REVIEW`, refuse:
   > `BUILD_FLEET_REFUSE: feature '<active>' is in <PHASE>. The restrict-reviewer-writes hook confines all writes to .sdd/<active>/ during feature review, so the product scribe cannot write .sdd/_product/. Finish or escalate the feature review first. Exit 2.`

   The interrogator roles (`product-owner`, `architect`, `qa`) also overlap the
   feature-reviewer set, so a mid-review feature would mis-fire `check-review-written`
   on them. This single guard covers both hooks. *(Any other active-feature phase —
   SPEC, FINALIZE, BUILD, HANDOFF — is fine: plan-review touches only `.sdd/_product/`.)*

4. **Normalize the product PROGRESS (legacy-tier tolerance).** Read
   `.sdd/_product/PROGRESS.md`. The product-scope scribe replaces fields **in place**,
   so both `PHASE` and `CYCLE` must exist before dispatch:
   - If `PHASE` is absent (a tier scaffolded before M3.1), add `PHASE: PLAN`.
   - If `CYCLE` is absent, add `CYCLE: 0`.
   These writes land under `.sdd/_product/` (permitted by `block-source-before-finalized`).
   Do **not** otherwise edit PROGRESS — the workflow's scribe owns the PHASE/CYCLE bump.

5. **Check phase.** Read the (now-normalized) `PHASE`. It must be `PLAN` or
   `PLAN_REVIEW`. If `DEVELOPING`, refuse — the plan is already ratified; re-planning
   after ratification is M3.2. If `ESCALATED`, refuse and point at `_product/ESCALATION.md`.
   Exit 2, naming the actual phase.

6. **Check for prior escalation.** If `.sdd/_product/ESCALATION.md` exists, refuse —
   a human wrote it to halt the plan. Tell the user to resolve and remove it. Exit 2.

7. **Pick the new cycle number.** New cycle = `CYCLE + 1`. There is **no cycle-budget
   escalation** here (plan-review never auto-escalates); the counter is the audit
   trail. If `CYCLE` is already high (≥ 5), emit a soft note that the plan has been
   interrogated many times and may need a ratification decision rather than another
   cycle — but proceed.

8. **Compose the run id and drop the workflow-in-flight marker.** Compose a run id:
   `plan-review-<product>-c<new_cycle>-<iso8601 now>` (the same `now` you pass in
   step 10). Write `.sdd/_product/.workflow-in-flight` containing exactly that run
   id as its single line. The marker is **owned by this run**: the scribe removes it
   as the workflow's final phase (resolved under the envelope's `workspace_dir`)
   only if its content still matches the envelope's `run_id`. No per-reviewer hook
   keys off this marker in product scope (step 3's guard handles that), but the
   marker provides workflow liveness and is reaped if orphaned.
   **Cleanup obligation:** if the `Workflow` tool fails to launch, delete the marker
   (after verifying its content still matches your run id) before exiting.

9. **Emit the cost preview (headless contract).** Parse `@cost-ceiling` from the top
   of `${CLAUDE_PLUGIN_ROOT}/workflows/plan-review.js`. Write exactly one stdout line:
   ```
   BUILD_FLEET_COST_PREVIEW: {"workflow":"plan-review","product":"<slug>","cycle":<N>,"input_ceiling":<N>,"output_ceiling":<N>}
   ```

10. **Invoke the Workflow tool** with:
    - `scriptPath`: `${CLAUDE_PLUGIN_ROOT}/workflows/plan-review.js`
    - `args`: `{ "product": "<slug>", "cycle": <new_cycle>, "now": "<iso8601>", "run_id": "<run id from step 8>" }`

    Supply `now` yourself (the script cannot call `Date`); the workflow refuses to
    run without it. The tool is async-launched.

11. **Emit the launch line (headless contract).** Once the tool returns:
    ```
    BUILD_FLEET_WORKFLOW_LAUNCHED: {"runId":"<id>","transcriptDir":"<path>","status":"async_launched","product":"<slug>","cycle":<N>,"workflow":"plan-review"}
    ```

12. **Verify the run is alive (marker ownership).** Poll the launched run once
    (`TaskGet` on the returned task). If the run has already died (errored/cancelled)
    before any scribe ran, delete `.sdd/_product/.workflow-in-flight` yourself —
    **only if its content still matches your run id** — then report the failure.
    Orchestrators polling later must apply the same rule: dead run + marker content
    matching this run id → delete the marker.

13. **Report and exit.** Tell the user:
    - The interrogation is running in the background; `/workflows` shows progress.
    - On completion, `.sdd/_product/REVIEW.md` holds the interrogation report and
      `PHASE` becomes `PLAN_REVIEW`.
    - Next: read the report, revise vision/backlog/STACK as needed and re-run
      `/build-fleet:plan-review`, or ratify with `/build-fleet:plan-finalize`.
    - A verdict of `incomplete` / `invalid-args` means a transient agent fault or bad
      dispatch args: PHASE/CYCLE are unchanged, no report was written — re-run
      `/build-fleet:plan-review` (or fix the dispatch args).
    - **Scribe-apply failure is a hard failure.** If the completed run's return object
      carries `scribe_apply: "failed"`, the scribe could not write state even after a
      retry: the interrogation report and PROGRESS did **not** land and the marker may
      remain (delete it if its content matches your run id). Whoever reads that result
      must report the run as failed with its `scribe_error` — never treat the
      interrogation as recorded or proceed to `/build-fleet:plan-finalize` on its basis.

## Exit codes

| Exit | Meaning |
|---|---|
| 0 | Workflow launched; runId emitted |
| 1 | Workflow tool returned an error field — surface it |
| 2 | Pre-dispatch validation failed (no product, feature mid-review, wrong phase, escalation present) |
| 3 | Workflow runtime not available |

## What this command does NOT do

- Does not bump `PHASE` or `CYCLE` beyond the legacy-tolerance normalization in step 4.
  The workflow's scribe writes the real PHASE=PLAN_REVIEW + CYCLE bump via the envelope.
- Does not append to `_product/REVIEW.md` — the workflow's scribe does.
- Does not write `_product/ESCALATION.md` — plan-review never auto-escalates. Only a
  human halts a plan.
- Does not vote, refute, or auto-pass. Ratification is `/build-fleet:plan-finalize`.

## Refusal contract

All refusals begin with `BUILD_FLEET_REFUSE: ` for orchestrator consumption. Exit
codes as above.
