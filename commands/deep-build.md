---
description: Fan out parallel coders over a planned file partition
argument-hint: "[max_partitions] [--cycle-budget <1-3>]"
allowed-tools: Read, Write, Edit, Workflow
---

# /build-fleet:deep-build

You are the **orchestrator**. The runtime rulebook is the `sdd-protocol` skill. BUILD for multi-file / multi-package features runs as a Claude Code [dynamic workflow](https://code.claude.com/docs/en/workflows). This command validates preconditions, sets up the workflow handoff, and dispatches `workflows/deep-build.js`.

The workflow itself: architect plans an N-way file partition, N coders fan out in parallel (each owning a disjoint file set, all writing against the pre-existing failing tests qa authored), then architect + qa run an adversarial review of the merged diff against `acceptance.md`. The scribe aggregates results into `IMPL_NOTES.md` and updates PROGRESS.md.

## When to use this vs. standard BUILD

- **`/build-fleet:build`** runs standard BUILD (qa first, then a single coder). Best for single-file or tightly coupled features where partitioning has no benefit.
- **`/build-fleet:deep-build`** runs the fan-out workflow. Best for multi-package monorepos or features spanning many independent files where parallel coders give real time wins.

The classifier sets `BUILD_MODE: deep-build` in `PROGRESS.md` for features it routes here, and `/build-fleet:build` dispatches this workflow automatically. This command is the manual / iteration entry point.

## Workflow runtime requirement

Same as `/build-fleet:review`: `Workflow` tool must be available (Claude Code v2.1.154+ with workflows enabled). See ROADMAP.md.

## Arguments

- `$ARGUMENTS` — a leading optional integer overrides `max_partitions` (default 3, hard cap 8), e.g. `/build-fleet:deep-build 5`.
- `--cycle-budget <1-3>` — optional override of the BUILD escalation budget (default 3, clamped to the 3-cycle ceiling), e.g. `/build-fleet:deep-build 5 --cycle-budget 2`.

## What you do

1. **Verify the workflow runtime.** Check that the `Workflow` tool is available. If absent, refuse:
   > `BUILD_FLEET_REFUSE: {"command":"deep-build","code":3,"reason":"workflow-runtime-unavailable"}`
   then tell the user the deep-build workflow requires Claude Code v2.1.154+ with workflows enabled.

2. **Resolve the active feature.** Read `.sdd/ACTIVE`. If empty, refuse with `BUILD_FLEET_REFUSE: {"command":"deep-build","code":2,"reason":"no-active-feature"}`.

3. **Check phase.** Read `.sdd/<slug>/PROGRESS.md`. PHASE must be `BUILD`. STATUS in `spec.md` must be `FINALIZED`. If either fails, refuse and name the actual state (`{"command":"deep-build","code":2,"reason":"not-finalized","status":"<STATUS>","phase":"<PHASE>"}`).

4. **Check tests-first prerequisite.** List files under `tests/`. If empty or absent, refuse with: `BUILD_FLEET_REFUSE: {"command":"deep-build","code":2,"reason":"no-failing-tests","detail":"run /build-fleet:build first so qa drafts the suite (tests-first ordering)"}`.

5. **Check for prior escalation.** If `.sdd/<slug>/ESCALATION.md` exists, refuse (`{"command":"deep-build","code":2,"reason":"escalation-present"}`) — `/build-fleet:resolve-escalation` is the unblock path.

6. **Resolve the cycle budget, then check it.** The BUILD escalation budget is configurable (default 3). Resolve it — **a per-run flag wins over the durable default**: `--cycle-budget <n>` in `$ARGUMENTS` → else `BUILD_CYCLE_BUDGET:` in `.sdd/<slug>/PROGRESS.md` → else `3`. Call the resolved integer `effective_budget` (treat unset as `3`); clamp it to `1..3` (the workflow re-clamps anything above the ceiling). The **workflow is the authoritative validator** — pass the resolved value through (step 11) and let `deep-build.js` reject a malformed budget via its `invalid-args` path; do **not** persist `BUILD_CYCLE_BUDGET` (a flag override is per-run).

   Read `BUILD_CYCLE:` from `.sdd/<slug>/PROGRESS.md`. If the field is absent (a feature scaffolded before BUILD_CYCLE existed), add `BUILD_CYCLE: 0` to PROGRESS.md first — the workflow's scribe replaces fields **in place**, so the field must exist before dispatch (an `.sdd/` write; always gate-permitted). The workflow escalates **on** the cycle that exhausts `effective_budget`: blocker-severity concerns surviving the adversarial review at `BUILD_CYCLE == effective_budget` make that run write ESCALATION.md and set `PHASE: ESCALATED`. If `BUILD_CYCLE >= effective_budget` AND the last run left surviving blockers, refuse with: `BUILD_FLEET_REFUSE: {"command":"deep-build","code":2,"reason":"build-cycle-budget-exhausted","build_cycle":<n>,"cycle_budget":<effective_budget>}` — resolve the surviving blockers or accept the escalation.

7. **Pick the new cycle number.** New cycle = `BUILD_CYCLE + 1`. Pass it to the workflow as `cycle`; the workflow's scribe writes it back to `BUILD_CYCLE` via the envelope's `state_delta`.

8. **Parse arguments.** A leading integer in `[1, 8]` is `max_partitions` (else default `3`). A `--cycle-budget <n>` token sets the budget already resolved in step 6. Both are optional and independent.

9. **Compose the run id and drop the workflow-in-flight marker.** Compose a run id: `deep-build-<slug>-c<new_cycle>-<iso8601 now>` (the same `now` you pass to the workflow in step 11). Write `.sdd/<slug>/.workflow-in-flight` containing exactly that run id as its single line. Hooks skip while the marker is live. The marker is **owned by this run**: the scribe releases it (empties it) only if its content still matches the envelope's `run_id`. Cleanup obligation: see "Cleanup obligation" below.

10. **Emit the cost preview (headless mode contract).** Parse the `@cost-ceiling` header comment at the top of `${CLAUDE_PLUGIN_ROOT}/workflows/deep-build.js`. Emit one stdout line:

   ```
   BUILD_FLEET_COST_PREVIEW: {"workflow":"deep-build","feature":"<slug>","cycle":<N>,"max_partitions":<N>,"input_ceiling":<N>,"output_ceiling":<N>}
   ```

   Then emit one **config** line recording the effective budget and its source (so a non-persisted flag override is auditable in the run log):

   ```
   BUILD_FLEET_DEEP_BUILD_CONFIG: {"feature":"<slug>","cycle":<N>,"cycle_budget":<n | "default">,"budget_source":"flag"|"progress"|"default"}
   ```

11. **Invoke the Workflow tool.** Call `Workflow` with:
   - `scriptPath`: `${CLAUDE_PLUGIN_ROOT}/workflows/deep-build.js`
   - `args`: `{ "feature": "<slug>", "cycle": <new_cycle>, "max_partitions": <N>, "now": "<iso8601>", "run_id": "<run id from step 9>" }` — **plus** `"cycle_budget": <resolved int>` ONLY when resolved from a flag or `BUILD_CYCLE_BUDGET` in step 6. **Omit it when unset** so the workflow uses its default (omitting it reproduces the historical behavior exactly).

   Supply `now` yourself (the script cannot call `Date`); the workflow refuses to run without `feature`, `cycle`, or `now`.

12. **Emit the launch line.** Once the Workflow tool returns:

    ```
    BUILD_FLEET_WORKFLOW_LAUNCHED: {"runId":"<id>","transcriptDir":"<path>","status":"async_launched","feature":"<slug>","cycle":<N>,"workflow":"deep-build","max_partitions":<N>}
    ```

13. **Verify the run is alive (marker ownership).** Poll the launched run once (`TaskGet` on the returned task). If the run has already died (errored/cancelled) before any scribe ran, release `.sdd/<slug>/.workflow-in-flight` yourself — **only if its content still matches your run id**, by overwriting it with empty content — then report the failure. Orchestrators polling later must apply the same rule: dead run + marker content matching this run id → release the marker.

14. **Report and exit.** Tell the user:
    - The workflow is running in the background. Architect plans the partition first (visible in `/workflows` progress view); coders only fan out after partition is planned.
    - `/workflows` shows progress; press `x` to stop the workflow if the partition looks wrong.
    - Once it completes, `/build-fleet:status` shows the verdict. Next legal command depends on verdict:
      - `clean` → `/build-fleet:handoff` (runs CHANGE_REVIEW + devops).
      - `needs-iteration` → `/build-fleet:deep-build` again to re-run. The return envelope carries `cycles_remaining`; the budget is 3 build cycles tracked in PROGRESS.md's `BUILD_CYCLE` field. The workflow re-plans the partition each run, so iterations are expensive — read the surviving concerns in IMPL_NOTES.md before re-running.
      - `escalate` → genuine cycle exhaustion: blockers survived the adversarial review on the cycle that exhausted the 3-cycle budget. The scribe writes ESCALATION.md and sets `PHASE: ESCALATED`; human action required.
      - `incomplete` → a transient fault (architect/coder/reviewer returned no usable payload, or the partition plan was unusable/overlapping). PHASE/BUILD_CYCLE are unchanged, nothing was recorded, and the marker was cleaned up — but **if coders had already fanned out, partial writes may exist in the worktree**: surface the result's `note` and tell the user to inspect `git status`/`git diff` before re-running.
      - `invalid-args` → the dispatch args were malformed; nothing ran. Fix the dispatch and re-run.
    - **Scribe-apply failure is a hard failure.** If the completed run's return object carries `scribe_apply: "failed"`, the scribe could not write state even after a retry: IMPL_NOTES.md/PROGRESS.md did **not** land (though coders may have written source) and the marker may remain (release it if its content matches your run id). Whoever reads that result must report the run as failed with its `scribe_error` — never treat the verdict as applied or advance to `/build-fleet:handoff`.

## What this command does NOT do

- Does not draft tests. `/build-fleet:build` already dispatched qa for that. Deep-build assumes the failing test suite exists.
- Does not bump PHASE, `BUILD_CYCLE`, or run CHANGE_REVIEW. The workflow's scribe writes `BUILD_CYCLE` (and the rest of the BUILD-completion delta) via the envelope's `state_delta`; this command only normalizes a missing `BUILD_CYCLE: 0` field pre-dispatch. CHANGE_REVIEW is `/build-fleet:handoff`'s job.
- Does not write source. Only its coder subagents (inside the workflow) write source — each restricted to its partition.
- Does not release `.workflow-in-flight` on success. Scribe does that as the final phase (only when the marker still contains this run's id; it empties the marker and the reaper deletes the empty file).
- Does not persist `BUILD_CYCLE_BUDGET`. The durable default lives in `.sdd/<slug>/PROGRESS.md` (scaffolded by `/build-fleet:new-feature`; the scribe preserves it); a `--cycle-budget` flag overrides it for this run only.

## Cleanup obligation

If `.workflow-in-flight` was created and the Workflow tool fails to launch (returns `error`), release the marker — verify its content still matches your run id, then overwrite it with empty content — then report the failure with `BUILD_FLEET_REFUSE: {"command":"deep-build","code":1,"reason":"workflow-launch-failed"}` and the tool's error. The same ownership rule applies to the post-launch liveness check (step 13): a dead run plus a marker still containing this run's id means you release it; a marker with different content belongs to a newer dispatch and must be left alone.

## The BUILD_CYCLE field

`BUILD_CYCLE: <n>` in `.sdd/<slug>/PROGRESS.md` counts completed deep-build runs for the active feature, exactly as `CYCLE` counts REVIEW cycles (and `CHANGE_CYCLE` counts CHANGE_REVIEW cycles). This command reads it and passes `BUILD_CYCLE + 1` as the workflow's `cycle` arg; the workflow's scribe writes the new value back. Budget: 3 — the workflow escalates on the exhausting cycle, and its `needs-iteration` envelope carries `cycles_remaining` so headless orchestrators cannot loop the workflow forever.

## Refusal contract (machine-readable)

A slash command runs inside the model session and **cannot set a process exit
code** — the session exits 0 either way. The `BUILD_FLEET_*` signal lines on
stdout are the **sole machine contract**. Every refusal emits exactly one
`BUILD_FLEET_REFUSE:` line whose JSON carries `"code"` (an integer preserving
the legacy exit-code semantics: `2` = pre-dispatch validation refused, `3` =
workflow runtime unavailable, `1` = workflow tool launch error) and `"reason"`
(a kebab-case slug). Orchestrators dispatch on the signal line — and on the
`BUILD_FLEET_WORKFLOW_LAUNCHED` line for success — never on the process exit
status.
