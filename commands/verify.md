---
description: VERIFY gate of the bug lane — run the counterfactual (each reproducing test must FAIL if the fix is reverted) + architect blast-radius review; on a clean pass flip diagnosis.md→FIXED
argument-hint: ""
allowed-tools: Read, Write, Edit, Bash, Task
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
   `ESCALATION.md` absent. Otherwise refuse and name the actual state. Exit 2.

3. **Pre-flight.** ≥1 test exists under `tests/` and the **full suite passes** (the fix made
   the reproducing test green). If the suite fails → refuse: the fix isn't done; run
   `/build-fleet:fix`. Exit 2.

4. **Run the counterfactual + blast-radius review (parallel Task calls).**

   - **qa — the counterfactual (reused verbatim).** For each reproducing test: revert the
     coder's source change (e.g. `git stash` the fix, or check the changed source out to its
     pre-fix state), run the test, and confirm it now **FAILS** for the bug's reason; then
     **restore** the fix. A reproducing test that still **passes** with the fix reverted is
     decorative — qa records it as a `[blocker]`. qa appends its findings to `.sdd/<slug>/REVIEW.md`.
   - **architect — blast radius.** Review the diff against `diagnosis.md`'s `## Blast radius`:
     did the fix stay within the stated surface, or did it touch more than the diagnosis
     justified? Out-of-radius changes are a `[major]`/`[blocker]` per severity. Append to `REVIEW.md`.

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
