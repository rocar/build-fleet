---
description: Gate: flip the spec to FINALIZED and unlock source
allowed-tools: Read, Edit, Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/finalize-gate.sh":*), Bash(date:*)
---

# /build-fleet:finalize

You are the **orchestrator**. The runtime rulebook is the `sdd-protocol`
skill. Consult it for the finalize gate definition.

This is a **gate**, not a request. You do not finalize on demand — you check
the conditions, and if they hold you flip the state. If they don't, you
refuse with an actionable diff.

**This command is the gate ONLY.** It checks the review record, flips
`spec.md` to `FINALIZED`, sets `PHASE: BUILD`, and stops. The BUILD
orchestration (qa-first test drafting, coder dispatch, deep-build routing)
lives in **`/build-fleet:build`** — run it after this gate passes. The split
keeps finalize **idempotent**: re-running it on an already-finalized feature
is a safe no-op.

**Trivial fast-path.** Trivial features (TIER=trivial, set by the classifier
at `/build-fleet:new-feature` time) skip the REVIEW phase entirely. Step 2
below recognizes this and finalizes without requiring a completed review
cycle.

## What you do

1. **Resolve the active feature.** Read `.sdd/ACTIVE`. If empty, refuse:
   `BUILD_FLEET_FINALIZE_REFUSE: {"code":2,"reason":"no-active-feature"}`.

2. **Check phase + tier.** Read PROGRESS.md. Extract `PHASE`, `TIER`
   (defaults to `standard` if absent), and `STATUS` from spec.md.

   - **Already finalized (idempotent re-run).** If `STATUS=FINALIZED` and
     `PHASE=BUILD`, the gate has already passed — this re-run is a safe no-op.
     Emit:
     `BUILD_FLEET_FINALIZE_PASS: {"feature":"<slug>","status":"FINALIZED","phase":"BUILD","already_finalized":true}`
     and tell the user the next move is `/build-fleet:build` (or
     `/build-fleet:handoff` if BUILD already completed). Change nothing.

   - **Trivial fast-path.** If `TIER=trivial` AND `PHASE=SPEC` AND `CYCLE=0`:
     - The classifier already decided REVIEW is unnecessary; skip the
       review-cycle gate entirely.
     - **Still check `.sdd/<slug>/ESCALATION.md`.** Even on the trivial path, a
       human can write ESCALATION.md to halt a feature (e.g., "actually wait,
       I changed my mind"). If present, refuse with `BUILD_FLEET_FINALIZE_REFUSE:
       {"feature":"<slug>","code":2,"reason":"escalation-present","tier":"trivial"}` and
       surface the ESCALATION.md contents.
     - Verify `spec.md` exists and has a valid STATUS line + required sections
       (the `validate-spec-status` hook would catch missing sections anyway).
     - Emit: `BUILD_FLEET_FINALIZE_TRIVIAL_FAST_PATH: {"feature":"<slug>","tier":"trivial"}`
     - Skip step 4 (no review-cycle to validate). Jump directly to step 6 (pass output).

   - **Standard / large normal path.** `PHASE` must be `REVIEW`. If it's `SPEC`
     (no review has run) AND `TIER` is `standard` or `large`, refuse with:
     `BUILD_FLEET_FINALIZE_REFUSE: {"feature":"<slug>","code":2,"reason":"no-review-cycle","tier":"<TIER>","detail":"run /build-fleet:review first"}`.

   - If `PHASE` is past `REVIEW` and not already-finalized (handled above), refuse
     and surface the actual phase
     (`{"code":2,"reason":"wrong-phase","phase":"<PHASE>"}`).

3. **Check ESCALATION.md.** If `.sdd/<active>/ESCALATION.md` exists, refuse —
   the feature is escalated and only a human can unblock it
   (`/build-fleet:resolve-escalation` is the sanctioned path).

4. **Run the gate script.** The gate is deterministic (v0.9) — never evaluate REVIEW.md
   in prose. Run:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/finalize-gate.sh" "<slug>"
   ```

   The script reads `REVIEW_ROLES` from PROGRESS.md. It prints exactly one line:

   ```
   BUILD_FLEET_FINALIZE_GATE: {"feature":"<slug>","cycle":<N>,"pass":true|false,"reasons":[...],"open_blockers":[...],"open_majors":[...],"majors_without_adr":[...]}
   ```

   The rule it enforces, over the LAST block per roster role for the current `CYCLE`:
   - every roster role has a block (else `missing-<role>`);
   - zero `[blocker]` lines (else `open-blockers`);
   - zero `[major]` lines whose disposition is `fix` or absent (else `majors-open`);
   - every `disposition: adr ADR-N` cites an `## ADR-N:` present in the feature
     `DECISIONS.md` (else `majors-without-adr`).
   `status:` lines are informational and NOT evaluated. Exit 0 ⇒ pass (step 6);
   exit 2 ⇒ refuse (step 5), relaying the script's `reasons`; exit 1 ⇒ the workspace
   is unreadable — report it and stop.

5. **Refusal output.** If the gate refuses, emit exactly one machine-readable line
   first (for headless orchestrators), then the human-readable structured list:

   ```
   BUILD_FLEET_FINALIZE_REFUSE: {"feature":"<slug>","cycle":<N>,"code":2,"reasons":["missing-<role>","open-blockers","majors-without-adr"]}
   ```

   Reason codes (from the gate script; combine as needed):
   - `missing-<role>` — reviewer block absent for the current cycle (one per missing role)
   - `open-blockers` — current cycle has open `[blocker]` items
   - `majors-open` — `[major]` items dispositioned `fix` (or carrying no disposition line)
   - `majors-without-adr` — `[major]` items whose `disposition: adr ADR-N` cites an ADR absent from DECISIONS.md
   - `not-approved` — **no longer emitted since v0.9** (status lines are informational); kept in the grammar for older orchestrators

   Then the structured list (human-readable):
   - Reviewers missing their current-cycle block.
   - Open `[blocker]` items, verbatim, with the reviewer attribution.
   - `[major]` items lacking ADRs.
   - The recommended next command: `/build-fleet:revise` (hands the PO exactly the open items), then `/build-fleet:review`.

6. **Pass output — flip state and stop.** If the gate passes:

   - Edit `spec.md` so the STATUS line reads `STATUS: FINALIZED`.
   - Edit PROGRESS.md: set `PHASE: BUILD`, refresh `UPDATED:` with `date -u +%Y-%m-%dT%H:%M:%SZ`. The
     source-write block lifts at this point.
   - Emit:

     ```
     BUILD_FLEET_FINALIZE_PASS: {"feature":"<slug>","cycle":<N>,"status":"FINALIZED","phase":"BUILD"}
     ```

   - Tell the user: the spec is finalized; the next command is
     **`/build-fleet:build`**, which drives the BUILD sequence (qa drafts the
     failing test suite first, then coder implements — or routes to the
     deep-build workflow when `BUILD_MODE=deep-build`).

   Both edits are idempotent — flipping FINALIZED to FINALIZED is a no-op,
   and the step-2 already-finalized branch short-circuits before this point
   anyway.

## Hard rules

- This command **never** dispatches qa, coder, or any workflow. BUILD
  orchestration is `/build-fleet:build`'s job.
- This command **never** edits REVIEW.md. Reviewer blocks are append-only
  and owned by reviewers.
- This command **never** writes ADRs. A `[major]` reaches the gate already
  dispositioned by the review workflow's architect leg (`adr` = accepted, ADR
  written by the scribe; `fix` = open). `majors-open` means the PO has not closed a
  `fix` item — run `/build-fleet:revise`, then `/build-fleet:review`.
- This command **never** evaluates REVIEW.md itself — `scripts/finalize-gate.sh` is
  the gate; the command relays its line.
- A failing finalize is **not** a workflow failure — it's the gate doing
  its job. Report what's missing and let the user iterate.
- **Headless contract.** Every branch above emits exactly one `BUILD_FLEET_*:` line
  before any human-readable prose.

## Refusal contract (machine-readable)

A slash command runs inside the model session and **cannot set a process exit
code** — the session exits 0 either way. The `BUILD_FLEET_*` signal lines on
stdout are the **sole machine contract**. Every refusal emits exactly one
`BUILD_FLEET_FINALIZE_REFUSE:` line whose JSON carries `"code"` (an integer
preserving the legacy exit-code semantics: `2` = precondition refused) and
`"reason"`/`"reasons"` (kebab-case slugs). Orchestrators dispatch on the signal
line, never on the process exit status.
