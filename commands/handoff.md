---
description: Run CHANGE_REVIEW on the diff, then hand off to devops
allowed-tools: Read, Write, Edit, Bash, Task
user-invocable: false
---

<!-- Deliberately model-invocable (audit §3.22 evaluated): handoff is dispatched
     by the orchestrator inside the DEVELOPING loop, and its devops leg only
     advances on an explicit BUILD_FLEET_DEVOPS_OK signal — the human gates live
     at /build-fleet:finalize and /build-fleet:status ratify, not here. -->

# /build-fleet:handoff

You are the **orchestrator**. The runtime rulebook is the `sdd-protocol`
skill. Consult it for the CHANGE_REVIEW phase, the CHANGE_CYCLE budget
(≤ 3 then ESCALATE), and DevOps' refusal conditions.

## What you do

1. **Resolve the active feature.** Read `.sdd/ACTIVE`. If empty, refuse.

2. **Check phase.** Read PROGRESS.md. PHASE must be `BUILD`, `CHANGE_REVIEW`
   or `HANDOFF`. If it's anything else (especially `SPEC` or `REVIEW`), refuse
   and tell the user to run `/build-fleet:finalize` then `/build-fleet:implement`
   first. **`PHASE: HANDOFF` is a resume**: a previous run passed CHANGE_REVIEW
   and reached devops, and devops refused or failed (step 9 leaves `PHASE:
   HANDOFF` in that case). Run the gate to confirm the current change cycle
   still passes —
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/change-review-gate.sh" "<slug>"` — and
   on `"pass":true` run the drift gate (step 4) and, if it passes, skip straight to step 9.
   On `"pass":false` the workspace was edited by hand since; continue at step 3 as a normal run. If the gate prints
   no `BUILD_FLEET_CHANGE_REVIEW_GATE:` line it could not evaluate (exit 1: no
   PROGRESS.md, a non-integer `CHANGE_CYCLE`, jq missing); refuse with its
   stderr. The same holds wherever this command runs the gate.

3. **Check ESCALATION.md.** If it exists, refuse.

4. **Pre-flight: tests must exist and pass.**
   - If no tests exist (no test files under the test roots, no `test`
     command), refuse: BUILD is not complete until qa has authored tests
     for the spec's acceptance criteria.
   - Run the project's test command (npm test / pytest / make test, per
     `stop-tests.sh`'s detection). If tests fail, refuse with the failing
     output. The `stop-tests` hook would catch this at session-end anyway;
     catching it here gives a clearer error.
   - Run the drift gate: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/drift-gate.sh" "<slug>"`,
     and relay its `BUILD_FLEET_DRIFT_GATE:` line. This runs before the change-cycle
     budget and before `CHANGE_CYCLE` moves, so a failure never spends a review cycle.
     `"pass":true` (an unchecked feature included) → continue. `"pass":false` → set
     `QA_FAIL: drift` in PROGRESS.md, emit
     `BUILD_FLEET_HANDOFF_REFUSE: {"feature":"<slug>","code":2,"reason":"drift","gate":<the gate line's JSON>}`
     and stop; the lite `build` command repairs the criterion markers. No line at all (exit 1) →
     emit `BUILD_FLEET_HANDOFF_REFUSE: {"feature":"<slug>","code":2,"reason":"drift-gate-error"}`
     with its stderr and stop.

5. **Check the change-cycle budget.** Read `CHANGE_CYCLE:` from PROGRESS.md.
   The budget is 3 change-review cycles. If `CHANGE_CYCLE >= 3`, run the gate
   over the current cycle — never evaluate REVIEW.md in prose:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/change-review-gate.sh" "<slug>"
   ```
   Relay its `BUILD_FLEET_CHANGE_REVIEW_GATE:` line. On `"pass":true` the
   current cycle already passed (a previous run stopped before devops): skip to
   step 9. On `"pass":false` the budget is exhausted with findings open: write
   `ESCALATION.md` with the change-cycle context, the gate line's
   `open_blockers` verbatim and each `open_majors` id with its raising `- [major]`
   line from REVIEW.md, set `PHASE: ESCALATED`, stop. If `reasons` holds only
   `missing-<role>`, `unparsed-findings` or `majors-without-adr`, apply step 8's
   re-dispatch bullets first and re-run the gate before escalating. This guard exists for a workspace whose third cycle
   was recorded before the gate existed and bounced without escalating; a run
   that reaches step 8 on the exhausting cycle escalates there directly.

6. **Bump the change-cycle.** Increment `CHANGE_CYCLE` in PROGRESS.md. Set
   `PHASE: CHANGE_REVIEW`. Refresh `UPDATED:` (computed with
   `date -u +%Y-%m-%dT%H:%M:%SZ`, never guessed). If `REVIEW.md` does not exist yet (a
   trivial feature has no spec review), create it with the standard append-only header
   now, so the two parallel reviewers in stage one never both create it.

7. **Run CHANGE_REVIEW in two stages.** The reviewers are `build-fleet:product-owner`,
   `build-fleet:qa` and `build-fleet:architect`. **Stage one:** launch product-owner
   and qa in parallel (two Task calls in a single message) and wait for both
   `## Change-Cycle <CHANGE_CYCLE>` blocks to exist in REVIEW.md. **Stage two:**
   launch the architect alone, pointing it at those two fresh blocks. The
   architect runs last so it can accept a peer's major by ADR in this same cycle
   (closed-by-id, below) instead of after a coder bounce. Agent count is
   unchanged; the cycle takes roughly one architect run longer.

   Every prompt includes:
   - The active feature slug and the current CHANGE_CYCLE number.
   - The current UTC time (`date -u +%Y-%m-%dT%H:%M:%SZ`) for the block heading:
     reviewers without Bash use it and never guess one.
   - A pointer to the diff (the orchestrator runs `git diff` against the
     base if a git repo; otherwise describe the changed files).
   - A pointer to `spec.md` (its acceptance criteria included), `DECISIONS.md` and
     `IMPL_NOTES.md` if it exists. The tests' `<slug>/AC-<n>` markers map criteria to tests.
   - The reviewer-specific lens:
     - architect: design adherence + ADR compliance.
     - product-owner: meets the spec's acceptance criteria?
     - qa: coverage gaps before handoff.
   - The REVIEW.md entry format and severity rubric reminder. **CHANGE_REVIEW
     blocks are headed `## Change-Cycle <CHANGE_CYCLE> — <role> — <iso8601>`**
     (distinct from spec-review's `## Cycle N`, so they never collide in one
     REVIEW.md and the `check-review-written` hook enforces the right block).
   - **The finding grammar the gate reads.** Every finding carries a stable id
     `(<role>-cc<K>-<n>)` where `K` is the change cycle it was FIRST raised in; a
     re-raised finding keeps its id. Every `[major]` carries a continuation line
     `  disposition: fix` (the default — coder must close it) or
     `  disposition: adr ADR-N` (architect only, after appending ADR-N to
     DECISIONS.md).
   - **When `CHANGE_CYCLE >= 2`, the delta rule**, with a pointer to the previous
     cycle's `## Change-Cycle <CHANGE_CYCLE-1>` blocks: verify closure of your own
     prior blockers and `fix` majors against the new diff and re-raise by original
     id what is still open; new findings are `[blocker]` only, plus advisory
     `[minor]`s. A new `[major]` raised at this cycle is advisory — the gate
     reports it as demoted and it does not block.
   - **Architect only — closed-by-id.** Read the product-owner and qa blocks for
     this cycle (and, from cycle 2, the previous cycle's). For each open `fix`
     major that is a design trade-off rather than a defect: append the ADR to
     `DECISIONS.md` first, then list the peer's id under your own block with
     `  disposition: adr ADR-N`. The gate closes that id in every block. A defect
     stays `fix`.

8. **Evaluate the cycle with the gate.** Once the three `## Change-Cycle <CHANGE_CYCLE>`
   blocks exist, run — never evaluate REVIEW.md in prose:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/change-review-gate.sh" "<slug>"
   ```
   Relay its `BUILD_FLEET_CHANGE_REVIEW_GATE:` line verbatim. The rule is the
   rubric's: every roster role has a current-cycle block; zero unrefuted
   `[blocker]`s; every `[major]` closed by `disposition: adr ADR-N` (ADR present) or
   demoted as a new major on a delta cycle.
   - `"pass":true` → CHANGE_REVIEW passes. Continue to step 9.
   - `"pass":false` with `missing-<role>` or `unparsed-findings` in `reasons` → a
     reviewer's block is absent, or holds a finding bullet the grammar cannot read
     (an indented `- [blocker]` / `- [major]`; the gate lists them under
     `unparsed`). Re-dispatch that reviewer (`build-fleet:<role>`) to write its
     `## Change-Cycle <CHANGE_CYCLE>` block with every finding at column 0, then
     re-run the gate. No cycle bump; coder is not involved.
   - `"pass":false` with `majors-without-adr` in `reasons` → the architect cited an
     ADR that DECISIONS.md does not hold (ids under `majors_without_adr`). That is
     the architect's defect, not coder's: re-dispatch `build-fleet:architect` to
     append the ADR or correct the id, then re-run the gate. No cycle bump.
   - `"pass":false` with only `open-blockers` / `majors-open` left and
     `CHANGE_CYCLE < 3` → delegate to `build-fleet:coder` with exactly the line's
     `open_blockers` (full text) and `open_majors` — resolve each id to its
     `- [major]` line in the raising block and pass id + text — plus a pointer to
     the blocks that raised them (PHASE returns to `BUILD`). Do not auto-loop; tell
     the user BUILD is open again and to re-run `/build-fleet:handoff` once coder
     is done. The `CHANGE_CYCLE` counter persists. **STOP here — do NOT continue to
     steps 9–12.** The feature is not shipped; `.sdd/ACTIVE` stays set.
   - `"pass":false` with only `open-blockers` / `majors-open` left and
     `CHANGE_CYCLE >= 3` → the exhausting cycle escalates: write `ESCALATION.md`
     with the change-cycle context, the line's `open_blockers` verbatim and each
     `open_majors` id with its raising line, set `PHASE: ESCALATED`, stop.
   - `"demoted"` non-empty → mention the demoted ids to the user as advisory; they
     never block.

9. **Hand off to devops.** Set `PHASE: HANDOFF` in PROGRESS.md. Use the Task
   tool to launch `build-fleet:devops` with a prompt that:
   - Names the active feature.
   - Carries the passing `BUILD_FLEET_CHANGE_REVIEW_GATE:` line verbatim (from
     step 8, or from step 2 / step 5 when those skipped here). devops refuses
     without it.
   - Pointers to spec.md, DECISIONS.md, and IMPL_NOTES.md if it exists.
   - Asks for CI/CD updates, IaC if applicable, and release notes.
   - Reminds devops to refuse if PHASE isn't HANDOFF — defense in depth.
   - Reminds devops to end with its completion signal — `BUILD_FLEET_DEVOPS_OK`
     on a genuine ship, `BUILD_FLEET_DEVOPS_REFUSED` otherwise (per `agents/devops.md`).

   **Branch on the devops result before step 10 — key off its machine signal, not
   its prose.** devops emits exactly one terminal line (`agents/devops.md` →
   Completion signal): `BUILD_FLEET_DEVOPS_OK: {…}` on a genuine ship, or
   `BUILD_FLEET_DEVOPS_REFUSED: {…,"reason":…}` on any refusal/failure. **Proceed to
   step 10 ONLY if you see `BUILD_FLEET_DEVOPS_OK`.** In every other case — `_REFUSED`,
   **or neither line present (a silent/ambiguous return counts as failure)** — emit:
   ```
   BUILD_FLEET_HANDOFF_DEVOPS_FAIL: {"feature":"<slug>","reason":"<refused|deploy-failed|no-signal>"}
   ```
   then surface devops' output, **leave `PHASE: HANDOFF` and `.sdd/ACTIVE`
   untouched, and STOP.** **Steps 10–12 run ONLY on `BUILD_FLEET_DEVOPS_OK`** — the
   feature is not shipped otherwise, so it must not be marked done and its `ACTIVE`
   must not be cleared. The user resolves the devops issue and re-runs
   `/build-fleet:handoff`. *(Defaulting an unrecognized/missing signal to failure is
   deliberate — the safe default is "not shipped," never a false advance.)*

10. **On devops success.** Leave `spec.md` untouched (it is frozen and at its line
    budget). Record the ship in PROGRESS.md: `SHIPPED: <iso8601>` and
    `SHIPPED_CHANGE_CYCLE: <the CHANGE_CYCLE that approved>` (add the lines if absent;
    an `.sdd/` write, always gate-permitted).
    Tell the user the feature is shipped (or in the project's equivalent
    of shipped — opened PR, queued release, etc.).

11. **Flip the product backlog, if a product tier exists.** After a
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
    scribe is append-only and only workflows write through it.

12. **Advance the DEVELOPING loop.** This step runs **only** on the
    full-completion path — you reached it after devops **succeeded** (step 10) and the
    backlog flip (step 11). A CHANGE_REVIEW bounce-back to BUILD (step 8) and a devops
    refusal/failure (step 9 branch) both STOP earlier and never reach here, so an
    unshipped feature is never advanced.

    a. **Release the in-flight lock.** The shipped feature is no longer in flight —
       release via the shared script (it verifies the slug, removes `.sdd/ACTIVE.lock`,
       and empties `.sdd/ACTIVE` without deleting it; never hand-empty the file):
       ```bash
       bash "${CLAUDE_PLUGIN_ROOT}/scripts/acquire-active.sh" release "<slug>"
       ```
       This is **always** done on a successful ship, whether or not a product tier
       exists: it is the fix that lets the loop continue (`/build-fleet:new-feature`
       refuses while the lock is held, and nothing else releases it; leaving it held
       would deadlock the next feature). *(Safe: with no active feature,
       `block-source-before-finalized` and the per-reviewer hooks are simply inactive —
       correct between features.)*

    b. **Resolve the next unblocked feature (live).** Run the shared resolver — exactly
       one read-only call, the single source of truth for "what's next" (it returns
       `no-backlog` on its own when there is no product tier, so call it unconditionally):
       ```bash
       bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-feature.sh"
       ```
       It re-reads the **live** backlog (never a cached index) and emits one JSON line:
       `next` (slug+phase) | `complete` | `deadlocked` | `empty` | `no-backlog`. Do
       **not** re-derive the next feature in prose — use this output verbatim.

    c. **Surface, do not auto-start.** Report based on `status`:
       - `next` → name the next slug + its phase, and tell the user to start it with
         `/build-fleet:new-feature <slug>` (the loop surfaces; it does not auto-advance —
         starting the next feature stays an explicit act).
       - `complete` → the product backlog is fully shipped (`done/total`). Congratulate;
         note that appending features/phases to `backlog.md` re-opens the loop. ("Complete"
         is **derived** from the backlog — there is no terminal PHASE value to set.)
       - `deadlocked` → `<pending>` features remain but none are unblocked. Warn the user
         to check `depends-on` edges / dependency cycles in `backlog.md`. Do **not**
         escalate — the human reorders deps.
       - `empty` → a product backlog exists but **no feature rows parsed** (`total=0`).
         This is **not** "complete" — warn that the backlog has no parseable
         `- [ ] <slug> …` rows and to check its format. Do not congratulate.
       - `no-backlog` → the feature was not part of a product backlog (ad-hoc). Nothing
         to advance; skip silently.

    d. **Emit the machine-readable line** (headless contract):
       ```
       BUILD_FLEET_LOOP_ADVANCE: {"completed":"<slug>","backlog":"<in-progress|complete|deadlocked|empty|none>","next":"<next-slug|null>"}
       ```
       Map resolver `status` → `backlog`: `next`→`in-progress`, `complete`→`complete`,
       `deadlocked`→`deadlocked`, `empty`→`empty`, `no-backlog`→`none`. `next` is the
       slug only for `status:next`; it is `null` for every other status.

## Refusal cases

- `.sdd/ACTIVE` empty → refuse.
- PHASE not in `{BUILD, CHANGE_REVIEW, HANDOFF}` → refuse with the actual phase
  (`HANDOFF` is a resume, step 2).
- ESCALATION.md exists → refuse.
- No tests, or test command fails → refuse with the failing output.
- The drift gate fails, or prints no line → `BUILD_FLEET_HANDOFF_REFUSE` with reason
  `drift` (and `QA_FAIL: drift` set) or `drift-gate-error`.
- The gate prints no `BUILD_FLEET_CHANGE_REVIEW_GATE:` line (exit 1) → refuse
  with its stderr.
- `CHANGE_CYCLE` budget exhausted with the gate failing (`open-blockers` or
  `majors-open` in its `reasons`, after step 8's re-dispatches for
  `missing-<role>`, `unparsed-findings` and `majors-without-adr`) → write
  ESCALATION.md and stop.
- Gate failing below the budget → bounce to BUILD (not a refusal: coder is
  dispatched, the user re-runs handoff).
