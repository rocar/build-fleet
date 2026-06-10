STATUS: DRAFT

## Self-review notes

Walked the product-owner self-review checklist against this draft before signalling ready:

1. **Template coverage** — all 8 required headings (`Overview`, `Goals`, `Non-goals`,
   `Behavior`, `Interfaces / Contracts`, `Constraints`, `Risks`, `Acceptance Criteria`)
   are present in order and non-empty. STATUS line is `DRAFT` (REVIEW sets `IN_REVIEW`,
   not me).
2. **Testability** — every acceptance criterion in `acceptance.md` is phrased so QA can
   write a passing/failing test from it alone (file-presence assertions, hook exit-code
   assertions, JSON-signal grep assertions, STATUS-transition assertions). No "TBD".
3. **1:1 mapping** — every Behavior clause (B1–B12) has ≥1 acceptance criterion and every
   criterion names its Behavior clause. The mapping table at the bottom of Behavior is the
   audit aid for reviewers.
4. **Non-goals** — explicit and load-bearing (the brief warns of scope creep into a second
   product and boundary confusion with the trivial path; both are pre-empted here).
5. **STATUS line** — `DRAFT`, correct for the SPEC phase.

**Deviations from / elaborations on the design brief** (flagged per role instructions):

- **D1 — `diagnose.js` is a *fork* of `review.js`, not a runtime parameterization.**
  The brief says "INVERTED `review.js` … reuse the survival-vote engine, inverted." The
  product tier already set the precedent that workflows fork rather than parameterize
  (`plan-review.js` is "a **fork** of `review.js` … fork, don't parameterize"). I specify
  a fork so the inversion (a *hypothesis* survives only if **not** refuted, vs. a *concern*
  survives unless refuted) lives in its own file and can't regress `review.js`. This is an
  elaboration, not a contradiction — the engine *logic* (cross-examination, the ≥40-char +
  section-cite refutation floor, the pure-JS vote) is reused verbatim; only the polarity and
  the cited-evidence target (the reproduction, not the spec) differ. Flagging for the
  architect to ratify fork-vs-parameterize as an ADR.

- **D2 — the "inverted" survival vote needs care about what "refuted" means.** In
  `review.js` a concern is killed by a refutation. Inverted, a *root-cause hypothesis* is
  killed by a refutation. I made the polarity explicit in B6 rather than hand-waving
  "inverted", because a naive inversion (hypothesis survives iff someone affirms) would be
  weaker, not stronger — it would let an unchallenged-but-also-unsupported hypothesis pass.
  The correct inversion: a hypothesis is CONFIRMED iff it survives an adversarial
  refutation attempt that cites the reproduction. Reviewers should scrutinize this clause.

- **D3 — severity-vs-tier coexistence.** The brief says SEVERITY replaces SIZE *as the
  routing axis for the bug path*. I scoped that strictly: the bug path adds `SEV` to
  PROGRESS.md and does **not** touch the existing `TIER`/`BUILD_MODE` fields' meaning for
  the forward machine. A bug feature's PROGRESS still carries `TIER` (set to `trivial` by
  the triage classifier only for the known-cause → existing-fast-path bounce, otherwise
  left `n/a`) so existing hooks that read PROGRESS don't choke. Flagged for architect: the
  PROGRESS schema addition is additive but reviewers should confirm no existing hook
  hard-requires `TIER ∈ {trivial,standard,large}`.

- **Open question for reviewers (Q1):** the brief says sev0 "MAY skip the adversarial
  diagnosis-confirmation workflow (do it post-hoc)". I specified post-hoc confirmation as a
  *recorded obligation* (a `diagnosis.md` STATUS note + a `BUILD_FLEET_POSTHOC_DIAGNOSIS_DUE`
  signal), not an enforced gate, because enforcing it would re-introduce the hotfix-tempo
  paradox. Is an unenforced obligation strong enough, or should a follow-up hook warn (not
  block) on a shipped sev0 whose diagnosis never reached CONFIRMED? Left as a Risk + a
  non-blocking acceptance criterion (AC-22) for QA to decide.

- **Open question for reviewers (Q2):** one-bug-in-flight mirrors `.sdd/ACTIVE`. A bug and
  a forward feature cannot both be active (they share `.sdd/ACTIVE`). That is the simplest
  correct rule and matches "one feature in flight," but it means an urgent sev0 cannot
  start while a forward feature is mid-BUILD without the human parking the feature. I chose
  the simple shared-lock over a second `.sdd/ACTIVE_BUG` lane (which would double the
  gating surface — a brief-named maintenance-cost risk). Flagged for architect.

# Troubleshoot & Bug-Fix Path

## Overview

build-fleet today is a purely forward-engineering machine: a feature flows
`SPEC → REVIEW → FINALIZE → BUILD → CHANGE_REVIEW → HANDOFF`, the spec is the
contract, the unknown is *how*, and verification asks "does it meet the spec?".
There is no path for "production is broken — fix it." A bug fix inverts all three
of those assumptions: the **symptom is the trigger** (not a spec), the **unknown is
*why*** (diagnosis *is* the primary work, not implementation), and verification asks
a sharper question — "does a regression test that *reproduces* the bug now pass, and
did it *fail* before the fix?". Forcing a bug through the forward machine produces a
hollow ceremony (a "spec" for a fix nobody designed) and, worse, skips the one
discipline a fix actually needs: a failing reproduction promoted to a guard test.

This feature adds a **second, parallel state machine** to the build-fleet plugin for
diagnosing and fixing bugs whose cause is *unknown*:
`REPORT → REPRODUCE → DIAGNOSE → FIX → VERIFY → HANDOFF`. Its contract is not a spec
but a **failing reproduction plus a `diagnosis.md` artifact** (the bug-fix analog of
`spec.md`). It serves the operator who has a broken build and a symptom, not a
greenfield feature request. It ships now because the forward machine has matured
(product tier, deep-build, the survival-vote review engine) and the missing inverse —
diagnosis-as-primary-work with an inviolable reproducing-test gate — is the largest
remaining gap in the software house's coverage.

## Goals

- **A complete, self-contained bug-fix lane** parallel to (never replacing) the forward
  feature machine: the six phases `REPORT → REPRODUCE → DIAGNOSE → FIX → VERIFY → HANDOFF`,
  driven by build-fleet's own commands, hooks, agents, and one new workflow.
- **Make the failing reproduction the contract.** No fix may land without a regression test
  that was demonstrably RED before the fix and GREEN after — enforced as a *new hard hook
  gate*, holding even at the highest severity.
- **Make diagnosis a first-class, adversarially-confirmed artifact.** Root-cause
  confirmation runs as a workflow (a judgment), not a hook (a deterministic gate): a
  hypothesis is CONFIRMED only when a different-role reviewer, citing the reproduction,
  fails to refute it.
- **Reuse, don't reinvent, the keystones.** The existing CHANGE_REVIEW counterfactual
  ("would each test FAIL if the source change were reverted?") *is* the regression
  discipline a bug fix needs — reuse it verbatim. The survival-vote engine from `review.js`
  is reused inverted for diagnosis confirmation.
- **Severity-driven tempo.** `sev0 | sev1 | sev2` replaces SIZE as the routing axis for
  this lane: sev0 may skip the adversarial diagnosis-confirmation (post-hoc), but never the
  reproducing-test gate; sev2 gets the full adversarial loop.
- **Purely additive and non-weakening.** A repo that never uses the bug path behaves
  exactly as it does today; the existing FINALIZED source-write gate is not weakened, only
  taught a second, equally-strict unlock.

## Non-goals

- **No bug-tier `_product/` analog.** This path adds no product-level "incident portfolio,"
  no `_incidents/` namespace, and no outer plan machine. It operates at the single-bug
  level, mirroring the flat feature workspace.
- **This path does NOT swallow or replace the existing `trivial` fast-path.** A *known-cause*
  small change (off-by-one obvious from the report, a missing null check) stays on the
  existing trivial feature path. Only an *unknown-cause* bug — where diagnosis is real work —
  enters this diagnose lane. The triage classifier routes on cause-known-vs-unknown.
- **Not a general incident-management / observability / alerting system.** No paging, no
  SLOs, no dashboards, no postmortem templates beyond `diagnosis.md`, no metrics ingestion.
- **It does not auto-detect bugs.** Entry is an explicit human-invoked
  `/build-fleet:triage <symptom>`. Nothing watches logs or CI to file bugs.
- **It does not change the existing forward feature machine's behavior.** No edit to
  `review.js`, `deep-build.js`, the forward commands, or the forward STATUS contract. The
  `block-source-before-finalized` hook is *taught a second unlock*, not rewired — the
  FINALIZED path is byte-identical.
- **The Product Owner largely drops out of this lane.** The bug report *is* the requirement;
  there is no PO-authored spec, no `acceptance.md` for the bug. (PO retains its forward-machine
  role unchanged.)
- **No new severity for the forward machine.** `sev0/1/2` exists only in the bug lane's
  `diagnosis.md` + PROGRESS `SEV` field; the forward `TIER` axis is untouched.

## Behavior

The bug-fix lane is a second state machine layered onto the same `.sdd/<slug>/`
workspace conventions, the same one-active-at-a-time lock (`.sdd/ACTIVE`), the same
scribe-envelope state-mutation mechanism, and the same headless-first
`BUILD_FLEET_*` signal discipline as the forward machine. Where the forward machine's
source-of-truth artifact is `spec.md`, the bug lane's is **`diagnosis.md`**.

**B1 — Entry & scaffolding (`REPORT`).** `/build-fleet:triage <symptom>` is the sole
entry point. It refuses if `.sdd/ACTIVE` is non-empty (one item in flight — a bug and
a forward feature cannot coexist; they share the lock). On a clean lock it derives a
kebab-case bug slug (e.g. `bug-login-500-on-empty-email`), scaffolds `.sdd/<bug-slug>/`
containing `diagnosis.md` (seeded `STATUS: REPORTED`, with the required headings — see
Interfaces) and `PROGRESS.md` (with the bug-lane fields), writes the slug into
`.sdd/ACTIVE`, and creates **no** `spec.md` or `acceptance.md` (the bug lane has neither).
The `<symptom>` argument is captured verbatim into `diagnosis.md`'s Symptom section.

**B2 — Severity classification & cause-known routing (`REPORT`).** Immediately after
scaffolding, `/build-fleet:triage` runs the **triage classifier** (a reuse of the existing
classifier agent, given a bug-mode prompt) which emits a JSON verdict with two independent
axes: `severity ∈ {sev0, sev1, sev2}` (drives tempo) and `cause_known ∈ {true, false}`
(drives lane selection). The classifier writes no state; `/build-fleet:triage` consumes the
verdict:
- `cause_known: true` → this is **not** a diagnose-lane bug. `/build-fleet:triage` does not
  enter the bug machine; it emits `BUILD_FLEET_TRIAGE_KNOWN_CAUSE` and tells the human to use
  the existing forward `trivial`/`standard` feature path (`/build-fleet:new-feature`) instead,
  and removes the scaffold it created (clean `.sdd/ACTIVE`, delete the bug dir) so the known-cause
  bug does not occupy the lock. This is the sharp boundary with the trivial fast-path.
- `cause_known: false` → proceed in the bug lane; write `SEV: <sev0|sev1|sev2>` to PROGRESS,
  set `PHASE: REPORT`, emit `BUILD_FLEET_TRIAGE`.

**B3 — Reproduce (`REPRODUCE`).** `/build-fleet:reproduce` advances a `REPORT`-phase bug to
`REPRODUCE`. It delegates to **QA** to author a **failing reproduction test** under `tests/`
that fails *because of the bug* (not because of a missing fixture). QA records the reproduction
steps into `diagnosis.md`'s "Symptom + reproduction steps" section and flips
`diagnosis.md` `STATUS: REPORTED → REPRODUCING`. The phase exit condition: at least one test
exists under `tests/` and the suite is RED with a failure attributable to the symptom. QA
emits `BUILD_FLEET_REPRO_READY: <count> failing test(s) reproducing <slug>`. Because no
source has been edited, writing this test is permitted even though `diagnosis.md` is not yet
`CONFIRMED` — the reproducing test is *test code under `tests/`*, and the new gate (B7) gates
**source**, not tests. (QA may write tests at any bug phase; coders may not write source until
CONFIRMED.)

**B4 — Diagnose (`DIAGNOSE`).** `/build-fleet:diagnose` advances a `REPRODUCE`-phase bug to
`DIAGNOSE` and dispatches the **`diagnose.js` workflow** (the bug-lane analog of
`/build-fleet:review` → `review.js`). The author role (QA, or whoever holds the reproduction)
records a **root-cause hypothesis**, a **blast radius**, and a **fix strategy** into
`diagnosis.md`, flipping `STATUS: REPRODUCING → DIAGNOSED`. The workflow then runs the
adversarial confirmation (B6).

**B5 — `diagnosis.md` STATUS lifecycle.** `diagnosis.md` carries a STATUS line whose value is
one of `REPORTED | REPRODUCING | DIAGNOSED | CONFIRMED | FIXED`, transitioning monotonically:
`REPORTED` (B1) → `REPRODUCING` (B3, a reproducing test exists) → `DIAGNOSED` (B4, a hypothesis
is written) → `CONFIRMED` (B6, the hypothesis survives adversarial refutation **and** a
reproducing test exists) → `FIXED` (B9, VERIFY passes). A `validate-diagnosis-status` PostToolUse
hook (the bug-lane analog of `validate-spec-status`) rejects any write to `diagnosis.md` whose
STATUS is missing/malformed or whose required sections are absent.

**B6 — Diagnosis confirmation is a workflow, not a hook (`diagnose.js`).** Root-cause
confirmation is a **judgment**, so it runs as a dynamic workflow — an *inverted* `review.js`.
A fork of the survival-vote engine: different-role reviewers (Architect for blast-radius +
root-cause refutation; Coder for fix-strategy feasibility) attempt to **refute** the recorded
root-cause hypothesis, each citing the **reproduction** (the failing test, or `diagnosis.md`'s
reproduction steps) as counter-evidence. The inversion vs. `review.js`: in review a *concern*
survives unless refuted; here a *hypothesis* is **CONFIRMED iff it is NOT refuted** by a
substantive, different-role, reproduction-citing refutation. Substantive reuses `review.js`'s
floor verbatim — a refutation counts only if it is ≥40 characters and cites the reproduction
(an inverted analog of the `(spec|acceptance)\.md §|line N` regex, retargeted to
`diagnosis\.md §|tests?/|line N`); self-refutation (the hypothesis author refuting its own
hypothesis) is filtered. Verdicts:
- `confirmed` — no surviving refutation. Scribe flips `diagnosis.md STATUS → CONFIRMED`, sets
  `PHASE: DIAGNOSE → FIX`. Next: `/build-fleet:fix`.
- `refuted` — a substantive refutation survives; `CYCLE < 3`. Author revises the hypothesis;
  re-run `/build-fleet:diagnose`.
- `escalate` — a refutation survives at `CYCLE >= 3`, **or** the root cause genuinely cannot
  be found. Scribe writes `ESCALATION.md`, sets `PHASE: ESCALATED`, halts. (Diagnosis is
  inherently non-deterministic — "we never found the cause" is a first-class escalation, not
  a failure.) Cross-examination rounds inside one `diagnose.js` run do not bump `CYCLE`; one
  `/build-fleet:diagnose` invocation = one cycle, mirroring `review.js`.

**B7 — The inviolable reproducing-test gate (new hard hook).** A new
`require-reproducing-test` PreToolUse(Write|Edit) hook enforces the keystone discipline: when
the active item is a **bug** (PROGRESS carries a `SEV` field / `diagnosis.md` exists) and the
write targets **source** (outside `.sdd/`, outside `tests/`), the hook **blocks (exit 2)**
unless **both** hold: (a) `diagnosis.md STATUS == CONFIRMED`, and (b) at least one test exists
under `tests/`. This holds **even for sev0** — severity may skip the *diagnosis-confirmation
workflow's adversarial rigor* (B11) but never this gate. The gate is the bug-lane analog of
`block-source-before-finalized`; both block source until the lane's contract is satisfied.

**B8 — `block-source-before-finalized` gains a second unlock (no weakening).** The existing
`block-source-before-finalized` hook is taught one additional permit branch: it allows a
source write when the active item is a bug and `diagnosis.md STATUS == CONFIRMED` — precisely
mirroring the `spec.md STATUS == FINALIZED` unlock. The FINALIZED branch is unchanged
byte-for-byte; for a forward feature (no `diagnosis.md`) behavior is identical to today. With
B7 layered on top, a bug's source writes require `CONFIRMED` *and* a reproducing test — strictly
stronger than the forward path's single condition, never weaker.

**B9 — Fix & verify (`FIX` → `VERIFY`).** `/build-fleet:fix` (after `CONFIRMED`) delegates to
**Coder** to implement the fix to the recorded fix-strategy; coder writes source +
`IMPL_NOTES.md`, makes the reproducing test(s) GREEN, and must not break the existing suite.
`/build-fleet:verify` advances `FIX → VERIFY` and runs the **reused CHANGE_REVIEW
counterfactual verbatim**: QA verifies each reproducing test *would FAIL if the coder's source
change were reverted* (a test that passes regardless of the fix is decorative, not a
regression guard). Architect reviews blast radius against `diagnosis.md`. On a clean verify
with the counterfactual satisfied, scribe flips `diagnosis.md STATUS → FIXED`, sets
`PHASE: VERIFY → HANDOFF`. A failed counterfactual or surviving blocker bounces back to `FIX`
(bounded by a `FIX_CYCLE` ≤ 3, then ESCALATE).

**B10 — Handoff (`HANDOFF`).** `/build-fleet:ship-fix` (the bug-lane handoff) takes the
verified fix to **DevOps** for release — and, for `sev0`, the hotfix lane (expedited release
notes / cherry-pick guidance; DevOps-authored, no new infra in this feature). On a full
completion it clears `.sdd/ACTIVE` (mirroring the forward DEVELOPING-loop's clear), so the next
`/build-fleet:triage` or `/build-fleet:new-feature` is unblocked. A bug has no backlog row, so
no completion-flip is attempted.

**B11 — Severity tempo.** `SEV` drives which phases are mandatory:
- `sev2` — the full adversarial loop: REPRODUCE → DIAGNOSE (full `diagnose.js` confirmation)
  → FIX → VERIFY.
- `sev1` — same as sev2 (full loop); severity affects only DevOps urgency at HANDOFF.
- `sev0` (hotfix) — **MAY skip the adversarial diagnosis-confirmation workflow**:
  `/build-fleet:fix` is permitted directly from `DIAGNOSED` (not requiring `CONFIRMED` via the
  workflow) **only if** sev0 — but the orchestrator must record a post-hoc obligation: it emits
  `BUILD_FLEET_POSTHOC_DIAGNOSIS_DUE: <slug>` and notes in `diagnosis.md` that confirmation is
  owed post-ship. **sev0 NEVER skips the reproducing-test gate (B7)** — a reproducing test must
  still exist before any source write, so for sev0 the unlock is "diagnosis.md STATUS forced to
  CONFIRMED by the sev0 fast-path *and* a reproducing test exists." The reproducing-test
  precondition is identical across all severities.

**B12 — Bounded cycles & escalation throughout.** Both the `diagnose.js` confirmation cycle
(`CYCLE`) and the verify→fix cycle (`FIX_CYCLE`) are bounded at 3, after which the responsible
command/workflow writes `ESCALATION.md` (verbatim reuse of the scribe's ESCALATION writer) and
sets `PHASE: ESCALATED`. Escalation is first-class: an unconfirmable root cause halts for a human.

**Behavior → acceptance map (audit aid for reviewers):**
B1→AC-1,AC-2; B2→AC-3,AC-4,AC-5; B3→AC-6,AC-7; B4→AC-8; B5→AC-9,AC-10; B6→AC-11,AC-12,AC-13;
B7→AC-14,AC-15,AC-16; B8→AC-17,AC-18; B9→AC-19,AC-20; B10→AC-21,AC-25; B11→AC-22,AC-23; B12→AC-24.

## Interfaces / Contracts

This feature exposes new build-fleet plugin surfaces. All are additive.

### New slash commands (`commands/*.md`)

| Command | Arg | Phase transition | Delegates to |
|---|---|---|---|
| `/build-fleet:triage <symptom>` | symptom text | (none) → `REPORT` | triage classifier |
| `/build-fleet:reproduce` | — | `REPORT` → `REPRODUCE` | qa |
| `/build-fleet:diagnose` | — | `REPRODUCE`/`DIAGNOSE` → `DIAGNOSE` | `diagnose.js` workflow |
| `/build-fleet:fix` | — | `DIAGNOSE`(CONFIRMED) → `FIX` | coder |
| `/build-fleet:verify` | — | `FIX` → `VERIFY` | qa + architect (counterfactual) |
| `/build-fleet:ship-fix` | — | `VERIFY` → `HANDOFF` → done | devops |

Every command is headless-first: it emits its `BUILD_FLEET_*` JSON signal line **before**
any prose, and refuses (with a one-line reason) when the active item's `PHASE`/`diagnosis.md
STATUS` does not match its required precondition.

### Headless signals (emitted before prose)

```
BUILD_FLEET_TRIAGE:            {"slug":"<bug-slug>","severity":"sev0|sev1|sev2","cause_known":false,"phase":"REPORT"}
BUILD_FLEET_TRIAGE_KNOWN_CAUSE:{"symptom":"<text>","recommended":"/build-fleet:new-feature","reason":"cause is known — use the forward path"}
BUILD_FLEET_REPRO_READY:       {"slug":"<bug-slug>","failing_tests":<int>}
BUILD_FLEET_DIAGNOSIS:         {"slug":"<bug-slug>","verdict":"confirmed|refuted|escalate","cycle":<int>}
BUILD_FLEET_FIX_DONE:          {"slug":"<bug-slug>","tests_green":<int>}
BUILD_FLEET_VERIFY:            {"slug":"<bug-slug>","verdict":"clean|bounce|escalate","counterfactual_ok":<bool>}
BUILD_FLEET_SHIP_FIX:          {"slug":"<bug-slug>","severity":"sev0|sev1|sev2"}
BUILD_FLEET_POSTHOC_DIAGNOSIS_DUE: {"slug":"<bug-slug>"}   # sev0 only, when confirmation was skipped
```

### `diagnosis.md` artifact (new — the bug-lane `spec.md` analog)

First non-blank line is the STATUS line. Required sections, validated structurally by
`validate-diagnosis-status`:

```
STATUS: REPORTED | REPRODUCING | DIAGNOSED | CONFIRMED | FIXED

# Bug: <title>

## Symptom + reproduction steps
The observed failure (verbatim from the triage <symptom>) and the concrete steps /
failing test that reproduce it.

## Root-cause hypothesis
The single best explanation of *why* the symptom occurs. (Empty until DIAGNOSE.)

## Blast radius
What else this touches — code paths, data, callers — and the regression surface.

## Fix strategy
The intended change and why it addresses the root cause without widening blast radius.
```

`validate-diagnosis-status` (PostToolUse, keyed on `basename == diagnosis.md`) rejects the
write (exit 2) if the STATUS line is missing/malformed (not one of the 5 tokens) or any of the
four `##` headings is absent. Feature dirs have no `diagnosis.md`, so there is no collision with
`validate-spec-status` (keyed on `spec.md`).

### New / modified hooks (`hooks/scripts/*.sh`, registered in `hooks/hooks.json`)

- **`require-reproducing-test.sh`** (NEW, PreToolUse Write|Edit). Resolves the active slug via
  `resolve_active` (from `_lib.sh` — never an env var). No active item → exit 0. If the active
  item is **not** a bug (no `.sdd/<slug>/diagnosis.md`) → exit 0 (forward features unaffected).
  If the target path is under `.sdd/` or under `tests/` → exit 0 (workspace + test writes always
  allowed). Otherwise (a source write on an active bug): exit 2 unless **both**
  `diagnosis.md STATUS == CONFIRMED` **and** ≥1 file exists under `tests/`. Error message names
  which precondition failed and the next legal command.
- **`block-source-before-finalized.sh`** (MODIFIED — one added permit branch). After resolving
  the active slug and confirming the path is source, before the existing `read_spec_status`
  branch, add: if `.sdd/<slug>/diagnosis.md` exists and its STATUS is `CONFIRMED`, exit 0 (the
  bug-lane unlock). The existing FINALIZED branch is unchanged. New `_lib.sh` helper
  `read_diagnosis_status <slug>` mirrors `read_spec_status` (scan first ~30 lines for `^STATUS:`).
- **`stop-tests.sh`, `restrict-reviewer-writes.sh`, `check-review-written.sh`** are reused
  as-is (the bug lane uses the same `.workflow-in-flight` marker convention, so the reviewer
  hooks skip during `diagnose.js`; `stop-tests` already gates Stop on the test suite).

### `diagnose.js` workflow (`workflows/diagnose.js` — fork of `review.js`)

- `args`: `{ slug: "<bug-slug>", cycle: <int>, now: "<iso8601>" }` (mirrors `review.js`'s
  `{feature,cycle,now}`; `now` supplied by the command because the runtime forbids `Date`).
- Reuses `review.js`'s structure verbatim: a `HYPOTHESIS_SCHEMA` (the recorded root-cause +
  blast-radius + fix-strategy, read from `diagnosis.md`), a `REFUTATION_SCHEMA` (identical shape
  to review's), the cross-examination phase, and the **same survival-vote engine** with the
  polarity inverted (a hypothesis is retained-as-CONFIRMED iff **not** refuted; in review a
  concern is retained iff **not** refuted — same engine, the bug lane has exactly one
  "concern": the negation of the hypothesis). The substantive-refutation floor is reused: ≥40
  chars + a citation regex retargeted to `(diagnosis\.md\s*§|tests?\/|line\s+\d+)`;
  self-refutation filtered by role.
- Reviewer roles: `["architect", "coder"]` (PO drops out of this lane). Emits the same
  scribe-applied **envelope** shape (`state_delta`, `review_entries`, `escalation_payload`,
  optional `workspace_dir`) — the scribe is reused unchanged, writing `diagnosis.md` STATUS via
  `state_delta`-adjacent handling is **not** done by the scribe (the scribe never writes
  `spec.md`/`diagnosis.md` bodies); the STATUS flip to `CONFIRMED` is applied by the
  `/build-fleet:diagnose` command after a `confirmed` verdict, the same division of labor as
  `/build-fleet:finalize` flipping `spec.md` to `FINALIZED`.
- Cost ceiling declared in the header `@cost-ceiling` comment, parsed by `commands/diagnose.md`
  to emit `BUILD_FLEET_COST_PREVIEW` in headless mode (mirrors `review.js`).

### Agents

- **triage classifier** — the existing `classifier` agent given a bug-mode prompt. Emits a JSON
  verdict `{ "severity": "sev0|sev1|sev2", "cause_known": true|false, "rationale": "...",
  "confidence": "high|medium|low" }`. Writes no state. (A bug-mode addendum to
  `agents/classifier.md`, or a sibling `agents/triage-classifier.md` — the architect chooses;
  either way it never modifies `.sdd/`.)
- **qa, coder, architect, devops** — reused verbatim. Their prompts gain a short bug-lane
  addendum (qa authors the reproducing test + the counterfactual; coder fixes to the
  fix-strategy; architect refutes the root cause + reviews blast radius; devops ships /
  hotfixes). PO is **not** invoked in this lane.

### PROGRESS.md schema additions (bug lane)

A bug's `PROGRESS.md` adds these fields; a forward feature's PROGRESS is unchanged. Hooks and
commands parse them:

```
FEATURE: <bug-slug>                 # reused field name (the active item's slug)
PHASE: REPORT | REPRODUCE | DIAGNOSE | FIX | VERIFY | HANDOFF | ESCALATED
SEV: sev0 | sev1 | sev2             # NEW — severity, set by the triage classifier
CYCLE: <int>                        # diagnose-confirmation cycles (one per /build-fleet:diagnose run)
FIX_CYCLE: <int>                    # NEW — verify→fix cycles (one per /build-fleet:verify bounce)
LANE: bug                           # NEW — disambiguates the bug lane from a forward feature
UPDATED: <iso8601>
```

`LANE: bug` is the explicit, cheap discriminator (presence of `diagnosis.md` is the structural
one; `LANE` is the parseable one for commands/`/build-fleet:status`). Forward features carry no
`LANE` field (or `LANE: feature`) — absence reads as a forward feature.

### `/build-fleet:status` extension

`/build-fleet:status` (existing) gains bug-lane awareness: when the active item's PROGRESS
carries `LANE: bug`, it prints the bug phase, `SEV`, `diagnosis.md` STATUS, the `CYCLE`/`FIX_CYCLE`
counters, and the count of failing/passing tests under `tests/`. For a forward feature its output
is unchanged.

## Constraints

- **Purely additive.** A repo that never invokes `/build-fleet:triage` behaves **exactly** as
  today: no new file appears, every existing hook returns its existing exit code on every
  existing path, and the forward `SPEC→…→HANDOFF` machine is byte-for-byte unchanged. The bug
  lane's hooks short-circuit to `exit 0` whenever no `diagnosis.md` exists for the active slug.
- **The existing FINALIZED gate must not be weakened.** `block-source-before-finalized`'s
  FINALIZED branch is unchanged; the bug unlock is an *additional* branch that is *stricter*
  (requires CONFIRMED **and** a reproducing test, via B7 layered on top). A forward feature
  (no `diagnosis.md`) sees identical behavior.
- **Deterministic gates stay hooks; judgments stay workflows.** The reproducing-test gate (B7),
  the source-write unlock (B8), and `diagnosis.md` structural validity (B5) are **hooks**
  (binary, exit-2). Root-cause confirmation (B6) is a **workflow** (the survival vote). The
  category error to avoid — hook-enforcing the judgment "is this the real root cause?" — is
  not committed here.
- **One item in flight.** The bug lane shares `.sdd/ACTIVE` with the forward machine; a bug and
  a feature cannot both be active. `/build-fleet:triage` refuses while `.sdd/ACTIVE` is non-empty,
  exactly as `/build-fleet:new-feature` does.
- **Headless-first.** Every command emits its `BUILD_FLEET_*` JSON signal before prose, so a
  `claude -p` driver can parse state transitions without reading narration.
- **Bounded cycles + first-class escalation.** `CYCLE` (diagnose) and `FIX_CYCLE` (verify) are
  each bounded at 3; the 4th unresolved cycle writes `ESCALATION.md` and halts.
- **No new external dependencies.** The lane is bash hooks + a JS workflow + markdown
  commands/agents, the same toolchain build-fleet already ships. `jq` (already required) is the
  only binary dependency; absent-`jq` degrades to allow, matching existing hooks.
- **Workflow-runtime constraints inherited from `review.js`.** No `Date.now()`/`Math.random()`
  in `diagnose.js` (`now` comes via `args`); `args` may arrive as a JSON string and must be
  normalized; the cost ceiling lives in a header comment, not `meta`.

## Risks

- **Scope creep into a second product.** The lane could metastasize into incident management
  (paging, postmortems, SLOs). *Mitigation:* the Non-goals fence this hard — no `_incidents/`
  tier, no auto-detection, no observability. Reviewers should flag any acceptance criterion that
  implies more than "diagnose one human-reported bug."
- **The hotfix-tempo paradox.** Adversarial rigor (sev2) versus sev0 speed are in tension.
  *Mitigation (the load-bearing resolution):* only the *diagnosis-confirmation workflow* (B6/B11)
  is skippable for sev0; the *reproducing-test gate* (B7) is **never** skippable. A sev0 that
  ships without a reproducing test is impossible by construction. The residual risk is an unenforced
  post-hoc confirmation obligation (see Q1 in Self-review notes) — surfaced as a signal, not a
  gate, to avoid re-introducing the paradox.
- **Boundary confusion with the trivial fast-path.** An operator might `/build-fleet:triage` a
  known-cause one-liner that belongs on the trivial path. *Mitigation:* the triage classifier's
  `cause_known` axis routes known-cause bugs *out* of the lane (B2), tearing down its own
  scaffold and pointing at `/build-fleet:new-feature`. Reviewers should pressure-test the
  classifier's known-vs-unknown boundary criteria.
- **Diagnosis is inherently non-deterministic.** The root cause may never be found.
  *Mitigation:* `escalate` is a first-class `diagnose.js` verdict (B6) — "we couldn't confirm
  the cause" halts for a human rather than shipping a guess. This is by design, not a defect.
- **Maintenance cost of a second state machine.** Two machines, two sets of hooks/commands,
  two STATUS contracts. *Mitigation:* maximal reuse — the survival-vote engine, the scribe
  envelope, the counterfactual, the `.sdd/ACTIVE` lock, the `BUILD_FLEET_*` discipline, and the
  classifier agent are all reused; the genuinely new surface is `diagnosis.md`, `diagnose.js`,
  `require-reproducing-test.sh`, one `block-source` branch, the bug commands, and a few
  PROGRESS fields. Reviewers should challenge any *new* mechanism that duplicates an existing one.
- **PROGRESS-schema coupling.** Existing hooks read PROGRESS fields. Adding `SEV`/`FIX_CYCLE`/
  `LANE` must not break a hook that hard-requires the forward field set. *Mitigation:* additions
  are new lines; no existing field is renamed or removed. (See Self-review D3 / Q-for-architect.)
- **The shared lock blocks an urgent sev0 behind a mid-flight feature** (Q2 in Self-review notes).
  Accepted trade-off: simplicity over a second lock lane. Flagged for architect ratification.

## Acceptance Criteria

See [acceptance.md](./acceptance.md)
