---
description: Run the v0.2 deep-build workflow — architect plans file partition, N coders fan out in parallel against M2's failing tests, adversarial review catches integration gaps before BUILD declares complete
argument-hint: "[max_partitions]"
allowed-tools: Read, Write, Edit, Workflow
---

# /build-fleet:deep-build

You are the **orchestrator**. The runtime rulebook is the `sdd-protocol` skill. In v0.2 M3, BUILD for multi-file / multi-package features runs as a Claude Code [dynamic workflow](https://code.claude.com/docs/en/workflows). This command validates preconditions, sets up the workflow handoff, and dispatches `workflows/deep-build.js`.

The workflow itself: architect plans an N-way file partition, N coders fan out in parallel (each owning a disjoint file set, all writing against pre-existing failing tests from M2), then architect + qa run an adversarial review of the merged diff against `acceptance.md`. The scribe aggregates results into `IMPL_NOTES.md` and updates PROGRESS.md.

## When to use this vs. M2 standard BUILD

- **`/build-fleet:finalize`** runs M2 standard BUILD (qa first, then a single coder). Best for single-file or tightly coupled features where partitioning has no benefit.
- **`/build-fleet:deep-build`** runs the fan-out workflow. Best for multi-package monorepos or features spanning many independent files where parallel coders give real time wins.

M4's classifier will set `BUILD_MODE: deep-build` in `PROGRESS.md` for features it routes here, and `/build-fleet:finalize` will dispatch this command automatically. Until M4 ships, this is a manual entry point.

## Workflow runtime requirement (v0.2)

Same as `/build-fleet:review`: `Workflow` tool must be available (Claude Code v2.1.154+ with workflows enabled). See ROADMAP.md.

## Arguments

- `$ARGUMENTS` — optional integer override for `max_partitions` (default 3, hard cap 8). E.g., `/build-fleet:deep-build 5`.

## What you do

1. **Verify the workflow runtime.** Check that the `Workflow` tool is available. If absent, refuse:
   > `BUILD_FLEET_REFUSE: workflow runtime unavailable. v0.2 requires Claude Code v2.1.154+ with workflows enabled. Exit 3.`

2. **Resolve the active feature.** Read `.sdd/ACTIVE`. If empty, refuse with `BUILD_FLEET_REFUSE: no active feature`. Exit 2.

3. **Check phase.** Read `.sdd/<slug>/PROGRESS.md`. PHASE must be `BUILD`. STATUS in `spec.md` must be `FINALIZED`. If either fails, refuse and name the actual state. Exit 2.

4. **Check tests-first prerequisite.** List files under `tests/`. If empty or absent, refuse with: `BUILD_FLEET_REFUSE: deep-build requires pre-existing failing tests; run /build-fleet:finalize first so qa drafts the suite (M2 ordering).` Exit 2.

5. **Check for prior escalation.** If `.sdd/<slug>/ESCALATION.md` exists, refuse. Exit 2.

6. **Check the BUILD cycle budget.** Read `BUILD_CYCLE:` from `.sdd/<slug>/PROGRESS.md`. If the field is absent (a feature scaffolded before BUILD_CYCLE existed), add `BUILD_CYCLE: 0` to PROGRESS.md first — the workflow's scribe replaces fields **in place**, so the field must exist before dispatch (an `.sdd/` write; always gate-permitted). The budget is **3 build cycles**, and the workflow escalates **on** the cycle that exhausts it: blocker-severity concerns surviving the adversarial review at cycle 3 make that run write ESCALATION.md and set `PHASE: ESCALATED`. If `BUILD_CYCLE >= 3` AND the last run left surviving blockers, refuse. Exit 2 with: `BUILD_FLEET_REFUSE: build cycle budget exhausted (BUILD_CYCLE=<n>); the budget is 3 cycles and the workflow escalates on the exhausting cycle. Resolve the surviving blockers or accept the escalation.`

7. **Pick the new cycle number.** New cycle = `BUILD_CYCLE + 1`. Pass it to the workflow as `cycle`; the workflow's scribe writes it back to `BUILD_CYCLE` via the envelope's `state_delta`.

8. **Parse arguments.** If `$ARGUMENTS` is an integer in `[1, 8]`, use it as `max_partitions`. Otherwise default to `3`.

9. **Compose the run id and drop the workflow-in-flight marker.** Compose a run id: `deep-build-<slug>-c<new_cycle>-<iso8601 now>` (the same `now` you pass to the workflow in step 11). Write `.sdd/<slug>/.workflow-in-flight` containing exactly that run id as its single line. Hooks skip while the marker is present. The marker is **owned by this run**: the scribe deletes it only if its content still matches the envelope's `run_id`. Cleanup obligation: see "Cleanup obligation" below.

10. **Emit the cost preview (headless mode contract).** Parse the `@cost-ceiling` header comment at the top of `${CLAUDE_PLUGIN_ROOT}/workflows/deep-build.js`. Emit one stdout line:

   ```
   BUILD_FLEET_COST_PREVIEW: {"workflow":"deep-build","feature":"<slug>","cycle":<N>,"max_partitions":<N>,"input_ceiling":<N>,"output_ceiling":<N>}
   ```

11. **Invoke the Workflow tool.** Call `Workflow` with:
   - `scriptPath`: `${CLAUDE_PLUGIN_ROOT}/workflows/deep-build.js`
   - `args`: `{ "feature": "<slug>", "cycle": <new_cycle>, "max_partitions": <N>, "now": "<iso8601>", "run_id": "<run id from step 9>" }`

   Supply `now` yourself (the script cannot call `Date`); the workflow refuses to run without `feature`, `cycle`, or `now`.

12. **Emit the launch line.** Once the Workflow tool returns:

    ```
    BUILD_FLEET_WORKFLOW_LAUNCHED: {"runId":"<id>","transcriptDir":"<path>","status":"async_launched","feature":"<slug>","cycle":<N>,"workflow":"deep-build","max_partitions":<N>}
    ```

13. **Verify the run is alive (marker ownership).** Poll the launched run once (`TaskGet` on the returned task). If the run has already died (errored/cancelled) before any scribe ran, delete `.sdd/<slug>/.workflow-in-flight` yourself — **only if its content still matches your run id** — then report the failure. Orchestrators polling later must apply the same rule: dead run + marker content matching this run id → delete the marker.

14. **Report and exit.** Tell the user:
    - The workflow is running in the background. Architect plans the partition first (visible in `/workflows` progress view); coders only fan out after partition is planned.
    - `/workflows` shows progress; press `x` to stop the workflow if the partition looks wrong.
    - Once it completes, `/build-fleet:status` shows the verdict. Next legal command depends on verdict:
      - `clean` → `/build-fleet:handoff` (runs CHANGE_REVIEW + devops).
      - `needs-iteration` → `/build-fleet:deep-build` again to re-run. The return envelope carries `cycles_remaining`; the budget is 3 build cycles tracked in PROGRESS.md's `BUILD_CYCLE` field. The workflow re-plans the partition each run, so iterations are expensive — read the surviving concerns in IMPL_NOTES.md before re-running.
      - `escalate` → genuine cycle exhaustion: blockers survived the adversarial review on the cycle that exhausted the 3-cycle budget. The scribe writes ESCALATION.md and sets `PHASE: ESCALATED`; human action required.
      - `incomplete` → a transient fault (architect/coder/reviewer returned no usable payload, or the partition plan was unusable/overlapping). PHASE/BUILD_CYCLE are unchanged, nothing was recorded, and the marker was cleaned up — but **if coders had already fanned out, partial writes may exist in the worktree**: surface the result's `note` and tell the user to inspect `git status`/`git diff` before re-running.
      - `invalid-args` → the dispatch args were malformed; nothing ran. Fix the dispatch and re-run.
    - **Scribe-apply failure is a hard failure.** If the completed run's return object carries `scribe_apply: "failed"`, the scribe could not write state even after a retry: IMPL_NOTES.md/PROGRESS.md did **not** land (though coders may have written source) and the marker may remain (delete it if its content matches your run id). Whoever reads that result must report the run as failed with its `scribe_error` — never treat the verdict as applied or advance to `/build-fleet:handoff`.

## Exit codes

| Exit | Meaning |
|---|---|
| 0 | Workflow launched successfully |
| 1 | Workflow tool returned an error field |
| 2 | Pre-dispatch validation failed (active empty, wrong phase, no tests, escalation present) |
| 3 | Workflow runtime not available |

## What this command does NOT do

- Does not draft tests. M2's `/build-fleet:finalize` already dispatched qa for that. Deep-build assumes the failing test suite exists.
- Does not bump PHASE, `BUILD_CYCLE`, or run CHANGE_REVIEW. The workflow's scribe writes `BUILD_CYCLE` (and the rest of the BUILD-completion delta) via the envelope's `state_delta`; this command only normalizes a missing `BUILD_CYCLE: 0` field pre-dispatch. CHANGE_REVIEW is `/build-fleet:handoff`'s job.
- Does not write source. Only its coder subagents (inside the workflow) write source — each restricted to its partition.
- Does not delete `.workflow-in-flight` on success. Scribe does that as the final phase (only when the marker still contains this run's id).

## Cleanup obligation

If `.workflow-in-flight` was created and the Workflow tool fails to launch (returns `error`), delete the marker — after verifying its content still matches your run id — before exiting with exit code 1. The same ownership rule applies to the post-launch liveness check (step 13): a dead run plus a marker still containing this run's id means you delete it; a marker with different content belongs to a newer dispatch and must be left alone.

## The BUILD_CYCLE field

`BUILD_CYCLE: <n>` in `.sdd/<slug>/PROGRESS.md` counts completed deep-build runs for the active feature, exactly as `CYCLE` counts REVIEW cycles (and `CHANGE_CYCLE` counts CHANGE_REVIEW cycles). This command reads it and passes `BUILD_CYCLE + 1` as the workflow's `cycle` arg; the workflow's scribe writes the new value back. Budget: 3 — the workflow escalates on the exhausting cycle, and its `needs-iteration` envelope carries `cycles_remaining` so headless orchestrators cannot loop the workflow forever.

## Refusal contract

All refusals begin with `BUILD_FLEET_REFUSE: ` for orchestrator consumption. Exit codes as above.
