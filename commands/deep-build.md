---
description: Run the v0.2 deep-build workflow — architect plans file partition, N coders fan out in parallel against M2's failing tests, adversarial review catches integration gaps before BUILD declares complete
argument-hint: "[max_partitions]"
allowed-tools: Read, Write, Workflow
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

6. **Parse arguments.** If `$ARGUMENTS` is an integer in `[1, 8]`, use it as `max_partitions`. Otherwise default to `3`.

7. **Drop the workflow-in-flight marker.** Write `.sdd/<slug>/.workflow-in-flight` with the current iso8601. Hooks will skip while present; scribe removes it on workflow completion.

8. **Emit the cost preview (headless mode contract).** Parse the `estimatedCost` field from the top of `${CLAUDE_PLUGIN_ROOT}/workflows/deep-build.js`. Emit one stdout line:

   ```
   BUILD_FLEET_COST_PREVIEW: {"workflow":"deep-build","feature":"<slug>","max_partitions":<N>,"input_ceiling":<N>,"output_ceiling":<N>}
   ```

9. **Invoke the Workflow tool.** Call `Workflow` with:
   - `scriptPath`: `${CLAUDE_PLUGIN_ROOT}/workflows/deep-build.js`
   - `args`: `{ "feature": "<slug>", "max_partitions": <N> }`

10. **Emit the launch line.** Once the Workflow tool returns:

    ```
    BUILD_FLEET_WORKFLOW_LAUNCHED: {"runId":"<id>","transcriptDir":"<path>","status":"async_launched","feature":"<slug>","workflow":"deep-build","max_partitions":<N>}
    ```

11. **Report and exit.** Tell the user:
    - The workflow is running in the background. Architect plans the partition first (visible in `/workflows` progress view); coders only fan out after partition is planned.
    - `/workflows` shows progress; press `x` to stop the workflow if the partition looks wrong.
    - Once it completes, `/build-fleet:status` shows the verdict. Next legal command depends on verdict:
      - `clean` → `/build-fleet:handoff` (runs CHANGE_REVIEW + devops).
      - `needs-iteration` → `/build-fleet:deep-build` again to re-run. **M3 does not track a deep-build cycle counter** — there is no auto-escalation after N retries. The workflow re-plans the partition each run (no `resumeFromRunId` reuse in M3 — see VERIFY-AT-M1 in CONTRACT.md), so iterations are expensive. Cycle-bounded escalation is M3.1 / Phase 5 hardening.
      - `escalate` → **M3 only emits this on workflow malfunction** (spec not finalized at workflow entry, no tests present, partition planning failed, file-overlap detected in partition, reviewer/coder returned unparseable payload). On `escalate`, the scribe writes ESCALATION.md; human action required.

## Exit codes

| Exit | Meaning |
|---|---|
| 0 | Workflow launched successfully |
| 1 | Workflow tool returned an error field |
| 2 | Pre-dispatch validation failed (active empty, wrong phase, no tests, escalation present) |
| 3 | Workflow runtime not available |

## What this command does NOT do

- Does not draft tests. M2's `/build-fleet:finalize` already dispatched qa for that. Deep-build assumes the failing test suite exists.
- Does not bump PHASE or run CHANGE_REVIEW. The workflow's scribe handles the BUILD-completion delta; CHANGE_REVIEW is `/build-fleet:handoff`'s job.
- Does not write source. Only its coder subagents (inside the workflow) write source — each restricted to its partition.
- Does not delete `.workflow-in-flight` on success. Scribe does that as the final phase.

## Cleanup obligation

If `.workflow-in-flight` was created and the Workflow tool fails to launch (returns `error`), delete the marker before exiting with exit code 1.

## Refusal contract

All refusals begin with `BUILD_FLEET_REFUSE: ` for orchestrator consumption. Exit codes as above.
