---
description: DIAGNOSE phase of the bug lane — gate the recorded root-cause hypothesis, then dispatch the diagnose.js confirmation workflow (inverted survival vote; architect + coder try to refute the hypothesis citing the reproduction)
argument-hint: ""
allowed-tools: Read, Write, Edit, Workflow
---

# /build-fleet:diagnose

You are the **orchestrator**. The DIAGNOSE phase runs as a Claude Code dynamic workflow
(`workflows/diagnose.js`) — the bug-lane analog of `/build-fleet:review` → `review.js`, with
the survival vote **inverted**: a root-cause *hypothesis* is CONFIRMED iff no substantive,
different-role, reproduction-citing refutation survives. This command validates preconditions,
records the DIAGNOSED transition, and dispatches the workflow. The workflow does the fan-out,
cross-examination, vote, and state-mutation-via-scribe.

Rulebook: the `sdd-protocol` skill (bug-lane sections); `sdd-diagnosis-template` for the
artifact.

## Workflow runtime requirement

The `Workflow` tool must be available (Claude Code v2.1.154+, workflows enabled; in
`allowedTools` for headless callers). If absent, refuse:
> `BUILD_FLEET_REFUSE: workflow runtime unavailable. The bug lane's DIAGNOSE phase requires Claude Code v2.1.154+ with workflows enabled. Exit 3.`

## What you do

1. **Verify the workflow runtime.** Absent → refuse, exit 3 (as above).

2. **Resolve the active bug.** Read `.sdd/ACTIVE`. Empty → `BUILD_FLEET_REFUSE: no active item`, exit 2.
   Read `.sdd/<slug>/PROGRESS.md`; if `LANE` ≠ `bug` → refuse (`<slug> is a forward feature — use /build-fleet:review`), exit 2.

3. **Check phase.** `PHASE` must be `REPRODUCE` or `DIAGNOSE` (first run advances from
   REPRODUCE; a re-run after a `refuted` verdict is already at DIAGNOSE). Otherwise refuse and
   name the actual phase, exit 2.

4. **Check for prior escalation.** If `.sdd/<slug>/ESCALATION.md` exists → refuse; tell the
   user to read it and either revise the hypothesis (clear it) or abandon the bug. Exit 2.

5. **Gate on a recorded hypothesis (AC-8).** Read `.sdd/<slug>/diagnosis.md`. The
   `## Root-cause hypothesis`, `## Blast radius`, and `## Fix strategy` sections must each be
   **non-empty** — i.e. real content, not the `_(empty until DIAGNOSE)_` placeholder. If the
   **hypothesis** section is still empty/placeholder, refuse with a one-line reason naming the
   missing section:
   > `BUILD_FLEET_REFUSE: diagnosis.md § Root-cause hypothesis is empty — record a hypothesis (and blast radius + fix strategy) before diagnosing.`
   Exit 2. (Whoever holds the reproduction writes the hypothesis into `diagnosis.md` first.)

6. **Advance to DIAGNOSED.** If `diagnosis.md` STATUS is `REPRODUCING`, flip it to `DIAGNOSED`
   (keep all four `##` sections). Edit `.sdd/<slug>/PROGRESS.md` `PHASE: → DIAGNOSE`, refresh
   `UPDATED`. (Both are `.sdd/` writes — always gate-permitted.)

6b. **sev0 hotfix fast-path (B11 / AC-22) — skip the confirmation workflow.** Read `SEV` from
   PROGRESS.md. If `SEV == sev0`, the hotfix path **may skip** the adversarial confirmation. After
   the DIAGNOSED advance (step 6), do **not** drop the marker or dispatch `diagnose.js`. Emit:
   ```
   BUILD_FLEET_DIAGNOSE_SEV0_SKIP: {"slug":"<slug>","reason":"sev0 hotfix — adversarial confirmation deferred to post-ship"}
   ```
   and tell the user to run **`/build-fleet:fix`** directly — it takes the bug from
   `PHASE: DIAGNOSE` / STATUS `DIAGNOSED`, flips `diagnosis.md` → `CONFIRMED` via the fast-path, and
   records the post-hoc obligation (`BUILD_FLEET_POSTHOC_DIAGNOSIS_DUE`). The reproducing-test gate
   still holds. **Stop here** (no workflow). `sev1`/`sev2` continue to step 7. *(An operator who
   wants full confirmation on a `sev0` can lower `SEV` in PROGRESS.md before re-running.)*

7. **Check the cycle budget.** Read `CYCLE`. If `CYCLE >= 3` and the most recent diagnose cycle
   in `REVIEW.md` still records a surviving refutation, refuse — the next run would escalate;
   let the workflow own that write only on a fresh attempt. Exit 2:
   > `BUILD_FLEET_REFUSE: cycle budget exhausted (CYCLE=<n>); the next /build-fleet:diagnose will escalate. Revise the hypothesis in diagnosis.md or accept the escalation.`

8. **Pick the new cycle.** `new_cycle = CYCLE + 1`.

9. **Drop the workflow-in-flight marker.** Write `.sdd/<slug>/.workflow-in-flight` with one
   iso8601 line. The scribe deletes it in the workflow's final phase. **Cleanup obligation:** if
   you create the marker and the `Workflow` tool then fails to launch, delete the marker before exiting.

10. **Emit the cost preview** (parse the `@cost-ceiling` header comment of
    `${CLAUDE_PLUGIN_ROOT}/workflows/diagnose.js`):
    ```
    BUILD_FLEET_COST_PREVIEW: {"workflow":"diagnose","slug":"<slug>","cycle":<N>,"input_ceiling":<N>,"output_ceiling":<N>}
    ```

11. **Invoke the Workflow tool** with:
    - `scriptPath`: `${CLAUDE_PLUGIN_ROOT}/workflows/diagnose.js`
    - `args`: `{ "slug": "<slug>", "cycle": <new_cycle>, "now": "<iso8601>" }`

12. **Emit the launch line** once the tool returns:
    ```
    BUILD_FLEET_WORKFLOW_LAUNCHED: {"runId":"<id>","transcriptDir":"<path>","status":"async_launched","slug":"<slug>","cycle":<N>,"workflow":"diagnose"}
    ```

13. **Report and exit.** The workflow runs in the background (`/workflows` shows progress;
    `/build-fleet:status` shows the verdict on completion). Next legal command by verdict:
    - `confirmed` → **`/build-fleet:fix`** — the FIX gate reads the confirmed verdict, flips
      `diagnosis.md` → `CONFIRMED` + `PHASE` → `FIX`, then implements the fix.
    - `refuted` → revise `diagnosis.md`'s hypothesis, then re-run `/build-fleet:diagnose`.
    - `escalate` → human action on the `ESCALATION.md` the workflow's scribe writes.

## The CONFIRMED flip is the FIX gate's job (not this command)

The `diagnose.js` workflow is **async-launched**: this command dispatches it and returns; the
scribe records the verdict (`REVIEW.md` + `PROGRESS.md` CYCLE) on completion. The
`diagnosis.md` STATUS → `CONFIRMED` + `PHASE` → `FIX` flip is applied by **`/build-fleet:fix`**
when it reads a `confirmed` verdict — exactly as `/build-fleet:finalize` (not `/build-fleet:review`)
flips a spec to `FINALIZED` after the async review. This keeps the deterministic STATUS flip in a
synchronous gate command rather than inside the fire-and-forget workflow.

## What this command does NOT do

- Does not flip `diagnosis.md` to `CONFIRMED` — that is `/build-fleet:fix`'s gate (above).
- Does not append to `REVIEW.md` or write `ESCALATION.md` — the workflow's scribe does, via the envelope.
- Does not delete `.workflow-in-flight` on success — the scribe does, as the final phase.

## Exit codes

| Exit | Meaning |
|---|---|
| 0 | Workflow launched; runId emitted |
| 1 | Workflow tool returned an error (e.g. script syntax check failed) — surface it |
| 2 | Pre-dispatch validation failed (no active bug, wrong phase/lane, no hypothesis, escalation present, budget exhausted) |
| 3 | Workflow runtime unavailable |
