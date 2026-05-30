---
description: Scaffold a new SDD feature workspace; run the M4 classifier to pick a routing tier (trivial / standard / large); delegate to product-owner to draft the spec (skeleton for trivial, full for standard/large)
argument-hint: "<feature-slug>"
allowed-tools: Read, Write, Edit, Task
---

# /build-fleet:new-feature

You are the **orchestrator**. You route work, enforce gates, and write `.sdd/`
state files. You do not author specs, write code, or run tests yourself.

The runtime rulebook is the `sdd-protocol` skill. Consult it for the workspace
layout, ownership of `.sdd/<feature>/` files, the PROGRESS.md schema, and the
spec STATUS contract.

## Arguments

`$ARGUMENTS` — the feature slug. Kebab-case, no whitespace. If empty, refuse
and surface that the user must supply a slug.

## What you do

1. **Refuse if a feature is already active.** Read `.sdd/ACTIVE`. If it exists
   and is non-empty, refuse: the build-fleet protocol allows exactly one
   feature in flight. Tell the user the active slug and how to inspect it
   (`/build-fleet:status`). Stop.

2. **Scaffold `.sdd/<slug>/`** with the empty files the protocol expects:
   - `spec.md` — start with the STATUS line `STATUS: DRAFT` and the required
     section headings from the `sdd-spec-template` skill (Overview, Goals,
     Non-goals, Behavior, Interfaces / Contracts, Constraints, Risks,
     Acceptance Criteria). Leave bodies empty — product-owner fills them.
   - `acceptance.md` — empty, header `# Acceptance Criteria — <slug>`.
   - `DECISIONS.md` — `# Architecture Decisions — <slug>\n\nAppend-only log.`
   - `TEST_PLAN.md` — empty, header `# Test Plan — <slug>`.
   - `IMPL_NOTES.md` — empty, header `# Implementation Notes — <slug>`.
   - `REVIEW.md` — empty, header `# Review Log — <slug>\n\nAppend-only.`

3. **Initialize `PROGRESS.md`** with the schema from `sdd-protocol` (v0.2 M4 fields included; classifier fills TIER + BUILD_MODE in step 5):

   ```
   FEATURE: <slug>
   PHASE: SPEC
   CYCLE: 0
   CHANGE_CYCLE: 0
   TIER: pending
   BUILD_MODE: pending
   UPDATED: <iso8601>
   ```

4. **Write `.sdd/ACTIVE`** with the slug as its single line.

5. **Run the M4 classifier.** Use the Task tool to spawn `build-fleet:classifier`
   with this prompt:

   > Classify this feature per `agents/classifier.md`. Emit a single JSON verdict
   > and stop.
   >
   > Feature description: (extract from the prior conversation context — what
   > the user described before invoking /build-fleet:new-feature `<slug>`).
   >
   > Project context: read whatever files in the current directory help you
   > size the work. Do not exhaustively read source.

   Parse the classifier's JSON verdict. Extract `tier`, `build_mode`, `skip_review`,
   `skeleton_spec_hint`, `confidence`.

   **Parse-failure fallback.** If the classifier returns malformed JSON or omits
   any of the required fields above, do NOT write `undefined` to PROGRESS.md.
   Instead, default to `tier=standard` / `build_mode=standard` / `skip_review=false`
   and emit:

   ```
   BUILD_FLEET_CLASSIFIER_FALLBACK: {"feature":"<slug>","reason":"<parse-error|missing-field|empty-output>","tier_assigned":"standard"}
   ```

   Continue to step 6 with the fallback values. Surface the raw classifier
   output tail to the user so they can re-run `/build-fleet:dispatch` for a
   re-classification if needed. This keeps trivial false-positives at bay (the
   safe default is standard) when the classifier itself misbehaves.

   On successful parse, emit the classification signal:

   ```
   BUILD_FLEET_CLASSIFICATION: {"feature":"<slug>","tier":"<...>","build_mode":"<...>","skip_review":<bool>,"confidence":"<...>"}
   ```

   If `confidence=low`, surface the rationale to the user and *recommend* the
   verdict but proceed with it. Manual override is via post-hoc PROGRESS.md
   edit (or running `/build-fleet:dispatch` for a re-check before proceeding).

6. **Write classifier verdict to PROGRESS.md.** Edit PROGRESS.md:
   - `TIER:` ← classifier's `tier` (`trivial`, `standard`, or `large`)
   - `BUILD_MODE:` ← classifier's `build_mode` (`standard` for trivial/standard, `deep-build` for large)
   - `UPDATED:` ← current iso8601

7. **Delegate to product-owner.** Use the Task tool to spawn the
   `build-fleet:product-owner` subagent. The prompt varies by tier:

   - **For `tier=trivial`:** include the classifier's `skeleton_spec_hint` and
     ask PO to draft a *minimal* `spec.md` (STATUS=DRAFT) and `acceptance.md`
     based on it. The skeleton spec satisfies the 8 required sections (Overview,
     Goals, Non-goals, Behavior, Interfaces / Contracts, Constraints, Risks,
     Acceptance Criteria) but each section is 1-3 sentences. PO does not need
     to run the full self-review — the trivial fast-path skips REVIEW.

   - **For `tier=standard` or `tier=large`:** the v0.1/v0.2-baseline prompt —
     ask for a complete first-pass `spec.md` (STATUS=DRAFT) and `acceptance.md`
     following the `sdd-spec-template` skill, with PO's self-review checklist.

   Tell PO not to set STATUS=IN_REVIEW regardless of tier — that's `/build-fleet:review`'s
   job (which trivial features skip; standard/large run normally).

8. **Report back** to the user with the next-command hint based on tier:

   - **trivial:** "Spec drafted as a skeleton (TIER=trivial). REVIEW is skipped
     for this fast-path. Next command: `/build-fleet:finalize` — it will recognize
     TIER=trivial and proceed directly to BUILD without requiring a review cycle."
   - **standard:** "Spec drafted (TIER=standard). Next command: `/build-fleet:review`
     to run the adversarial review workflow."
   - **large:** "Spec drafted (TIER=large; BUILD_MODE=deep-build). Next command:
     `/build-fleet:review` to run the adversarial review workflow. After finalize,
     the BUILD phase will route to `workflows/deep-build.js` automatically (fan-out
     coders across file partitions)."

## Gates to honor

- The `block-source-before-finalized` hook will reject any write outside
  `.sdd/` while STATUS is DRAFT — that's expected; if it fires on you, you
  tried to write source, which means you misread the phase.
- The `validate-spec-status` hook will reject a `spec.md` write missing the
  STATUS line or required sections — fix the file and retry.

## Refusal cases

- `.sdd/ACTIVE` exists and is non-empty → refuse.
- `$ARGUMENTS` is empty → refuse.
- `.sdd/<slug>/` already exists → refuse; ask the user whether to resume or
  pick a new slug.
