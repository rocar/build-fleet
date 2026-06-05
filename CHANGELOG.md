# Changelog

All notable changes to the build-fleet plugin. Follows [Keep a Changelog](https://keepachangelog.com/) conventions; semver bumps track the plugin's `version` in `.claude-plugin/plugin.json`.

## [0.5.0] — 2026-06-05

### Added

- **Troubleshoot-fix bug lane** — a second, parallel state machine for diagnosing and fixing
  *unknown-cause* bugs, additive to the forward feature machine (a repo that never files a bug is
  byte-for-byte unchanged). Phases: `REPORT → REPRODUCE → DIAGNOSE → FIX → VERIFY → HANDOFF`. Its
  contract is a new **`diagnosis.md`** artifact (STATUS `REPORTED|REPRODUCING|DIAGNOSED|CONFIRMED|FIXED`),
  not a spec. Spec of record: `.sdd/troubleshoot-fix/`.
- **Artifact + validator (M0).** `skills/sdd-diagnosis-template` (the diagnosis.md contract);
  `hooks/scripts/validate-diagnosis-status.sh` (PostToolUse, keyed on `basename==diagnosis.md`; no
  cross-fire with the spec validator). `_lib.sh` gains `read_diagnosis_status`, `resolve_lane`,
  `tests_exist`, `path_in_tests`.
- **Source-write gates (M2).** `hooks/scripts/require-reproducing-test.sh` (NEW) — a bug source
  write is blocked unless `diagnosis.md` STATUS==CONFIRMED **and** ≥1 test exists under `tests/`
  (severity-independent — holds for sev0). `block-source-before-finalized.sh` gains a second unlock
  (CONFIRMED), the FINALIZED path byte-identical.
- **Entry (M1).** `/build-fleet:triage <symptom>` scaffolds the bug + runs the classifier in a new
  **bug mode** (`{severity, cause_known}`); a known-cause bug is bounced to the forward trivial path.
- **Diagnosis confirmation (M3).** `workflows/diagnose.js` — an inverted `review.js`: architect +
  coder try to refute the root-cause hypothesis citing the reproduction; CONFIRMED iff no refutation
  survives. Driven by `/build-fleet:reproduce` + `/build-fleet:diagnose`.
- **Fix tail (M4).** `/build-fleet:fix` (FIX gate — flips diagnosis.md→CONFIRMED, drives the coder),
  `/build-fleet:verify` (reuses the CHANGE_REVIEW counterfactual verbatim), `/build-fleet:ship-fix`
  (devops + clears `.sdd/ACTIVE`). sev0 hotfix fast-path. `/build-fleet:status` is bug-lane-aware.
- **New PROGRESS bug-lane fields:** `LANE: bug`, `SEV: sev0|sev1|sev2`, `FIX_CYCLE`. New signals
  include `BUILD_FLEET_TRIAGE`(`_KNOWN_CAUSE`), `BUILD_FLEET_REPRO_READY`,
  `BUILD_FLEET_DIAGNOSE_SEV0_SKIP`, `BUILD_FLEET_FIX_GATE`/`_DONE`, `BUILD_FLEET_VERIFY`,
  `BUILD_FLEET_SHIP_FIX`, `BUILD_FLEET_POSTHOC_DIAGNOSIS_DUE`.
- **Planted-bug smoke test** (`docs/v0.5/smoke/`) — a fixture (a paginator with a floor-division
  bug) + a driver that walks the bug through the lane's deterministic backbone (the hook gates +
  the STATUS lifecycle + RED→GREEN + the VERIFY counterfactual) against the **actual** hooks, plus
  a live-run `WALKTHROUGH.md` for the LLM-driven classifier + `diagnose.js` parts.

### Fixed

- **Hook fail-open under bash 3.2.** The `_lib.sh` STATUS/field readers ended in an unguarded `grep`
  pipeline that, under `set -euo pipefail`, aborted the hook with exit 1 (non-blocking) on a
  status-less file instead of reaching exit 2 — letting a source write slip the gate. Guarded all
  five readers (`read_diagnosis_status`, `read_spec_status`, `read_progress_field`,
  `read_product_field`, `resolve_product`); closes a latent `spec.md` bypass dating to v0.2.
- **Bug-lane `tests/` deadlock (AC-7).** `block-source-before-finalized` blocked a bug's `tests/`
  writes until CONFIRMED — but the reproducing test, written at REPRODUCE *before* CONFIRMED, is the
  precondition for ever reaching CONFIRMED, so the lane deadlocked at REPRODUCE. Taught the bug
  branch to permit `tests/` (mirroring `require-reproducing-test`). Caught by the new planted-bug
  smoke test; now a regression case in `block-source-before-finalized.test.sh`.

## [0.2.1] — 2026-05-30

### Fixed

- **Stop-hook deadlock at SPEC phase.** `hooks/scripts/stop-tests.sh` ran the
  test suite in every phase and treated `pytest` exit code 5 ("no tests
  collected") as a failure. Pre-BUILD there are no tests yet — and the
  `block-source-before-finalized` gate makes it impossible to write any — so the
  session could neither stop nor pass. The hook now (a) only enforces the suite
  in `BUILD | CHANGE_REVIEW | HANDOFF`, and (b) tolerates `pytest` exit 5 as a
  non-failure. Surfaced by the first real install dogfood (bf-smoke).
- **`new-feature` classified from the bare slug.** With no description in
  conversation context, the command let the classifier infer requirements from
  the slug name alone, producing a hallucinated spec. New step 5 ("Establish the
  feature description") stops and asks the user what the feature should do when
  no description exists in context; subsequent steps renumbered.

## [0.2.0] — 2026-05-30

### Added

- **Dynamic workflow for REVIEW phase** (M1). `workflows/review.js` runs 5 phases: read state → fan-out reviewers (architect/qa/coder) → adversarial cross-examination → survival vote → scribe applies state delta. Replaces the v0.1 parallel-Task fan-out + cycle-3 agent-teams fallback.
- **`workflows/deep-build.js` for fan-out BUILD** (M3). Architect plans a file partition; up to 8 coders fan out in parallel; in-workflow adversarial review (architect + qa) catches integration gaps before BUILD declares complete. Partition overlap detection prevents concurrent coders from racing on shared files.
- **Three-tier M4 routing.** New `agents/classifier.md` (read-only subagent emitting JSON verdicts) + new `commands/dispatch.md` (query-only classifier wrapper). `/build-fleet:new-feature` now invokes the classifier and writes `TIER` + `BUILD_MODE` to PROGRESS.md. Trivial features skip REVIEW; large features get `BUILD_MODE=deep-build` for automatic routing through finalize.
- **`agents/scribe.md` subagent** — write-only state applier; the canonical writer of workflow-driven `.sdd/` state mutations (workflows can't touch the filesystem directly).
- **Headless mode first-class.** Every command emits `BUILD_FLEET_*:` JSON-line signals before any human-readable prose. New signals: `BUILD_FLEET_REFUSE`, `BUILD_FLEET_CLASSIFICATION`, `BUILD_FLEET_CLASSIFIER_FALLBACK`, `BUILD_FLEET_COST_PREVIEW`, `BUILD_FLEET_WORKFLOW_LAUNCHED`, `BUILD_FLEET_FINALIZE_PASS/REFUSE`, `BUILD_FLEET_FINALIZE_TRIVIAL_FAST_PATH`, `BUILD_FLEET_BUILD_ROUTE`, `BUILD_FLEET_QA_TESTS_READY`, `BUILD_FLEET_QA_VERIFY_FAIL`, `BUILD_FLEET_CODER_REFUSE`, `BUILD_FLEET_BUILD_COMPLETE/INCOMPLETE/DISPATCH_FAIL`.
- **Tests-first BUILD ordering** (M2). `/build-fleet:finalize` now sequences qa-first then coder for `BUILD_MODE=standard`. coder refuses to begin until QA's failing tests exist (emits `BUILD_FLEET_CODER_REFUSE:` machine-readable). CHANGE_REVIEW adds the M2 counterfactual gate ("would each test fail without coder's source change?").
- **`hooks/scripts/reap-stale-workflow-markers.sh`** — Stop hook that removes `.workflow-in-flight` markers older than 1 hour (handles orphan markers from failed workflow launches; preserves safety property of per-reviewer hooks).
- **PROGRESS.md schema fields:** `TIER` (M4: `trivial | standard | large | pending`), `BUILD_MODE` (M3+M4: `standard | deep-build | pending`).
- **`docs/v0.2/CONTROLS.md`** — M0 gate-vs-judgment control inventory.
- **`docs/v0.2/CONTRACT.md`** — workflow ↔ command-layer contract, grounded against `@anthropic-ai/claude-agent-sdk@0.3.158`. Reproduces `WorkflowInput`/`WorkflowOutput` schemas verbatim from SDK type definitions.
- **`ROADMAP.md`** — v0.2 milestones + v0.3 forecast (orchestrator-mediated human intervention via Hermes).

### Changed

- **`hooks/scripts/check-review-written.sh` and `restrict-reviewer-writes.sh`** add a `.sdd/<slug>/.workflow-in-flight` marker bypass. The hooks skip while a workflow is running (workflow's envelope post-condition replaces them for workflow paths); they still fire on non-workflow review paths (CHANGE_REVIEW via `/build-fleet:handoff`).
- **CYCLE semantics:** v0.2 cycles count workflow runs (not command invocations). Cross-examination rounds inside one workflow run do NOT bump CYCLE.
- **Severity rubric (review-rubric skill) preloaded into workflow reviewer subagents** via `AgentDefinition.skills: ["review-rubric"]` instead of v0.1's duplication into agent prompt bodies.
- **`commands/finalize.md` is now a gate AND orchestrator** for the BUILD sequence (M2 sequential or M3 deep-build, routed on BUILD_MODE; M4 trivial fast-path skips review-cycle gate but still honors ESCALATION.md).
- **`agents/scribe.md`** also writes IMPL_NOTES.md when envelope has `impl_notes_appendix` (used by deep-build workflow). Tight constraint: scribe only writes files whose corresponding envelope field is present and non-empty.
- **Signal rename: `QA_TESTS_READY:` → `BUILD_FLEET_QA_TESTS_READY:`** for namespace consistency with the rest of the `BUILD_FLEET_*` family.
- **`.claude-plugin/plugin.json`** version bumped to `0.2.0`.

### Deprecated

- **`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` env var** — no longer needed. The cycle-3 agent-teams fallback in `/build-fleet:review` is gone; workflow cross-examination replaces it. The README section that asked for this env var has been removed.

### Decisions deferred to a future version

- **`hooks/scripts/restrict-reviewer-writes.sh` is retained** despite V0.2-PLAN's "retire entirely" guidance. CHANGE_REVIEW (`/build-fleet:handoff`) is still v0.1-style and depends on the hook for its reviewer-write-boundary enforcement. The hook will be retired when CHANGE_REVIEW becomes a workflow.
- **`check-review-written.sh` is similarly retained** for the same non-workflow CHANGE_REVIEW path.
- Several **VERIFY-AT-M1 markers** remain in `workflows/review.js` and `workflows/deep-build.js` — runtime-global signature assumptions (`agent()`, `parallel()`, `phase()`) that will be confirmed against a real `/deep-research` raw script at first dispatch.

### Notes for v0.2 users

- **Requires Claude Code v2.1.154 or later** with dynamic workflows enabled (`/config` → "Dynamic workflows" on Pro plans). Hard requirement; no v0.1 fallback if workflows are unavailable.
- **Headless callers** (`claude -p`, Agent SDK / Hermes) must include `Workflow` in `--allowedTools`. The orchestrator is responsible for human approval between workflow runs (no mid-workflow gates in v0.2; that's v0.3's scope).
- The `BUILD_FLEET_*:` signal grammar is documented in `README.md`; the full contract is in `docs/v0.2/CONTRACT.md` § 8.

## [0.1.0] — 2026-05-30

Initial release. Five role subagents (product-owner, architect, coder, qa, devops) executing the deterministic SPEC → REVIEW → FINALIZE → BUILD → CHANGE_REVIEW → HANDOFF state machine. Five hooks enforce gate boundaries: `block-source-before-finalized`, `restrict-reviewer-writes`, `validate-spec-status`, `check-review-written`, `stop-tests`. Five skills (sdd-protocol, sdd-spec-template, adr, review-rubric, test-plan), five commands (new-feature, review, finalize, handoff, status). Bounded review cycles (≤3 then ESCALATE); first-class human escalation.

Validated end-to-end via the a–g dry-run matrix on 2026-05-30.
