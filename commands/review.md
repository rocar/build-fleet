---
description: Run the adversarial spec-review workflow
allowed-tools: Read, Write, Workflow
---

# /build-fleet:review

You are the **orchestrator**. The runtime rulebook is the `sdd-protocol` skill. The REVIEW phase runs as a Claude Code [dynamic workflow](https://code.claude.com/docs/en/workflows). This command validates preconditions, sets up the workflow handoff, and dispatches the workflow. The workflow (`workflows/review.js`) does the actual fan-out, cross-examination, survival vote, and state-mutation-via-scribe.

## Workflow runtime requirement

The `Workflow` tool must be available. This requires:

- Claude Code v2.1.154 or later
- Workflows enabled in `/config` (Pro plans) — or available by default on Max/Team/Enterprise
- `Workflow` in the session's `allowedTools` (e.g., for headless callers: `claude -p --allowedTools "Workflow,Read,Edit,Write,Bash,Agent" '/build-fleet:review'`)

There is no non-workflow fallback for REVIEW. If the runtime is missing, refuse with the `workflow-runtime-unavailable` signal below and tell the user how to enable workflows.

## What you do

1. **Verify the workflow runtime.** Check that the `Workflow` tool is available. If absent, refuse:
   > `BUILD_FLEET_REFUSE: {"command":"review","code":3,"reason":"workflow-runtime-unavailable"}`
   then tell the user the review workflow requires Claude Code v2.1.154+ with workflows enabled (see ROADMAP.md).

2. **Resolve the active feature.** Read `.sdd/ACTIVE`. If empty, refuse with `BUILD_FLEET_REFUSE: {"command":"review","code":2,"reason":"no-active-feature"}`.

3. **Check phase.** Read `.sdd/<slug>/PROGRESS.md`. If `PHASE` is not `SPEC` or `REVIEW`, refuse (`{"command":"review","code":2,"reason":"wrong-phase","phase":"<PHASE>"}`).

4. **Check for prior escalation.** If `.sdd/<slug>/ESCALATION.md` exists, refuse (`{"command":"review","code":2,"reason":"escalation-present"}`) — tell the user to read it and resolve it with `/build-fleet:resolve-escalation <decision>` (or park the feature).

5. **Check the cycle budget.** Read `CYCLE:` from PROGRESS.md. The budget is **3 review cycles**, and the workflow escalates **on** the cycle that exhausts it: if blockers still survive the survival vote at cycle 3, that run writes ESCALATION.md and sets `PHASE: ESCALATED` (there is no separate "4th cycle" — cycle 3 with surviving blockers is the escalation). This refusal is a belt-and-suspenders guard for the edge where CYCLE is already ≥ 3 without a recorded escalation: if `CYCLE >= 3` AND the most recent REVIEW.md cycle still has open `[blocker]` items, refuse — a further run can only escalate, and the workflow owns that write. Refuse with: `BUILD_FLEET_REFUSE: {"command":"review","code":2,"reason":"cycle-budget-exhausted","cycle":<n>}` — the budget is 3 cycles and the workflow escalates on the exhausting cycle; resolve blockers in spec.md or accept the escalation.

6. **Pick the new cycle number.** New cycle = `CYCLE + 1`. Pass to the workflow.

7. **Compose the run id and drop the workflow-in-flight marker.** Compose a run id: `review-<slug>-c<new_cycle>-<iso8601 now>` (the same `now` you pass to the workflow in step 9). Write `.sdd/<slug>/.workflow-in-flight` containing exactly that run id as its single line. The hooks `check-review-written` and `restrict-reviewer-writes` skip their gates while this marker exists. The marker is **owned by this run**: the workflow's scribe releases it only if its content still matches the envelope's `run_id`, so a stale or retried run can never release a newer dispatch's marker. Cleanup obligation: if you create this marker and the Workflow tool subsequently fails to launch, release the marker yourself — verify its content still matches your run id, then overwrite it with empty content (an empty marker counts as released; the Stop-hook reaper deletes it) — before exiting.

8. **Emit the cost preview (headless mode contract).** Parse the `@cost-ceiling` header comment at the top of `${CLAUDE_PLUGIN_ROOT}/workflows/review.js`. Write exactly one stdout line — JSON payload for parsability:

   ```
   BUILD_FLEET_COST_PREVIEW: {"workflow":"review","feature":"<slug>","cycle":<N>,"input_ceiling":<N>,"output_ceiling":<N>}
   ```

   This substitutes for the interactive launch-prompt's token caution. Orchestrators (Hermes) parse this line and may surface it for human approval before the workflow runs.

9. **Invoke the Workflow tool.** Call `Workflow` with:
   - `scriptPath`: `${CLAUDE_PLUGIN_ROOT}/workflows/review.js`
   - `args`: `{ "feature": "<slug>", "cycle": <new_cycle>, "now": "<iso8601>", "run_id": "<run id from step 7>" }`

   Supply `now` yourself (the script cannot call `Date`); the workflow refuses to run without it. The Workflow tool is async-launched: it returns immediately with a `runId`, `taskId`, and `transcriptDir`.

10. **Emit the launch line (headless mode contract).** Once the Workflow tool returns, write exactly one stdout line:

    ```
    BUILD_FLEET_WORKFLOW_LAUNCHED: {"runId":"<id>","transcriptDir":"<path>","status":"async_launched","feature":"<slug>","cycle":<N>}
    ```

    Orchestrators consume this line to track the workflow's progress (poll via `TaskList`/`TaskGet` until completion).

11. **Verify the run is alive (marker ownership).** The marker from step 7 is normally deleted by the workflow's scribe. After emitting the launch line, poll the launched run once (`TaskGet` on the returned task). If the run has already died (errored/cancelled) before any scribe ran, release `.sdd/<slug>/.workflow-in-flight` yourself — **only if its content still matches your run id**, by overwriting it with empty content — then report the failure instead of step 12's success message. Orchestrators polling later must apply the same rule: dead run + marker content matching this run id → release the marker.

12. **Report and exit.** Tell the user:
    - The workflow is running in the background.
    - `/workflows` shows progress (in interactive mode).
    - Once it completes, `/build-fleet:status` will show the verdict.
    - Next legal command depends on the workflow's verdict:
      - `clean` → `/build-fleet:finalize` (the gate), then `/build-fleet:build`
      - `revise` → `/build-fleet:review` again after PO revises spec.md
      - `escalate` → human action on the ESCALATION.md the workflow writes (the budget is 3 cycles; the workflow escalates on the exhausting cycle)
      - `incomplete` / `invalid-args` → a transient agent fault or bad dispatch args; PHASE/CYCLE are unchanged and nothing was written — re-run `/build-fleet:review` (or fix the dispatch args).
    - **Scribe-apply failure is a hard failure.** If the completed run's return object carries `scribe_apply: "failed"`, the scribe could not write state even after a retry: REVIEW.md/PROGRESS.md did **not** land and the marker may remain (release it if its content matches your run id). Whoever reads that result (you, `/build-fleet:status`, or an orchestrator) must report the run as failed with its `scribe_error` — never treat the verdict as applied or advance to the next command.

## What this command does NOT do

- Does not bump `PHASE` or `CYCLE` in PROGRESS.md. The workflow's scribe writes those via the envelope's `state_delta` on completion. Pre-bumping by this command would trip the hooks before the workflow could write its marker bypass.
- Does not append to REVIEW.md. The workflow's reviewer subagents return structured payloads; the scribe appends the canonical entries.
- Does not write ESCALATION.md. The workflow detects budget-exhaustion and writes via the envelope.
- Does not release `.workflow-in-flight` on success. The scribe does that as the final phase (it empties the marker; the reaper deletes the empty file).

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
