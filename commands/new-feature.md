---
description: Scaffold a feature workspace and draft its spec
argument-hint: "<feature-slug>"
allowed-tools: Read, Write, Edit, Task, Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/intent-block.sh":*)
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

3. **Initialize `PROGRESS.md`** with the schema from `sdd-protocol` (the classifier fills TIER + BUILD_MODE in step 7):

   ```
   FEATURE: <slug>
   PHASE: SPEC
   CYCLE: 0
   CHANGE_CYCLE: 0
   BUILD_CYCLE: 0
   TIER: pending
   BUILD_MODE: pending
   UPDATED: <iso8601>
   ```

4. **Write `.sdd/ACTIVE`** with the slug as its single line.

5. **Establish the feature description.** Before classifying or drafting,
   determine *what the feature actually is* — the slug alone is not a spec.

   - Look back through the conversation for a description the user already gave
     (e.g. "build a celsius→fahrenheit converter that handles negatives").
   - **Check the product backlog for an inherited intent.** If
     `.sdd/_product/backlog.md` exists, run the shared intent-block extractor — the
     SAME script `/build-fleet:next-feature` uses, so the two always reach the same
     verdict (one grammar, one quality floor, one implementation):
     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}/scripts/intent-block.sh" --slug "<slug>" .sdd/_product/backlog.md
     ```
     It prints the canonical intent block (the 1–3 indented lines under the feature
     row) and a final `INTENT_VERDICT: usable|too-thin` line. On `usable`, that
     intent is the **plan author's starting description** — carry it forward (prefer
     it over re-deriving from the slug) and label it to the PO as the inherited
     intent (step 8). (If the slug has no backlog row, the script errors — that just
     means there is no inherited intent; continue.)
   - **Quality floor — a thin intent does NOT suppress the gate.** The script's
     verdict encodes the floor: usable = at least 2 of the intent's 3 components
     (what the feature is / its scope boundary / its non-goals); a missing intent or
     a bare slug-restatement ("the API client") is `too-thin`. On `too-thin`, treat
     the intent as absent and fall through to the STOP-and-ask below — the mere
     presence of a line does not excuse the gate. (The canonical prose definition of
     the floor lives in the `sdd-protocol` skill's `references/product-tier.md`.)
   - **If no usable description exists in context *and* no usable backlog intent, STOP and ask the user.**
     Do not infer requirements from the slug — a slug like `celsius-converter`
     names the feature but says nothing about behavior, inputs/outputs, edge
     cases, or constraints. Ask a focused prompt, e.g.: "What should `<slug>`
     do? Briefly: the behavior, inputs/outputs, and any edge cases or
     constraints." Wait for the answer before continuing. The classifier and
     product-owner both consume this description; classifying from a bare slug
     produces a hallucinated spec.
   - Carry the description (from context or from the user) verbatim into the
     classifier prompt below and into the product-owner delegation in step 8.

5b. **Inherit the product stack, if a product tier exists.** Check for
   `.sdd/_product/STACK.md`. If it exists:
   - Read `.sdd/_product/STACK.md` and `.sdd/_product/DECISIONS.md`.
   - Pass both verbatim into the classifier prompt (step 6) and the product-owner
     delegation (step 8) as **inherited, read-only product context**.
   - Instruct product-owner (and, if it raises a stack concern in review, the
     architect): the feature **inherits the *binding* product stack** — the
     `## Baseline (current)` section on a brownfield product, or the ratified
     greenfield stack. Any `## Forward direction (PROVISIONAL — unreviewed)`
     entries are **advisory only** and do not constrain this feature unless the
     feature *is* the migration that promotes them. The feature's feature-local
     `DECISIONS.md` must not contradict the binding stack. If the feature
     genuinely needs a different binding stack, that is **not** a feature-local
     override — it is a signal to revise the product tier (edit
     `.sdd/_product/STACK.md` + append a product ADR). Surface that to the user
     rather than silently diverging.

   If `.sdd/_product/STACK.md` does **not** exist, this is a plain feature-first
   repo (no product tier) — proceed exactly as before. The product tier is
   additive; its absence changes nothing.

6. **Run the classifier.** Use the Task tool to spawn `build-fleet:classifier`
   with this prompt:

   > Classify this feature per `agents/classifier.md`. Emit a single JSON verdict
   > and stop.
   >
   > Feature description: <the description established in step 5 — paste it
   > verbatim; never substitute the slug for a missing description>.
   >
   > Inherited product stack (only if a product tier exists — from step 5b):
   > <paste the BINDING stack from .sdd/_product/STACK.md — i.e. everything EXCEPT
   > entries marked provisional (whether a `## Forward direction (PROVISIONAL —
   > unreviewed)` section or per-line `PROVISIONAL` tags). If nothing is marked
   > provisional, the whole file binds (greenfield, or a fully-adopted brownfield).
   > Write "none — no product tier" only if .sdd/_product/STACK.md is absent>. Use
   > it only to size the work (a feature that migrates the product stack is
   > larger); do not let provisional forward entries inflate the size.
   >
   > Project context: read whatever files in the current directory help you
   > size the work. Do not exhaustively read source.

   Parse the classifier's JSON verdict. Extract `tier`, `build_mode`, `skip_review`,
   `skeleton_spec_hint`, `confidence`, `skill_manifest` (may be `null`).

   **Parse-failure fallback.** If the classifier returns malformed JSON or omits
   any of the required fields above, do NOT write `undefined` to PROGRESS.md.
   Instead, default to `tier=standard` / `build_mode=standard` / `skip_review=false`
   and emit:

   ```
   BUILD_FLEET_CLASSIFIER_FALLBACK: {"feature":"<slug>","reason":"<parse-error|missing-field|empty-output>","tier_assigned":"standard"}
   ```

   Continue to step 7 with the fallback values. Surface the raw classifier
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

7. **Write classifier verdict to PROGRESS.md.** Edit PROGRESS.md:
   - `TIER:` ← classifier's `tier` (`trivial`, `standard`, or `large`)
   - `BUILD_MODE:` ← classifier's `build_mode` (`standard` for trivial/standard, `deep-build` for large)
   - `UPDATED:` ← current iso8601

7b. **Persist the skill manifest, if any.** The `skill-routing` skill is
   the convention. If the classifier's `skill_manifest` is **non-null and has at
   least one non-empty `roles` entry**, write it to `.sdd/<slug>/SKILL_MANIFEST.md`:
   a one-line header `# Skill Manifest — <slug>` followed by a fenced ```json block
   containing the manifest object with `"feature":"<slug>"` added. This routes
   domain-appropriate skills to coder/qa at BUILD (see the `skill-routing` skill
   for the schema and the load-if-available semantics). Emit:

   ```
   BUILD_FLEET_SKILL_MANIFEST: {"feature":"<slug>","feature_type":"<...>","coder_skills":[...],"qa_skills":[...]}
   ```

   If `skill_manifest` is `null` or has only empty `roles`, **write no file** — its
   absence means "no routing," and BUILD proceeds unrouted. Do not scaffold an
   empty manifest. (Manifest routing is advisory and never gates anything.)

8. **Delegate to product-owner.** Use the Task tool to spawn the
   `build-fleet:product-owner` subagent. The prompt varies by tier:

   - **For `tier=trivial`:** include the classifier's `skeleton_spec_hint` and
     ask PO to draft a *minimal* `spec.md` (STATUS=DRAFT) and `acceptance.md`
     based on it. The skeleton spec satisfies the 8 required sections (Overview,
     Goals, Non-goals, Behavior, Interfaces / Contracts, Constraints, Risks,
     Acceptance Criteria) but each section is 1-3 sentences. PO does not need
     to run the full self-review — the trivial fast-path skips REVIEW.

   - **For `tier=standard` or `tier=large`:** ask for a complete first-pass `spec.md` (STATUS=DRAFT) and `acceptance.md`
     following the `sdd-spec-template` skill, with PO's self-review checklist.

   **Inherited product stack (both tiers — from step 5b).** If
   `.sdd/_product/STACK.md` exists, **prepend to the PO prompt**, verbatim and
   labeled "inherited, read-only product context": the **binding** stack and the
   product `DECISIONS.md`. The binding stack is everything in STACK.md NOT marked
   provisional (a `## Forward direction (PROVISIONAL — unreviewed)` section, or
   per-line `PROVISIONAL` tags); if nothing is marked provisional, the whole file
   binds (greenfield, or a fully-adopted brownfield). Instruct PO to draft the spec
   and acceptance so they **conform to the binding product stack** —
   the feature's stack choices must not contradict it.
   `## Forward direction (PROVISIONAL — unreviewed)` entries are advisory only and
   must not be treated as the stack unless this feature *is* the migration that
   promotes them. If the feature genuinely cannot fit the binding stack, PO must
   surface that as a product-tier revision signal (architect edits STACK.md +
   appends a product ADR), **not** a feature-local override.

   **Inherited feature intent.** If step 5 found a usable backlog
   **intent (1–3 lines)** for this slug, pass it to the PO labeled "inherited intent
   (the plan author's intended scope — a sketch, not the contract)". Instruct PO to **realize
   and elaborate** that intent into the full spec (Behavior / Interfaces / Acceptance
   Criteria), and to flag in `## Self-review notes` if the spec must deviate from the
   stated intent rather than silently drifting. If there was no intent line, omit this
   block — PO drafts from the established description as usual.

   Tell PO not to set STATUS=IN_REVIEW regardless of tier — that's `/build-fleet:review`'s
   job (which trivial features skip; standard/large run normally).

9. **Report back** to the user with the next-command hint based on tier:

   - **trivial:** "Spec drafted as a skeleton (TIER=trivial). REVIEW is skipped
     for this fast-path. Next commands: `/build-fleet:finalize` (which recognizes
     TIER=trivial and flips the spec without requiring a review cycle), then
     `/build-fleet:build`."
   - **standard:** "Spec drafted (TIER=standard). Next command: `/build-fleet:review`
     to run the adversarial review workflow (then finalize, then build)."
   - **large:** "Spec drafted (TIER=large; BUILD_MODE=deep-build). Next command:
     `/build-fleet:review` to run the adversarial review workflow. After
     `/build-fleet:finalize`, `/build-fleet:build` routes the BUILD phase to
     `workflows/deep-build.js` automatically (fan-out coders across file
     partitions)."

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
