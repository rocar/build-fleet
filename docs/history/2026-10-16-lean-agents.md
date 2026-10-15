# build-fleet lean agents — design

**Date:** 2026-10-16
**Status:** draft for review (design approved section by section in brainstorming on
2026-10-15); implementation plan follows approval
**Ships as:** part D of build-fleet v0.12.0 ("lite"), with parts A (lite commands) and C
(drift gate), both done, and B (four files per feature).
**Evidence:** roadmap review, section 5 "Tuning the agent definitions" —
https://claude.ai/artifact/RjjQEmAJ6woyP1aGQXdK4j

## 1. Problem

The eight agent definitions carry descriptions of 61–116 words and bodies of 652–1,654
words. Descriptions are the delegation surface: Claude routes on them, they cost
context in every session, and Claude Code's guidance is to keep them short and put
detail in the body. Today's descriptions instead narrate which stage runs before which,
which lens runs where, and the bug-lane step names; the commands already own all of
that. The bodies repeat the same sequencing at length, so an agent reads a workflow it
does not drive.

| Agent | Description | Body | Model |
|---|---|---|---|
| architect | 116 | 1,527 | opus |
| classifier | 92 | 1,654 | sonnet |
| coder | 96 | 990 | sonnet |
| devops | 61 | 652 | sonnet |
| product-owner | 79 | 1,623 | opus |
| qa | 113 | 1,552 | sonnet |
| reviewer | 83 | 791 | sonnet |
| scribe | 99 | 1,588 | sonnet |

Skill descriptions run 33–99 words (`sdd-protocol` 99, `skill-routing` 55,
`sdd-spec-template` 44).

## 2. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | Scope: the 8 agents (descriptions and bodies) plus the 7 skill **descriptions**, and two guard tests. Skill bodies, command bodies and the dispatch-brief audit are out. | The roadmap's highest-value cut is the routing surface. `sdd-protocol` is the rulebook every command consults, and the commands are part B's subject; cutting either here would mix two changes. |
| D2 | Descriptions: at most 40 words, shaped "Use when …. Do NOT use for …", routing only. | Descriptions route; they don't explain. |
| D3 | Bodies: at most 800 words by default. An agent whose contract cannot fit gets its own cap, written in the test with a one-line reason. | The scribe's write procedure and the classifier's tables are contract, not narration. Moving them into a skill is unsafe: in workflow and team mode, skills do not load into an agent. |
| D4 | No behaviour change. Every gate, signal line, file-ownership rule and mirrored section stays. | The measurement step that follows compares review shapes; it needs the agents to behave as today. |
| D5 | `tools:` allowlists are pinned by a test. | An omitted list inherits every tool, and plugin subagents ignore per-agent hooks and permission mode, so the allowlist is the main per-agent limit. |

## 3. Design

### 3.1 Descriptions

Every agent and skill description is at most 40 words and contains "Do NOT use". It says
when to use the agent or skill and when not to, naming the neighbour it is confused
with (coder vs qa for tests; the reviewer agent vs the role lenses). It does not name
hidden steps (`/build-fleet:<step>`), stage order, or which workflow runs which lens.

### 3.2 Agent bodies

**Kept verbatim** (the drift tests pin each):
- the severity-rubric table in architect, qa and reviewer (`scripts/rubric-drift.test.sh`);
- the verified-review rule between `<!-- verified-rule:start/end -->` markers
  (`scripts/rubric-drift.test.sh`);
- every `## Review lens` section (`scripts/lens-drift.test.sh`);
- every `BUILD_FLEET_*` signal line an agent emits, with its JSON shape.

**Kept, tightened:** the role in one or two sentences; authority; the files the agent
may write and must never write; its output format (REVIEW.md entry shape, return
object, signal); its hard "no"s; its bug-lane duties as duties, not as a step sequence.

**Cut:**
- prose retelling a command's sequence ("during CHANGE_REVIEW you run in the first
  stage, before the architect…");
- worked REVIEW.md examples that repeat the format the agent already states;
- history and rationale ("since the tap pilot…", "why this design");
- repetition between sections of the same body.

**Moved.** When a cut sentence is a rule the agent must still follow at dispatch (for
example "qa's CHANGE_REVIEW majors carry disposition fix"), it moves into the Task
prompt of the command that dispatches that agent, as one added line. No other command
text changes.

**Caps.** 800 words by default. Expected exceptions, each set in the plan to what
remains after the cut plus 10%, never above today's length:
- **scribe** — its numbered write procedure (PROGRESS, REVIEW, IMPL_NOTES, DECISIONS,
  ESCALATION, the marker release) is the contract every workflow's apply step depends
  on;
- **classifier** — the tier and risk tables and the bug-mode triage decide routing;
- **product-owner**, only if its product-tier section (used by `plan-review`) cannot
  fit.

Word counts exclude the frontmatter and count whitespace-separated tokens
(`awk '{w+=NF}'`).

### 3.3 Guard test: `scripts/agent-surface.test.sh`

- Every `agents/*.md` and `skills/*/SKILL.md` description: at most 40 words, contains
  `Do NOT use`, contains no `/build-fleet:`.
- Every agent body: at most 800 words, or its named cap. The caps live in the test as
  `name:cap:reason` lines.
- Every agent's `tools:` line equals its recorded list exactly (order included); a
  missing `tools:` line fails. Recorded lists are today's:

  | Agent | tools |
  |---|---|
  | architect | Read, Grep, Glob, Edit |
  | classifier | Read, Grep, Glob |
  | coder | Read, Grep, Glob, Edit, Write, Bash |
  | devops | Read, Grep, Glob, Edit, Write, Bash |
  | product-owner | Read, Grep, Glob, Edit, Write |
  | qa | Read, Grep, Glob, Edit, Write, Bash |
  | reviewer | Read, Grep, Glob |
  | scribe | Read, Write, Edit |

  A deliberate change edits the test in the same commit.
- `model:` lines are not pinned (the measurement step may change them).

### 3.4 Existing tests

`rubric-drift`, `lens-drift` and every other suite stay green. `drift-wiring.test.sh`'s
assertion on qa's description phrase is updated to the new wording (the drift gate's
repair pass stays named in qa's body, which the same test checks).

## 4. Verification

No eval harness exists, so behaviour is checked by live runs on `/tmp/bf-lite` with the
branch plugin, compared against the drift-gate live run (2026-10-15):
1. **Feature:** a new feature through `start`, `build` and `ship`. Every agent emits its
   signal lines; each writes only its own files (the write gates would refuse
   otherwise); the review gates parse every block (no `unparsed`, no `missing-<role>`);
   the drift gate passes at all three points; the run ends `shipped`.
2. **Bug:** a planted bug through `fix`, ending at devops' OK.
3. A missing signal, a refused gate or a role writing outside its files is a regression
   and is fixed before the plan completes.

## 5. Success criteria

1. `agent-surface.test.sh` passes; the full suite is green on macOS and Linux.
2. Every agent and skill description is at most 40 words.
3. Every agent body is at most 800 words, or at its named cap with a reason.
4. The total agent body word count drops by at least 35% (from 10,377).
5. Both live runs complete with the same signal sequence as before.

## 6. Out of scope

- Skill bodies, including `sdd-protocol`.
- The dispatch-brief audit of command Task prompts.
- Model choices; the typed critic (the measurement step).
- Command bodies (part B's files change them anyway).
