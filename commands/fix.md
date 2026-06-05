---
description: FIX gate of the bug lane — confirm the diagnosis (flip diagnosis.md→CONFIRMED), then delegate to coder to make the reproducing test pass; supports the sev0 hotfix fast-path
argument-hint: ""
allowed-tools: Read, Write, Edit, Bash, Task
---

# /build-fleet:fix

You are the **orchestrator**. This is the bug-lane analog of `/build-fleet:finalize` — a
**gate**, not a request. The `diagnose.js` workflow advances a confirmed bug to `PHASE: FIX`;
this command applies the deterministic `diagnosis.md` STATUS → `CONFIRMED` *content* flip (the
write the scribe must not do, mirroring how `/build-fleet:finalize` flips `spec.md` after
review), which unlocks source writes (`block-source-before-finalized`'s second unlock +
`require-reproducing-test`: CONFIRMED **and** the reproducing test from REPRODUCE both hold),
then drives the coder to turn the reproducing test GREEN.

Rulebook: the `sdd-protocol` skill (bug-lane sections).

## What you do

1. **Resolve the active bug.** Read `.sdd/ACTIVE` (empty → `BUILD_FLEET_REFUSE: no active item`, exit 2).
   Read `.sdd/<slug>/PROGRESS.md`; `LANE` must be `bug` (else refuse — use the forward commands).

2. **Check ESCALATION.** If `.sdd/<slug>/ESCALATION.md` exists → refuse, exit 2.

3. **The gate — determine the path.** Read `PHASE` + `SEV` from PROGRESS.md and the
   `diagnosis.md` STATUS:

   - **Confirmed (normal).** `PHASE == FIX` → the `diagnose.js` workflow CONFIRMED the
     hypothesis. Proceed.
   - **sev0 hotfix fast-path (AC-22).** `PHASE == DIAGNOSE` **and** `SEV == sev0` **and**
     `diagnosis.md` STATUS == `DIAGNOSED` → sev0 may skip the adversarial confirmation
     workflow. Proceed via the fast-path (step 4b records the post-hoc obligation). This
     **never** skips the reproducing-test gate.
   - **Re-entry after a verify bounce.** `PHASE == FIX` with STATUS already `CONFIRMED` →
     proceed (re-dispatch the coder).
   - **Otherwise** (`PHASE == DIAGNOSE` and not sev0, or any other phase) → refuse:
     `BUILD_FLEET_REFUSE: diagnosis not confirmed — run /build-fleet:diagnose first (sev0 may use the fast-path).` Exit 2.

4. **Pre-flight: the reproducing test must exist.** Confirm ≥1 file under `tests/` (REPRODUCE
   produced it). If none → refuse: `BUILD_FLEET_REFUSE: no reproducing test under tests/ — run /build-fleet:reproduce first.` Exit 2. (The gate would block source anyway; refusing here is clearer.)

5. **Apply the confirm flip.**
   a. If `diagnosis.md` STATUS ≠ `CONFIRMED`, flip it → `CONFIRMED` (keep all four `##`
      sections). Ensure PROGRESS `PHASE: FIX`; refresh `UPDATED`. Source writes are now permitted.
   b. **sev0 fast-path only:** append a note under `## Fix strategy` that adversarial
      confirmation was skipped and is **owed post-ship**, and emit:
      ```
      BUILD_FLEET_POSTHOC_DIAGNOSIS_DUE: {"slug":"<slug>"}
      ```
   Emit:
   ```
   BUILD_FLEET_FIX_GATE: {"slug":"<slug>","sev":"<sev>","path":"confirmed|sev0-fast-path"}
   ```

6. **Delegate to coder.** Use the Task tool to invoke `build-fleet:coder`:

   > PHASE=FIX for bug `<slug>`. `diagnosis.md` is CONFIRMED and a failing reproduction test
   > exists under `tests/`. Read `.sdd/<slug>/diagnosis.md` — implement the recorded **fix
   > strategy** so the reproducing test(s) turn GREEN **without breaking the existing suite**.
   > Stay within the stated **blast radius**; do not widen it. Record `gap:`/`deviation:`/`todo:`
   > markers in `.sdd/<slug>/IMPL_NOTES.md`. When the reproducing test(s) pass and the suite is
   > green, emit exactly: `BUILD_FLEET_FIX_DONE: <count> tests green`.

7. **Verify and report.** When coder returns, run the project's test command (per
   `stop-tests.sh` detection). 
   - All green (reproducing test(s) now pass, suite passes) → emit:
     ```
     BUILD_FLEET_FIX_DONE: {"slug":"<slug>","tests_green":<N>}
     ```
     Next command: `/build-fleet:verify` (the counterfactual gate).
   - Still failing → emit `BUILD_FLEET_FIX_INCOMPLETE: {"slug":"<slug>","failing_tests":<N>}`,
     surface the failures; coder iterates (no auto-loop). PHASE stays `FIX`.

## What this does NOT do

- Does not run the `diagnose.js` workflow (that is `/build-fleet:diagnose`).
- For `sev1`/`sev2`, does **not** bypass confirmation — it refuses unless `PHASE == FIX`.

## Refusal cases

- No active bug / active item is a forward feature / `ESCALATION.md` present.
- `PHASE == DIAGNOSE` and not `sev0` → confirm via `/build-fleet:diagnose` first.
- No reproducing test under `tests/`.
