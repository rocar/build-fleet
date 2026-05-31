# build-fleet

A spec-driven multi-agent software house, packaged as a Claude Code plugin.
**v0.2.1**

build-fleet turns Claude Code into a disciplined software house: a fleet of
role subagents drives every change through a deterministic state machine —
**SPEC → REVIEW → FINALIZE → BUILD → CHANGE_REVIEW → HANDOFF** — with phase
gates enforced by hooks, not vibes. No source is written until the spec is
FINALIZED; no handoff until tests pass and the change is reviewed.

What's new in v0.2:

- **REVIEW runs as a dynamic workflow** — reviewers fan out, cross-examine each
  other adversarially, and concerns survive only by a survival vote (see
  [Dynamic workflows](#dynamic-workflows)).
- **Three-tier routing** — a classifier sizes each feature; trivial work skips
  REVIEW, large work fans out across partitioned coders.
- **Tests-first BUILD** — qa writes a failing suite before coder writes a line
  of source.
- **Headless-first** — every command emits machine-readable `BUILD_FLEET_*`
  signals, so an orchestrator (Hermes, the Agent SDK, `claude -p`) can drive the
  fleet without scraping prose.

---

## What you get

Seven role subagents. The **main session is the orchestrator** — it routes,
gates, and writes `.sdd/` state, but never writes source itself.

| Role | Subagent | Writes | Model |
|---|---|---|---|
| Product Owner | `build-fleet:product-owner` | `spec.md`, `acceptance.md` | opus |
| Architect | `build-fleet:architect` | `DECISIONS.md`, review notes | opus |
| Coder | `build-fleet:coder` | source, `IMPL_NOTES.md` | sonnet |
| QA | `build-fleet:qa` | `tests/`, `TEST_PLAN.md` | sonnet |
| DevOps | `build-fleet:devops` | CI/CD, release notes | sonnet |
| Classifier | `build-fleet:classifier` | *(read-only — emits a routing verdict)* | sonnet |
| Scribe | `build-fleet:scribe` | applies workflow state deltas to `.sdd/` | sonnet |

The **classifier** and **scribe** are v0.2 infrastructure agents. The classifier
sizes incoming work into a routing tier; the scribe is the canonical writer for
state mutations produced by dynamic workflows (workflow scripts cannot touch the
filesystem directly, so they hand a structured envelope to the scribe).

Plus the shared memory layer under `.sdd/<feature>/`, two dynamic workflows
(`workflows/review.js`, `workflows/deep-build.js`), and the gate-enforcing hooks.

---

## Requirements

- **Claude Code v2.1.154 or later**, with the **dynamic workflows** feature
  enabled (`/config` → "Dynamic workflows" on Pro plans; on by default for
  Max / Team / Enterprise). v0.2 has a **hard** dependency on the `Workflow`
  tool — REVIEW and deep-build BUILD run as dynamic workflows, and there is no
  v0.1 command-pipeline fallback. If the runtime is missing, `/build-fleet:review`
  refuses with `BUILD_FLEET_REFUSE: workflow runtime unavailable` (exit 3).
- For **headless** callers, `Workflow` must be in the session's allowed tools,
  e.g. `claude -p --allowedTools "Workflow,Read,Edit,Write,Bash,Agent,Task" …`.

---

## Install

The plugin is distributed from a GitHub repository as its own single-plugin
marketplace.

```
/plugin marketplace add https://github.com/rocar/build-fleet.git
/plugin install build-fleet
```

Then verify the fleet loaded — `/agents` should list all seven `build-fleet:*`
agents.

**Transport note.** The `owner/repo` shorthand (`/plugin marketplace add
rocar/build-fleet`) resolves to **SSH** (`git@github.com:…`). On a machine
without a GitHub SSH key configured it will fail with a publickey error — use
the full **HTTPS** URL shown above instead, or a local path during development.
If the repo is **private**, the same credential (SSH key or HTTPS token via
`gh auth`) must be able to read it.

For local development, point Claude Code at a working copy directly:

```
claude --plugin-dir /path/to/build-fleet
```

### Updating

The plugin cache is **keyed by version** (`.claude-plugin/plugin.json`'s
`version`). `/reload-plugins` only re-reads the *local* cache — it does **not**
re-fetch from GitHub. To pull a new release you must update the marketplace
clone and reinstall:

```
/plugin marketplace update build-fleet   # re-fetches the repo
/plugin update build-fleet               # installs the new version into a fresh cache
/reload-plugins
```

A version bump is required for the cache to refresh; same-version pushes won't
take effect on an installed instance.

---

## Quickstart

```
# 1. describe the feature → scaffold + classify
/build-fleet:new-feature my-feature

# 2. (standard/large only) adversarial review workflow
/build-fleet:review

# 3. gate the spec, then run tests-first BUILD
/build-fleet:finalize

# 4. change-review the diff, then ship
/build-fleet:handoff
```

`new-feature` will **ask you what the feature should do** if it can't find a
description in the conversation — the slug alone is never treated as a spec.

The exact path depends on the routing tier the classifier assigns (below).

---

## Three-tier routing

When you run `/build-fleet:new-feature`, the **classifier** sizes the work and
writes `TIER` + `BUILD_MODE` into `PROGRESS.md`:

| Tier | Path | BUILD |
|---|---|---|
| **trivial** | skips REVIEW (`/build-fleet:finalize` straight from SPEC) | standard (qa → coder) |
| **standard** | full SPEC → REVIEW → FINALIZE → BUILD | standard (qa → coder) |
| **large** | full pipeline, then `BUILD_MODE=deep-build` | fan-out across partitioned coders |

The classifier is deliberately conservative: a **false-trivial is the dangerous
miss**, so anything touching auth, billing, or CI is never trivial, and a malformed
classifier verdict falls back to `standard`. Re-check or override at any time:

- `/build-fleet:dispatch` — re-runs the classifier on the active feature
  (query-only; doesn't change state).
- Edit `PROGRESS.md`'s `TIER:` line by hand to force a tier.

---

## Dynamic workflows

Two phases run as Claude Code **dynamic workflows** (JS scripts under
`workflows/` executed by the Workflow runtime), not direct Task fan-outs:

- **`/build-fleet:review` → `workflows/review.js`.** Fan-out reviewers
  (architect/qa/coder) → adversarial **cross-examination** → **survival vote** →
  scribe applies the verdict. A concern survives only if it is *not* refuted by a
  different-role reviewer citing a specific `spec.md`/`acceptance.md` section.
  This kills plausible-but-unfounded concerns before they block finalize.
- **deep-build → `workflows/deep-build.js`** (BUILD for `large` features).
  Architect partitions the work across files; coders fan out in parallel;
  overlap detection prevents two coders racing on the same file; an in-workflow
  adversarial review catches integration gaps before BUILD declares complete.

Because a workflow can't write files, it emits a structured envelope that the
**scribe** applies to `.sdd/`. While a workflow is running, a
`.sdd/<feature>/.workflow-in-flight` marker tells the per-reviewer hooks to
stand down (the workflow's own post-conditions replace them); the scribe deletes
the marker on completion, and a Stop hook reaps any orphaned markers older than
an hour.

> CYCLE counts **workflow runs**, not command invocations — cross-examination
> rounds inside a single run do not bump it. Review cycles are bounded (default
> 3); the 4th unresolved cycle writes `ESCALATION.md` and halts for a human.

---

## Command reference

| Command | Phase | What it does |
|---|---|---|
| `/build-fleet:new-feature <slug>` | SPEC | Scaffolds `.sdd/<slug>/`, runs the classifier, has PO draft `spec.md` + `acceptance.md`. Asks for a description if none is in context. |
| `/build-fleet:dispatch` | — | Re-classifies the active feature (query-only). |
| `/build-fleet:review` | REVIEW | Runs the adversarial review workflow. (Skipped for trivial.) |
| `/build-fleet:finalize` | FINALIZE → BUILD | Gate: refuses on open blockers. On pass, flips spec to FINALIZED and orchestrates BUILD (qa-first, then coder; routes to deep-build for large). |
| `/build-fleet:deep-build` | BUILD | Directly dispatches the fan-out build workflow (normally invoked for you by finalize). |
| `/build-fleet:handoff` | CHANGE_REVIEW → HANDOFF | architect + PO + qa review the diff; refuses if tests are missing/failing. On pass, devops ships. |
| `/build-fleet:status` | — | Prints `.sdd/ACTIVE`, `PROGRESS.md`, open concerns, cycle counts, and any escalation. |

---

## Tests-first BUILD

In standard BUILD, `/build-fleet:finalize` sequences **qa before coder**: qa
authors a failing test suite from `acceptance.md` first, and coder refuses to
begin until those tests exist. CHANGE_REVIEW then applies a counterfactual gate
— *would each test fail without coder's change?* — so the suite actually pins the
behavior rather than rubber-stamping it.

---

## Headless mode

Every command prints machine-readable `BUILD_FLEET_*:` JSON lines **before** any
human prose, so an orchestrator can drive build-fleet non-interactively (e.g.
`claude -p`, the Agent SDK, or a Hermes profile) by parsing those signals.

Representative signals: `BUILD_FLEET_CLASSIFICATION`,
`BUILD_FLEET_CLASSIFIER_FALLBACK`, `BUILD_FLEET_WORKFLOW_LAUNCHED`,
`BUILD_FLEET_FINALIZE_PASS` / `_REFUSE`, `BUILD_FLEET_FINALIZE_TRIVIAL_FAST_PATH`,
`BUILD_FLEET_BUILD_ROUTE`, `BUILD_FLEET_QA_TESTS_READY`, `BUILD_FLEET_CODER_REFUSE`,
`BUILD_FLEET_BUILD_COMPLETE` / `_INCOMPLETE`, `BUILD_FLEET_REFUSE`.

---

## State lives in the target project

Everything the fleet produces for a feature lives in `.sdd/<feature>/` in the
**target project's** working directory — never inside the plugin:

```
.sdd/
  ACTIVE                 # the one feature in flight
  <feature>/
    spec.md              # PO — STATUS: DRAFT|IN_REVIEW|FINALIZED|BLOCKED
    acceptance.md        # PO — testable criteria
    DECISIONS.md         # architect — append-only ADRs
    TEST_PLAN.md         # qa
    IMPL_NOTES.md        # coder
    REVIEW.md            # append-only review log (every cycle)
    PROGRESS.md          # orchestrator — phase, TIER, BUILD_MODE, handoff state
    ESCALATION.md        # only if review cycles exhausted
    .workflow-in-flight  # transient marker while a workflow runs
```

`PROGRESS.md` carries the v0.2 routing fields:

```
FEATURE: <slug>
PHASE:   SPEC | REVIEW | FINALIZE | BUILD | CHANGE_REVIEW | HANDOFF | ESCALATED
CYCLE:   <review-workflow runs>
CHANGE_CYCLE: <change-review rounds>
TIER:    trivial | standard | large | pending
BUILD_MODE: standard | deep-build | pending
UPDATED: <iso8601>
```

The plugin tree itself is read-only and re-installable; wiping and reinstalling
the plugin never touches your `.sdd/` state.

---

## Gates (enforced by hooks, not agents)

| Hook | Effect |
|---|---|
| `block-source-before-finalized` | Blocks writes outside `.sdd/` until `spec.md` is FINALIZED. |
| `restrict-reviewer-writes` | Confines writes to `.sdd/<active>/` during REVIEW / CHANGE_REVIEW. |
| `validate-spec-status` | Rejects a `spec.md` missing its STATUS line or required sections. |
| `check-review-written` | Rejects a reviewer that stops without logging to `REVIEW.md`. |
| `stop-tests` | During BUILD / CHANGE_REVIEW / HANDOFF, blocks stop on a failing suite (tolerates "no tests collected" pre-suite). |
| `reap-stale-workflow-markers` | Removes orphaned `.workflow-in-flight` markers older than an hour. |

Hooks block with exit code 2 and return actionable feedback. They are the
deterministic backbone — agents can't talk their way past a gate.

---

## The rules live in a skill

The full workflow contract — phase order, gate semantics, the survival-vote
convergence rule, escalation policy, file ownership, the `PROGRESS.md` schema —
is encoded in the **`sdd-protocol`** skill, loaded automatically by the commands
and agents. Read it at `skills/sdd-protocol/SKILL.md`. Supporting craft skills:
`sdd-spec-template`, `review-rubric`, `adr`, `test-plan`.

---

## Conventions

- One feature in flight per `.sdd/` at a time (named in `.sdd/ACTIVE`).
- Reviewers append to `REVIEW.md`; they never overwrite it.
- Every surviving design decision becomes an ADR in `DECISIONS.md`.
- The orchestrator (main session) never writes source — it routes and gates.
- Human escalation is a first-class outcome, not a failure.
