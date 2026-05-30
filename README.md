# build-fleet

A reusable Claude Code plugin that turns any project into a spec-driven multi-agent software house. v0.2 ships dynamic workflows for adversarial spec review and parallel fan-out builds, with first-class headless-mode support for orchestrator-driven (Hermes, Agent SDK) use cases.

Seven subagents — `product-owner`, `architect`, `coder`, `qa`, `devops`, `scribe`, `classifier` — execute a deterministic state machine for every feature:

```
              [M4 classifier]
                      │
                      ▼
SPEC ──► REVIEW ──► FINALIZE ──► BUILD ──► CHANGE_REVIEW ──► HANDOFF
        [M1 workflow]            [M3 deep-build workflow
                                  or M2 sequential, per BUILD_MODE]
          ▲  │                              ▲       │
          └──┘ (≤3 cycles, then ESCALATE)   └───────┘ (≤3 cycles, then ESCALATE)
```

Phase transitions are enforced by hooks and workflow post-conditions, not by agents deciding they're done. The authoritative rulebook is the `sdd-protocol` skill bundled with this plugin.

## Requirements

- **Claude Code v2.1.154 or later** with the **dynamic workflows feature enabled** (`/config` → "Dynamic workflows" on Pro plans; available by default on Max / Team / Enterprise). v0.2 has a hard requirement on the `Workflow` tool — there is no v0.1 fallback. See `ROADMAP.md`.

## Install

From a Claude Code marketplace once distributed:

```
/plugin install build-fleet
```

During local development, point Claude Code at this directory:

```
claude --plugin-dir /path/to/build-fleet
```

Use `/reload-plugins` after editing plugin files to pick up changes.

## Quickstart (interactive)

In a target project (NOT inside the plugin tree):

```
/build-fleet:new-feature my-feature
  # scaffolds .sdd/my-feature/, runs the M4 classifier (sets TIER + BUILD_MODE),
  # delegates to PO to draft spec (skeleton for trivial, full for standard/large)
/build-fleet:review
  # dynamic workflow: fan-out reviewers + cross-examination + survival vote
/build-fleet:finalize
  # gate; flips spec to FINALIZED; dispatches qa-first then coder (M2 ordering)
  # OR routes to workflows/deep-build.js for BUILD_MODE=deep-build (M3 workflow)
/build-fleet:handoff
  # change-review by architect + PO + qa (counterfactual gate); then devops
/build-fleet:status
  # current phase, open concerns, cycle counts, tier
```

For trivial features the classifier sets `TIER=trivial`, and `/build-fleet:finalize` skips REVIEW automatically — go straight from `new-feature` to `finalize`.

Inspect a classification before scaffolding:

```
/build-fleet:dispatch "rewrite auth to use Argon2id across cli + core + api"
  # returns tier, build_mode, confidence; does not modify state
```

Run `/build-fleet:deep-build` manually if you want fan-out BUILD without going through finalize's routing (useful for re-iteration after `verdict=needs-iteration`).

## Quickstart (headless / orchestrator-driven)

Every command emits `BUILD_FLEET_*:` JSON-line signals **before any human-readable prose**, so orchestrators can branch on machine-readable outcomes without parsing the wider response.

```bash
claude -p '/build-fleet:new-feature my-feature' \
  --allowedTools "Workflow,Read,Edit,Write,Bash,Agent,Task"
# emits: BUILD_FLEET_CLASSIFICATION: {"feature":"my-feature","tier":"...","build_mode":"...","skip_review":...,"confidence":"..."}

claude -p '/build-fleet:review' --allowedTools "Workflow,Read,Edit,Write,Bash,Agent"
# emits: BUILD_FLEET_COST_PREVIEW: {"workflow":"review",...}
#        BUILD_FLEET_WORKFLOW_LAUNCHED: {"runId":"...","transcriptDir":"...","status":"async_launched",...}

# Poll workflow completion (e.g. via TaskList/TaskGet), then read .sdd/<feature>/ for state.
```

The signal grammar:

| Signal | Emitted by | Meaning |
|---|---|---|
| `BUILD_FLEET_REFUSE:` | any command | Refusal; always followed by exit ≥ 2 |
| `BUILD_FLEET_CLASSIFICATION:` | new-feature, dispatch | Classifier verdict |
| `BUILD_FLEET_CLASSIFIER_FALLBACK:` | new-feature | Classifier parse failure; safe-default to standard |
| `BUILD_FLEET_COST_PREVIEW:` | review, deep-build, finalize | Cost ceiling for upcoming workflow |
| `BUILD_FLEET_WORKFLOW_LAUNCHED:` | review, deep-build, finalize | Workflow dispatched with runId |
| `BUILD_FLEET_FINALIZE_PASS:` / `_REFUSE:` | finalize | Gate outcome (machine-parseable reason codes on refuse) |
| `BUILD_FLEET_FINALIZE_TRIVIAL_FAST_PATH:` | finalize | M4 trivial fast-path through finalize |
| `BUILD_FLEET_BUILD_ROUTE:` | finalize | Routing to deep-build workflow vs M2 sequential |
| `BUILD_FLEET_QA_TESTS_READY:` | qa subagent | Failing test suite ready; coder may proceed |
| `BUILD_FLEET_QA_VERIFY_FAIL:` | finalize | qa signal absent or test count mismatch |
| `BUILD_FLEET_CODER_REFUSE:` | coder subagent | Refuses to start (no tests / tests-pass-empty) |
| `BUILD_FLEET_BUILD_COMPLETE:` / `_INCOMPLETE:` / `_DISPATCH_FAIL:` | finalize | BUILD result |

See `docs/v0.2/CONTRACT.md` for the full headless contract and the workflow ↔ command-layer state-mutation spec.

## State lives in the target project

The plugin tree itself is read-only machinery — Claude Code wipes the plugin cache on update, so nothing mutable can live here.

All runtime state lives in the **target project's** `.sdd/` directory:

```
<target-project>/.sdd/
  ACTIVE                 # one-line slug naming the active feature
  <feature>/
    spec.md              # STATUS: DRAFT | IN_REVIEW | FINALIZED | BLOCKED
    acceptance.md
    DECISIONS.md         # append-only ADRs
    TEST_PLAN.md
    IMPL_NOTES.md        # also receives deep-build's per-run aggregation (M3)
    REVIEW.md            # append-only review log
    PROGRESS.md          # PHASE, CYCLE, CHANGE_CYCLE, TIER, BUILD_MODE
    ESCALATION.md        # exists only when a gate exhausts its cycle budget
    .workflow-in-flight  # transient — present only while a workflow is running
```

Commit `.sdd/` alongside your source — it's the audit trail for every decision the fleet made.

## What changed from v0.1

See `CHANGELOG.md` for the full v0.1 → v0.2 diff. Highlights:

- **REVIEW phase is now a dynamic workflow** with adversarial cross-examination and a survival-vote convergence rule (replaces v0.1's "all approved" check, which was a binary proxy for a judgment).
- **The `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` env-var step is gone.** v0.1's cycle-3 agent-teams fallback is retired — workflow cross-examination replaces it.
- **Tests-first BUILD ordering.** qa writes failing tests before coder begins; CHANGE_REVIEW verifies the counterfactual.
- **Deep-build workflow for fan-out implementation.** `BUILD_MODE=deep-build` (set automatically by the M4 classifier for `tier=large`) partitions files across up to 8 coders running in parallel.
- **Three-tier routing.** A classifier subagent runs at `/build-fleet:new-feature` time. Trivial features skip REVIEW.
- **Headless mode is first-class.** Every command emits structured `BUILD_FLEET_*:` signals; designed for Hermes / Agent SDK integration.
- **`scribe` and `classifier` subagents** are new in v0.2.

## Where to read the rules

The single source of truth for the workflow, gates, severity rubric, and escalation policy is the `sdd-protocol` skill at `skills/sdd-protocol/SKILL.md`. When this README, an agent body, or the original design history in `CLAUDE.md` disagrees with the skill, the skill wins.

Design references:
- `ROADMAP.md` — v0.2 milestones (shipped) + v0.3 forecast (orchestrator-mediated human intervention via Hermes).
- `V0.2-PLAN.md` — the build plan that produced v0.2 (retires once v0.3 begins).
- `docs/v0.2/CONTROLS.md` — gate-vs-judgment control inventory.
- `docs/v0.2/CONTRACT.md` — workflow ↔ command-layer contract (grounded against `@anthropic-ai/claude-agent-sdk@0.3.158`).
- `CHANGELOG.md` — per-version changes.
