# CLAUDE.md — contributing to build-fleet

This repo is the **build-fleet Claude Code plugin**: a spec-driven multi-agent
software house. Claude Code is both the *runtime* (it executes the workflow in a
target repo) and the *builder* (it authors and edits the agents, skills, hooks,
commands, and workflows here). Treat everything in this repo as production source:
review it, version it, test it.

The runtime workflow rules (state machine, gates, escalation) live in the
**`sdd-protocol` skill** — `skills/sdd-protocol/SKILL.md` plus its
`references/{product-tier,bug-lane}.md`. That skill is the authority on how the
fleet runs; this file only covers how to work on the plugin itself.

## Layout (what actually ships)

```
.claude-plugin/plugin.json    # manifest (+ marketplace.json)
agents/                       # 7 role subagents: product-owner, architect, coder,
                              #   qa, devops, classifier, scribe
commands/                     # 21 slash commands (/build-fleet:*)
skills/                       # 7 skills: sdd-protocol (+references/), adr,
                              #   review-rubric, sdd-spec-template,
                              #   sdd-diagnosis-template, test-plan, skill-routing
hooks/hooks.json              # hook registration (the ONLY registration point)
hooks/scripts/                # 10 gate scripts + their *.test.sh harnesses
workflows/                    # 4 dynamic workflows: review.js, deep-build.js,
                              #   diagnose.js, plan-review.js
scripts/                      # deterministic helpers (next-feature, intent-block,
                              #   product-memory-splice, status-snapshot, run-tests)
                              #   + their *.test.sh
docs/                         # contracts, smoke fixtures, history
.github/workflows/ci.yml      # CI: test matrix + release-channel check
```

The orchestrator is the main session; agents are dispatched via Task/workflows.
State lives in the target repo's `.sdd/` — see the `sdd-protocol` skill for the
`.sdd/` layout, ownership, and policy.

## Running the tests

```bash
bash scripts/run-tests.sh        # every hook + script suite, then the smoke test
```

- Individual suites run directly: `bash hooks/scripts/<name>.test.sh`,
  `bash scripts/<name>.test.sh`. Each is a hermetic mktemp harness that feeds the
  real hook stdin contract and asserts exit codes + stderr.
- The smoke test (`docs/v0.5/smoke/smoke.sh`) walks a planted bug through the
  whole deterministic backbone.
- Workflows: `node --check workflows/*.js` after any edit (they run in an
  isolated JS runtime — no `Date`, no filesystem; timestamps come from
  `args.now`, all state writes go through the scribe).
- CI (`.github/workflows/ci.yml`) runs the suite on macOS (bash 3.2) and Linux,
  and pins every pushed `v*` tag to plugin.json's version. Keep every hook
  script bash-3.2 compatible AND GNU-coreutils compatible (probe GNU flags
  first: e.g. GNU `stat -f` succeeds with the wrong meaning, it doesn't fail).
- TDD for gates: any hook behavior change gets a failing test case first, in the
  existing harness style.

## Hard rules

- **The release checklist is atomic.** A release moves these together or not at
  all: the git tag, `plugin.json` version, `marketplace.json`, a CHANGELOG entry,
  README component counts, and the agent `description:` frontmatter for any agent
  whose body changed. The plugin cache is version-keyed — a content change
  without a version bump never reaches installed users. Main always equals the
  latest tag (release discipline; CI pins each pushed tag to its manifest
  version).
- **A lane that touches an agent's body must touch its description.** The
  description is the delegation surface; a stale one misroutes work.
- **Severity rubric is triple-maintained on purpose.** The blocker/major/minor
  table lives canonically in `skills/review-rubric/SKILL.md` and is mirrored
  verbatim in `agents/architect.md` and `agents/qa.md`. The mirrors are
  load-bearing: when a role runs as an agent-team teammate, its frontmatter
  `skills:` are **ignored** (loaded from project/user settings instead), so
  review rules that must survive team mode live in the prompt body, not only in
  a skill. Never "deduplicate" the copies; `scripts/rubric-drift.test.sh` fails
  the suite if they drift. Run it after any `agents/` edit.
- **Hooks fail closed.** Gate scripts anchor at `CLAUDE_PROJECT_DIR`, reject
  `..` traversal, require jq while an item is active, and trap unexpected errors
  to exit 2. Deliberate allows are explicit `exit 0`. Keep it that way.
- **Signal lines are the machine contract.** Commands cannot set process exit
  codes; orchestrators dispatch on the `BUILD_FLEET_*:` stdout lines (refusals
  carry `{"code":<int>,"reason":"<slug>"}`). Never document an exit-code table.
- **No milestone jargon in the user-facing surface.** Command descriptions stay
  short and imperative; command bodies and agent prompts name behaviors, not the
  internal milestone that shipped them. History belongs in CHANGELOG/ROADMAP/docs.
- **The scribe has no Bash.** It releases the `.workflow-in-flight` marker by
  overwriting it with empty content; the gate hooks treat an empty marker as
  absent and the Stop-hook reaper deletes it. Keep agent tool allowlists tight.

## Where things are decided

- Workflow/gate semantics → `skills/sdd-protocol/SKILL.md` (+ references/).
- Envelope schema + headless contract → `docs/v0.2/CONTRACT.md`.
- Severity vocabulary → `skills/review-rubric/SKILL.md`.
- Spec/diagnosis artifact structure → `skills/sdd-spec-template`,
  `skills/sdd-diagnosis-template`.
- Design lineage (the original v0.1 design spec, prior plans, audits) →
  `docs/history/` (start with `DESIGN-SPEC-v0.1.md`).
