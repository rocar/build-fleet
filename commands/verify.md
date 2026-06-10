---
description: VERIFY gate of the bug lane — run the counterfactual (each reproducing test must FAIL if the fix is reverted) + architect blast-radius review; on a clean pass flip diagnosis.md→FIXED
allowed-tools: Read, Write, Edit, Task, Bash(git status:*), Bash(git diff:*), Bash(git stash:*), Bash(npm test:*), Bash(pytest:*), Bash(make test:*)
---

# /build-fleet:verify

You are the **orchestrator**. This is the bug-lane analog of CHANGE_REVIEW, and it **reuses the
counterfactual gate verbatim**: a reproducing test that passes *regardless* of the fix is
decorative, not a regression guard. The fix is verified only when each reproducing test would
**fail if the coder's change were reverted**.

Rulebook: the `sdd-protocol` skill (bug-lane sections; the CHANGE_REVIEW counterfactual).

## What you do

1. **Resolve the active bug.** `.sdd/ACTIVE` non-empty; PROGRESS `LANE == bug`. Else refuse.

2. **Check phase + status.** `PHASE` must be `FIX`; `diagnosis.md` STATUS must be `CONFIRMED`.
   `ESCALATION.md` absent. Otherwise refuse and name the actual state.

3. **Pre-flight.** ≥1 test exists under `tests/` and the **full suite passes** (the fix made
   the reproducing test green). If the suite fails → refuse: the fix isn't done; run
   `/build-fleet:fix`.

3b. **Snapshot the fix BEFORE any counterfactual (mandatory).** The working tree holds the
   *uncommitted, only copy* of the fix — reverting it without a recoverable snapshot is how
   a fix gets destroyed. Run:
   ```bash
   git stash create "verify-counterfactual snapshot <slug>"
   ```
   It snapshots the working tree **without modifying it** and prints a commit SHA. Record
   that SHA in `.sdd/<slug>/IMPL_NOTES.md` as a line:
   `counterfactual-snapshot: <sha> (<iso8601>)`.
   **If the command fails or prints nothing** (e.g. not a git repo, or nothing to snapshot —
   which would mean there is no uncommitted fix to protect and the state needs a human look),
   **refuse to proceed**: `BUILD_FLEET_REFUSE: {"command":"verify","code":2,"reason":"snapshot-failed"}`.
   No counterfactual runs without a recorded snapshot SHA.

4. **Run the counterfactual + blast-radius review (parallel Task calls).**

   - **qa — the counterfactual, against the recorded snapshot.** Pass qa the snapshot SHA
     from step 3b. For each reproducing test: revert the coder's source change with
     `git stash` (recoverable — the stash plus the recorded SHA both hold the fix), run the
     test, and confirm it now **FAILS** for the bug's reason; then **restore** the fix
     (`git stash pop`, or `git stash apply <sha>` from the recorded snapshot if anything
     goes wrong). **A bare `git checkout` of the fixed files is FORBIDDEN** — it destroys
     the uncommitted fix with no recovery path. A reproducing test that still **passes**
     with the fix reverted is decorative — qa records it as a `[blocker]`. qa appends its
     findings to `.sdd/<slug>/REVIEW.md`.
   - **architect — blast radius.** Review the diff against `diagnosis.md`'s `## Blast radius`:
     did the fix stay within the stated surface, or did it touch more than the diagnosis
     justified? Out-of-radius changes are a `[major]`/`[blocker]` per severity. Append to `REVIEW.md`.

4b. **Verify the restore BEFORE evaluating (mandatory).** After qa returns and before you
   read any verdict: confirm the working tree again matches the step-3b snapshot —
   `git status` shows the same set of modified files, and `git diff <recorded-sha>` over the
   fix's files is empty. If the tree does NOT match, **stop — do not evaluate**: restore the
   fix from the snapshot (`git stash apply <recorded-sha>` / `git stash pop`), re-verify, and
   only then continue. Emit `BUILD_FLEET_VERIFY_RESTORE_FAIL: {"slug":"<slug>","snapshot":"<sha>"}`
   if the restore itself fails — that is a hard stop for a human; the recorded SHA in
   IMPL_NOTES.md is the recovery handle (`git stash apply <sha>`).

5. **Evaluate.**

   - **Clean** — every reproducing test fails when reverted (counterfactual satisfied) **and**
     no surviving `[blocker]`. Flip `diagnosis.md` STATUS → `FIXED`; set PROGRESS `PHASE:
     HANDOFF`; refresh `UPDATED`. Emit:
     ```
     BUILD_FLEET_VERIFY: {"slug":"<slug>","verdict":"clean","counterfactual_ok":true}
     ```
     Next command: `/build-fleet:ship-fix`.

   - **Bounce** — a reproducing test passes with the fix reverted (counterfactual fails) **or**
     a surviving `[blocker]`. Increment `FIX_CYCLE`; set PROGRESS `PHASE: FIX`. 
     - If `FIX_CYCLE >= 3` → **escalate**: write `.sdd/<slug>/ESCALATION.md` (the failing
       counterfactual / surviving blockers), set `PHASE: ESCALATED`, stop. Emit
       `BUILD_FLEET_VERIFY: {"slug":"<slug>","verdict":"escalate","counterfactual_ok":false}`.
     - Else emit:
       ```
       BUILD_FLEET_VERIFY: {"slug":"<slug>","verdict":"bounce","counterfactual_ok":false}
       ```
       Next command: `/build-fleet:fix` — the coder iterates.

## Refusal cases

- No active bug / active item is a forward feature.
- `PHASE` ≠ `FIX`, or `diagnosis.md` STATUS ≠ `CONFIRMED`, or `ESCALATION.md` present.
- No tests, or the suite fails (the fix isn't complete).
- `git stash create` fails or returns no SHA (no recorded snapshot → no counterfactual).

A slash command cannot set a process exit code; the `BUILD_FLEET_*` signal lines on stdout
are the sole machine contract (refusals carry `{"code":2,"reason":"<kebab-slug>"}`).
