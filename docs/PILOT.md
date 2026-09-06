# build-fleet — pilot onboarding

**What it is.** A spec-driven multi-agent software house, packaged as a Claude Code
plugin. A high-level spec goes in; a change comes out that is *verified against that
spec* — with the whole audit trail on disk. Eight role subagents (product-owner,
architect, coder, qa, devops, classifier, scribe, reviewer) drive every change through
**SPEC → REVIEW → FINALIZE → BUILD → CHANGE_REVIEW → HANDOFF**, with the phases
enforced by hooks rather than by prompting.

---

## 1. Prerequisites

Check these first — the first one is the usual blocker.

- **Claude Code v2.1.154+ with dynamic workflows enabled** (`/config` → *Dynamic
  workflows*; on by default for Max / Team / Enterprise, opt-in on Pro).
  build-fleet has a **hard** dependency on this — REVIEW and deep-build run as
  JavaScript workflow scripts, with no fallback. Without it those commands refuse.
- **`jq`** and **`bash`** — every gate hook is a bash script (Windows ⇒ Git Bash or
  WSL; without bash the gate layer silently does not run).
- A **git repository**, and a **test command that actually runs**. The `stop-tests`
  hook blocks the session from ending on a red suite, and `/handoff` refuses if
  tests are missing or failing. Pick an area with an existing test harness.

## 2. Install

```
/plugin marketplace add https://github.com/rocar/build-fleet.git
/plugin install build-fleet
```

Use the **HTTPS URL** — the `owner/repo` shorthand resolves to SSH and fails without
a configured key. Verify with `/agents`: all eight `build-fleet:*` agents should be
listed.

Work on a **feature branch**. Everything the fleet produces lands in `.sdd/` in your
repo; the scaffolder writes a `.sdd/.gitignore` so live locks stay out of git while
the audit trail is committable. No source is written before the spec is FINALIZED,
so scaffolding is safe against a production codebase.

## 3. First run — describe the feature inline

The simplest entry point. Everything after the slug is the feature description:

```
/build-fleet:new-feature price-rounding "Order totals must round half-up to 2dp at
    the line level before tax, not at the invoice level. Applies to the checkout
    and invoice PDF paths. Out of scope: currency conversion."

/build-fleet:review      # adversarial review workflow — architect, qa, coder
/build-fleet:finalize    # the gate: flips spec.md to FINALIZED, unlocks source
/build-fleet:build       # qa writes the failing suite first, then coder implements
/build-fleet:handoff     # change-review against acceptance.md, then ship
```

`/build-fleet:status` prints where you are at any point. If the description is too
thin, `new-feature` asks in a short structured loop rather than guessing from the
slug.

## 4. Alternative — you already have a large, detailed spec document

Don't paste a long document into the command argument. Instead:

1. **Commit the document into the repo** (e.g. `docs/specs/<name>.md`) so it is part
   of the traceability chain.
2. **Reference it in the conversation** — tell Claude to read it, and discuss it.
3. **Run `/build-fleet:new-feature <slug>` with *no* inline argument.**

> ⚠️ **The gotcha:** an inline argument is treated as *authoritative* and **overrides
> conversation context**. Passing `/new-feature x "see the spec doc"` makes that
> seven-word string the spec. Leave the argument empty so the discussed document
> resolves, or make the argument a real pointer that names the file path.

**Your document does not become `spec.md`.** The product-owner *translates* it into
the eight sections the `validate-spec-status` hook enforces — Overview, Goals,
Non-goals, Behavior, Interfaces / Contracts, Constraints, Risks, Acceptance
Criteria — plus a separate `acceptance.md` of testable criteria. That translation is
where prose requirements become verifiable ones, and it is the step worth watching.

**Review the translation before you finalize.** After `/new-feature` and before
`/build-fleet:review`, have the spec's author read `.sdd/<slug>/spec.md` and
`acceptance.md` next to the original document. Correct anything dropped or misread
there — it is far cheaper than at any later gate.

**If the document spans phases or reads like a PRD, it is a backlog, not a feature.**
Use the product tier instead: `/build-fleet:new-product <slug>` (on an existing
codebase the architect *infers* your real stack as the binding baseline) →
`/build-fleet:plan-review` → `/build-fleet:plan-finalize ratify` (a human gate that
never auto-passes) → then run each backlog row through the feature loop above.

## 5. How the outcome gets verified against the spec

| Step | What guarantees it |
|---|---|
| High-level spec → testable criteria | PO writes `acceptance.md` separately from the narrative spec |
| Review is evidence-based | Reviewers must cite `{file, locator}`; an uncited refutation is discarded |
| No premature code | `block-source-before-finalized` rejects every non-`.sdd/` write until FINALIZED; `guard-bash-writes` closes the shell escape hatch |
| Tests precede implementation | `/build` sequences qa → coder; coder refuses to start until the failing suite exists |
| Every criterion is covered | At CHANGE_REVIEW each acceptance criterion must name the test exercising it — a gap is a `[blocker]` |
| Tests actually pin behavior | **Counterfactual gate:** revert the change and every test must go red |
| Nothing ships red | `/handoff` refuses on missing or failing tests |

Hooks block with a non-zero exit and actionable feedback — agents cannot talk past a
gate. The full record (`spec.md` → `acceptance.md` → `TEST_PLAN.md` →
`IMPL_NOTES.md` → `REVIEW.md` → `DECISIONS.md`) stays in `.sdd/<slug>/`, committed.

## 6. Things to know before the pilot

- **Your existing `CLAUDE.md` can fight the gates.** It outranks skills in instruction
  precedence, but the hooks enforce the protocol regardless — so "write the plan to
  `tasks/todo.md`" or "given a bug, just fix it" doesn't win, it just makes the agent
  attempt a blocked action and burn a cycle. It is injected into every role agent too,
  so orchestrator-directed advice reaches the coder. Reconcile it before the first
  run — [`CLAUDE.sample.md`](CLAUDE.sample.md) lists the common conflicts and gives a
  copyable fleet-native version.
- **Escalation is designed behavior, not failure.** Review is capped at 3 cycles; if
  blockers survive, the workflow writes `ESCALATION.md`, sets `PHASE: ESCALATED`,
  and refuses further review until a human runs
  `/build-fleet:resolve-escalation <decision>` — which is archived append-only.
- **Decide what "ship" means up front.** At `/handoff` the devops role wires CI and
  writes release notes. For a pilot, state in-session that shipping means *open a PR
  only*.
- **One item in flight, one session per working tree.** `.sdd/ACTIVE` is a lock;
  `/build-fleet:park <reason>` is the sanctioned way to preempt it.
- **Scope the first feature deliberately.** Standard tier is the sweet spot: real
  enough to need a spec, small enough to finish in one session. Trivial features
  skip `/review` entirely; genuinely large ones fan out to the deep-build workflow
  (more impressive, longer, more surface for a first run).
- **Bug lane (optional second act).** For a real unknown-cause bug:
  `/triage` → `/reproduce` → `/diagnose` → `/fix` → `/verify`. A fix cannot touch
  source until a reproducing test exists — *even for sev0*.
