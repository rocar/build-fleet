---
description: Ratify the product plan. Bare call is a dry-run (prints the interrogation report + open blockers, then halts). `ratify` flips vision/backlog to FINALIZED and PHASE to DEVELOPING; `ratify force` overrides open blocker-severity findings. Never auto-passes.
argument-hint: "[ratify [force]]"
allowed-tools: Read, Write, Edit
---

# /build-fleet:plan-finalize

You are the **orchestrator**. The runtime rulebook is the `sdd-protocol` skill
(**Product tier → PLAN state machine**). This is the **ratification gate** — the
one place a human (or the calling orchestrator) chooses to commit to the product
plan.

**A product plan is a strategic bet, not a contract the machine can converge.** So
this gate **never auto-passes**, even with zero findings. Ratification is an explicit
act: the bare command is a *dry-run* that shows the plan and its open blockers and
halts; flipping state requires the explicit `ratify` token. In headless mode this is
the whole safety story — `claude -p '/build-fleet:plan-finalize'` emits the report
and stops; it cannot ratify on its own.

This gate is **advisory by design (v0.4 M3.1 decision)**: ratifying does NOT gate
`/build-fleet:new-feature` (features build against the binding stack regardless).
What it does is (a) record the ratification, (b) flip vision/backlog `STATUS` to
`FINALIZED`, and (c) set `PHASE: DEVELOPING` — the entry condition the M3.2
DEVELOPING loop reads. The "teeth" land in M3.2's loop, not as a feature block.

## Arguments

`$ARGUMENTS` is a token list (lowercase):
- *(empty)* — **dry-run**. Print the latest interrogation report + open-blocker count,
  emit the dry-run signal, halt. No state changes.
- `ratify` — **ratify**. Flip state IF there are zero open blocker-severity findings.
  If any blockers are open, refuse (use `ratify force` to override).
- `ratify force` — **ratify over open blockers**. Flip state regardless, recording
  that ratification happened with N blockers consciously accepted.

Any other argument → treat as empty (dry-run) and note the recognized tokens.

## What you do

1. **Resolve the product.** Read `.sdd/PRODUCT` (fall back to `.sdd/_product/PROGRESS.md`
   `PRODUCT:`). If no product tier, refuse:
   > `BUILD_FLEET_PLAN_FINALIZE_REFUSE: {"reason":"no-product"}` — run `/build-fleet:new-product`. Exit 2.

2. **Refuse while a feature is mid-review (hook-confinement guard).** Read `.sdd/ACTIVE`;
   if non-empty and `.sdd/<active>/PROGRESS.md` `PHASE` is `REVIEW` or `CHANGE_REVIEW`,
   refuse — the `restrict-reviewer-writes` hook would block the `STATUS`/`PHASE` flips
   into `.sdd/_product/`:
   > `BUILD_FLEET_PLAN_FINALIZE_REFUSE: {"reason":"feature-mid-review","feature":"<active>","phase":"<PHASE>"}`. Exit 2.

3. **Check escalation.** If `.sdd/_product/ESCALATION.md` exists, refuse — a human
   halted the plan. Surface its contents. Exit 2.

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
     > `BUILD_FLEET_PLAN_FINALIZE_REFUSE: {"product":"<slug>","reason":"already-ratified","phase":"DEVELOPING"}`.
     Tell the user the plan is already ratified; re-planning after DEVELOPING is M3.2. Exit 2.
   - Any other phase (e.g. `PLAN` for a non-small product) → refuse with
     `{"reason":"no-interrogation-cycle","detail":"run /build-fleet:plan-review first"}`. Exit 2.
   - *(Legacy tier, no `PHASE` field — scaffolded before M3.1.)* The read returns empty,
     which falls into the `no-interrogation-cycle` refusal above — correct, since
     `/build-fleet:plan-review` is also what normalizes a legacy PROGRESS (seeds
     `PHASE`/`CYCLE`). Unlike `/build-fleet:plan-review`, this gate does **not** normalize;
     run plan-review once first.

5. **Count open blocker-severity findings.** Unless on the small fast-path, read
   `.sdd/_product/REVIEW.md`. Find the **latest** `## Plan Cycle <N>` blocks (highest N).
   Count `[blocker]` items across that cycle's role blocks. (The workflow also writes a
   `## Plan Cycle <N> — interrogation summary` block stating the count — use it to
   cross-check, but the authoritative count is the `[blocker]` line tally.) Call this `B`.

6. **Branch on `$ARGUMENTS`.**

   **a. Dry-run (empty / unrecognized args).** Emit:
   ```
   BUILD_FLEET_PLAN_FINALIZE_DRYRUN: {"product":"<slug>","phase":"<PHASE>","open_blockers":<B>,"cycle":<N>}
   ```
   Then print, human-readably:
   - **Normal path** (`PHASE=PLAN_REVIEW`): the open `[blocker]` and `[major]` findings
     verbatim (with role attribution), and the consolidated summary line from REVIEW.md.
   - **Small fast-path** (`SIZE=small`, `PHASE=PLAN`, `CYCLE=0`): there is **no**
     `_product/REVIEW.md` — do not try to read it. Print `open_blockers: 0` and a note
     that this small product is ratifying without an interrogation cycle.

   End with:
   > To ratify, re-run `/build-fleet:plan-finalize ratify`<if B>0: ` — `B`> blocker(s) open, so you'll need `/build-fleet:plan-finalize ratify force` to override them</if>.

   **Do not change any state.** This is the headless safety stop.

   **b. `ratify` with `B > 0`.** Refuse — open blockers, no `force`:
   ```
   BUILD_FLEET_PLAN_FINALIZE_REFUSE: {"product":"<slug>","reason":"open-blockers","open_blockers":<B>}
   ```
   List the open blockers verbatim and tell the user to either resolve them (edit the
   plan and re-run `/build-fleet:plan-review`) or override with
   `/build-fleet:plan-finalize ratify force`. No state changes. Exit 2.

   **c. `ratify` with `B = 0`, OR `ratify force` (any B).** **Ratify — flip state** (step 7).

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
     (then re-run plan-review) before ratifying. The per-ADR `STATUS:` lines in `DECISIONS.md`
     are owned by the architect and are never edited here.

   Emit exactly one line:
   ```
   BUILD_FLEET_PLAN_FINALIZE_PASS: {"product":"<slug>","phase":"DEVELOPING","ratified_with_blockers":<true|false>,"accepted_blockers":<B-if-force-else-0>,"stack_finalized":<true|false>}
   ```
   (`stack_finalized` is `true` when STACK.md was flipped to `FINALIZED`, `false` when it
   was left as-is because provisional/forward content is present.)

7b. **Generate product memory (best-effort, v0.4 M3.1.1).** Seed the repo-root
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
     Tell the user to run `/build-fleet:product-memory` once the active feature is
     `FINALIZED` or cleared. **This is best-effort: a deferred memory block never fails
     the ratification** — the plan is ratified regardless.
   - **Otherwise** (no active feature, or its spec is `FINALIZED`) generate/splice the
     block and emit:
     ```
     BUILD_FLEET_PLAN_FINALIZE_CLAUDEMD: {"product":"<slug>","status":"<created|updated-in-place|appended>"}
     ```

8. **Report.** Tell the user:
   - The product plan is **ratified**; vision + backlog are `FINALIZED`; `PHASE=DEVELOPING`.
     Note whether `STACK.md` was also flipped to `FINALIZED` (fully-binding stack) or left
     as-is because provisional/forward content remains un-ratified.
   - Whether the root `./CLAUDE.md` product-memory block was written or **deferred** (and
     if deferred, that `/build-fleet:product-memory` regenerates it later).
   - If `ratify force` accepted open blockers, name them so the acceptance is explicit
     and on the record.
   - Features continue to build against the binding stack via `/build-fleet:new-feature`
     (M3.1 ratification is advisory — it does not gate feature creation).
   - The M3.2 DEVELOPING loop arms the next backlog feature off the **presence of
     `.sdd/_product/backlog.md`** (re-resolved live on each `/build-fleet:handoff`);
     `PHASE=DEVELOPING` is advisory context, not a hard gate.

## Hard rules

- **Never auto-pass.** The bare command must not flip state, even with zero findings.
  Only an explicit `ratify` token ratifies. This is the headless contract.
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

## Exit codes

| Exit | Meaning |
|---|---|
| 0 | Ratified (state flipped) — PASS emitted |
| 2 | Refused (no product, feature mid-review, escalation, wrong phase, open blockers without force) |
| (dry-run exits 0; it is a successful no-op report, not a refusal) |
