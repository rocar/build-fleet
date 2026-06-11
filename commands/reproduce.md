---
description: Author a failing reproduction test for the active bug
allowed-tools: Read, Write, Edit, Task
---

# /build-fleet:reproduce

You are the **orchestrator** for the bug lane's REPRODUCE phase. You route and gate; you do
not write the test or source yourself. **Headless-first:** emit the machine signal before prose.

Rulebook: the `sdd-protocol` skill (`references/bug-lane.md`). The `diagnosis.md` contract is the
`sdd-diagnosis-template` skill. This is the bug-lane analog of qa's tests-first BUILD work.

## Preconditions (refuse with a `BUILD_FLEET_REFUSE: {"command":"reproduce","code":2,"reason":"<kebab-slug>"}` line — the stdout signal is the sole machine contract; a slash command cannot set a process exit code)

1. **Active bug.** Read `.sdd/ACTIVE`. If empty → refuse (`no active item`). Read
   `.sdd/<slug>/PROGRESS.md`; if `LANE` is not `bug` → refuse (`<slug> is a forward feature —
   use the feature commands`).
2. **Phase.** `PHASE` must be `REPORT`. Otherwise refuse and name the actual phase (e.g. a bug
   already at `REPRODUCE` has its test; one at `DIAGNOSE` is past this step).
3. **Diagnosis status.** `diagnosis.md` STATUS must be `REPORTED`.

## What you do

1. **Delegate to qa.** Use the Task tool to spawn `build-fleet:qa` with this prompt:

   > You are qa in the troubleshoot-fix **bug lane**, REPRODUCE phase, for bug `<slug>`.
   > Read `.sdd/<slug>/diagnosis.md` (the symptom is under `## Symptom + reproduction steps`).
   >
   > Author **at least one failing test under `tests/`** that **reproduces the bug** — it must
   > fail *because of the defect*, not because of a missing fixture or import. Run the suite and
   > confirm the new test(s) are RED for the right reason. (Writing under `tests/` is always
   > permitted; you must NOT write source — `require-reproducing-test` blocks source until the
   > diagnosis is CONFIRMED, which is later.)
   >
   > Then edit `.sdd/<slug>/diagnosis.md`: sharpen `## Symptom + reproduction steps` with the
   > concrete steps / the test's path, and flip the STATUS line `REPORTED → REPRODUCING`
   > (keep all four `##` sections — `validate-diagnosis-status` enforces them).
   >
   > Signal when done: `BUILD_FLEET_REPRO_READY: <count> failing test(s) reproducing <slug>`.

2. **Verify and advance.** Confirm qa signalled `BUILD_FLEET_REPRO_READY` with ≥1 failing test
   and that `diagnosis.md` STATUS is now `REPRODUCING`. Then edit `.sdd/<slug>/PROGRESS.md`:
   `PHASE: REPORT → REPRODUCE`, refresh `UPDATED`.

3. **Emit** the signal (before prose):
   ```
   BUILD_FLEET_REPRO_READY: {"slug":"<slug>","failing_tests":<int>}
   ```

4. **Report** the next command: `/build-fleet:diagnose` — record a root-cause hypothesis in
   `diagnosis.md`, then run the adversarial confirmation workflow.

## Notes

- You do not flip `diagnosis.md` STATUS yourself — qa owns the artifact's content in this phase
  (it writes the reproduction steps and the `REPORTED→REPRODUCING` flip). You own `PROGRESS.md`.
- All `tests/` and `.sdd/` writes are gate-permitted at any bug phase; only *source* is gated.

## Refusal cases

- No active item / active item is a forward feature → refuse.
- `PHASE` ≠ `REPORT`, or `diagnosis.md` STATUS ≠ `REPORTED` → refuse, naming the actual state.
