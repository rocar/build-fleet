---
description: Run the finalize gate on the active feature; flip the spec to FINALIZED and unlock source writes
argument-hint: ""
allowed-tools: Read, Write, Edit, Bash, Task, Workflow
---

# /build-fleet:finalize

You are the **orchestrator**. The runtime rulebook is the `sdd-protocol`
skill. Consult it for the finalize gate definition.

This is a **gate**, not a request. You do not finalize on demand — you check
the conditions, and if they hold you flip the state. If they don't, you
refuse with an actionable diff.

**v0.2 architecture notes:**
- **M2 (sequential BUILD).** For `BUILD_MODE=standard`, the qa-then-coder
  orchestration in step 6 is implemented via sequential `Task` calls inside this
  command. The BUILD orchestration is NOT idempotent: if a session is interrupted
  between qa and coder, the step-2 already-FINALIZED guard refuses re-runs.
- **M3 (deep-build workflow).** For `BUILD_MODE=deep-build`, step 6d routes to
  `workflows/deep-build.js` via the `Workflow` tool — proper resumability and the
  platform's plan-approval gate.
- **M4 (trivial fast-path).** Trivial features (TIER=trivial, set by the classifier
  at `/build-fleet:new-feature` time) skip the REVIEW phase entirely. Step 2 below
  recognizes this and routes directly to the pass-output BUILD orchestration without
  requiring a completed review cycle.

## What you do

1. **Resolve the active feature.** Read `.sdd/ACTIVE`. If empty, refuse.

2. **Check phase + tier (M4-aware).** Read PROGRESS.md. Extract `PHASE`, `TIER`
   (defaults to `standard` if absent), and `STATUS` from spec.md.

   - **Already finalized.** If `STATUS=FINALIZED` and `PHASE=BUILD`, refuse with:
     `BUILD_FLEET_FINALIZE_REFUSE: {"feature":"<slug>","reason":"already-finalized","detail":"re-running BUILD is not idempotent in M2"}`
     and exit 2. Tell the user the next move is `/build-fleet:handoff` once coder
     declares complete.

   - **Trivial fast-path.** If `TIER=trivial` AND `PHASE=SPEC` AND `CYCLE=0`:
     - This is the M4 trivial fast-path. The classifier already decided REVIEW
       is unnecessary; skip the review-cycle gate entirely.
     - **Still check `.sdd/<slug>/ESCALATION.md`.** Even on the trivial path, a
       human can write ESCALATION.md to halt a feature (e.g., "actually wait,
       I changed my mind"). If present, refuse with `BUILD_FLEET_FINALIZE_REFUSE:
       {"feature":"<slug>","reason":"escalation-present","tier":"trivial"}` and
       surface the ESCALATION.md contents. Exit 2.
     - Verify `spec.md` exists and has a valid STATUS line + required sections
       (the `validate-spec-status` hook would catch missing sections anyway).
     - Emit: `BUILD_FLEET_FINALIZE_TRIVIAL_FAST_PATH: {"feature":"<slug>","tier":"trivial"}`
     - Skip step 4 (no review-cycle to validate). Jump directly to step 6 (pass output).

   - **Standard / large normal path.** `PHASE` must be `REVIEW`. If it's `SPEC`
     (no review has run) AND `TIER` is `standard` or `large`, refuse with:
     `BUILD_FLEET_FINALIZE_REFUSE: {"feature":"<slug>","reason":"no-review-cycle","tier":"<TIER>","detail":"run /build-fleet:review first"}`
     and exit 2.

   - If `PHASE` is past `REVIEW` and not already-finalized (handled above), refuse
     and surface the actual phase.

3. **Check ESCALATION.md.** If `.sdd/<active>/ESCALATION.md` exists, refuse —
   the feature is escalated and only a human can unblock it.

4. **Check the most recent review cycle.** Read REVIEW.md. Find every block
   tagged with the current `CYCLE:` value. The gate requires:
   - Exactly three reviewer blocks for the current cycle (one each for
     architect, qa, coder). Missing reviewer → refuse.
   - Every block ends in `status: approved`. Any `status: concerns-raised`
     → refuse.
   - Zero open `[blocker]` items across all current-cycle blocks.
     (A `[blocker]` in a prior cycle that the reviewer's current-cycle
     block approves through is fine — what matters is the latest verdict.)
   - `[major]` items in the current cycle are acceptable **only** if each
     is cited by an ADR ID in DECISIONS.md, or resolved in the spec. If a
     `[major]` is neither fixed nor recorded as an ADR, refuse.

5. **Refusal output.** If the gate refuses, emit exactly one machine-readable line
   first (for headless orchestrators), then the human-readable structured list:

   ```
   BUILD_FLEET_FINALIZE_REFUSE: {"feature":"<slug>","cycle":<N>,"reasons":["missing-<role>","open-blockers","majors-without-adr"]}
   ```

   Reason codes (combine as needed):
   - `missing-<role>` — reviewer block absent for current cycle (one code per missing role)
   - `open-blockers` — current cycle has open `[blocker]` items
   - `majors-without-adr` — `[major]` items lacking ADR citations
   - `not-approved` — at least one reviewer block ends in `status: concerns-raised`

   Then the structured list (human-readable):
   - Reviewers missing their current-cycle block.
   - Open `[blocker]` items, verbatim, with the reviewer attribution.
   - `[major]` items lacking ADRs.
   - The recommended next command (`/build-fleet:review` to run another
     cycle, after PO has revised).

6. **Pass output (v0.2 M2 tests-first ordering — replaces v0.1's "do not spawn agents").**
   If the gate passes, you flip state AND drive the BUILD sequence:

   a. **Flip state.** Edit `spec.md` so the STATUS line reads `STATUS: FINALIZED`.
      Edit PROGRESS.md: set `PHASE: BUILD`, refresh `UPDATED:`. The source-write block
      lifts at this point. Emit:

      ```
      BUILD_FLEET_FINALIZE_PASS: {"feature":"<slug>","cycle":<N>,"status":"FINALIZED","phase":"BUILD"}
      ```

   b. **Dispatch qa first.** Use the Task tool to invoke `build-fleet:qa` with this
      prompt:

      > PHASE=BUILD for feature `<slug>`. STATUS=FINALIZED. Draft `.sdd/<slug>/TEST_PLAN.md`
      > per the `test-plan` skill, then implement the failing test suite under `tests/`.
      > Every test must initially FAIL. When the full failing suite is in place, emit
      > exactly: `BUILD_FLEET_QA_TESTS_READY: <count> failing tests in tests/`. Do NOT signal coder
      > or write any source — only tests.
      > If `.sdd/<slug>/SKILL_MANIFEST.md` exists, first load and apply the skills it
      > lists under the `qa` role (per the `skill-routing` skill); an unavailable
      > skill is a no-op — note it in TEST_PLAN.md and proceed.

   c. **Wait for QA's signal and verify.** When qa's Task call returns, parse its
      output for the `BUILD_FLEET_QA_TESTS_READY: <N>` line.

      **Branch — qa never emitted the signal.** If qa returns without `BUILD_FLEET_QA_TESTS_READY:`
      (e.g., qa surfaced a spec gap, errored, or refused), do NOT dispatch coder. Emit:

      ```
      BUILD_FLEET_QA_VERIFY_FAIL: {"feature":"<slug>","reason":"no-signal","qa_output_tail":"<last 200 chars>"}
      ```

      then surface qa's full output and stop. The spec stays FINALIZED, PHASE stays
      BUILD — coder is not dispatched. This is the v0.2 M2 design: BUILD halts safely
      when qa cannot proceed.

      **Branch — signal present, verify the suite.** Run the project's test command
      (`npm test` / `pytest -q` / `make test` per stack detection). Confirm:
      - At least one test exists (count > 0).
      - All QA-authored tests currently fail.
      - The count in the `BUILD_FLEET_QA_TESTS_READY: <N>` signal exactly matches the actually-failing
        count (no tolerance — M2 enforces strict counting; M3 may relax with a workflow).

      If verification fails (zero tests, all pass, count mismatch), emit:

      ```
      BUILD_FLEET_QA_VERIFY_FAIL: {"feature":"<slug>","reason":"<zero-tests|all-pass|count-mismatch>","claimed":<N>,"observed":<M>}
      ```

      then refuse to dispatch coder and surface the discrepancy. STATUS stays FINALIZED,
      PHASE stays BUILD. The user resolves the discrepancy externally (re-run qa
      manually or edit the test suite) and re-running `/build-fleet:finalize` will
      refuse via the already-FINALIZED guard at step 2.

   d. **Route on BUILD_MODE (v0.2 M3).** Read `BUILD_MODE:` from PROGRESS.md.
      Absent or `standard` → standard sequential BUILD (this command continues with
      single coder dispatch below). `deep-build` → dispatch the deep-build workflow.

      The deep-build branch mirrors `/build-fleet:deep-build`'s own dispatch shape
      so the workflow is invoked under identical preconditions regardless of entry
      point:

      i.   Verify `Workflow` tool availability. If absent, emit
           `BUILD_FLEET_REFUSE: workflow runtime unavailable for BUILD_MODE=deep-build;
           use /build-fleet:finalize with BUILD_MODE=standard or upgrade Claude Code`
           and exit 3.

      ii.  Emit the route signal:
           ```
           BUILD_FLEET_BUILD_ROUTE: {"feature":"<slug>","build_mode":"deep-build"}
           ```

      iii. **Drop the workflow-in-flight marker.** Write `.sdd/<slug>/.workflow-in-flight`
           containing the current iso8601. Hooks `check-review-written` and
           `restrict-reviewer-writes` skip while the marker is present; scribe deletes
           it as the workflow's final phase. **Cleanup obligation:** if the Workflow
           tool subsequently returns an `error` (step v) or fails to launch, delete
           the marker before reporting the failure.

      iv.  **Emit cost preview** (headless contract parity with /build-fleet:deep-build).
           Parse `estimatedCost` from the top of `${CLAUDE_PLUGIN_ROOT}/workflows/deep-build.js`:
           ```
           BUILD_FLEET_COST_PREVIEW: {"workflow":"deep-build","feature":"<slug>","input_ceiling":<N>,"output_ceiling":<N>}
           ```

      v.   **Invoke the `Workflow` tool** with:
           - `scriptPath`: `${CLAUDE_PLUGIN_ROOT}/workflows/deep-build.js`
           - `args`: `{ "feature": "<slug>" }`

      vi.  **Emit the launch line:**
           ```
           BUILD_FLEET_WORKFLOW_LAUNCHED: {"runId":"<id>","transcriptDir":"<path>","status":"async_launched","feature":"<slug>","workflow":"deep-build"}
           ```

      vii. Tell the user the deep-build workflow is running in the background;
           `/workflows` shows progress; next command after completion is
           `/build-fleet:handoff` (for verdict=clean) or `/build-fleet:deep-build` to
           iterate (for verdict=needs-iteration). **Exit step 6 here** — the workflow's
           scribe handles state writes; the BUILD-complete signal will come from the
           workflow's envelope, not from this command. Skip step 6e.

      Otherwise (BUILD_MODE absent or `standard`) — continue with single-coder
      dispatch:

      Use the Task tool to invoke `build-fleet:coder` with this prompt:

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
      This is the v0.2 M2 tests-first violation check (per V0.2-PLAN Phase 2 verification).

      **Branch — coder completed.** When coder's Task call returns and the source has
      been written, run the test suite one final time. If all tests pass, emit:

      ```
      BUILD_FLEET_BUILD_COMPLETE: {"feature":"<slug>","tests_passing":<N>,"impl_notes_path":".sdd/<slug>/IMPL_NOTES.md"}
      ```

      then tell the user: BUILD complete (qa drafted the failing suite, coder drove them
      green); review `IMPL_NOTES.md` for `gap:` / `deviation:` / `todo:` markers; the
      next command is `/build-fleet:handoff` (which runs CHANGE_REVIEW including QA's M2
      counterfactual gate).

      If the final test run shows failures, emit:

      ```
      BUILD_FLEET_BUILD_INCOMPLETE: {"feature":"<slug>","failing_tests":<N>}
      ```

      then surface the failing tests. Coder needs to iterate — the user can dispatch
      coder again manually (this command does not auto-loop). STATUS stays FINALIZED,
      PHASE stays BUILD.

## Hard rules

- This command **never** edits REVIEW.md. Reviewer blocks are append-only
  and owned by reviewers.
- This command **never** writes ADRs. If a `[major]` needs an ADR, the
  refusal output should say so and a subsequent `/build-fleet:review`
  cycle is where architect records it.
- A failing finalize is **not** a workflow failure — it's the gate doing
  its job. Report what's missing and let the user iterate.
- **Idempotency (M2 limitation).** The state flip (step 6a) is idempotent — flipping
  FINALIZED to FINALIZED is a no-op. The BUILD orchestration (steps 6b–6e) is NOT
  idempotent: re-running this command on a feature whose PHASE is already BUILD would
  re-dispatch qa over an existing test suite. The step-2 already-FINALIZED guard
  prevents this by refusing. **M3 fixes this** by lifting the BUILD sequence into
  `workflows/deep-build.js` which uses the platform's `resumeFromRunId` for proper
  resumability.
- **Headless contract.** Every branch above emits exactly one `BUILD_FLEET_*:` line
  before any human-readable prose, so orchestrators can dispatch on machine-readable
  outcome codes without parsing the wider response.
