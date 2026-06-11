---
description: File a bug into the troubleshoot-fix lane
argument-hint: "<symptom>"
allowed-tools: Read, Write, Edit, Task, Bash(rm -rf .sdd/:*)
---

# /build-fleet:triage

You are the **orchestrator** for the troubleshoot-fix bug lane. You route, gate, and write
`.sdd/` state; you do not diagnose or write source yourself. **Headless-first:** emit the
machine signal line **before** any human prose.

The runtime rulebook is the `sdd-protocol` skill (`references/bug-lane.md`). The `diagnosis.md`
structure is the `sdd-diagnosis-template` skill. This command is the bug-lane analog of
`/build-fleet:new-feature` and is the lane's **sole entry point** (the `REPORT` phase).

## Arguments

`$ARGUMENTS` — the bug **symptom** (free text: what's wrong, where, how it shows up). If
empty, refuse — you cannot triage without a symptom. Emit `BUILD_FLEET_REFUSE` and stop.

## What you do

1. **Refuse if an item is already active.** Read `.sdd/ACTIVE`. If it exists and is non-empty,
   refuse: build-fleet allows exactly one item in flight, and **a bug and a forward feature
   share the `.sdd/ACTIVE` lock**. Name the active slug and how to inspect it
   (`/build-fleet:status`). Emit:
   ```
   BUILD_FLEET_REFUSE: {"command":"triage","reason":"item-in-flight","active":"<slug>"}
   ```
   Stop. (A sev0 cannot preempt a mid-flight feature here; the human parks the feature
   first with `/build-fleet:park <reason>` — the sanctioned preemption path — then re-runs
   the triage.)

2. **Derive a bug slug.** kebab-case, prefixed `bug-`, a ≤6-word summary of the symptom
   (e.g. `bug-login-500-on-empty-email`). If `.sdd/<bug-slug>/` already exists, append a short
   disambiguator.

3. **Scaffold `.sdd/<bug-slug>/`** — exactly two files (the bug lane has **no** `spec.md`,
   `acceptance.md`, REVIEW.md, or TEST_PLAN.md at entry):

   - `diagnosis.md` per `sdd-diagnosis-template` — first non-blank line `STATUS: REPORTED`,
     then `# Bug: <short title>`, then the four required sections. Put the `$ARGUMENTS`
     symptom **verbatim** under `## Symptom + reproduction steps`; leave the other three as
     placeholders:
     ```
     STATUS: REPORTED

     # Bug: <short title>

     ## Symptom + reproduction steps
     <$ARGUMENTS, verbatim>

     (Concrete reproduction steps / a failing test land at /build-fleet:reproduce.)

     ## Root-cause hypothesis
     _(empty until DIAGNOSE)_

     ## Blast radius
     _(empty until DIAGNOSE)_

     ## Fix strategy
     _(empty until DIAGNOSE)_
     ```
   - `PROGRESS.md`:
     ```
     FEATURE: <bug-slug>
     PHASE: REPORT
     LANE: bug
     SEV: pending
     CYCLE: 0
     FIX_CYCLE: 0
     UPDATED: <iso8601>
     ```
     A bug PROGRESS carries **no** `TIER`/`BUILD_MODE` (forward-machine fields); the bug-lane
     hooks never read them.

4. **Write `.sdd/ACTIVE`** with the bug slug as its single line.

5. **Run the triage classifier.** Use the Task tool to spawn `build-fleet:classifier` in
   **bug mode** (see `agents/classifier.md` § Bug-mode):

   > Classify this BUG for the troubleshoot-fix lane per the "Bug-mode" section of
   > `agents/classifier.md`. Emit the bug-mode JSON verdict
   > (`{severity, cause_known, rationale, confidence}`) and stop.
   >
   > Symptom: <the `$ARGUMENTS` symptom, verbatim>.
   >
   > Project context: read whatever files help you judge severity and whether the root cause
   > is already obvious from the report. Do not exhaustively read source.

   Parse `severity`, `cause_known`, `confidence`.

   **Parse-failure fallback.** If the verdict is malformed or missing a field, default to
   `severity=sev1`, `cause_known=false` (stay in the lane — the dangerous miss is bouncing a
   genuine unknown-cause bug onto the trivial fast-path), and emit:
   ```
   BUILD_FLEET_CLASSIFIER_FALLBACK: {"slug":"<bug-slug>","reason":"<parse-error|missing-field>","cause_known":false,"severity":"sev1"}
   ```

6. **Route on `cause_known`.**

   - **`cause_known == true`** → the cause is obvious from the report; there is nothing to
     diagnose. This is **not** a bug-lane bug — it belongs on the forward trivial path. Emit:
     ```
     BUILD_FLEET_TRIAGE_KNOWN_CAUSE: {"symptom":"<text>","recommended":"/build-fleet:new-feature","reason":"cause is known — use the forward path"}
     ```
     Then **undo the scaffold** so the known-cause bug does not occupy the lock: `rm -rf` the
     `.sdd/<bug-slug>/` directory (Bash) and **empty `.sdd/ACTIVE`** (write an empty file).
     Tell the user to run `/build-fleet:new-feature <slug>` instead. Stop. (This is the sharp
     boundary with the trivial fast-path.)

   - **`cause_known == false`** → stay in the bug lane. Edit `PROGRESS.md`: set
     `SEV: <severity>` and `UPDATED:` (keep `PHASE: REPORT`). Emit:
     ```
     BUILD_FLEET_TRIAGE: {"slug":"<bug-slug>","severity":"<sev0|sev1|sev2>","cause_known":false,"phase":"REPORT"}
     ```
     If `confidence == low`, surface the rationale and recommend the verdict but proceed.

7. **Report** the next command: `/build-fleet:reproduce` — qa authors a failing reproduction
   test under `tests/` and flips `diagnosis.md` to `REPRODUCING`.

## Signals (emitted before prose)

```
BUILD_FLEET_TRIAGE:             {"slug":"<bug-slug>","severity":"sev0|sev1|sev2","cause_known":false,"phase":"REPORT"}
BUILD_FLEET_TRIAGE_KNOWN_CAUSE: {"symptom":"<text>","recommended":"/build-fleet:new-feature","reason":"cause is known — use the forward path"}
BUILD_FLEET_CLASSIFIER_FALLBACK:{"slug":"<bug-slug>","reason":"<...>","cause_known":false,"severity":"sev1"}
BUILD_FLEET_REFUSE:             {"command":"triage","reason":"<item-in-flight|empty-symptom>", ...}
```

## Gates to honor

- All `.sdd/` writes are always permitted (`block-source-before-finalized` and
  `require-reproducing-test` short-circuit on `.sdd/` paths), so scaffolding never trips a gate.
- The `diagnosis.md` you write is validated by `validate-diagnosis-status`: it must carry
  `STATUS: REPORTED` and all four `##` headings — the template above satisfies both.

## Refusal cases

- `.sdd/ACTIVE` exists and is non-empty → refuse (one item in flight).
- `$ARGUMENTS` is empty → refuse (no symptom to triage).
