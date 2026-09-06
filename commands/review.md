---
description: Run the adversarial spec-review workflow
argument-hint: "[--roles <r1,r2,...>] [--cycle-budget <1-3>] [--override-cost]"
allowed-tools: Read, Write, Workflow, Bash(date:*), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-rotate.sh":*), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/adr-index.sh":*)
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

5. **Resolve the review config, then check the cycle budget.**

   **The reviewer roster and the cycle budget are configurable** (default roster `architect, qa, coder`; default budget `3`). Resolve each from two sources — **a per-run flag wins over the durable PROGRESS.md default**:
   - **roster**: `--roles <r1,r2,...>` in `$ARGUMENTS` → else `REVIEW_ROLES:` in PROGRESS.md → else unset. A roster is a comma-separated, ≥2-element subset of `architect, qa, coder, product-owner`.
   - **budget**: `--cycle-budget <n>` flag → else `REVIEW_CYCLE_BUDGET:` in PROGRESS.md → else `3`. Call the resolved integer `effective_budget` (treat unset as `3`); clamp it to `1..3` for the precondition below — the workflow re-clamps anything above the 3-cycle ceiling.

   The **workflow is the authoritative validator**: pass the resolved values straight through (step 9) and let `review.js` reject a malformed roster/budget via its `invalid-args` path — do **not** re-implement the allowed-role list or bounds here (that would drift). Do **not** write these into PROGRESS.md; a flag override applies to this run only and is recorded by the config signal line in step 8.

   **Cycle-budget precondition.** The workflow escalates **on** the cycle that exhausts `effective_budget`: if open blockers or `fix`-dispositioned majors remain at `CYCLE == effective_budget`, that run writes ESCALATION.md and sets `PHASE: ESCALATED` (there is no separate "next cycle" — the exhausting cycle with surviving blockers *is* the escalation). This refusal is a belt-and-suspenders guard for the edge where `CYCLE` is already `>= effective_budget` without a recorded escalation: if `CYCLE >= effective_budget` AND the most recent REVIEW.md cycle still has open `[blocker]` items or `disposition: fix` majors, refuse — a further run can only escalate, and the workflow owns that write. Refuse with: `BUILD_FLEET_REFUSE: {"command":"review","code":2,"reason":"cycle-budget-exhausted","cycle":<n>,"cycle_budget":<effective_budget>}` — resolve blockers in spec.md or accept the escalation.

   **Cumulative-cycle precondition (v0.9).** Read `CYCLE_TOTAL` (absent ⇒ use `CYCLE`)
   and `CYCLE_TOTAL_MAX` (absent ⇒ `6`; `0` disables). `CYCLE_TOTAL` never resets —
   not on resolve-escalation, not on park — so it is the bound the per-escalation
   budget is not. If `CYCLE_TOTAL_MAX` is not `0` and `CYCLE_TOTAL >= CYCLE_TOTAL_MAX`, refuse **before dispatch**:
   `BUILD_FLEET_REFUSE: {"command":"review","code":2,"reason":"cycle-total-exhausted","cycle_total":<n>,"max":<m>}`
   and lay out the three options: cut the feature's scope so the open findings stop
   mattering; finalize what exists and file the remainder as a follow-up feature; or
   raise `CYCLE_TOTAL_MAX` in PROGRESS.md deliberately (a recorded decision). This
   refusal is placed at dispatch on purpose — the pilot's post-hoc guard fired only
   after a cycle had already cost ~866k tokens.

   **Cost-runaway precondition (v0.9).** Read `LAST_REVIEW_OUTPUT_TOKENS` (absent ⇒
   skip). Parse the `@cost-ceiling` header's `output_tokens` (step 8). If the last
   value exceeds 3× that ceiling and `--override-cost` is not in `$ARGUMENTS`, refuse:
   `BUILD_FLEET_REFUSE: {"command":"review","code":2,"reason":"cost-runaway","last_output_tokens":<n>,"ceiling":<c>}`
   and say the spec/inputs should shrink (split, or cut) before another cycle; pass
   `--override-cost` to run anyway (recorded by the config line).

6. **Pick the new cycle number.** New cycle = `CYCLE + 1`. Pass to the workflow.

6b. **Rotate REVIEW.md (v0.9).** Bound the reviewers' input to the previous cycle by
   ALWAYS running the deterministic rotation — never do this by hand:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-rotate.sh" "<slug>"
   ```
   (add `--roster <N>` when a `--roles` flag changed the roster size). It moves every
   block older than the last roster-sized run of `## Cycle` blocks into
   `.sdd/<slug>/REVIEW-archive.md` (append-only) and prints one
   `BUILD_FLEET_REVIEW_ROTATED: {...}` line — relay it. Idempotent; a no-op when there
   is nothing older than the kept run (e.g. cycle 0, or the first cycle after a reset
   once the old log was already rotated).

6c. **Compute `next_adr_id` and `cycle_total`.**
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/adr-index.sh" ".sdd/<slug>/DECISIONS.md" --next
   ```
   prints the next free feature ADR integer (1 for an empty/absent log); the workflow's
   disposition leg numbers its ADRs from it. `cycle_total` is the `CYCLE_TOTAL` value
   read in step 5 (or `CYCLE` when absent) — the count BEFORE this run.

7. **Compose the run id and drop the workflow-in-flight marker.** Compute `now` as `date -u +%Y-%m-%dT%H:%M:%SZ` — never guess it — and compose the run id `review-<slug>-c<new_cycle>-<now>` (the same `now` you pass to the workflow in step 9). Write `.sdd/<slug>/.workflow-in-flight` containing exactly that run id as its single line. The hooks `check-review-written` and `restrict-reviewer-writes` skip their gates while this marker exists. The marker is **owned by this run**: the workflow's scribe releases it only if its content still matches the envelope's `run_id`, so a stale or retried run can never release a newer dispatch's marker. Cleanup obligation: if you create this marker and the Workflow tool subsequently fails to launch, release the marker yourself — verify its content still matches your run id, then overwrite it with empty content (an empty marker counts as released; the Stop-hook reaper deletes it) — before exiting.

8. **Emit the cost preview (headless mode contract).** Parse the `@cost-ceiling` header comment at the top of `${CLAUDE_PLUGIN_ROOT}/workflows/review.js`. Write exactly one stdout line — JSON payload for parsability:

   ```
   BUILD_FLEET_COST_PREVIEW: {"workflow":"review","feature":"<slug>","cycle":<N>,"input_ceiling":<N>,"output_ceiling":<N>}
   ```

   This substitutes for the interactive launch-prompt's token caution. Orchestrators (Hermes) parse this line and may surface it for human approval before the workflow runs.

   Then emit exactly one **review-config** line recording the effective roster + budget and where each came from — this is what makes a flag override (which is not persisted) auditable in the run log:

   ```
   BUILD_FLEET_REVIEW_CONFIG: {"feature":"<slug>","cycle":<N>,"roles":<["..."] | "default">,"cycle_budget":<n | "default">,"roles_source":"flag"|"progress"|"default","budget_source":"flag"|"progress"|"default","cycle_total":<n>,"next_adr_id":<n>,"override_cost":<true|false>}
   ```

9. **Invoke the Workflow tool.** Call `Workflow` with:
   - `scriptPath`: `${CLAUDE_PLUGIN_ROOT}/workflows/review.js`
   - `args`: `{ "feature": "<slug>", "cycle": <new_cycle>, "now": "<now>", "run_id": "<run id from step 7>", "cycle_total": <cycle_total from 6c>, "next_adr_id": <next_adr_id from 6c> }` — **plus** `"roles": [<resolved roster>]` and/or `"cycle_budget": <resolved int>` ONLY when they were resolved from a flag or a `REVIEW_*` PROGRESS.md field in step 5. **Omit those two keys entirely when unset** so the workflow applies its own default.

   The `now` is the one you computed with `date -u` in step 7 (the script cannot call `Date`); the workflow refuses to run without it. The Workflow tool is async-launched: it returns immediately with a `runId`, `taskId`, and `transcriptDir`.

10. **Emit the launch line (headless mode contract).** Once the Workflow tool returns, write exactly one stdout line:

    ```
    BUILD_FLEET_WORKFLOW_LAUNCHED: {"runId":"<id>","transcriptDir":"<path>","status":"async_launched","feature":"<slug>","cycle":<N>}
    ```

    Orchestrators consume this line to track the workflow's progress (poll via `TaskList`/`TaskGet` until completion).

11. **Verify the run is alive (marker ownership).** The marker from step 7 is normally deleted by the workflow's scribe. After emitting the launch line, poll the launched run once (`TaskGet` on the returned task). If the run has already died (errored/cancelled) before any scribe ran, release `.sdd/<slug>/.workflow-in-flight` yourself — **only if its content still matches your run id**, by overwriting it with empty content — then report the failure instead of step 12's success message. Orchestrators polling later must apply the same rule: dead run + marker content matching this run id → release the marker.

12. **Report and exit.** Tell the user:
    - The workflow is running in the background.
    - The effective reviewer roster and cycle budget for this run — and note if a `--roles`/`--cycle-budget` flag overrode the PROGRESS.md default (the override applies to this run only and is not persisted).
    - `/workflows` shows progress (in interactive mode).
    - Once it completes, `/build-fleet:status` will show the verdict.
    - The run's return object carries `finalize_ready`, `open_majors`, `adrs_written`,
      `cycle_total` and `output_tokens`. Next legal command:
      - `finalize_ready: true` (zero blockers, every major accepted via ADR) →
        `/build-fleet:finalize` (the gate), then `/build-fleet:build`.
      - `finalize_ready: false` with `verdict` `clean` or `revise` → `/build-fleet:revise`
        (hands the PO exactly the open blockers + `fix` majors), then `/build-fleet:review`.
      - `escalate` → human action on the ESCALATION.md the workflow wrote (it lists both
        surviving blockers and open `fix` majors; the exhausting cycle escalates either).
      - `incomplete` / `invalid-args` → a transient agent fault or bad dispatch args;
        PHASE/CYCLE are unchanged and nothing was written — re-run `/build-fleet:review`
        (or fix the dispatch args). `incomplete` with `reason: disposition-incomplete` means
        the architect leg missed a major — re-run.
      Note `verdict: clean` means zero surviving BLOCKERS and is NOT finalize-readiness;
      `finalize_ready` is.
    - **Scribe-apply failure is a hard failure.** If the completed run's return object carries `scribe_apply: "failed"`, the scribe could not write state even after a retry: REVIEW.md/PROGRESS.md did **not** land and the marker may remain (release it if its content matches your run id). Whoever reads that result (you, `/build-fleet:status`, or an orchestrator) must report the run as failed with its `scribe_error` — never treat the verdict as applied or advance to the next command.

## What this command does NOT do

- Does not bump `PHASE` or `CYCLE` in PROGRESS.md. The workflow's scribe writes those via the envelope's `state_delta` on completion. Pre-bumping by this command would trip the hooks before the workflow could write its marker bypass.
- Does not append to REVIEW.md. The workflow's reviewer subagents return structured payloads; the scribe appends the canonical entries.
- Does not write ESCALATION.md. The workflow detects budget-exhaustion and writes via the envelope.
- Does not release `.workflow-in-flight` on success. The scribe does that as the final phase (it empties the marker; the reaper deletes the empty file).
- Does not persist `REVIEW_ROLES` / `REVIEW_CYCLE_BUDGET`. The durable per-feature default lives in PROGRESS.md (set out-of-band — e.g. a human edit; the scribe preserves unknown fields across its state writes). A `--roles`/`--cycle-budget` flag overrides that default for the current run only.
- Does not evaluate or edit REVIEW.md beyond the deterministic rotation script (which moves whole blocks verbatim into REVIEW-archive.md and never edits a block).

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
