---
description: Drive the BUILD phase of the active feature — qa drafts the failing suite first, then coder implements to green; routes to the deep-build workflow when BUILD_MODE=deep-build
allowed-tools: Read, Write, Edit, Task, Workflow, Bash(npm test:*), Bash(pytest:*), Bash(make test:*)
---

# /build-fleet:build

You are the **orchestrator**. The runtime rulebook is the `sdd-protocol`
skill. This command drives the BUILD sequence for a feature whose spec the
`/build-fleet:finalize` gate has already flipped to `FINALIZED`. It was split
out of finalize (which is now the gate only) so the gate stays idempotent and
this orchestration owns its own preconditions.

**Architecture notes:**
- **Standard BUILD (sequential).** For `BUILD_MODE=standard`, the qa-then-coder
  orchestration below runs via sequential `Task` calls inside this command.
- **Deep-build routing.** For `BUILD_MODE=deep-build`, step 4 routes to
  `workflows/deep-build.js` via the `Workflow` tool — proper resumability and the
  platform's plan-approval gate.

## Preconditions (refuse with a signal line on any failure)

1. **Resolve the active feature.** Read `.sdd/ACTIVE`. If empty, refuse:
   `BUILD_FLEET_BUILD_REFUSE: {"code":2,"reason":"no-active-feature"}`.
   Read `.sdd/<slug>/PROGRESS.md`; if it carries `LANE: bug`, refuse —
   the bug lane builds via `/build-fleet:fix`
   (`{"code":2,"reason":"bug-lane-item"}`).

2. **Check the gate has passed.** `spec.md` STATUS must be `FINALIZED` and
   `PHASE` must be `BUILD` (tolerate a legacy `FINALIZE` phase value the same
   way). If not, refuse and name the actual state:
   `BUILD_FLEET_BUILD_REFUSE: {"feature":"<slug>","code":2,"reason":"not-finalized","status":"<STATUS>","phase":"<PHASE>","detail":"run /build-fleet:finalize first"}`.

3. **Check ESCALATION.md.** If `.sdd/<slug>/ESCALATION.md` exists, refuse
   (`{"code":2,"reason":"escalation-present"}`) —
   `/build-fleet:resolve-escalation` is the sanctioned unblock path.

4. **Re-run guard (the orchestration is NOT idempotent).** If
   `.sdd/<slug>/IMPL_NOTES.md` already records BUILD activity, or a qa-authored
   failing suite for this feature is already in place under `tests/`, a re-run
   would re-dispatch qa over an existing suite. Refuse:
   `BUILD_FLEET_BUILD_REFUSE: {"feature":"<slug>","code":2,"reason":"build-already-started"}`
   and tell the user how to proceed instead: dispatch coder manually for an
   iteration, run `/build-fleet:deep-build` (which requires the existing failing
   suite and is resumable), or `/build-fleet:handoff` if BUILD completed.

## What you do (tests-first ordering)

a. **Dispatch qa first.** Use the Task tool to invoke `build-fleet:qa` with this
   prompt:

   > PHASE=BUILD for feature `<slug>`. STATUS=FINALIZED. Draft `.sdd/<slug>/TEST_PLAN.md`
   > per the `test-plan` skill, then implement the failing test suite under `tests/`.
   > Every test must initially FAIL. When the full failing suite is in place, emit
   > exactly: `BUILD_FLEET_QA_TESTS_READY: <count> failing tests in tests/`. Do NOT signal coder
   > or write any source — only tests.
   > If `.sdd/<slug>/SKILL_MANIFEST.md` exists, first load and apply the skills it
   > lists under the `qa` role (per the `skill-routing` skill); an unavailable
   > skill is a no-op — note it in TEST_PLAN.md and proceed.

b. **Wait for QA's signal and verify.** When qa's Task call returns, parse its
   output for the `BUILD_FLEET_QA_TESTS_READY: <N>` line.

   **Branch — qa never emitted the signal.** If qa returns without `BUILD_FLEET_QA_TESTS_READY:`
   (e.g., qa surfaced a spec gap, errored, or refused), do NOT dispatch coder. Emit:

   ```
   BUILD_FLEET_QA_VERIFY_FAIL: {"feature":"<slug>","reason":"no-signal","qa_output_tail":"<last 200 chars>"}
   ```

   then surface qa's full output and stop. The spec stays FINALIZED, PHASE stays
   BUILD — coder is not dispatched. BUILD halts safely when qa cannot proceed.

   **Branch — signal present, verify the suite.** Run the project's test command
   (`npm test` / `pytest -q` / `make test` per stack detection). Confirm:
   - At least one test exists (count > 0).
   - All QA-authored tests currently fail.
   - The count in the `BUILD_FLEET_QA_TESTS_READY: <N>` signal exactly matches the actually-failing
     count (no tolerance — strict counting; the deep-build workflow may relax this).

   If verification fails (zero tests, all pass, count mismatch), emit:

   ```
   BUILD_FLEET_QA_VERIFY_FAIL: {"feature":"<slug>","reason":"<zero-tests|all-pass|count-mismatch>","claimed":<N>,"observed":<M>}
   ```

   then refuse to dispatch coder and surface the discrepancy. STATUS stays FINALIZED,
   PHASE stays BUILD. The user resolves the discrepancy externally (re-run qa
   manually or edit the test suite); a blind re-run of `/build-fleet:build` will
   refuse via the precondition-4 re-run guard.

c. **Route on BUILD_MODE.** Read `BUILD_MODE:` from PROGRESS.md.
   Absent or `standard` → standard sequential BUILD (this command continues with
   single coder dispatch below). `deep-build` → dispatch the deep-build workflow.

   The deep-build branch mirrors `/build-fleet:deep-build`'s own dispatch shape
   so the workflow is invoked under identical preconditions regardless of entry
   point:

   i.   Verify `Workflow` tool availability. If absent, emit
        `BUILD_FLEET_BUILD_REFUSE: {"feature":"<slug>","code":3,"reason":"workflow-runtime-unavailable","detail":"use BUILD_MODE=standard or upgrade Claude Code"}`
        and stop.

   ii.  Emit the route signal:
        ```
        BUILD_FLEET_BUILD_ROUTE: {"feature":"<slug>","build_mode":"deep-build"}
        ```

   iii. **Resolve the BUILD cycle.** Read `BUILD_CYCLE:` from PROGRESS.md; if the
        field is absent, add `BUILD_CYCLE: 0` first (the scribe replaces fields in
        place, so it must exist before dispatch). If `BUILD_CYCLE >= 3`, refuse —
        mirror `/build-fleet:deep-build`'s budget refusal (the budget is 3 build
        cycles; the workflow escalates on the exhausting cycle). New cycle =
        `BUILD_CYCLE + 1`.

   iv.  **Compose the run id and drop the workflow-in-flight marker.** Compose a
        run id `deep-build-<slug>-c<new_cycle>-<iso8601 now>` (the same `now` you
        pass in step vi) and write `.sdd/<slug>/.workflow-in-flight` containing
        exactly that run id as its single line. Hooks `check-review-written` and
        `restrict-reviewer-writes` skip while the marker is present; the scribe
        deletes it as the workflow's final phase — only if its content still
        matches the envelope's `run_id`. **Cleanup obligation:** if the Workflow
        tool subsequently returns an `error` (step vi) or fails to launch — or a
        post-launch poll shows the run died before any scribe ran — delete the
        marker (after verifying its content still matches your run id) before
        reporting the failure.

   v.   **Emit cost preview** (headless contract parity with /build-fleet:deep-build).
        Parse the `@cost-ceiling` header comment at the top of
        `${CLAUDE_PLUGIN_ROOT}/workflows/deep-build.js`:
        ```
        BUILD_FLEET_COST_PREVIEW: {"workflow":"deep-build","feature":"<slug>","cycle":<N>,"input_ceiling":<N>,"output_ceiling":<N>}
        ```

   vi.  **Invoke the `Workflow` tool** with:
        - `scriptPath`: `${CLAUDE_PLUGIN_ROOT}/workflows/deep-build.js`
        - `args`: `{ "feature": "<slug>", "cycle": <new_cycle>, "now": "<iso8601>", "run_id": "<run id from step iv>" }`

        Supply `now` yourself (the script cannot call `Date`); the workflow
        refuses to run without `feature`, `cycle`, or `now`.

   vii. **Emit the launch line:**
        ```
        BUILD_FLEET_WORKFLOW_LAUNCHED: {"runId":"<id>","transcriptDir":"<path>","status":"async_launched","feature":"<slug>","cycle":<N>,"workflow":"deep-build"}
        ```

   viii. Tell the user the deep-build workflow is running in the background;
        `/workflows` shows progress; next command after completion is
        `/build-fleet:handoff` (for verdict=clean) or `/build-fleet:deep-build` to
        iterate (for verdict=needs-iteration — the envelope carries
        `cycles_remaining` against the 3-cycle BUILD_CYCLE budget). A verdict of
        `incomplete`/`invalid-args` means PHASE/BUILD_CYCLE are unchanged — re-run
        after reading the result's `note` (partial worktree writes are possible if
        coders had fanned out). **Scribe-apply failure is a hard failure:** a
        return object carrying `scribe_apply: "failed"` means IMPL_NOTES.md/
        PROGRESS.md did NOT land — report the run as failed with its
        `scribe_error`; never treat the verdict as applied. **Stop here** —
        the workflow's scribe handles state writes; the BUILD-complete signal will
        come from the workflow's envelope, not from this command. Skip step d/e.

   Otherwise (BUILD_MODE absent or `standard`) — continue with single-coder
   dispatch:

d. **Dispatch coder.** Use the Task tool to invoke `build-fleet:coder` with this prompt:

   > PHASE=BUILD for feature `<slug>`. STATUS=FINALIZED. QA has authored
   > `<count>` failing tests under `tests/`. Per `agents/coder.md`, refuse-to-begin
   > if tests are absent or already passing. Implement source until every QA test
   > passes. Record `gap:` / `deviation:` / `todo:` markers in
   > `.sdd/<slug>/IMPL_NOTES.md`. Self-review against acceptance.md before
   > declaring BUILD complete.
   > If `.sdd/<slug>/SKILL_MANIFEST.md` exists, first load and apply the skills it
   > lists under the `coder` role (per the `skill-routing` skill); an unavailable
   > skill is a no-op — record `skill-unavailable: <name>` in IMPL_NOTES.md and
   > proceed with normal craft.

e. **Wait for coder's Task call to return, then branch.**

   **Branch — coder refused to begin.** Parse coder's output for
   `BUILD_FLEET_CODER_REFUSE:`. If present, do NOT report BUILD complete. Emit:

   ```
   BUILD_FLEET_BUILD_DISPATCH_FAIL: {"feature":"<slug>","reason":"coder-refused","coder_refusal":"<the BUILD_FLEET_CODER_REFUSE line verbatim>"}
   ```

   then surface coder's output and stop. STATUS stays FINALIZED, PHASE stays BUILD.
   This is the tests-first violation check.

   **Branch — coder completed.** When coder's Task call returns and the source has
   been written, run the test suite one final time. If all tests pass, emit:

   ```
   BUILD_FLEET_BUILD_COMPLETE: {"feature":"<slug>","tests_passing":<N>,"impl_notes_path":".sdd/<slug>/IMPL_NOTES.md"}
   ```

   then tell the user: BUILD complete (qa drafted the failing suite, coder drove them
   green); review `IMPL_NOTES.md` for `gap:` / `deviation:` / `todo:` markers; the
   next command is `/build-fleet:handoff` (which runs CHANGE_REVIEW including QA's
   counterfactual gate).

   If the final test run shows failures, emit:

   ```
   BUILD_FLEET_BUILD_INCOMPLETE: {"feature":"<slug>","failing_tests":<N>}
   ```

   then surface the failing tests. Coder needs to iterate — the user can dispatch
   coder again manually (this command does not auto-loop). STATUS stays FINALIZED,
   PHASE stays BUILD.

## Hard rules

- This command **never** flips `spec.md` STATUS — that is `/build-fleet:finalize`'s
  gate. It refuses if the gate has not already passed.
- This command **never** edits REVIEW.md or writes ADRs.
- **Non-idempotency.** The orchestration (steps a–e) is NOT idempotent: the
  precondition-4 re-run guard refuses rather than re-dispatching qa over an
  existing suite. The deep-build workflow path is the resumable variant
  (`workflows/deep-build.js` uses the platform's `resumeFromRunId`).
- **Headless contract.** Every branch above emits exactly one `BUILD_FLEET_*:` line
  before any human-readable prose, so orchestrators can dispatch on machine-readable
  outcome codes without parsing the wider response.

## Refusal contract (machine-readable)

A slash command runs inside the model session and **cannot set a process exit
code** — the session exits 0 either way. The `BUILD_FLEET_*` signal lines on
stdout are the **sole machine contract**. Every refusal emits exactly one
`BUILD_FLEET_BUILD_REFUSE:` line whose JSON carries `"code"` (an integer
preserving the legacy exit-code semantics: `2` = precondition refused, `3` =
workflow runtime unavailable, `1` = workflow tool launch error) and `"reason"`
(a kebab-case slug). Orchestrators dispatch on the signal line, never on the
process exit status.
