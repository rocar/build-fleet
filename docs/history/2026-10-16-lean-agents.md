# build-fleet lean agents — design

**Date:** 2026-10-16
**Status:** draft for review (design approved section by section in brainstorming on
2026-10-15); implementation plan follows approval
**Revised:** 2026-10-16 after an independent Gemini review (§7).
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
| D1 | Scope: the 8 agents (descriptions and bodies) plus the 7 skill **descriptions**, and one guard test. Skill bodies, the dispatch-brief audit and command rewrites are out; the only command edits allowed are the one-line moves of §3.2, each listed in the plan. | The roadmap's highest-value cut is the routing surface. `sdd-protocol` is the rulebook every command consults, and the commands are part B's subject; cutting either here would mix two changes. |
| D2 | Descriptions: at most 40 words, shaped "Use when …. Do NOT use for …", routing only. | Descriptions route; they don't explain. |
| D3 | Bodies: at most 800 words by default. Any agent whose rules cannot fit after the cut gets its own cap, written in the test with a one-line reason. | The scribe's write procedure and the classifier's tables are contract, not narration, and architect and qa carry about 300 words of mirrored text. Moving rules into a skill is unsafe: in workflow and team mode, skills do not load into an agent. |
| D3a | **Rules are never cut, only narration.** Every rule in a body today (an imperative: must, never, refuse, only, always; a signal; an ownership line) is inventoried before the cut and must survive in the same body. | Workflows dispatch agents with prompts built in the workflow script, not in the commands, so a rule moved to a command vanishes in workflow mode. A rule is the agent's runtime logic. |
| D4 | No behaviour change. Every gate, signal line, file-ownership rule and mirrored section stays. | The measurement step that follows compares review shapes; it needs the agents to behave as today. |
| D5 | `tools:` allowlists are pinned by a test. | An omitted list inherits every tool, and a plugin agent's own frontmatter `hooks` and `permissionMode` are ignored, so the allowlist is the main per-agent limit. (The plugin-wide hooks in `hooks/hooks.json`, which the write gates use, do fire for subagents.) |

## 3. Design

### 3.1 Descriptions

Every agent and skill description is one line of at most 40 words. An agent's says when
to use it and, with "Do NOT use", when not to, naming the neighbour it is confused with
(coder vs qa for tests; the reviewer agent vs the role lenses). An agent serving several
modes names each mode in a word or two ("feature tiering and bug triage"). A skill's
says what it holds and when to consult it; "Do NOT use" is optional there. Neither names
hidden steps (`/build-fleet:<step>`), stage order, or which workflow runs which lens. The
commands and workflows dispatch agents by name, so the description is not what routes
them inside the flow; it routes Claude's own delegation in a user's session.

### 3.2 Agent bodies

**Kept verbatim** (the drift tests pin each):
- the severity-rubric table in architect, qa and reviewer (`scripts/rubric-drift.test.sh`);
- the verified-review rule between `<!-- verified-rule:start/end -->` markers
  (`scripts/rubric-drift.test.sh`);
- every `## Review lens` section (`scripts/lens-drift.test.sh`);
- every signal line an agent emits (`BUILD_FLEET_*`, `SCRIBE_OK:` and the like), in its
  exact format: JSON where it is JSON today, plain text where it is plain text.

**Kept, every one (D3a):** each rule in the inventory. Examples that must survive, by
name: qa's counterfactual snapshot (`git stash create`, never a bare `git checkout`);
coder's refuse-to-begin check and its refusal line; the CHANGE_REVIEW disposition
contract (product-owner and qa majors carry `disposition: fix`; only the architect
converts a peer's major to `disposition: adr ADR-N`; no new majors on a delta cycle);
the architect's brownfield baseline rules; qa's drift-gate repair duties.

**Kept, tightened:** the role in one or two sentences; authority; the files the agent
may write and must never write; its output format (REVIEW.md entry shape, return
object, signal); its bug-lane duties as duties, not as a step sequence. Tightening may
reword a rule's surrounding prose; it never drops the rule or weakens it.

**Cut:**
- prose retelling a command's sequence ("during CHANGE_REVIEW you run in the first
  stage, before the architect…");
- worked REVIEW.md examples that repeat the format the agent already states;
- history and rationale ("since the tap pilot…", "why this design");
- repetition between sections of the same body.

**Not moved.** Rules stay in the body (D3a). A command's Task prompt may gain one line
only to keep a hint that is purely about that command's dispatch and appears in no
workflow; the plan lists each such line, and there may be none.

**The inventory.** Before cutting an agent, the plan extracts its rules into
`docs/history/2026-10-16-lean-agents-RULES.md`: one line per rule, with the agent and a
short quote. After the cut, each line is checked off against the new body (the quote, or
the reworded rule beside it). The plan's final reviewer checks the inventory against
both versions.

**Caps.** 800 words by default. Any agent whose inventoried rules cannot fit gets a cap
set to what remains after the cut plus 10%, never above today's length. Expected
exceptions:
- **scribe** — its numbered write procedure (PROGRESS, REVIEW, IMPL_NOTES, DECISIONS,
  ESCALATION, the marker release) is the contract every workflow's apply step depends
  on;
- **classifier** — the tier and risk tables and the bug-mode triage decide routing;
- **product-owner**, **architect** and **qa**, if their product-tier, change-review and
  bug-lane rules plus the mirrored text cannot fit.

Word counts exclude the frontmatter and count whitespace-separated tokens other than a
bare `|` (so table pipes don't count). A `---` line inside the body is a rule, not the
end of the count.

### 3.3 Guard test: `scripts/agent-surface.test.sh`

- Every `agents/*.md` and `skills/*/SKILL.md` description: a single line (a folded `>`
  or `|` value fails), at most 40 words, no `/build-fleet:`. Agent descriptions also
  contain `Do NOT use`.
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

No eval harness exists. The gates check structure, not judgement: a reviewer that finds
less passes them faster. So verification has two parts.

**A. Planted-defect review, before and after.** A fixture feature (in `/tmp/bf-lean`)
has a draft spec with three planted defects: two criteria that contradict each other,
an unstated failure behaviour, and an untestable criterion. `/build-fleet:review` (the
default debate shape) runs on it once with the agents as they are today (the branch
before part D) and once after. Each planted defect must be raised in both runs at the
same severity or higher. A defect found before and missed after is a regression. This is
one run each, so it detects a gross loss of judgement, not a small one; the measurement
step that follows is the real test of review quality.

**B. Live runs** on `/tmp/bf-lite` with the branch plugin, compared against the
drift-gate live run (2026-10-15):
1. **Feature:** a new feature through `start`, `build` and `ship`. Every agent emits its
   signal lines; each writes only its own files (the write gates would refuse
   otherwise); the review gates parse every block (no `unparsed`, no `missing-<role>`);
   the drift gate passes at all three points; the run ends `shipped`.
2. **Bug:** a planted bug through `fix`, ending at devops' OK.
3. A missing signal, a refused gate, a role writing outside its files, or a planted
   defect lost in A is a regression and is fixed before the plan completes (by restoring
   the rule or text that carried it).

## 5. Success criteria

1. `agent-surface.test.sh` passes; the full suite is green on macOS and Linux.
2. Every agent and skill description is at most 40 words.
3. Every agent body is at most 800 words, or at its named cap with a reason.
4. Every line of the rules inventory is checked off against the new bodies.
5. The planted-defect review raises each defect after the cut at no lower severity than
   before.
6. Both live runs complete with the same signal sequence as before.

The total body word count (10,377 today) is reported, not targeted: the caps bound it,
and a percentage target would reward cutting rules.

## 6. Out of scope

- Skill bodies, including `sdd-protocol`.
- The dispatch-brief audit of command Task prompts.
- Model choices; the typed critic (the measurement step).
- Command bodies (part B's files change them anyway).

## 7. Review record

An independent Gemini 3.8 Flash (High) review of the first draft (pro tier unavailable)
returned 14 findings. Fixed above:
- Moving cut rules into command prompts fails in workflow mode, where workflows build
  their own prompts. Rules are now never cut (D3a), and a rules inventory proves it.
- Load-bearing rules at risk are named: qa's stash snapshot, coder's refuse-to-begin,
  the CHANGE_REVIEW disposition contract, brownfield baseline rules, qa's drift-gate
  duties.
- Gates cannot see judgement loss. A planted-defect review before and after is added.
- Architect and qa carry about 300 words of mirrored text; any agent may now get a cap.
- Signal lines are kept in their exact format (most are plain text, not JSON).
- D5's wording: frontmatter hooks are ignored; plugin-wide hooks fire.
- The guard test rejects folded descriptions and does not count table pipes;
  "Do NOT use" is required for agents only.
- The 35% word target is dropped as a success criterion.

Rejected:
- "40 words breaks multi-mode routing": the commands and workflows dispatch agents by
  name, so descriptions do not route the flow; multi-mode agents name their modes in a
  word or two.
- "A `---` in the body truncates the count": the count runs from the second
  frontmatter delimiter to the end of the file; later `---` lines are skipped, not
  terminators.

Kept as known limits: a cap can be raised in the same commit as the text that needs it
(a reviewed change, like `AC_MAX`); one planted-defect run per side is a coarse check.
