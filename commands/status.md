---
description: Report state and the next command, or take a decision (park, resolve, ratify)
argument-hint: "[park <reason> | resolve [<slug>] <decision> | ratify [force]]"
allowed-tools: Read, Write, Edit, Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/status-snapshot.sh":*), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-feature.sh":*), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/finalize-gate.sh":*), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/lite-next.sh":*), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/acquire-active.sh":*), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/product-memory-splice.sh":*), Bash(rm:*), Bash(date:*)
disable-model-invocation: true
---

<!-- disable-model-invocation: status carries the three human decisions — park,
     resolve and ratify. If the model could invoke it, it could ratify a plan, waive an
     escalation or shelve work on its own, and the "only a human decides" guarantee would
     be fiction (audit §3.22). A human types this command. -->

# /build-fleet:status

You are the **orchestrator**. Read the first word of `$ARGUMENTS`:

- *(empty)* → **Report**. Read-only.
- `park` → **Park**; the rest of the arguments is the reason.
- `resolve` → **Resolve**; the rest is `[<slug>] <decision>`.
- `ratify` → **Ratify**; `force` may follow.
- anything else → print the argument hint above and stop.

This command never runs the lite loop. It asks `lite-next.sh status` once, for the
next command only.

## Report

### Pre-loaded state (gathered at prompt-build time)

The deterministic snapshot below was injected before you started — narrate
from it; only Read the underlying `.sdd/` files when you need detail it does
not carry (e.g. verbatim `[blocker]` text from REVIEW.md, ESCALATION.md
contents). If the snapshot line is empty or an error (e.g. `jq` missing),
fall back to reading the files directly per the steps below.

Snapshot (`build-fleet/status-snapshot@1`):
!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/status-snapshot.sh" 2>&1 || true`

### What you do

1. **Read `.sdd/ACTIVE`.** If empty or absent:
   - If `.sdd/_product/backlog.md` exists, there is a product tier with no feature
     in flight — skip the feature-detail steps (2–5) and go straight to the
     **Product backlog** section (step 5b), which surfaces the backlog and names the
     next unblocked feature to scaffold.
   - Otherwise report "no active feature" and go to step 6 for the next command.

1b. **Bug lane.** Read `.sdd/<active>/PROGRESS.md`. If it carries `LANE: bug`, the
   active item is a troubleshoot-fix **bug**, not a forward feature — report the **bug view** and
   **skip steps 2–4** (a bug has no `spec.md` or spec-review cycle):
   - Bug slug; `PHASE` (`REPORT|REPRODUCE|DIAGNOSE|FIX|VERIFY|HANDOFF|ESCALATED`); `SEV`.
   - `diagnosis.md` STATUS (`REPORTED|REPRODUCING|DIAGNOSED|CONFIRMED|FIXED`).
   - `CYCLE` (diagnose-confirmation cycles) and `FIX_CYCLE` (verify→fix bounces); `UPDATED`.
   - The count of test files under `tests/` (read-only — status never runs the suite; the
     `diagnosis.md` STATUS conveys the red→green lifecycle).
   - The most recent `.sdd/<slug>/REVIEW.md` diagnose block(s), if any (verbatim verdict lines).
   - Then do the ESCALATION check (step 5) and step 6 (the next command).
   Then **stop** — do not run the forward-feature steps 2–4.

2. **Read `.sdd/<active>/PROGRESS.md`.** Print:
   - Feature slug.
   - PHASE.
   - TIER and RISK (`pending` when the classifier has not run; absent RISK on a
     feature scaffolded before this field existed prints as `unset`).
   - REVIEW_ROLES and REVIEW_CYCLE_BUDGET (the seeded review roster and budget).
   - CYCLE (spec-review cycles consumed).
   - CHANGE_CYCLE (change-review cycles consumed).
   - CYCLE_TOTAL (cumulative spec-review cycles, never reset) against CYCLE_TOTAL_MAX
     (default 6), when present.
   - LAST_REVIEW_OUTPUT_TOKENS, when present.
   - UPDATED timestamp.

3. **Read `.sdd/<active>/spec.md` first line.** Print the STATUS value.

4. **Summarize the most recent REVIEW.md cycle.** If `REVIEW_SHAPE: verified` is set and the newest cycle blocks are verified, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/finalize-gate.sh" "<active>" --report` and print: the shape; open blockers and majors by id with their `why`; `spec_changed` when true ("the spec changed after it was reviewed — run /build-fleet:start"); and, from the last `script:quote-check` line of `.sdd/<active>/EVENTS.jsonl`, `checked` and `failures` (a failed quote means a reviewer or verifier cited text the spec does not contain).
   If PHASE is in spec-review
   territory, find the LAST block per roster role tagged with the current
   `CYCLE` (a same-numbered earlier block — e.g. after the 0.8→0.9 migration
   reset — is superseded); if PHASE is in change-review territory, find every
   block tagged with the current `CHANGE_CYCLE`. For each reviewer block,
   print:
   - Reviewer name.
   - `status:` line value.
   - Count of `[blocker]`, `[major]`, `[minor]` items — and for each `[major]`, its
     `disposition:` (`fix` = open, `adr ADR-N` = accepted; none = open, legacy block).
   - `finalize_ready`: yes iff zero UNREFUTED `[blocker]` lines (a `refuted-by:`
     continuation closes one) and zero open majors across the current cycle's blocks
     (this is the finalize gate's rule).
   - `change_review_ready` (change-review territory only): yes iff the rule of
     `scripts/change-review-gate.sh` holds over the current `CHANGE_CYCLE` blocks —
     every roster role (architect, product-owner, qa) has a block, zero unrefuted
     `[blocker]` lines, and every `[major]` is closed by `disposition: adr ADR-N`
     with that ADR in DECISIONS.md (an architect ADR closes a peer's id in every
     block) or is a new major on cycle ≥ 2 (advisory, "demoted"). A finding bullet
     the gate cannot read (an indented `- [blocker]` / `- [major]`) makes it `no`.
     `status:` lines are not evaluated.
   - Verbatim text of every `[blocker]` item (so the user sees what's
     actually open).

5. **Check for `.sdd/<active>/ESCALATION.md`.** If it exists, print a
   prominent banner: the feature is escalated. Then print the file's
   contents — phase, cycle count, unresolved blockers, conflicting
   positions. Only a human unblocks an escalation — by running
   **`/build-fleet:status resolve <decision>`** (archives the escalation into
   REVIEW.md, resets the exhausted cycle counter, restores the phase), or
   **`/build-fleet:status park <reason>`** to shelve the item entirely.

5b. **Product backlog, if a product tier exists.** If
   `.sdd/_product/backlog.md` exists, summarize it:
   - For each `## Phase N: <name> — STATUS:` line, print the phase name + its STATUS.
   - Under each phase, print every feature row with its state: `PENDING`, or `DONE`
     (with its `handoff:` date) — and if a row's slug matches `.sdd/ACTIVE`, annotate
     it `← active (in flight, PHASE=<phase>)`. Active is **derived from `.sdd/ACTIVE`**,
     not a backlog marker.
   - A roll-up line: `<done>/<total> features done across <N> phases`.
   - **If no feature is active, resolve what's next via the shared resolver**
     — the same read-only helper `/build-fleet:handoff` uses, so status and the loop never
     disagree:
     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-feature.sh"
     ```
     It emits one JSON line; report from its `status`:
     - `next` → name the slug + phase and suggest `/build-fleet:start`.
     - `complete` → "product backlog complete (`done/total`)" — nothing to start.
     - `deadlocked` → "`<pending>` features remain but none are unblocked — check
       `depends-on` / cycles in `backlog.md`."
     - `empty` → "backlog has no parseable feature rows — check its format" (not
       "complete"; `total=0`).
     Do **not** re-derive the next feature in prose; use the resolver output verbatim.
   Read-only, like the rest of status (the resolver only reads `backlog.md`).

5c. **Product plan awaiting ratification.** If `.sdd/_product/PROGRESS.md` has
   `PHASE: PLAN_REVIEW` (or the small fast-path holds: `SIZE: small`, `PHASE: PLAN`,
   `CYCLE: 0`), show what you would be ratifying: run **Ratify** steps 1–5 below
   read-only and print the dry run of step 6a there (its `BUILD_FLEET_PLAN_FINALIZE_DRYRUN`
   line, the open findings, and how to ratify). Change no state.

6. **Name the next command.** Run:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/lite-next.sh" status
   ```
   It prints one `BUILD_FLEET_LITE_NEXT:` line. End the report with
   "Next: `<next>`", or, when the line has no `next`, with its `why`. Do not
   derive the next command yourself; the router is the one source of truth.
   `build`, `ship` and `status` are human-only, so they
   never appear in your own command list; the router's `next` is still correct. Relay it verbatim and never substitute a
   hidden step (such as `finalize` or `handoff`) for it.
   A parked item's resume is a deliberate human edit (see **Park**).

## Park

Parking is a **human decision**. It is the **sanctioned sev0-preemption path**: build-fleet allows one item in flight,
and `/build-fleet:fix` refuses while `.sdd/ACTIVE` is occupied — when a sev0
lands mid-feature, the human parks the feature with this command, runs the bug
lane, and resumes later. It is also the sanctioned way to shelve a feature or
abandon a bug without hand-editing `.sdd/` state.

Parking does **not** delete anything. The `.sdd/<slug>/` workspace (spec,
reviews, notes, diagnosis) stays intact; only the in-flight lock is released
and the parked state is recorded.

### Arguments

The reason — the words after `park` (free text, **required**). If empty,
refuse: a park with no recorded reason is an audit hole.
`BUILD_FLEET_PARK_REFUSE: {"code":2,"reason":"missing-reason"}`.

### What you do

1. **Resolve the active item.** Read `.sdd/ACTIVE`. If empty or absent, refuse —
   there is nothing to park:
   `BUILD_FLEET_PARK_REFUSE: {"code":2,"reason":"no-active-item"}`.
   Verify `.sdd/<slug>/PROGRESS.md` exists; if not, refuse
   (`{"code":2,"reason":"missing-progress","feature":"<slug>"}`) — the state is
   already irregular and needs a human look, not an automated edit.

2. **Record the parked state in PROGRESS.md.** Edit `.sdd/<slug>/PROGRESS.md`:
   - Set the `PHASE:` field to `PARKED`.
   - Append a line at the end of the file:
     ```
     PARKED: <iso8601 now> — was PHASE <previous phase> — <reason verbatim>
     ```
     (Recording the pre-park phase is what makes an informed resume possible.)
   - Refresh `UPDATED:`.

3. **Release the lock via the shared script** (it verifies the slug, removes
   `.sdd/ACTIVE.lock`, and empties `.sdd/ACTIVE` without deleting it — never
   hand-empty the file). Do **not** delete `.sdd/<slug>/`:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/acquire-active.sh" release "<slug>"
   ```

4. **Emit the signal, then report.**
   ```
   BUILD_FLEET_PARKED: {"feature":"<slug>","reason":"<reason>","was_phase":"<previous phase>"}
   ```
   Tell the user: the item is parked with its workspace intact; the in-flight
   lock is free, so `/build-fleet:start` / `/build-fleet:fix` can start
   the next item. To resume the parked item later: re-acquire the lock —
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/acquire-active.sh" acquire "<slug>" --owner "human:resume" --now "<iso8601>"`
   — and restore the recorded pre-park `PHASE` in its PROGRESS.md (a deliberate,
   human act — there is no auto-resume).

### Park rules

- **Never** delete or truncate anything under `.sdd/<slug>/`.
- **Never** park on your own initiative — this command exists for the human;
  the orchestrator's job when blocked is to surface the conflict
  (`item-in-flight`) and stop.

## Resolve

An escalation means the bounded cycles were exhausted (or a human halted the work);
**only a human decision unblocks it**.

### Arguments

The words after `resolve` — `[<slug>] <decision>`:

- If the first token names an existing `.sdd/<token>/` directory, it selects
  that feature/bug; otherwise the active item from `.sdd/ACTIVE` is used.
- Everything else is the **decision** (free text, **required**): what the human
  chose — e.g. "accept architect's position, drop the streaming requirement" or
  "blockers waived for the prototype phase; revisit at v2".

If the decision is empty, refuse — an escalation cannot be waved through
without a recorded choice:
`BUILD_FLEET_RESOLVE_REFUSE: {"code":2,"reason":"missing-decision"}`.

### What you do

1. **Resolve the target.** Determine `<slug>` per the arguments. If neither a
   named slug nor a non-empty `.sdd/ACTIVE` resolves, refuse
   (`{"code":2,"reason":"no-target"}`).

2. **Require the escalation.** `.sdd/<slug>/ESCALATION.md` must exist. If not,
   refuse — there is nothing to resolve:
   `BUILD_FLEET_RESOLVE_REFUSE: {"feature":"<slug>","code":2,"reason":"no-escalation"}`.

3. **Read the escalation context.** From `ESCALATION.md`, note the phase it was
   written in and the cycle count. From `.sdd/<slug>/PROGRESS.md`, read `PHASE`
   (normally `ESCALATED`) and `LANE` (bug vs forward feature).

4. **Determine the pre-escalation phase and its cycle counter.** Prefer the
   phase recorded inside ESCALATION.md; if it is absent, infer from which
   counter is exhausted in PROGRESS.md. The mapping:

   | Pre-escalation phase | Counter to reset |
   |---|---|
   | `REVIEW` (spec review) | `CYCLE` |
   | `BUILD` (deep-build iterations) | `BUILD_CYCLE` |
   | `CHANGE_REVIEW` | `CHANGE_CYCLE` |
   | `DIAGNOSE` (bug lane) | `CYCLE` |
   | `FIX` / `VERIFY` (bug lane) | `FIX_CYCLE` |

   If you cannot determine the phase from either source, refuse
   (`{"code":2,"reason":"phase-undeterminable"}`) and ask the human to name it —
   never guess a state transition.

5. **Archive into the audit trail (append-only).** Append a block to
   `.sdd/<slug>/REVIEW.md`:

   ```
   ## Escalation resolved — <iso8601 now>
   ### Archived ESCALATION.md
   <the full ESCALATION.md content, verbatim>
   ### Human decision
   <the decision, verbatim>
   resolution: counter <name> reset, phase restored to <phase>
   ```

   `<iso8601 now>` is computed with `date -u +%Y-%m-%dT%H:%M:%SZ` — never guess it.

   Append only — never modify existing REVIEW.md entries. (For a bug that has
   no REVIEW.md yet, create it with the standard append-only header first.)

6. **Reset state.** Edit `.sdd/<slug>/PROGRESS.md`:
   - Set the exhausted counter from step 4 back to `0` (the human decision
     re-opens the budget).
   - Set `PHASE:` back to the pre-escalation phase from step 4.
   - Refresh `UPDATED:`.
   - **Never touch `CYCLE_TOTAL`** — the cumulative counter survives every reset
     by design; `/build-fleet:review` refuses at `CYCLE_TOTAL_MAX`, and raising
     that max is the human's recorded decision, not a side effect of resolving.

7. **Delete `.sdd/<slug>/ESCALATION.md`.** The gates key off this file's
   existence; it must go for work to resume. Its content is preserved verbatim
   in REVIEW.md (step 5), so nothing is lost.

8. **Emit the signal, then report.**
   ```
   BUILD_FLEET_RESOLVED: {"feature":"<slug>","phase":"<restored phase>","counter_reset":"<CYCLE|BUILD_CYCLE|CHANGE_CYCLE|FIX_CYCLE>","decision":"<first ~100 chars>"}
   ```
   Tell the user which phase the item is back in and the next command from
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lite-next.sh" status`. If the decision implies spec
   or diagnosis edits (e.g. "drop the requirement"), remind the human those edits
   are theirs/PO's to make before re-running the phase.

### Resolve rules

- **Never resolve without an explicit decision argument** — that text is the
  audit record of *why* the deadlock broke.
- **REVIEW.md is append-only.** Archive; never rewrite history.
- **Never touch spec.md, diagnosis.md, or DECISIONS.md** — the
  decision may *call for* edits there, but those belong to their owners.

## Ratify

The runtime rulebook is the `sdd-protocol` skill (`references/product-tier.md` — the PLAN
state machine). This is the **ratification gate** — the one place a human commits to the
product plan.

**A product plan is a strategic bet, not a contract the machine can converge.** So
this gate **never auto-passes**, even with zero findings. Ratification is an explicit
act: bare `/build-fleet:status` shows the plan and its open blockers and halts;
flipping state requires the explicit `ratify` form, typed by a human (`status` is not
model-invocable). The model cannot ratify on its own.

This gate is **advisory by design**: ratifying does NOT gate
`/build-fleet:start` (features build against the binding stack regardless).
What it does is (a) record the ratification, (b) flip vision/backlog `STATUS` to
`FINALIZED`, and (c) set `PHASE: DEVELOPING` — the state the DEVELOPING loop
reports against. The "teeth" live in that loop, not in a feature-creation block.

### Arguments

The words after `ratify`:
- *(none)* — **ratify**. Flip state IF there are zero open blocker-severity findings
  and zero unresolved split suggestions; otherwise refuse (`ratify force` overrides).
- `force` — **ratify over open blockers**. Flip state regardless, recording that
  ratification happened with N blockers consciously accepted.

The dry run (no state change) is bare `/build-fleet:status` (Report step 5c).

### What you do

1. **Resolve the product.** Read `.sdd/PRODUCT` (fall back to `.sdd/_product/PROGRESS.md`
   `PRODUCT:`). If no product tier, refuse:
   > `BUILD_FLEET_PLAN_FINALIZE_REFUSE: {"code":2,"reason":"no-product"}` — run `/build-fleet:start --product "<vision>"`.

2. **Refuse while a feature is mid-review (hook-confinement guard).** Read `.sdd/ACTIVE`;
   if non-empty and `.sdd/<active>/PROGRESS.md` `PHASE` is `REVIEW` or `CHANGE_REVIEW`,
   refuse — the `restrict-reviewer-writes` hook would block the `STATUS`/`PHASE` flips
   into `.sdd/_product/`:
   > `BUILD_FLEET_PLAN_FINALIZE_REFUSE: {"code":2,"reason":"feature-mid-review","feature":"<active>","phase":"<PHASE>"}`.

3. **Check escalation.** If `.sdd/_product/ESCALATION.md` exists, refuse — a human
   halted the plan. Refuse (`{"code":2,"reason":"escalation-present"}`) and surface its contents.

4. **Read product state.** From `.sdd/_product/PROGRESS.md` extract `PHASE`, `SIZE`,
   `CYCLE`. Determine the legal entry:
   - **Normal path.** `PHASE` must be `PLAN_REVIEW` — at least one interrogation cycle
     has run, so there is a report to ratify against.
   - **Small fast-path.** If `SIZE=small` AND `PHASE=PLAN` AND `CYCLE=0`, allow
     ratification without a prior `/build-fleet:plan-review` (mirrors the trivial-feature
     fast-path). There is no interrogation report; treat open-blocker count as 0.
     Emit `BUILD_FLEET_PLAN_FINALIZE_FAST_PATH: {"product":"<slug>","size":"small"}`
     before proceeding.
   - **Already ratified.** If `PHASE=DEVELOPING`, refuse:
     > `BUILD_FLEET_PLAN_FINALIZE_REFUSE: {"product":"<slug>","code":2,"reason":"already-ratified","phase":"DEVELOPING"}`.
     Tell the user the plan is already ratified; revise the `_product/` files directly
     and re-run `/build-fleet:start` (plan review) and `/build-fleet:status ratify` if strategy changes.
   - Any other phase (e.g. `PLAN` for a non-small product) → refuse with
     `{"code":2,"reason":"no-interrogation-cycle","detail":"run /build-fleet:start first (it reviews the plan)"}`.
   - *(Legacy tier, no `PHASE` field.)* The read returns empty,
     which falls into the `no-interrogation-cycle` refusal above — correct, since
     `/build-fleet:plan-review` is also what normalizes a legacy PROGRESS (seeds
     `PHASE`/`CYCLE`). Unlike `/build-fleet:plan-review`, this gate does **not** normalize;
     run plan-review once first.

5. **Count open blocker-severity findings.** Unless on the small fast-path, read
   `.sdd/_product/REVIEW.md`. Find the **latest** `## Plan Cycle <N>` blocks (highest N).
   Count `[blocker]` items across that cycle's role blocks. (The workflow also writes a
   `## Plan Cycle <N> — interrogation summary` block stating the count — use it to
   cross-check, but the authoritative count is the `[blocker]` line tally.) Call this `B`.

   **Split suggestions (v0.9).** In the same latest-cycle blocks collect every
   `  split-into: a, b, …` line (each sits under the finding it belongs to; the finding
   line carries its id in parentheses). For each proposed slug, it is **resolved** if
   `.sdd/_product/backlog.md` has a row `- [ ] <slug>` / `- [x] <slug>`, OR
   `.sdd/_product/DECISIONS.md` contains an ADR whose text cites that finding's id with
   the word `refuses` (e.g. "refuses product-owner-3: the split would …"). Call the
   count of unresolved split suggestions `S`.

6. **Branch on `$ARGUMENTS`.**

   **a. Dry run (Report step 5c only — never from the `ratify` form).** Emit:
   ```
   BUILD_FLEET_PLAN_FINALIZE_DRYRUN: {"product":"<slug>","phase":"<PHASE>","open_blockers":<B>,"unresolved_splits":<S>,"cycle":<N>}
   ```
   Then print, human-readably:
   - **Normal path** (`PHASE=PLAN_REVIEW`): the open `[blocker]` and `[major]` findings
     verbatim (with role attribution), and the consolidated summary line from REVIEW.md.
   - **Small fast-path** (`SIZE=small`, `PHASE=PLAN`, `CYCLE=0`): there is **no**
     `_product/REVIEW.md` — do not try to read it. Print `open_blockers: 0` and a note
     that this small product is ratifying without an interrogation cycle.

   End with:
   > To ratify, run `/build-fleet:status ratify`<if B>0: ` — `B`> blocker(s) open, so you'll need `/build-fleet:status ratify force` to override them</if>.

   **Do not change any state.** This is the headless safety stop.

   **b. `ratify` (no `force`) with `B > 0`.** Refuse — open blockers, no `force`:
   ```
   BUILD_FLEET_PLAN_FINALIZE_REFUSE: {"product":"<slug>","code":2,"reason":"open-blockers","open_blockers":<B>}
   ```
   List the open blockers verbatim and tell the user to either resolve them (edit the
   plan and run `/build-fleet:start`, which re-reviews an edited plan) or override with
   `/build-fleet:status ratify force`. No state changes.

   **b2. `ratify` (no `force`) with `S > 0`.** Refuse — a split the plan neither made
   nor refused:
   ```
   BUILD_FLEET_PLAN_FINALIZE_REFUSE: {"product":"<slug>","code":2,"reason":"split-unresolved","unresolved_splits":<S>}
   ```
   List each `split-into:` line with its finding id and which proposed slugs are
   missing; tell the user to either add the rows to `backlog.md` (and run
   `/build-fleet:start` to re-review) or have the architect record a product ADR refusing the
   split by finding id — or override with `ratify force`.

   **c. `ratify` with `B = 0` and `S = 0`, OR `ratify force` (any B, any S).** **Ratify — flip state** (step 7).

7. **Flip state (ratification).** This is the only path that writes:
   - Edit `.sdd/_product/vision.md`: set its `STATUS:` line to `FINALIZED`.
   - Edit `.sdd/_product/backlog.md`: set its `STATUS:` line to `FINALIZED`. *(This edit
     re-triggers `validate-backlog-status`; `FINALIZED` is a valid STATUS, so it passes.)*
   - Edit `.sdd/_product/PROGRESS.md`: set `PHASE: DEVELOPING`, refresh `UPDATED:`.
   - **`STACK.md` STATUS — conditional flip.** The stack-of-record is part of the ratified
     plan, so a `FINALIZED` product should not leave it labelled `DRAFT` — **but only when
     the whole stack is binding.** Read `STACK.md`:
     - If it contains **no** `## Forward direction (PROVISIONAL — unreviewed)` section and
       **no** `PROVISIONAL`-tagged lines (greenfield, or a fully-adopted brownfield), set its
       `STATUS:` line to `FINALIZED`.
     - If any provisional/forward content **is** present, **leave `STACK.md` STATUS
       untouched** — the file genuinely holds un-ratified strategy, and flipping the
       top-level STATUS would imply that strategy is ratified.
   - **Never promote PROVISIONAL → binding, and never touch `DECISIONS.md`.** Whatever the
     STACK STATUS decision above, do **not** un-tag, rewrite, or promote any
     `## Forward direction (PROVISIONAL — unreviewed)` section or `STATUS: PROVISIONAL` ADR.
     Ratification finalizes the plan **as written** — the binding stack is whatever is
     currently un-tagged; the conditional STACK STATUS flip only re-labels an already-fully-
     binding file. If the user wants a forward direction to bind, they un-tag it themselves
     (then run `/build-fleet:start` to re-review) before ratifying. The per-ADR `STATUS:` lines in `DECISIONS.md`
     are owned by the architect and are never edited here.

   Emit exactly one line:
   ```
   BUILD_FLEET_PLAN_FINALIZE_PASS: {"product":"<slug>","phase":"DEVELOPING","ratified_with_blockers":<true|false>,"accepted_blockers":<B-if-force-else-0>,"accepted_splits":<S-if-force-else-0>,"stack_finalized":<true|false>}
   ```
   (`stack_finalized` is `true` when STACK.md was flipped to `FINALIZED`, `false` when it
   was left as-is because provisional/forward content is present.)

7b. **Generate product memory (best-effort).** Seed the repo-root
   `./CLAUDE.md` with the ratified product per the `sdd-protocol` skill's **Product
   memory** generation algorithm (the `<!-- BEGIN/END build-fleet:product -->` block;
   non-clobbering + idempotent; binding stack only — never PROVISIONAL).

   - **Pre-check the block-source gate.** `./CLAUDE.md` is **outside** `.sdd/`, so
     `block-source-before-finalized` blocks the write if `.sdd/ACTIVE` names a feature
     whose `spec.md` STATUS ≠ `FINALIZED`. If that is the case, **do NOT attempt the
     write** — the ratification flip already succeeded (step 7, all in `.sdd/_product/`).
     Skip generation and emit:
     ```
     BUILD_FLEET_PLAN_FINALIZE_CLAUDEMD: {"product":"<slug>","status":"deferred","reason":"active-feature-not-finalized","feature":"<active>"}
     ```
     Tell the user the block is regenerated automatically by `/build-fleet:start` once
     the active feature is `FINALIZED` or cleared. **This is best-effort: a deferred memory block never fails
     the ratification** — the plan is ratified regardless.
   - **Otherwise** (no active feature, or its spec is `FINALIZED`) generate the
     block content (per the skill's distillation algorithm, WITHOUT the markers)
     and splice it via the tested script — **never** via model-driven Edit
     (audit §3.29):
     ```bash
     printf '%s\n' "<the generated block content>" | \
       bash "${CLAUDE_PLUGIN_ROOT}/scripts/product-memory-splice.sh" ./CLAUDE.md
     ```
     The script prints `created` / `updated-in-place` / `appended` (and refuses,
     exit 1 with no write, on a corrupt marker pair). Emit its status word:
     ```
     BUILD_FLEET_PLAN_FINALIZE_CLAUDEMD: {"product":"<slug>","status":"<created|updated-in-place|appended>"}
     ```
     If the script errors, surface its stderr and report the memory block as
     deferred (`{"status":"deferred","reason":"splice-error"}`) — best-effort,
     never failing the ratification.

8. **Report.** Tell the user:
   - The product plan is **ratified**; vision + backlog are `FINALIZED`; `PHASE=DEVELOPING`.
     Note whether `STACK.md` was also flipped to `FINALIZED` (fully-binding stack) or left
     as-is because provisional/forward content remains un-ratified.
   - Whether the root `./CLAUDE.md` product-memory block was written or **deferred** (and
     if deferred, that `/build-fleet:start` regenerates it later).
   - If `ratify force` accepted open blockers, name them so the acceptance is explicit
     and on the record.
   - Features continue to build against the binding stack via `/build-fleet:start`
     (ratification is advisory — it does not gate feature creation).
   - The DEVELOPING loop arms the next backlog feature off the **presence of
     `.sdd/_product/backlog.md`** (re-resolved live on each `/build-fleet:start`);
     `PHASE=DEVELOPING` is advisory context, not a hard gate.

### Ratify rules

- **Never auto-pass.** Bare `status` must not flip state, even with zero findings.
  Only the explicit `ratify` form ratifies. This is the headless contract.
- **Never promote PROVISIONAL → binding.** Ratification finalizes what is binding now. The
  conditional `STACK.md` STATUS flip only re-labels an already-fully-binding stack; it never
  touches a file that still carries provisional/forward content, and never un-tags an entry.
- **Never append to `REVIEW.md`** — that is the workflow scribe's append-only log.
- **Never edit `DECISIONS.md`** — per-ADR STATUS is the architect's.
- **Never write source.** This gate edits only `.sdd/_product/{vision,backlog,PROGRESS}.md`
  (plus `STACK.md`'s STATUS line when the stack is fully binding) and — best-effort on
  ratification — the delimited product block in root `./CLAUDE.md` (never clobbering content
  outside the build-fleet markers).
- A dry-run or a refusal is the gate doing its job — report what is open and let the
  human decide.
- **Headless contract.** Every branch emits exactly one `BUILD_FLEET_PLAN_FINALIZE_*:`
  line before any prose.


## Machine-readable snapshot (orchestrators / polling)

For a non-interactive caller (an external orchestrator polling project state), the
human report above is the wrong shape and too costly — it spawns a model. Use the
deterministic, LLM-free resolver instead:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/status-snapshot.sh"
```

It reads the same `.sdd/` state this command narrates and emits **exactly one JSON
object** (`schema: build-fleet/status-snapshot@1`) on stdout — the product tier
(vision/stack one-liners, backlog counts + per-feature rows, next unblocked feature)
and the active item (feature or bug lane: phase, status, cycles, escalation).
Read-only; run from the repo root. `product` is `null` with no product tier;
`active` is `null` with nothing in flight. Backlog resolution + counts reuse
`scripts/next-feature.sh` (one source of truth). **build-fleet ships no publishing
path** — where (or whether) the snapshot goes is the orchestrator's concern
(orchestrator-agnostic).

## Hard rules

- The **Report** form never writes any file and never runs tests or invokes subagents.
  (It may run the read-only `next-feature.sh`, `finalize-gate.sh --report`,
  `status-snapshot.sh` and `lite-next.sh` scripts.)
- The **Park**, **Resolve** and **Ratify** forms write only what their sections name.
- If any of the expected `.sdd/<active>/` files are missing or malformed,
  report which and stop — recovery is the user's call (probably
  hand-edit PROGRESS.md, or `/build-fleet:start` with a fresh idea
  if the workspace is irrecoverable).
- **Headless contract.** Each decision form emits exactly one of its `BUILD_FLEET_*`
  signal lines before any prose. A slash command cannot set a process exit code — the
  signal lines on stdout are the sole machine contract (`code` 2 = refused).
