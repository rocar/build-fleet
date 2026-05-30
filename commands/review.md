---
description: Run a v0.2 review workflow on the active feature — fan-out + cross-examination + survival vote, applied via scribe
argument-hint: ""
allowed-tools: Read, Write, Workflow
---

# /build-fleet:review

You are the **orchestrator**. The runtime rulebook is the `sdd-protocol` skill. In v0.2, the REVIEW phase runs as a Claude Code [dynamic workflow](https://code.claude.com/docs/en/workflows). This command validates preconditions, sets up the workflow handoff, and dispatches the workflow. The workflow (`workflows/review.js`) does the actual fan-out, cross-examination, survival vote, and state-mutation-via-scribe.

## Workflow runtime requirement (v0.2)

The `Workflow` tool must be available. This requires:

- Claude Code v2.1.154 or later
- Workflows enabled in `/config` (Pro plans) — or available by default on Max/Team/Enterprise
- `Workflow` in the session's `allowedTools` (e.g., for headless callers: `claude -p --allowedTools "Workflow,Read,Edit,Write,Bash,Agent" '/build-fleet:review'`)

v0.2 does not gracefully fall back to v0.1's command pipeline. If the runtime is missing, refuse with exit code 3 (graceful-fallback signal) and tell the user how to enable workflows.

## What you do

1. **Verify the workflow runtime.** Check that the `Workflow` tool is available. If absent, refuse:
   > `BUILD_FLEET_REFUSE: workflow runtime unavailable. v0.2 requires Claude Code v2.1.154+ with workflows enabled (see ROADMAP.md). Exit 3.`

2. **Resolve the active feature.** Read `.sdd/ACTIVE`. If empty, refuse with `BUILD_FLEET_REFUSE: no active feature`. Exit 2.

3. **Check phase.** Read `.sdd/<slug>/PROGRESS.md`. If `PHASE` is not `SPEC` or `REVIEW`, refuse and name the actual phase. Exit 2.

4. **Check for prior escalation.** If `.sdd/<slug>/ESCALATION.md` exists, refuse — tell the user to read it and either resolve the deadlock or start a new feature. Exit 2.

5. **Check the cycle budget.** Read `CYCLE:` from PROGRESS.md. If `CYCLE >= 3` AND the most recent REVIEW.md cycle still has open `[blocker]` items, refuse — the next workflow invocation would trip the escalation path inside the workflow itself, but let the workflow own that write. Exit 2 with: `BUILD_FLEET_REFUSE: cycle budget exhausted (CYCLE=<n>); next /build-fleet:review will escalate. Resolve blockers in spec.md or accept the escalation.`

6. **Pick the new cycle number.** New cycle = `CYCLE + 1`. Pass to the workflow.

7. **Drop the workflow-in-flight marker.** Write `.sdd/<slug>/.workflow-in-flight` containing a single line with the current iso8601 timestamp. The hooks `check-review-written` and `restrict-reviewer-writes` skip their gates while this marker exists. The scribe deletes it as part of the workflow's final phase. Cleanup obligation: if you create this marker and the Workflow tool subsequently fails to launch, delete the marker before exiting.

8. **Emit the cost preview (headless mode contract).** Read the `estimatedCost` field from the top of `${CLAUDE_PLUGIN_ROOT}/workflows/review.js` (parse the `meta` block). Write exactly one stdout line — JSON payload for parsability:

   ```
   BUILD_FLEET_COST_PREVIEW: {"workflow":"review","feature":"<slug>","cycle":<N>,"input_ceiling":<N>,"output_ceiling":<N>}
   ```

   This substitutes for the interactive launch-prompt's token caution. Orchestrators (Hermes) parse this line and may surface it for human approval before the workflow runs.

9. **Invoke the Workflow tool.** Call `Workflow` with:
   - `scriptPath`: `${CLAUDE_PLUGIN_ROOT}/workflows/review.js`
   - `args`: `{ "feature": "<slug>", "cycle": <new_cycle> }`

   The Workflow tool is async-launched: it returns immediately with a `runId`, `taskId`, and `transcriptDir`.

10. **Emit the launch line (headless mode contract).** Once the Workflow tool returns, write exactly one stdout line:

    ```
    BUILD_FLEET_WORKFLOW_LAUNCHED: {"runId":"<id>","transcriptDir":"<path>","status":"async_launched","feature":"<slug>","cycle":<N>}
    ```

    Orchestrators consume this line to track the workflow's progress (poll via `TaskList`/`TaskGet` until completion).

11. **Report and exit.** Tell the user:
    - The workflow is running in the background.
    - `/workflows` shows progress (in interactive mode).
    - Once it completes, `/build-fleet:status` will show the verdict.
    - Next legal command depends on the workflow's verdict:
      - `clean` → `/build-fleet:finalize`
      - `revise` → `/build-fleet:review` again after PO revises spec.md
      - `escalate` → human action on the ESCALATION.md the workflow writes

## Exit codes

| Exit | Meaning |
|---|---|
| 0 | Workflow launched successfully; runId emitted |
| 1 | Workflow tool returned an error field (e.g., script syntax check failed) — surface the error |
| 2 | Pre-dispatch validation failed (active empty, wrong phase, escalation present, budget exhausted) |
| 3 | Workflow runtime not available — caller should upgrade Claude Code or enable workflows |

## What this command does NOT do

- Does not bump `PHASE` or `CYCLE` in PROGRESS.md. The workflow's scribe writes those via the envelope's `state_delta` on completion. Pre-bumping by this command would trip the hooks before the workflow could write its marker bypass.
- Does not append to REVIEW.md. The workflow's reviewer subagents return structured payloads; the scribe appends the canonical entries.
- Does not write ESCALATION.md. The workflow detects budget-exhaustion and writes via the envelope.
- Does not delete `.workflow-in-flight` on success. The scribe does that as the final phase.

## Refusal contract (machine-readable)

All refusals begin with a line prefixed `BUILD_FLEET_REFUSE: ` for orchestrator consumption. Exit codes as above.
