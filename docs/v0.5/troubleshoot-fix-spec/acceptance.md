# Acceptance Criteria — troubleshoot-fix

Each criterion is testable in isolation and names the Behavior clause it covers
(see `spec.md` § Behavior). "Source" means a path outside `.sdd/` and outside `tests/`.
A bug is "active" when `.sdd/ACTIVE` names a slug whose dir contains `diagnosis.md`.

## Entry & scaffolding (B1)

- **AC-1.** Running `/build-fleet:triage "<symptom>"` against a repo with an empty
  `.sdd/ACTIVE` creates `.sdd/<bug-slug>/` containing `diagnosis.md` (first non-blank line
  `STATUS: REPORTED`, plus the four required `##` headings) and `PROGRESS.md` (with
  `LANE: bug`, `PHASE: REPORT`), writes the slug into `.sdd/ACTIVE`, and creates **no**
  `spec.md` and **no** `acceptance.md` in that dir. The `<symptom>` text appears verbatim
  under `## Symptom + reproduction steps` in `diagnosis.md`.
- **AC-2.** Running `/build-fleet:triage "<symptom>"` while `.sdd/ACTIVE` is non-empty
  refuses (emits no new scaffold, leaves `.sdd/ACTIVE` unchanged) and its output states the
  active slug. (Mirrors `/build-fleet:new-feature`'s one-in-flight refusal.)

## Severity classification & cause-known routing (B2)

- **AC-3.** After scaffolding, `/build-fleet:triage` invokes the triage classifier, which
  emits a single JSON verdict containing both `severity ∈ {sev0,sev1,sev2}` and
  `cause_known ∈ {true,false}`; the classifier writes no file under `.sdd/`.
- **AC-4.** When the classifier returns `cause_known: true`, `/build-fleet:triage` emits
  `BUILD_FLEET_TRIAGE_KNOWN_CAUSE` (recommending `/build-fleet:new-feature`), **removes** the
  scaffold it just created, and leaves `.sdd/ACTIVE` empty — the known-cause bug does not
  occupy the lock or enter the bug machine.
- **AC-5.** When the classifier returns `cause_known: false`, `/build-fleet:triage` writes
  `SEV: <verdict.severity>` and `PHASE: REPORT` into `PROGRESS.md` and emits
  `BUILD_FLEET_TRIAGE` with the same severity and `"phase":"REPORT"`.

## Reproduce (B3)

- **AC-6.** `/build-fleet:reproduce` on a `PHASE: REPORT` bug advances it to
  `PHASE: REPRODUCE`, results in ≥1 test under `tests/` that fails, flips `diagnosis.md`
  STATUS from `REPORTED` to `REPRODUCING`, and emits
  `BUILD_FLEET_REPRO_READY` with a `failing_tests` count ≥ 1.
- **AC-7.** Writing the reproducing test under `tests/` succeeds even though `diagnosis.md`
  STATUS is `REPRODUCING` (not `CONFIRMED`) — i.e. no hook blocks a `tests/` write at this
  phase. (Confirms B7 gates source, not tests.)

## Diagnose (B4)

- **AC-8.** `/build-fleet:diagnose` on a `PHASE: REPRODUCE` bug requires `diagnosis.md`'s
  `## Root-cause hypothesis`, `## Blast radius`, and `## Fix strategy` sections to be
  non-empty (STATUS flipped to `DIAGNOSED`) before it dispatches `diagnose.js`; if the
  hypothesis is empty it refuses with a one-line reason naming the missing section.

## diagnosis.md STATUS lifecycle (B5)

- **AC-9.** A write to `diagnosis.md` whose first non-blank STATUS line is absent or holds a
  token outside `{REPORTED,REPRODUCING,DIAGNOSED,CONFIRMED,FIXED}` is rejected by the
  `validate-diagnosis-status` PostToolUse hook (exit code 2). A write with a valid STATUS and
  all four required headings is accepted (exit 0).
- **AC-10.** `validate-diagnosis-status` fires only on files named `diagnosis.md`; a write to
  a feature's `spec.md` is unaffected by it, and a write to `diagnosis.md` is unaffected by
  `validate-spec-status` (no cross-fire between the two validators).

## Diagnosis confirmation workflow (B6)

- **AC-11.** `diagnose.js` accepts `args = {slug, cycle, now}` (tolerating `args` delivered as
  a JSON string), and dispatches reviewer roles `architect` and `coder` (never
  `product-owner`) in its fan-out/cross-examination phases.
- **AC-12.** A recorded root-cause hypothesis is reported `confirmed` **iff** no surviving
  refutation remains, where a refutation counts only if it is ≥40 characters, cites the
  reproduction (matches `(diagnosis\.md §|tests?/|line N)`), and comes from a different role
  than the hypothesis author (self-refutation is filtered). On `confirmed`, the `diagnose.js`
  workflow advances `PHASE: FIX` (via the scribe, as `review.js` advances PHASE) and records the
  verdict in `REVIEW.md` + `PROGRESS.md`; the **`/build-fleet:fix` gate** then flips `diagnosis.md`
  STATUS to `CONFIRMED` — the content write the scribe must not do, mirroring how
  `/build-fleet:finalize` flips `spec.md` after the async review. *(v0.5 refinement: the original
  "/build-fleet:diagnose flips it synchronously" does not fit the fire-and-forget Workflow runtime,
  so the deterministic STATUS flip moves to the synchronous FIX gate.)*
- **AC-13.** A surviving refutation with `CYCLE < 3` yields `verdict: refuted` (re-run after
  revising the hypothesis); a surviving refutation at `CYCLE >= 3`, or an explicit
  "cause-not-found" outcome, yields `verdict: escalate` — the scribe writes `ESCALATION.md`
  and sets `PHASE: ESCALATED`. Cross-examination rounds within one `diagnose.js` run do not
  increment `CYCLE`.

## The inviolable reproducing-test gate (B7)

- **AC-14.** With an active bug whose `diagnosis.md` STATUS is **not** `CONFIRMED`, a
  Write/Edit to a **source** path is blocked by `require-reproducing-test.sh` (exit 2), and the
  error names which precondition failed.
- **AC-15.** With an active bug whose `diagnosis.md` STATUS **is** `CONFIRMED` but **no** test
  exists under `tests/`, a Write/Edit to a source path is still blocked by
  `require-reproducing-test.sh` (exit 2) — the reproducing-test precondition is independent of
  STATUS.
- **AC-16.** With an active bug whose STATUS is `CONFIRMED` **and** ≥1 test exists under
  `tests/`, a Write/Edit to a source path is allowed (exit 0). This holds identically for a
  bug whose `SEV` is `sev0` (the gate is severity-independent).

## block-source-before-finalized second unlock (B8)

- **AC-17.** For an active **forward feature** (a `.sdd/<slug>/` with `spec.md` and no
  `diagnosis.md`), `block-source-before-finalized.sh` returns its existing exit codes on every
  path: blocked (exit 2) while STATUS ≠ FINALIZED, allowed (exit 0) when FINALIZED — byte-for-byte
  unchanged from today (regression test against the pre-feature behavior).
- **AC-18.** For an active **bug**, `block-source-before-finalized.sh` permits a source write
  (exit 0) when `diagnosis.md` STATUS is `CONFIRMED`, and blocks it (exit 2) otherwise — and the
  combined effect with `require-reproducing-test.sh` is that a bug source write requires both
  CONFIRMED and a reproducing test (strictly stronger than the FINALIZED-only forward path).

## Fix & verify (B9)

- **AC-19.** `/build-fleet:fix` on a `CONFIRMED` bug delegates to coder, which writes source +
  `IMPL_NOTES.md` and turns the reproducing test(s) GREEN without breaking the existing suite;
  it emits `BUILD_FLEET_FIX_DONE` with a `tests_green` count.
- **AC-20.** `/build-fleet:verify` runs the CHANGE_REVIEW counterfactual reused verbatim: for
  each reproducing test it confirms the test **fails** when the coder's source change is
  reverted. A clean verify (counterfactual satisfied, no surviving blocker) flips `diagnosis.md`
  STATUS to `FIXED`, sets `PHASE: HANDOFF`, and emits `BUILD_FLEET_VERIFY` with
  `"verdict":"clean","counterfactual_ok":true`. A failed counterfactual yields
  `"verdict":"bounce"` and returns `PHASE` to `FIX`.

## Handoff (B10) & ship

- **AC-21.** `/build-fleet:ship-fix` on a `PHASE: VERIFY` / STATUS `FIXED` bug delegates to
  devops, emits `BUILD_FLEET_SHIP_FIX`, and on full completion **clears `.sdd/ACTIVE`** (empties
  the file) so the next `/build-fleet:triage` or `/build-fleet:new-feature` is unblocked. No
  backlog completion-flip is attempted for a bug (a bug has no backlog row).
- **AC-25.** `/build-fleet:status` on an active bug (PROGRESS `LANE: bug`) prints the bug phase,
  `SEV`, `diagnosis.md` STATUS, the `CYCLE` and `FIX_CYCLE` counters, and a tests
  failing/passing count; on a forward feature its output is unchanged.

## Severity tempo (B11)

- **AC-22.** For `SEV: sev0`, `/build-fleet:fix` is permitted from `PHASE: DIAGNOSE` /
  `diagnosis.md` STATUS `DIAGNOSED` **without** a completed `diagnose.js` confirmation, provided
  a reproducing test exists under `tests/`; in that case `/build-fleet:fix` (or the orchestrator)
  emits `BUILD_FLEET_POSTHOC_DIAGNOSIS_DUE` for the slug and records the post-hoc obligation in
  `diagnosis.md`. (Non-blocking: see Self-review Q1 — QA decides whether a post-ship warning is
  also wanted.)
- **AC-23.** For `SEV: sev1` and `SEV: sev2`, `/build-fleet:fix` refuses from `DIAGNOSED` and
  requires `diagnosis.md` STATUS `CONFIRMED` (the full `diagnose.js` loop) before a fix may
  begin — severity does not relax the reproducing-test gate for any value (AC-16 holds across
  all three).

## Bounded cycles & escalation (B12)

- **AC-24.** When the diagnose cycle (`CYCLE`) reaches 3 with a surviving refutation, or the
  verify→fix cycle (`FIX_CYCLE`) reaches 3 with a surviving blocker, an `ESCALATION.md` is
  written (the scribe's existing ESCALATION writer, verbatim) listing the unresolved items and
  `PHASE` is set to `ESCALATED`; no further phase advance is permitted until a human clears it.

## Additivity guarantee (Constraints — cross-cutting)

- **AC-26.** In a repo that has never run `/build-fleet:triage` (no `diagnosis.md` anywhere),
  every new and modified hook returns exit 0 on every path a forward feature exercises, and the
  full existing forward-machine acceptance suite passes unchanged — i.e. the feature is provably
  additive.
