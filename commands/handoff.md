---
description: Run CHANGE_REVIEW on the active feature (architect + PO + qa review the diff); on approval delegate to devops
argument-hint: ""
---

# /build-fleet:handoff

You are the **orchestrator**. The runtime rulebook is the `sdd-protocol`
skill. Consult it for the CHANGE_REVIEW phase, the CHANGE_CYCLE budget
(≤ 3 then ESCALATE), and DevOps' refusal conditions.

## What you do

1. **Resolve the active feature.** Read `.sdd/ACTIVE`. If empty, refuse.

2. **Check phase.** Read PROGRESS.md. PHASE must be `BUILD` or
   `CHANGE_REVIEW`. If it's anything else (especially `SPEC` or `REVIEW`),
   refuse and tell the user to run `/build-fleet:finalize` first.

3. **Check ESCALATION.md.** If it exists, refuse.

4. **Pre-flight: tests must exist and pass.**
   - If no tests exist (no `tests/` dir, no test files, no `test`
     command), refuse: BUILD is not complete until qa has authored tests
     per `acceptance.md`.
   - Run the project's test command (npm test / pytest / make test, per
     `stop-tests.sh`'s detection). If tests fail, refuse with the failing
     output. The `stop-tests` hook would catch this at session-end anyway;
     catching it here gives a clearer error.

5. **Check the change-cycle budget.** Read `CHANGE_CYCLE:` from PROGRESS.md.
   If `CHANGE_CYCLE >= 3` AND the most recent CHANGE_REVIEW cycle in
   REVIEW.md still has open `[blocker]` items, this cycle would be the
   4th unresolved → write `ESCALATION.md` with the change-cycle context
   and unresolved blockers, set `PHASE: ESCALATED`, stop.

6. **Bump the change-cycle.** Increment `CHANGE_CYCLE` in PROGRESS.md. Set
   `PHASE: CHANGE_REVIEW`. Refresh `UPDATED:`.

7. **Fan out CHANGE_REVIEW reviewers.** Use the Task tool to launch
   `build-fleet:architect`, `build-fleet:product-owner`, and
   `build-fleet:qa` in parallel (three Task calls in a single message).
   Each prompt includes:
   - The active feature slug.
   - The current CHANGE_CYCLE number.
   - A pointer to the diff (the orchestrator runs `git diff` against the
     base if a git repo; otherwise describe the changed files).
   - A pointer to `spec.md`, `acceptance.md`, `DECISIONS.md`, `IMPL_NOTES.md`,
     `TEST_PLAN.md`.
   - The reviewer-specific lens:
     - architect: design adherence + ADR compliance.
     - product-owner: meets `acceptance.md`?
     - qa: coverage gaps before handoff.
   - The REVIEW.md entry format and severity rubric reminder.

8. **Evaluate the cycle.** Once all three CHANGE_CYCLE blocks exist in
   REVIEW.md:
   - If any open `[blocker]` or any reviewer's `status: concerns-raised`
     → delegate to `build-fleet:coder` to fix (PHASE returns to `BUILD`).
     Do not auto-loop; tell the user that BUILD is open again and they
     should re-run `/build-fleet:handoff` once coder is done. The
     `CHANGE_CYCLE` counter persists.
   - If all three are `status: approved` with zero open blockers →
     CHANGE_REVIEW passes. Continue to step 9.

9. **Hand off to devops.** Set `PHASE: HANDOFF` in PROGRESS.md. Use the Task
   tool to launch `build-fleet:devops` with a prompt that:
   - Names the active feature.
   - Pointers to spec.md, acceptance.md, DECISIONS.md, IMPL_NOTES.md.
   - Asks for CI/CD updates, IaC if applicable, and release notes.
   - Reminds devops to refuse if PHASE isn't HANDOFF — defense in depth.

10. **On devops completion.** Edit `spec.md` STATUS line to retain
    `FINALIZED` (no flip) and append a `## Implementation` section if not
    already present, noting the CHANGE_CYCLE that approved and the date.
    Tell the user the feature is shipped (or in the project's equivalent
    of shipped — opened PR, queued release, etc.).

11. **Flip the product backlog, if a product tier exists (v0.4 M2).** After a
    successful devops completion (step 10), if `.sdd/_product/backlog.md` exists,
    mark this feature done in it:
    - Find the row for the active slug — `- [ ] <slug> …`. If **no row matches**
      (the feature isn't a backlog item — e.g. an ad-hoc fix), **skip this step**
      and note `feature not in product backlog — nothing to flip`. Do not invent a
      row. (There is no `[>]`/active row state — "in flight" is derived from
      `.sdd/ACTIVE`, so a PENDING row is the only thing to flip.)
    - Flip the checkbox and state to:
      `- [x] <slug>   DONE   depends-on: <unchanged>   handoff:<iso-date>`.
      **Preserve any existing `depends-on:` token** (later features reference it);
      only change `- [ ]` → `- [x]`, the `PENDING` word → `DONE`, and append
      `handoff:<iso-date>`.
    - **Recompute the containing `## Phase N: … — STATUS:` line**: `complete` if
      every feature row in that phase is now `[x]`; else `in-progress` if at least
      one row in the phase is `[x]`; else `pending`.
    - Emit: `BUILD_FLEET_BACKLOG_FLIP: {"feature":"<slug>","phase":"<phase name>","phase_status":"<complete|in-progress|pending>"}`.

    **Orchestrator-direct write** to `.sdd/_product/backlog.md` — a `.sdd/` path the
    hooks permit at HANDOFF (`block-source-before-finalized` allows anything under
    `.sdd/`; `restrict-reviewer-writes` only acts during REVIEW/CHANGE_REVIEW, and
    we are past that). It deliberately does **not** go through the scribe: the
    scribe is append-only and product-scope writes are M3's concern. Keep this a
    thin, self-contained step — **M3 re-points product writes through the scribe's
    `workspace_dir` scheme**, so do not couple it to feature-scope state here.

## Refusal cases

- `.sdd/ACTIVE` empty → refuse.
- PHASE not in `{BUILD, CHANGE_REVIEW}` → refuse with the actual phase.
- ESCALATION.md exists → refuse.
- No tests, or test command fails → refuse with the failing output.
- `CHANGE_CYCLE` budget exhausted with open blockers → write ESCALATION.md
  and stop.
