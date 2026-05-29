---
name: sdd-protocol
description: The canonical spec-driven development protocol for the build-fleet agent software house. Defines the SPEC → REVIEW → FINALIZE → BUILD → CHANGE-REVIEW → HANDOFF state machine, the .sdd/ workspace layout and file ownership, the deterministic phase gates, the bounded review-cycle and human-escalation policy, and the blocker/major/minor severity rubric. This is the single source of truth for how the fleet runs. Consult it whenever orchestrating a feature, transitioning phases, running a review, finalizing a spec, handing off to devops, or deciding whether to escalate — and any time a build-fleet command or role agent (product-owner, architect, coder, qa, devops) needs the workflow rules.
---

# SDD Protocol

This skill governs the runtime behaviour of the **build-fleet** software house. Commands
and role agents defer to it for the workflow, gates, and escalation rules. It is the
authority: where any agent prompt, command body, or stale CLAUDE.md disagrees with this
file, this file wins.

## Operating principles

- **Spec is the contract.** No source is written until the active spec is `FINALIZED`.
- **Gates are deterministic.** Phase transitions are enforced by hooks (exit code 2 =
  block + feedback), never by an agent deciding it is finished.
- **Filesystem is shared memory.** Subagent context is isolated and does not sync between
  roles. Everything that must cross roles lives as a file in `.sdd/<feature>/`. There is
  no per-agent persistent memory layer.
- **Escalate, don't loop forever.** Each review gate is bounded (default **3** cycles).
  The 4th unresolved cycle writes `ESCALATION.md` and halts that phase for a human.
- **The orchestrator routes, it does not build.** The main session assigns work, runs
  gates, and synthesizes. It never writes production source itself.
- **One feature in flight.** `.sdd/ACTIVE` names the single active feature.

## Workspace layout and ownership

```
.sdd/
  ACTIVE                 # one line: the active feature slug. Empty = no active feature.
  <feature>/
    spec.md              # product-owner. STATUS line + spec body. Source of truth.
    acceptance.md        # product-owner. Testable acceptance criteria.
    DECISIONS.md         # architect. Append-only ADR log.
    TEST_PLAN.md         # qa. Test design mapped to acceptance criteria.
    IMPL_NOTES.md        # coder. Implementation notes and deviations.
    REVIEW.md            # reviewers. Append-only review log (see format below).
    PROGRESS.md          # orchestrator. Phase + cycle state (schema below).
    ESCALATION.md        # exists only when a gate has exhausted its cycles.
```

Write boundaries (enforced by hooks):
- `product-owner` writes `spec.md`, `acceptance.md`.
- `architect` and `qa` are reviewers: they may write **only inside `.sdd/<active>/`**
  (ADRs, REVIEW.md, TEST_PLAN.md). They never write source.
- `coder` writes source + `IMPL_NOTES.md`, only while `PHASE` is `BUILD`.
- `devops` writes CI/CD, IaC, release artifacts, only after CHANGE-REVIEW approval.

`.sdd/ACTIVE` empty (or absent) means no feature is active; all write-gating hooks then
allow operations through. Every hook resolves the active feature by reading this file —
never an environment variable.

## PROGRESS.md schema

Exact field names; hooks and commands parse these lines:

```
FEATURE: <slug>
PHASE: SPEC | REVIEW | FINALIZE | BUILD | CHANGE_REVIEW | HANDOFF | ESCALATED
CYCLE: <int>          # spec-review cycles consumed (incremented by /review)
CHANGE_CYCLE: <int>   # change-review cycles consumed (incremented by /handoff)
UPDATED: <iso8601>
```

## spec.md STATUS line

The first line of `spec.md` is always:

```
STATUS: DRAFT | IN_REVIEW | FINALIZED | BLOCKED
```

`validate-spec-status` (PostToolUse on spec.md) rejects a write whose STATUS is missing or
not one of the four values, or whose required sections are absent.

## REVIEW.md entry format

Append-only. Reviewers add one block per cycle; never edit prior blocks. Resolution of a
concern is a *new* approving entry in a later cycle, not an edit.

```
## Cycle <N> — <role> — <iso8601>
- [blocker] <concern>
- [major]   <concern>
- [minor]   <concern>
status: concerns-raised | approved
```

`check-review-written` (SubagentStop) rejects a reviewer that stops without appending a
block attributed to it for the current cycle.

## Severity rubric

| Severity | Definition | Gate effect |
|---|---|---|
| `blocker` | Correctness, security, data loss, or a contradiction of the spec/acceptance. | Blocks FINALIZE and HANDOFF. |
| `major` | Scalability, maintainability, or missing acceptance coverage. | Must be resolved or explicitly accepted (as an ADR) before the gate opens. |
| `minor` | Style, wording, nits. | Advisory; never blocks a gate. |

The severity vocabulary is duplicated verbatim in each reviewer agent's prompt body,
because skill frontmatter is not loaded when an agent runs as an agent-team teammate.

## State machine

```
SPEC ──► REVIEW ──► FINALIZE ──► BUILD ──► CHANGE_REVIEW ──► HANDOFF
          ▲  │                              ▲       │
          └──┘ (≤3 cycles, then ESCALATE)   └───────┘ (≤3 cycles, then ESCALATE)
```

**SPEC.** product-owner drafts `spec.md` (STATUS=DRAFT) + `acceptance.md`.
Exit: a non-empty spec with all required sections exists.

**REVIEW.** `/review` sets PHASE=REVIEW, increments `CYCLE`, sets STATUS=IN_REVIEW, and
runs architect + qa + coder against the spec. Each appends a REVIEW.md block. product-owner
then revises the spec in response.
- Cycles 1–2: spawn reviewers as parallel subagents (Task fan-out).
- Cycle 3: promote to an agent team so reviewers can debate and challenge each other
  before the escalation boundary.
Exit (to FINALIZE): in the most recent completed cycle, every reviewer block has
`status: approved` and zero `[blocker]` items.
Escalation: if `CYCLE` would exceed 3 with blockers still open, write `ESCALATION.md`,
set PHASE=ESCALATED, and halt.

**FINALIZE.** `/finalize` runs the finalize gate. Permitted only when the most recent
review cycle is fully approved with no open blockers. On success: set STATUS=FINALIZED,
PHASE=BUILD. The source-write block lifts at this point and not before.

**BUILD.** In parallel: qa authors tests under `tests/` mapped to `acceptance.md`; coder
implements to spec and records deviations in `IMPL_NOTES.md`. coder refuses to start while
STATUS≠FINALIZED.
Exit: implementation and tests exist; tests pass locally.

**CHANGE_REVIEW.** `/handoff` sets PHASE=CHANGE_REVIEW, increments `CHANGE_CYCLE`, and runs
architect + product-owner + qa against the diff:
- architect: design adherence and ADR compliance.
- product-owner: meets `acceptance.md`.
- qa: coverage gaps before handoff.
Exit (to HANDOFF): all three approve with no open blockers. Fail → back to BUILD (bounded
by `CHANGE_CYCLE` ≤ 3, then ESCALATE).

**HANDOFF.** devops takes the finalized, reviewed change → CI/CD, IaC, release notes.

## Hard gates (enforced by hooks)

1. No source write while the active spec STATUS ≠ FINALIZED.
   *(block-source-before-finalized, PreToolUse Write|Edit)*
2. architect/qa may not write outside `.sdd/<active>/`.
   *(restrict-reviewer-writes, PreToolUse Write|Edit)*
3. spec.md always carries a valid STATUS line and required sections.
   *(validate-spec-status, PostToolUse Write|Edit on spec.md)*
4. A reviewer cannot stop without recording its review for the current cycle.
   *(check-review-written, SubagentStop)*
5. A session cannot stop on a failing test/lint stack; if no recognized stack exists yet,
   the Stop hook is a silent no-op so bootstrap and empty repos don't deadlock.
   *(stop-tests, Stop)*

`TaskCompleted` and `TeammateIdle` (agent-teams-only) are intentionally **not** shipped
yet; they are deferred to a hardening pass once team mode is exercised.

## Escalation

When a review gate exhausts its cycle budget with blockers still open, the responsible
command writes `.sdd/<feature>/ESCALATION.md` containing: the phase, the cycle count, the
unresolved blockers (verbatim from REVIEW.md), and the conflicting positions. It sets
PHASE=ESCALATED and stops. Escalation is a first-class outcome, not a failure — the human
decides how to break the deadlock.
