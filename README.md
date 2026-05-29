# build-fleet

A reusable Claude Code plugin that turns any project into a spec-driven
multi-agent software house. Ships five role subagents — `product-owner`,
`architect`, `coder`, `qa`, `devops` — that execute a deterministic state
machine for every feature:

```
SPEC ──► REVIEW ──► FINALIZE ──► BUILD ──► CHANGE_REVIEW ──► HANDOFF
          ▲  │                              ▲       │
          └──┘ (≤3 cycles, then ESCALATE)   └───────┘ (≤3 cycles, then ESCALATE)
```

Phase transitions are enforced by hooks, not by agents deciding they're done.
The authoritative rulebook is the `sdd-protocol` skill bundled with this
plugin.

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

## Required one-time user step

This plugin uses Claude Code's experimental agent-teams mode for the third
review cycle (so reviewers can debate before escalation). Add to your shell
rc:

```
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

Plugins cannot set environment variables, so this must live in your shell.
Without it, cycle-3 falls back to parallel subagents — the workflow still
completes, but you lose cross-reviewer debate.

## Quickstart

In a target project (NOT inside the plugin tree):

```
/build-fleet:new-feature my-feature      # scaffolds .sdd/my-feature/, PO drafts spec
/build-fleet:review                      # parallel review by architect + qa + coder
/build-fleet:finalize                    # gate; flips spec to FINALIZED, unlocks source writes
... coder implements, qa writes tests ...
/build-fleet:handoff                     # change-review by architect + PO + qa, then devops
/build-fleet:status                      # current phase, open concerns, cycle counts
```

## State lives in the target project

The plugin tree itself is read-only machinery — Claude Code wipes the plugin
cache on update, so nothing mutable can live here.

All runtime state lives in the **target project's** `.sdd/` directory:

```
<target-project>/.sdd/
  ACTIVE                 # one-line slug naming the active feature
  <feature>/
    spec.md              # STATUS: DRAFT | IN_REVIEW | FINALIZED | BLOCKED
    acceptance.md
    DECISIONS.md         # append-only ADRs
    TEST_PLAN.md
    IMPL_NOTES.md
    REVIEW.md            # append-only review log
    PROGRESS.md          # PHASE, CYCLE, CHANGE_CYCLE
    ESCALATION.md        # exists only when a gate exhausts its cycle budget
```

Commit `.sdd/` alongside your source — it's the audit trail for every
decision the fleet made.

## Where to read the rules

The single source of truth for the workflow, gates, severity rubric, and
escalation policy is the `sdd-protocol` skill at `skills/sdd-protocol/SKILL.md`.
When this README, an agent body, or the original design history in `CLAUDE.md`
disagrees with the skill, the skill wins.
