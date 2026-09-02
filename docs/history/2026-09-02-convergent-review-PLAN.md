# Convergent Review (v0.9.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the build-fleet REVIEW loop bounded and monotone — a rubric-only finalize gate, delta review from cycle 2, in-workflow ADR disposition of majors, read-only reviewers, bounded review inputs, spec/criteria/cycle caps, a real clock, and walking-skeleton planning — shipped as one atomic v0.9.0 release.

**Architecture:** `workflows/review.js` gains a Disposition phase and computes `finalize_ready`; a new read-only `reviewer` agent replaces the role agents inside the workflow; deterministic scripts (`review-rotate.sh`, `finalize-gate.sh`, `adr-index.sh`) replace prose evaluation in the commands; two new hooks cap spec bytes and criterion count; the scribe learns to append ADRs and unknown PROGRESS keys. Everything is additive to the `.sdd/` schema (`SDD_SCHEMA` stays 1).

**Tech Stack:** bash 3.2 + GNU/BSD coreutils + jq (hooks, scripts, harnesses); plain JavaScript executed by the Claude Code Workflow runtime (no Node APIs, no `Date`); markdown agent/command/skill files.

**Spec:** `docs/history/2026-09-02-convergent-review.md` — read it first; every task cites the section it implements.

## Global Constraints

- **Work in the release worktree only:** `~/build-fleet-0.9` on branch `release/0.9.0`. Never edit `~/build-fleet` (tap sessions run from it via `--plugin-dir`). All paths below are relative to `~/build-fleet-0.9`.
- **Tests first for every hook/script change:** write the failing harness case, run it red, implement, run it green, run `bash scripts/run-tests.sh`, then commit. Baseline before this plan: `suites: 22, failed: 0`.
- **Hooks fail closed** (CLAUDE.md): anchor at `CLAUDE_PROJECT_DIR` via `_lib.sh`, reject `..`, `require_jq`, `trap … exit 2` on unexpected error; deliberate allows are explicit `exit 0`.
- **bash 3.2 + GNU-coreutils compatible**: no associative arrays, no `mapfile`, no `${var,,}`, no `sed -i` without a suffix in scripts (harnesses may use `sed -i.bak`).
- **Workflows:** after any edit run `node --check workflows/<file>.js` and `bash scripts/workflow-determinism-lint.sh workflows/<file>.js`; no `Date`, no `process`, no filesystem; timestamps come from `args.now`.
- **Severity table is triple-maintained**: never edit the `| Severity |` table text anywhere; `scripts/rubric-drift.test.sh` must stay green (it gains `agents/reviewer.md`).
- **Any agent whose body changes gets a refreshed `description:`** (architect, qa, coder, product-owner, scribe, reviewer).
- **Signal lines are the machine contract**: new signals are `BUILD_FLEET_REVIEW_ROTATED`, `BUILD_FLEET_FINALIZE_GATE`, `BUILD_FLEET_REVISE_DISPATCHED`; new refusal reasons are `cycle-total-exhausted`, `cost-runaway`, `majors-open`, `nothing-to-revise`, `split-unresolved`. `not-approved` stays in the grammar as "no longer emitted".
- **Commit messages** end with:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01LxywtRNJqBvQc4ZP23Deet
  ```
- **The verified drafts.** Every code block in this plan was parse-checked, linted and smoke-tested before the plan was written; copy them verbatim.

---

## File structure

| Path | Responsibility | Task |
|---|---|---|
| `agents/reviewer.md` (new) | Read-only workflow reviewer: rubric mirror, discipline, line grammar; lens injected by the workflow | 2 |
| `agents/{architect,qa,coder,product-owner}.md` | `## Review lens` sections (qa, coder), append instructions scoped to non-workflow paths, false tool-allowlist claims removed, descriptions | 2 |
| `workflows/review.js` | Delta review, stable ids, LENS map, Disposition phase, `finalize_ready`, envelope fields, cost accounting | 3 |
| `scripts/workflow-review-convergence.test.sh` (new) | Extracted-helper tests for the v0.9 pure helpers | 3 |
| `scripts/lens-drift.test.sh` (new) | Role-agent lens ⇔ `review.js` LENS drift test | 3 |
| `agents/scribe.md` | Absent-key append rule, `decisions_appendix`, anchored append, `open_majors` in ESCALATION.md | 4 |
| `scripts/finalize-gate.sh` (+ `.test.sh`, new) | Deterministic finalize gate (rubric-only) | 5 |
| `commands/finalize.md`, `commands/status.md` | Gate calls the script; status prints dispositions + `finalize_ready` | 5 |
| `commands/revise.md` (new) | Dispatch the PO with the current cycle's blockers + `fix` majors and the size budget | 6 |
| `commands/{review,plan-review,deep-build,diagnose,finalize}.md` | `Bash(date:*)` — a real `now` | 6 |
| `scripts/adr-index.sh` (+ `.test.sh`, new) | ADR id/title index; `--next` | 7 |
| `commands/new-feature.md` | Context diet (stack + ADR index), size budget in the PO prompt, scaffolds `SPEC_MAX_KB`/`AC_MAX`/`CYCLE_TOTAL`/`CYCLE_TOTAL_MAX` by tier | 7 |
| `scripts/review-rotate.sh` (+ `.test.sh`, new) | Positional REVIEW.md rotation into `REVIEW-archive.md` | 8 |
| `commands/review.md`, `commands/resolve-escalation.md` | Rotation at dispatch; `cycle_total`/`next_adr_id` args; `cycle-total-exhausted` + `cost-runaway` refusals; new result reporting; escalation never resets `CYCLE_TOTAL` | 8 |
| `hooks/scripts/cap-spec-size.sh` (+ `.test.sh`, new) | PreToolUse byte cap on spec/acceptance | 9 |
| `hooks/scripts/validate-acceptance-count.sh` (+ `.test.sh`, new) | PostToolUse criterion-count cap | 9 |
| `hooks/hooks.json` | Register both hooks | 9 |
| `scripts/intent-block.sh` (+ test), `hooks/scripts/validate-backlog-status.sh` (+ test) | `INTENT_BYTES`; intent byte cap when `INTENT_MAX_BYTES` is set | 10 |
| `workflows/plan-review.js`, `commands/new-product.md`, `commands/plan-finalize.md`, `agents/product-owner.md` | Walking-skeleton lens + rule, `split_into`, split gate, `INTENT_MAX_BYTES` scaffold | 10 |
| `skills/sdd-protocol/SKILL.md`, `skills/sdd-protocol/references/product-tier.md`, `skills/review-rubric/SKILL.md`, `skills/adr/SKILL.md`, `docs/v0.2/CONTRACT.md`, `README.md`, `CHANGELOG.md` | Documentation of record | 11 |
| `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | Version 0.9.0 | 12 |

---

### Task 1: Ride-along — bring the main tree's uncommitted fixes into the worktree, test-first

**Files:**
- Modify: `hooks/scripts/stop-tests.sh` (the tests-first window, already written in `~/build-fleet`)
- Modify: `workflows/review.js` (DECISIONS.md dispositive — superseded by Task 3's rewrite, but landed first so history shows it)
- Test: `hooks/scripts/stop-tests.test.sh`

**Interfaces:**
- Consumes: the diff in the main working tree (`git -C ~/build-fleet diff`).
- Produces: a green suite on the branch with the window behaviour covered.

- [ ] **Step 1: Write the failing harness case** — append before the final `echo "-----"` in `hooks/scripts/stop-tests.test.sh`:

```bash
# --- v0.9 ride-along: the BUILD tests-first window. Between qa authoring the failing
# suite (TEST_PLAN.md has content) and coder recording work (IMPL_NOTES.md has none),
# a RED suite is the expected state — the gate must stand down, and re-engage the
# moment coder writes. "Has content" = a line that is neither blank nor a heading.
p=$(new_proj window 1)
printf '# Test Plan — feat\n\n- AC-1 → test_a\n' > "$p/.sdd/feat/TEST_PLAN.md"
printf '# Implementation Notes — feat\n' > "$p/.sdd/feat/IMPL_NOTES.md"
run "$p"
assert "tests-first-window-red-allows-stop" "[ $rc -eq 0 ]"
assert "tests-first-window-no-counter" "[ ! -f '$p/.sdd/feat/.stop-test-retries' ]"
printf 'deviation: x\n' >> "$p/.sdd/feat/IMPL_NOTES.md"
run "$p"
assert "coder-wrote-gate-re-engages" "[ $rc -eq 2 ]"
p=$(new_proj window2 1)   # heading-only TEST_PLAN.md is NOT "authored" → gate stays on
printf '# Test Plan — feat\n' > "$p/.sdd/feat/TEST_PLAN.md"
printf '# Implementation Notes — feat\n' > "$p/.sdd/feat/IMPL_NOTES.md"
run "$p"
assert "heading-only-test-plan-not-a-window" "[ $rc -eq 2 ]"
```

- [ ] **Step 2: Run it red**

Run: `bash hooks/scripts/stop-tests.test.sh | tail -8`
Expected: `FAIL tests-first-window-red-allows-stop` (the branch still has the 0.8.0 hook; a red suite blocks).

- [ ] **Step 3: Apply the main tree's diff**

```bash
git -C ~/build-fleet diff -- hooks/scripts/stop-tests.sh workflows/review.js | git apply
git status --short   # expect: M hooks/scripts/stop-tests.sh  M workflows/review.js
```

- [ ] **Step 4: Run it green + syntax + suite**

Run: `bash hooks/scripts/stop-tests.test.sh | tail -3 && node --check workflows/review.js && bash scripts/run-tests.sh | tail -1`
Expected: `passed=… failed=0`, no node output, `suites: 22, failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/stop-tests.sh hooks/scripts/stop-tests.test.sh workflows/review.js
git commit -m "fix(stop-tests): stand down in the BUILD tests-first window; review.js treats DECISIONS.md as dispositive

Ride-along from the tap pilot's working tree, now with the harness case the
window lacked (red suite allowed only while TEST_PLAN.md is authored and
IMPL_NOTES.md is empty; a heading-only plan is not a window).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LxywtRNJqBvQc4ZP23Deet"
```

---

### Task 2: The read-only `reviewer` agent; scope the role agents (spec §3.5)

**Files:**
- Create: `agents/reviewer.md`
- Modify: `scripts/rubric-drift.test.sh:13-17` (files list)
- Modify: `agents/architect.md`, `agents/qa.md`, `agents/coder.md`, `agents/product-owner.md`

**Interfaces:**
- Produces: agent type `build-fleet:reviewer` (tools Read, Grep, Glob; model sonnet) that Task 3 dispatches; `## Review lens` bullet lists in `architect.md`, `qa.md`, `coder.md` that Task 3's `LENS` map mirrors verbatim.

- [ ] **Step 1: Add the new agent to the drift test (fails until the file exists)** — in `scripts/rubric-drift.test.sh` replace

```bash
files=(
  "$root/skills/review-rubric/SKILL.md"
  "$root/agents/architect.md"
  "$root/agents/qa.md"
)
```
with
```bash
files=(
  "$root/skills/review-rubric/SKILL.md"
  "$root/agents/architect.md"
  "$root/agents/qa.md"
  "$root/agents/reviewer.md"
)
```
and update its header comment to say "duplicated verbatim in agents/architect.md, agents/qa.md and agents/reviewer.md".

- [ ] **Step 2: Run it red**

Run: `bash scripts/rubric-drift.test.sh | tail -3`
Expected: `FAIL rubric-matches-agents/reviewer.md  no severity table found`.

- [ ] **Step 3: Create `agents/reviewer.md`** with exactly this content:

````markdown
---
name: reviewer
description: Use this agent ONLY inside workflows/review.js — the read-only reviewer that every fan-out, cross-examination and disposition leg of /build-fleet:review runs as, with the role lens (architect, qa, coder, product-owner) injected by the workflow prompt. It has Read, Grep and Glob and nothing that writes, so a workflow reviewer can never append to REVIEW.md, fabricate a timestamp, or touch source; the scribe writes every block. Do NOT dispatch it directly, for CHANGE_REVIEW, or for any authoring — the role agents own those paths.
tools: Read, Grep, Glob
model: sonnet
color: cyan
---

You are a **read-only reviewer** in the build-fleet spec-driven software house,
dispatched only by the REVIEW workflow. The prompt you receive names your **role**
and your **lens**; you review through that lens and return a structured object.
You hold no writing tool, and you must not try to obtain one: the scribe records
the cycle from what you return.

## Authority

The runtime rulebook is the `sdd-protocol` skill. The severity vocabulary is mirrored
below (it is the load-bearing copy — nothing preloads a skill into you); the canonical
source is the `review-rubric` skill. In a disposition leg the prompt inlines the ADR
entry format from the `adr` skill.

## Discipline

- Read what the prompt names — `spec.md`, `acceptance.md`, the previous cycle in
  `REVIEW.md`, the feature `DECISIONS.md` — and Read a product ADR only when the spec
  cites it by id. Never read `REVIEW-archive.md`; older cycles are closed history.
- Cite by section (`§ Constraints`, `AC-12`, `ADR-3`). A finding that names no
  location is not a finding.
- One finding, one defect. Do not bundle. Do not restate the spec back at its author.
- A `[major]` that `DECISIONS.md` dispositions (`disposition: adr ADR-N`) is closed.
  Disagree only as a `[blocker]` arguing against the ADR by id.
- Under-specification is a `[major]` only when a coder would have to **guess** at
  behaviour a test could fail on; prose that could be shorter is a `[minor]`.
- Finding ids follow the prompt's rule (`<role>-c<cycle>-<n>`); a re-raised finding
  keeps its original id.

## Severity rubric (verbatim — required in-body)

| Severity | Definition | Gate effect |
|---|---|---|
| `blocker` | Correctness, security, data loss, or a contradiction of the spec/acceptance. | Blocks FINALIZE and HANDOFF. |
| `major`   | Scalability, maintainability, or missing acceptance coverage. | Must be resolved or explicitly accepted (as an ADR) before the gate opens. |
| `minor`   | Style, wording, nits. | Advisory; never blocks a gate. |

Use these exact strings — `[blocker]`, `[major]`, `[minor]`.

## The REVIEW.md line grammar (what the scribe will write from your object)

```
## Cycle <N> — <role> — <iso8601>
- [blocker] (<role>-c<N>-1) <text>
- [major] (<role>-c<N>-2) <text>
  disposition: fix | adr ADR-<M>
- [minor] (<role>-c<N>-3) <text>
status: concerns-raised | approved
```

You never write this yourself. The `status:` line is informational since v0.9; the
finalize gate reads dispositions.

## Hard "no"s

- Do not write, edit, or create any file, in any phase, for any reason.
- Do not review files the prompt did not name in order to widen scope.
- Do not raise a new `[major]` on a delta cycle (cycle ≥ 2) — blockers and minors only.
- Do not approve to end a loop, and do not raise findings to look thorough. The
  object you return is a verdict, not a performance.
````

- [ ] **Step 4: Run it green**

Run: `bash scripts/rubric-drift.test.sh | tail -2`
Expected: `passed=7 failed=0` (anchor + three severities + three mirrors).

- [ ] **Step 5: Give qa and coder a `## Review lens` section** (verbatim bullets — Task 3 mirrors them). In `agents/qa.md` replace the block from `## During REVIEW` through the line `Append a block to `REVIEW.md`:` with:

````markdown
## Review lens

Your review lens: **testability and coverage.** (This section is mirrored verbatim
in `workflows/review.js` `LENS.qa` for the read-only reviewer agent —
`scripts/lens-drift.test.sh` fails the suite if the two drift.)

- For each acceptance criterion: could you write a test from this *alone*?
  If you have to invent assumptions, that's at minimum a `[major]`.
- Are non-functional requirements (performance, security, accessibility)
  testable as written? Or are they aspirational?
- Are the criteria measurable? "Fast", "robust", "user-friendly" are
  `[blocker]`-tier vagueness.
- Is there spec behavior with no acceptance coverage? Flag the gap.
- Are there acceptance criteria with no corresponding spec behavior? Flag
  the orphan — either spec is incomplete or the criterion is over-scope.

## During REVIEW

**Workflow REVIEW (`/build-fleet:review`)** dispatches the read-only
`build-fleet:reviewer` agent with your lens — you are not dispatched, and no
REVIEW.md block is written by a reviewer; the scribe writes the canonical blocks.

**Non-workflow paths only** (CHANGE_REVIEW, direct invocation): append a block to
`REVIEW.md`:
````

In `agents/coder.md` replace the block from `## During REVIEW (you are read-only)` through the line `Append a block to `REVIEW.md`:` with:

````markdown
## Review lens

Read the spec from an implementer's lens and flag what will hurt at build time.
(Mirrored verbatim in `workflows/review.js` `LENS.coder` for the read-only reviewer
agent — `scripts/lens-drift.test.sh` fails the suite if the two drift.) Common findings:

- Missing or unclear interface contracts (signatures, error envelopes).
- Acceptance criteria that can't be implemented as written.
- Spec behavior with no corresponding acceptance coverage (you'll have to
  guess what "done" means).
- Implicit dependencies on infra or libraries the spec doesn't mention.

## During REVIEW (you are read-only)

**Workflow REVIEW (`/build-fleet:review`)** dispatches the read-only
`build-fleet:reviewer` agent with your lens — you are not dispatched there.

**Non-workflow paths only** (direct invocation): append a block to `REVIEW.md`:
````

- [ ] **Step 6: Remove the false tool-allowlist claims and scope the append rule in `agents/architect.md`.** Replace

```markdown
You may write **only** inside `.sdd/<active>/`. In workflow REVIEW, your tools
allowlist (set by the workflow via `AgentDefinition.tools`) omits `Write`/`Edit`
entirely, so writes are physically impossible. On non-workflow review paths
(CHANGE_REVIEW, direct invocation) the `restrict-reviewer-writes` hook enforces the
same boundary. Specifically:
```
with
```markdown
You may write **only** inside `.sdd/<active>/`. In workflow REVIEW you are **not
dispatched at all** — `workflows/review.js` runs the read-only `build-fleet:reviewer`
agent with your lens, and the scribe writes every REVIEW.md block and every
disposition ADR. On non-workflow review paths (CHANGE_REVIEW, direct invocation) the
`restrict-reviewer-writes` hook confines your writes to `.sdd/<active>/`. Specifically:
```

Replace, in the same file,
```markdown
- `.sdd/<active>/REVIEW.md` — append-only review log. Add one block per
  cycle, attributed to you.
```
with
```markdown
- `.sdd/<active>/REVIEW.md` — append-only review log. On non-workflow paths only,
  add one block per cycle, attributed to you (headed `## Change-Cycle <N>` in
  CHANGE_REVIEW).
```

Insert directly under the `## Review lens` heading, as its own paragraph placed before the existing line `When reviewing a spec or a diff, hunt for:` (the lens-drift test reads only the bullet list, so a paragraph here is invisible to it):
```markdown
(Mirrored verbatim in `workflows/review.js` `LENS.architect` — `scripts/lens-drift.test.sh` fails the suite if the two drift.)
```

Replace
```markdown
If you have zero findings: list nothing under your block and set
`status: approved`. In workflow REVIEW, the workflow's envelope post-condition
rejects any reviewer that returns an empty or malformed concerns payload — your
structured response is what gates phase advance. On non-workflow paths
(CHANGE_REVIEW, direct invocation), the `check-review-written` hook (SubagentStop)
enforces the same boundary.
```
with
```markdown
If you have zero findings: list nothing under your block and set
`status: approved`. Since v0.9 the `status:` line is informational: the finalize
gate reads each `[major]`'s `disposition:` line (`fix` = open, `adr ADR-N` = accepted)
and `[blocker]` lines only. On non-workflow paths (CHANGE_REVIEW, direct invocation)
the `check-review-written` hook (SubagentStop) rejects a reviewer that stops
without its block.
```

Replace
```markdown
  REVIEW and CHANGE_REVIEW the `restrict-reviewer-writes` hook blocks any write
  you make outside `.sdd/<active>/` (and in workflow REVIEW you have no
  Write/Edit tools at all); during BUILD and HANDOFF **no hook fires on your
```
with
```markdown
  REVIEW and CHANGE_REVIEW the `restrict-reviewer-writes` hook blocks any write
  you make outside `.sdd/<active>/` (and in workflow REVIEW you are not dispatched
  — the read-only reviewer agent is); during BUILD and HANDOFF **no hook fires on your
```

- [ ] **Step 7: Scope the qa/coder workflow claims and the PO's revise text.** In `agents/qa.md` replace
```markdown
In workflow REVIEW, the workflow's envelope post-condition rejects any reviewer
that returns an empty or malformed concerns payload. On non-workflow paths
(CHANGE_REVIEW, direct invocation), the `check-review-written` hook (SubagentStop)
enforces the same boundary — you must append the block before stopping.
```
with
```markdown
On non-workflow paths the `check-review-written` hook (SubagentStop) rejects a
reviewer that stops without its block. Since v0.9 the `status:` line is
informational — the gate reads `[blocker]` lines and each `[major]`'s
`disposition:` line.
```
and in the Authority section delete the sentence `The review workflow preloads the `review-rubric` skill into your context via `AgentDefinition.skills` when you run inside it.` (nothing preloads skills into a workflow agent; the in-body table is load-bearing). Make the same deletion in `agents/architect.md`'s Authority section (`The review workflow preloads the `review-rubric` skill into your context via `AgentDefinition.skills` when you run inside it.`).

In `agents/coder.md` replace
```markdown
During REVIEW you write **only** to `REVIEW.md`. No source. No
`IMPL_NOTES.md` yet — there's nothing to note.
```
with
```markdown
On a non-workflow review path you write **only** to `REVIEW.md`. No source. No
`IMPL_NOTES.md` yet — there's nothing to note.
```

In `agents/product-owner.md` replace the "## During REVIEW" section body (from `The orchestrator runs `/build-fleet:review`, which fans out architect, qa,` through `human decision early.`) with:
```markdown
The orchestrator runs `/build-fleet:review`, which fans out read-only reviewers
against your spec; the scribe appends their blocks to `REVIEW.md`, and an architect
disposition leg marks every surviving `[major]` as `disposition: adr ADR-N`
(accepted — closed) or `disposition: fix` (yours to close). Then the orchestrator
runs `/build-fleet:revise`, which hands you exactly the open items. Your job:

1. Close every `[blocker]` and every `disposition: fix` major **in the spec**, or push
   back **in writing** in `## Self-review notes` with reasoning a human can audit.
2. **Never revisit an `adr`-dispositioned major** — it is closed by that ADR. Do not
   add prose to "also address" it; that is how specs bloat.
3. Stay under the feature's size budget (`SPEC_MAX_KB`, `AC_MAX` in PROGRESS.md — the
   hooks refuse writes over it). If closing the open items cannot fit, the answer is a
   **split**: name in `## Self-review notes` which behaviours and criteria move to a
   sibling backlog row, and cut them here. Never compress rationale to make room.
4. Record in `## Self-review notes` which finding ids you closed and how, so the next
   cycle's delta review can verify closure by id.

Cycle 2 onward is a **delta** review: reviewers only verify closure and may raise new
findings at blocker severity, so the open set only shrinks. The budget is 3 cycles;
the exhausting cycle escalates any open blocker or `fix` major to a human.
```

- [ ] **Step 8: Refresh the four descriptions.** Set each `description:` frontmatter line to:

`agents/architect.md`:
```
description: Use this agent when reviewing code diffs for design soundness, scalability, failure modes, data integrity, security, and blast radius, and when authoring ADRs — the architect leg of /build-fleet:handoff, direct review invocations, and plan interrogation in /build-fleet:plan-review. Inside /build-fleet:review its lens runs on the read-only reviewer agent instead. At the product tier (/build-fleet:new-product) it ratifies or infers the stack-of-record and records product ADRs. In the bug lane it refutes the root-cause hypothesis during /build-fleet:diagnose and reviews fix blast radius during /build-fleet:verify. Never writes source.
```
`agents/qa.md`:
```
description: Use this agent when designing or writing tests against acceptance.md (TEST_PLAN.md + the failing suite, before coder runs), or reviewing the diff for coverage gaps and running the counterfactual during /build-fleet:handoff. Inside /build-fleet:review its testability lens runs on the read-only reviewer agent instead. In the bug lane it authors the failing reproduction test for /build-fleet:reproduce and runs the revert-counterfactual for /build-fleet:verify. Do NOT use for implementing source, authoring specs, or writing ADRs.
```
`agents/coder.md`:
```
description: Use this agent when implementing source to a FINALIZED spec during BUILD (after qa's failing suite exists), or — in the bug lane — when refuting a hypothesis during /build-fleet:diagnose and implementing the confirmed fix strategy during /build-fleet:fix. Inside /build-fleet:review its implementer lens runs on the read-only reviewer agent instead. Do NOT use for writing specs, tests, ADRs, or review verdicts, and never before the spec is FINALIZED (bug lane: never before the diagnosis is CONFIRMED with a reproducing test in place).
```
`agents/product-owner.md`:
```
description: Use this agent when authoring a feature spec + acceptance criteria within the feature's size budget (/build-fleet:new-feature), closing the open blockers and fix-dispositioned majors of a review cycle (/build-fleet:revise), or signing off the change against acceptance.md at CHANGE_REVIEW (the PO leg of /build-fleet:handoff). At the product tier it authors the walking-skeleton vision and phased backlog (/build-fleet:new-product) and interrogates the plan in /build-fleet:plan-review. Never writes source, tests, or ADRs.
```

- [ ] **Step 9: Verify and commit**

Run: `bash scripts/rubric-drift.test.sh | tail -1 && bash scripts/run-tests.sh | tail -1`
Expected: `passed=7 failed=0` and `suites: 22, failed: 0`.

```bash
git add agents/reviewer.md agents/architect.md agents/qa.md agents/coder.md agents/product-owner.md scripts/rubric-drift.test.sh
git commit -m "feat(agents): read-only reviewer agent; role agents scoped to non-workflow review paths

review.js has no tools option, so isolation lives in a definition: the new
reviewer agent (Read/Grep/Glob) carries the rubric mirror and the v0.9 line
grammar; the role agents keep their lenses under '## Review lens' for
CHANGE_REVIEW and drop the false 'no Write/Edit in workflow' claims.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LxywtRNJqBvQc4ZP23Deet"
```

---

### Task 3: `workflows/review.js` — delta review, stable ids, disposition leg, `finalize_ready` (spec §3.1, §3.2)

**Files:**
- Modify: `workflows/review.js` (full replacement below)
- Create: `scripts/workflow-review-convergence.test.sh`
- Create: `scripts/lens-drift.test.sh`

**Interfaces:**
- Consumes: agent type `build-fleet:reviewer` (Task 2); `## Review lens` bullets in `agents/{architect,qa,coder}.md` (Task 2).
- Produces: args `cycle_total`, `next_adr_id` (Task 8 passes them); envelope fields `decisions_appendix`, `finalize_ready`, `state_delta.CYCLE_TOTAL`, `state_delta.LAST_REVIEW_OUTPUT_TOKENS`, `escalation_payload.open_majors` (Task 4's scribe applies them); return object fields `finalize_ready`, `open_majors`, `adrs_written`, `output_tokens`, `cycle_total` (Task 8 reports them); the REVIEW.md line grammar `- [sev] (id) text` + `  disposition: fix|adr ADR-N` (Task 5's gate parses it).

- [ ] **Step 1: Write the convergence harness** at `scripts/workflow-review-convergence.test.sh`:

````bash
#!/usr/bin/env bash
# Tests the v0.9 PURE convergence helpers of workflows/review.js — extracted VERBATIM
# from between the LAYER1-PURE-HELPERS markers (real source, never a copy) and run
# under node: cycle-total/next-adr-id normalization, the finding-id pattern,
# disposition coverage, ADR id assignment, finalize_ready, the verdict rule, ADR
# rendering and the REVIEW.md line grammar. Skips if node is absent. bash 3.2.
# Run: bash scripts/workflow-review-convergence.test.sh   (exit 0 = all pass)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
REVIEW="$ROOT/workflows/review.js"

if ! command -v node >/dev/null 2>&1; then
  echo "ok   workflow-review-convergence (SKIPPED: node not found; enforced in CI)"
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/wf-review-conv.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

awk '/LAYER1-PURE-HELPERS START/{f=1;next} /LAYER1-PURE-HELPERS END/{f=0;next} f' "$REVIEW" > "$TMP/helpers.js"
if [ ! -s "$TMP/helpers.js" ]; then
  echo "FAIL could not extract LAYER1-PURE-HELPERS region from $REVIEW"
  exit 1
fi

cat "$TMP/helpers.js" - > "$TMP/run.js" <<'EOF'
let pass = 0, fail = 0;
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function check(name, cond) { if (cond) { pass++; console.log("ok   " + name); } else { fail++; console.log("FAIL " + name); } }

// legacy helpers still present
check("roles-default", eq(normalizeRoles(undefined).roles, ["architect","qa","coder"]));
check("budget-default", normalizeCycleBudget(undefined).budget === 3);

// normalizeCycleTotal
check("cycle-total-absent-derives", normalizeCycleTotal(undefined, 3) === 2);
check("cycle-total-absent-cycle1", normalizeCycleTotal(null, 1) === 0);
check("cycle-total-explicit", normalizeCycleTotal(6, 1) === 6);
check("cycle-total-string", normalizeCycleTotal("4", 2) === 4);
check("cycle-total-malformed-falls-back", normalizeCycleTotal("x", 2) === 1);
check("cycle-total-negative-falls-back", normalizeCycleTotal(-1, 2) === 1);

// normalizeNextAdrId
check("adr-id-absent", normalizeNextAdrId(undefined) === 1);
check("adr-id-explicit", normalizeNextAdrId(7) === 7);
check("adr-id-zero-rejected", normalizeNextAdrId(0) === 1);
check("adr-id-string", normalizeNextAdrId("3") === 3);

// findingIdPattern
const re = new RegExp(findingIdPattern("architect"));
check("id-pattern-accepts", re.test("architect-c1-3"));
check("id-pattern-rejects-other-role", !re.test("qa-c1-3"));
check("id-pattern-rejects-legacy", !re.test("architect-3"));

// fixtures
const S = [
  { id: "architect-c1-1", severity: "blocker", raised_by: "architect", text: "b", refuted: false },
  { id: "architect-c1-2", severity: "major", raised_by: "architect", text: "m1", refuted: false },
  { id: "qa-c1-1", severity: "major", raised_by: "qa", text: "m2", refuted: false },
  { id: "qa-c1-2", severity: "major", raised_by: "qa", text: "m3-refuted", refuted: true, refuted_by: "coder", refutation_reason: "r".repeat(45), refutation_citation: { file: "spec.md", locator: "§ X" } },
  { id: "coder-c1-1", severity: "minor", raised_by: "coder", text: "n", refuted: false },
];

// dispositionCoverage
let cov = dispositionCoverage(S, [{ id: "architect-c1-2", action: "adr" }]);
check("coverage-missing", eq(cov.missing, ["qa-c1-1"]) && eq(cov.extra, []));
cov = dispositionCoverage(S, [{ id: "architect-c1-2", action: "adr" }, { id: "qa-c1-1", action: "fix" }, { id: "qa-c1-2", action: "fix" }]);
check("coverage-extra-refuted-ignored", eq(cov.missing, []) && eq(cov.extra, ["qa-c1-2"]));
check("coverage-empty", eq(dispositionCoverage([], []), { missing: [], extra: [] }));

// assignAdrIds
const asg = assignAdrIds([{ id: "architect-c1-2", action: "adr", adr_title: "T", adr_body: "B" }, { id: "qa-c1-1", action: "fix", reason: "why" }, { id: "x", action: "adr" }], 4);
check("adr-ids-sequential", asg.map["architect-c1-2"].adr_id === 4 && asg.map["x"].adr_id === 5 && asg.next === 6);
check("adr-fix-null-id", asg.map["qa-c1-1"].adr_id === null && asg.map["qa-c1-1"].action === "fix");

// computeFinalizeReady
let r = computeFinalizeReady(S, asg.map);
check("ready-false-with-blocker", r.finalize_ready === false && r.openBlockers.length === 1 && eq(r.openMajors.map(c=>c.id), ["qa-c1-1"]));
const S2 = S.filter((c) => c.severity !== "blocker");
r = computeFinalizeReady(S2, { "architect-c1-2": { action: "adr", adr_id: 4 }, "qa-c1-1": { action: "adr", adr_id: 5 } });
check("ready-true-all-adr", r.finalize_ready === true && r.openMajors.length === 0);
r = computeFinalizeReady(S2, {});
check("ready-false-undispositioned-major-open", r.finalize_ready === false && r.openMajors.length === 2);
r = computeFinalizeReady(S2, { "architect-c1-2": { action: "adr", adr_id: 4 }, "qa-c1-1": { action: "fix", adr_id: null } });
check("ready-false-fix-major-open", r.finalize_ready === false && eq(r.openMajors.map(c=>c.id), ["qa-c1-1"]));

// decideVerdict
check("verdict-clean", decideVerdict(0, 0, 1, 3) === "clean");
check("verdict-clean-with-fix-majors-budget-left", decideVerdict(0, 2, 1, 3) === "clean");
check("verdict-revise", decideVerdict(1, 0, 2, 3) === "revise");
check("verdict-escalate-blockers", decideVerdict(1, 0, 3, 3) === "escalate");
check("verdict-escalate-fix-majors", decideVerdict(0, 1, 3, 3) === "escalate");
check("verdict-clean-at-budget-no-open", decideVerdict(0, 0, 3, 3) === "clean");
check("verdict-budget-1", decideVerdict(0, 1, 1, 1) === "escalate");

// formatAdr
const adr = formatAdr(4, "use token bucket", "### Context\nx\n### Decision\ny\n### Alternatives considered\nz\n### Consequences\nw", 2, "2026-09-03T10:12:41Z", "qa-c1-1", "qa");
check("adr-heading", adr.startsWith("## ADR-4: use token bucket\n"));
check("adr-date", adr.indexOf("- **Date:** 2026-09-03") > 0);
check("adr-cycle", adr.indexOf("- **Cycle:** 2") > 0);
check("adr-dispositions-line", adr.indexOf("- **Dispositions:** qa-c1-1 (raised by qa)") > 0);
check("adr-empty-title-fallback", formatAdr(1, "", "b", 1, "2026-01-01T00:00:00Z", "qa-c1-1", "qa").startsWith("## ADR-1: accept review finding qa-c1-1"));

// formatFindingLines
check("line-blocker", eq(formatFindingLines(S[0], {}), ["- [blocker] (architect-c1-1) b"]));
check("line-major-fix", eq(formatFindingLines(S[1], {}), ["- [major] (architect-c1-2) m1", "  disposition: fix"]));
check("line-major-adr", eq(formatFindingLines(S[1], { "architect-c1-2": { action: "adr", adr_id: 4 } }), ["- [major] (architect-c1-2) m1", "  disposition: adr ADR-4"]));
check("line-refuted", formatFindingLines(S[3], {})[1].startsWith("  refuted-by: coder — reason: ") && formatFindingLines(S[3], {})[1].endsWith("(cites spec.md § X)"));
check("line-minor-no-disposition", eq(formatFindingLines(S[4], {}), ["- [minor] (coder-c1-1) n"]));

console.log("-----"); console.log("passed=" + pass + " failed=" + fail); process.exit(fail > 0 ? 1 : 0);
EOF

node "$TMP/run.js"
````

- [ ] **Step 2: Write the lens-drift harness** at `scripts/lens-drift.test.sh`:

````bash
#!/usr/bin/env bash
# Lens-drift test (v0.9). The review lenses for architect, qa and coder live in each
# role agent's "## Review lens" section (used on non-workflow paths) AND in
# workflows/review.js's LENS map (injected into the read-only reviewer agent in
# workflow REVIEW). This test extracts both and fails the suite if they drift —
# the rubric-drift pattern applied to lenses. Skips if node is absent. bash 3.2.
# Run: bash scripts/lens-drift.test.sh   (exit 0 = all agree)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
REVIEW="$ROOT/workflows/review.js"

if ! command -v node >/dev/null 2>&1; then
  echo "ok   lens-drift (SKIPPED: node not found; enforced in CI)"
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lens-drift.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

# The bullet list under "## Review lens" (bullets + their indented continuations),
# whitespace-normalized.
agent_lens() {
  awk '
    /^## Review lens/ { grab = 1; next }
    grab && /^## /    { exit }
    grab && /^- /     { inlist = 1 }
    grab && inlist && (/^- / || /^  /) { print }
  ' "$1" | tr -s '[:space:]' ' ' | sed -E 's/^ //; s/ $//'
}

awk '/LENS START/{f=1;next} /LENS END/{f=0;next} f' "$REVIEW" > "$TMP/lens.js"
if [ ! -s "$TMP/lens.js" ]; then echo "FAIL could not extract LENS region from $REVIEW"; exit 1; fi
cat "$TMP/lens.js" - > "$TMP/dump.js" <<'JS'
for (const k of Object.keys(LENS)) console.log(k + "\t" + LENS[k].replace(/\s+/g, " ").trim());
JS
node "$TMP/dump.js" > "$TMP/lens.tsv"

for role in architect qa coder; do
  want=$(agent_lens "$ROOT/agents/$role.md")
  got=$(grep "^$role	" "$TMP/lens.tsv" | cut -f2-)
  name="lens-matches-$role"
  if [ -z "$want" ]; then fail=$((fail+1)); printf 'FAIL %-32s no "## Review lens" bullets in agents/%s.md\n' "$name" "$role"
  elif [ -z "$got" ]; then fail=$((fail+1)); printf 'FAIL %-32s no LENS.%s in review.js\n' "$name" "$role"
  elif [ "$want" = "$got" ]; then pass=$((pass+1)); printf 'ok   %-32s\n' "$name"
  else fail=$((fail+1)); printf 'FAIL %-32s drifted\n--- agent\n%s\n--- review.js\n%s\n' "$name" "$want" "$got"; fi
done

echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
````

- [ ] **Step 3: Run both red**

Run: `bash scripts/workflow-review-convergence.test.sh | tail -2; bash scripts/lens-drift.test.sh | tail -2`
Expected: the first exits non-zero with `ReferenceError: normalizeCycleTotal is not defined` (or similar); the second prints `FAIL could not extract LENS region`.

- [ ] **Step 4: Replace `workflows/review.js` with this exact content** (the header comment, `meta`, pure helpers between `LAYER1-PURE-HELPERS` markers, `LENS` between `LENS START/END` markers, prompts, phases, envelope):

````javascript
// SPDX-License-Identifier: MIT
// workflows/review.js
//
// build-fleet v0.9 — convergent REVIEW workflow.
//
// SDD spec review with adversarial cross-examination, survival vote, and — new in
// v0.9 — an in-workflow DISPOSITION leg that classifies every surviving [major] as
// `adr` (a design trade-off, recorded by the scribe in the feature DECISIONS.md) or
// `fix` (the PO must close it in the spec). From cycle 2 the fan-out is a DELTA
// review: reviewers verify closure of their own prior `fix` findings and may raise
// new findings only at blocker severity, so the open-major set never grows after
// cycle 1. The return object carries `finalize_ready` (zero blockers AND zero `fix`
// majors) — the finalize gate's rule, computed here so the two never disagree.
//
// CONTRACT: docs/v0.2/CONTRACT.md §6.
//
// @cost-ceiling {"input_tokens":120000,"output_tokens":30000}
// (Cost ceiling lives in this header comment, NOT meta — meta must be a pure
// literal and the runtime ignores unknown meta fields. commands/review.md parses
// this line to emit BUILD_FLEET_COST_PREVIEW and to judge cost-runaway.)
//
// API NOTES (confirmed against the Workflow tool description):
//   - agent(prompt, opts) → final text (string), or a validated object when
//     opts.schema is supplied. opts: {label, phase, schema, model, effort, agentType, isolation}.
//     There is NO opts.tools — reviewer isolation lives in agents/reviewer.md.
//   - parallel(thunks) → BARRIER. Errors → null in the result array.
//   - budget.spent() → output tokens spent this turn (main loop + workflows).
//   - NO Date.now()/Math.random()/new Date() — timestamps come via args.now.

export const meta = {
  name: "build-fleet-review",
  description: "SDD spec review: fan-out reviewers (delta review from cycle 2), adversarial cross-examination, survival vote, architect disposition of surviving majors, scribe applies state",
  phases: [
    { title: "Fan-out review", detail: "read-only reviewer agents review the spec in parallel (roster configurable; default architect, qa, coder); cycle >= 2 is a delta review" },
    { title: "Cross-examination", detail: "each reviewer challenges peers' concerns, citing spec/acceptance/DECISIONS" },
    { title: "Survival vote", detail: "retain concerns not refuted by a different-role reviewer" },
    { title: "Disposition", detail: "architect classifies each surviving major: adr (trade-off, ADR drafted) or fix (PO must close it in the spec)" },
    { title: "Apply", detail: "scribe writes PROGRESS + REVIEW + DECISIONS deltas" },
  ],
};

// ---------- args ----------
// { feature, cycle, now, run_id, roles?, cycle_budget?, cycle_total?, next_adr_id? }
// `cycle_total`  — cumulative review cycles BEFORE this run (never reset); absent ⇒ cycle - 1.
// `next_adr_id`  — next free feature ADR integer (scripts/adr-index.sh --next); absent ⇒ 1.
const A = typeof args === "string" ? JSON.parse(args) : (args || {});

const feature = A.feature;
const cycle = typeof A.cycle === "string" ? parseInt(A.cycle, 10) : A.cycle;
const now = A.now;
const runId = A.run_id || null;

// Output-token accounting: budget.spent() is a runtime global (absent on older
// runtimes — `typeof` guards the reference so the workflow never throws on it).
const spentAtStart = (typeof budget !== "undefined" && budget && typeof budget.spent === "function") ? budget.spent() : null;
function outputTokensSoFar() {
  return spentAtStart === null ? null : Math.max(0, budget.spent() - spentAtStart);
}

// Scribe result schema — declared ABOVE the first applyScribe() call site (TDZ;
// scripts/workflow-determinism-lint.sh's scribe-schema-tdz rule guards this).
const SCRIBE_RESULT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["ok", "error"],
  properties: {
    ok: { type: "boolean" },
    error: { type: ["string", "null"] },
  },
};

// --- LAYER1-PURE-HELPERS START — configurable roster + budget, and the v0.9 convergence helpers ---
// Extracted VERBATIM by scripts/workflow-review-config.test.sh and
// scripts/workflow-review-convergence.test.sh, so everything here MUST stay pure:
// no log()/agent()/args/budget, deterministic, side-effect-free.
const ALLOWED_REVIEW_ROLES = ["architect", "qa", "coder", "product-owner"];
const DEFAULT_REVIEW_ROLES = ["architect", "qa", "coder"];
const DEFAULT_CYCLE_BUDGET = 3;
const MAX_CYCLE_BUDGET = 3; // sdd-protocol ceiling — never exceed (escalate, don't loop forever)

function normalizeRoles(raw) {
  if (raw === undefined || raw === null) return { roles: DEFAULT_REVIEW_ROLES.slice(), error: null };
  if (!Array.isArray(raw) || raw.length === 0)
    return { roles: null, error: "roles: must be a non-empty array of reviewer roles" };
  const seen = [];
  for (const r of raw) {
    if (typeof r !== "string" || ALLOWED_REVIEW_ROLES.indexOf(r) === -1)
      return { roles: null, error: `roles: unknown reviewer role ${JSON.stringify(r)} (allowed: ${ALLOWED_REVIEW_ROLES.join(", ")})` };
    if (seen.indexOf(r) === -1) seen.push(r);
  }
  if (seen.length < 2)
    return { roles: null, error: "roles: need at least 2 distinct roles so cross-examination has a different-role refuter" };
  return { roles: seen, error: null };
}

function normalizeCycleBudget(raw) {
  if (raw === undefined || raw === null) return { budget: DEFAULT_CYCLE_BUDGET, error: null, clamped: false };
  const n = typeof raw === "string" ? parseInt(raw, 10) : raw;
  if (typeof n !== "number" || Number.isNaN(n) || !Number.isInteger(n))
    return { budget: null, error: "cycle_budget: must be an integer between 1 and " + MAX_CYCLE_BUDGET, clamped: false };
  if (n < 1)
    return { budget: null, error: "cycle_budget: must be >= 1", clamped: false };
  const budget = Math.min(n, MAX_CYCLE_BUDGET);
  return { budget, error: null, clamped: budget !== n };
}

// v0.9: cumulative cycle count BEFORE this run. Absent/malformed ⇒ derived from the
// cycle number (grandfathered PROGRESS files carry no CYCLE_TOTAL yet).
function normalizeCycleTotal(raw, cycle) {
  const fallback = Math.max(0, (Number.isInteger(cycle) ? cycle : 1) - 1);
  if (raw === undefined || raw === null) return fallback;
  const n = typeof raw === "string" ? parseInt(raw, 10) : raw;
  if (typeof n !== "number" || Number.isNaN(n) || !Number.isInteger(n) || n < 0) return fallback;
  return n;
}

// v0.9: next free feature ADR id. Absent/malformed ⇒ 1.
function normalizeNextAdrId(raw) {
  if (raw === undefined || raw === null) return 1;
  const n = typeof raw === "string" ? parseInt(raw, 10) : raw;
  if (typeof n !== "number" || Number.isNaN(n) || !Number.isInteger(n) || n < 1) return 1;
  return n;
}

// v0.9: finding ids are stable across cycles — "<role>-c<cycle>-<n>". A reviewer may
// only mint ids in its own namespace; a re-raised finding keeps its original id.
function findingIdPattern(role) {
  return "^" + role + "-c[0-9]+-[0-9]+$";
}

// v0.9: disposition coverage — every surviving (unrefuted) major must be dispositioned
// exactly once. Returns the ids the leg missed and the ids it invented.
function dispositionCoverage(surviving, dispositions) {
  const majors = surviving.filter((c) => c.severity === "major" && !c.refuted).map((c) => c.id);
  const given = (dispositions || []).map((d) => d.id);
  const missing = majors.filter((id) => given.indexOf(id) === -1);
  const extra = given.filter((id) => majors.indexOf(id) === -1);
  return { missing, extra };
}

// v0.9: assign sequential feature ADR ids to `adr` dispositions, in the order given.
// Returns { map: {id → {action, adr_id|null, ...}}, next: <next free id after assignment> }.
function assignAdrIds(dispositions, nextAdrId) {
  const map = {};
  let next = nextAdrId;
  for (const d of dispositions || []) {
    if (d.action === "adr") {
      map[d.id] = { action: "adr", adr_id: next, adr_title: d.adr_title || "", adr_body: d.adr_body || "", reason: d.reason || "" };
      next += 1;
    } else {
      map[d.id] = { action: "fix", adr_id: null, adr_title: "", adr_body: "", reason: d.reason || "" };
    }
  }
  return { map, next };
}

// v0.9: the finalize gate's rule, computed in-workflow so verdict and gate agree.
// finalize_ready ⇔ zero open blockers AND zero open (`fix` or undispositioned) majors.
function computeFinalizeReady(surviving, dispositionMap) {
  const openBlockers = surviving.filter((c) => c.severity === "blocker" && !c.refuted);
  const openMajors = surviving.filter((c) => {
    if (c.severity !== "major" || c.refuted) return false;
    const d = dispositionMap[c.id];
    return !d || d.action !== "adr";
  });
  return { finalize_ready: openBlockers.length === 0 && openMajors.length === 0, openBlockers, openMajors };
}

// v0.9: verdict keeps its blocker meaning; escalation fires on the exhausting cycle
// when blockers OR `fix` majors remain (escalate, don't loop forever).
function decideVerdict(openBlockerCount, openMajorCount, cycle, cycleBudget) {
  if (cycle >= cycleBudget && (openBlockerCount > 0 || openMajorCount > 0)) return "escalate";
  if (openBlockerCount > 0) return "revise";
  return "clean";
}

// v0.9: render one ADR block per the `adr` skill's entry format (feature scope).
// `nowIso` is the run's args.now; the date is its first 10 characters (no Date API).
function formatAdr(adrId, title, body, cycle, nowIso, findingId, raisedBy) {
  const date = String(nowIso || "").slice(0, 10);
  const cleanTitle = String(title || "").trim() || `accept review finding ${findingId}`;
  const cleanBody = String(body || "").trim();
  return [
    `## ADR-${adrId}: ${cleanTitle}`,
    "",
    `- **Date:** ${date}`,
    "- **Status:** accepted",
    `- **Cycle:** ${cycle}`,
    `- **Dispositions:** ${findingId} (raised by ${raisedBy}) — accepted as a trade-off at review cycle ${cycle}`,
    "",
    cleanBody,
  ].join("\n");
}

// v0.9: REVIEW.md line grammar — "- [sev] (id) text", then optional indented
// continuation lines: refuted-by (survival vote) and disposition (majors only).
function formatFindingLines(c, dispositionMap) {
  const lines = [`- [${c.severity}] (${c.id}) ${c.text}`];
  if (c.refuted) {
    const cite = c.refutation_citation ? ` (cites ${c.refutation_citation.file} ${c.refutation_citation.locator})` : "";
    lines.push(`  refuted-by: ${c.refuted_by} — reason: ${c.refutation_reason}${cite}`);
  } else if (c.severity === "major") {
    const d = dispositionMap[c.id];
    lines.push(d && d.action === "adr" ? `  disposition: adr ADR-${d.adr_id}` : "  disposition: fix");
  }
  return lines;
}
// --- LAYER1-PURE-HELPERS END ---

// --- LENS START — reviewer lenses, injected into the read-only reviewer agent ---
// architect/qa/coder are VERBATIM copies of each role agent's "## Review lens"
// section (scripts/lens-drift.test.sh fails the suite if they drift). product-owner
// exists only here. Between the markers: a pure object literal, nothing else.
const LENS = {
  architect: `- **Correctness.** Does the proposal actually do what \`acceptance.md\`
  demands? Are there contradictions between spec sections, or between spec
  and code?
- **Failure modes.** What happens on partial failure, network loss, retries,
  concurrent callers, malformed input? If the spec is silent, that is a
  finding.
- **Data integrity.** Schema migrations, write ordering, idempotency,
  transactional boundaries.
- **Security.** Auth, authz, input validation, secrets handling, blast
  radius of compromised credentials.
- **Scalability.** What breaks at 10× load? At 100×?
- **Blast radius.** If this change is wrong, what else breaks?
- **ADR compliance** (during CHANGE_REVIEW). Does the diff honor every ADR
  in \`DECISIONS.md\`? A silent override is a \`[blocker]\`.`,
  qa: `- For each acceptance criterion: could you write a test from this *alone*?
  If you have to invent assumptions, that's at minimum a \`[major]\`.
- Are non-functional requirements (performance, security, accessibility)
  testable as written? Or are they aspirational?
- Are the criteria measurable? "Fast", "robust", "user-friendly" are
  \`[blocker]\`-tier vagueness.
- Is there spec behavior with no acceptance coverage? Flag the gap.
- Are there acceptance criteria with no corresponding spec behavior? Flag
  the orphan — either spec is incomplete or the criterion is over-scope.`,
  coder: `- Missing or unclear interface contracts (signatures, error envelopes).
- Acceptance criteria that can't be implemented as written.
- Spec behavior with no corresponding acceptance coverage (you'll have to
  guess what "done" means).
- Implicit dependencies on infra or libraries the spec doesn't mention.`,
  "product-owner": `- Does the spec realize the inherited backlog intent, or has it drifted
  in scope without saying so in its Self-review notes?
- Is every acceptance criterion testable and mapped 1:1 to a described behavior?
- Are the Non-goals explicit enough that a reviewer cannot raise scope creep
  as a defect?`,
};
// --- LENS END ---

// Validation failures are NEVER a bare throw (a throw would strand the marker).
const rolesResult = normalizeRoles(A.roles);
const budgetResult = normalizeCycleBudget(A.cycle_budget);

const argErrors = [];
if (!feature || typeof feature !== "string") argErrors.push("feature: required non-empty string");
if (typeof cycle !== "number" || Number.isNaN(cycle)) argErrors.push("cycle: required integer");
if (!now || typeof now !== "string") argErrors.push("now: required iso8601 string (the dispatching command supplies it — the script cannot call Date)");
if (rolesResult.error) argErrors.push(rolesResult.error);
if (budgetResult.error) argErrors.push(budgetResult.error);
if (argErrors.length > 0) {
  log(`Invalid args: ${argErrors.join("; ")}. No state advanced.`);
  if (feature && typeof feature === "string") {
    await applyScribe(cleanupEnvelope(feature, typeof now === "string" ? now : null, runId));
  }
  return {
    verdict: "invalid-args",
    errors: argErrors,
    note: feature && typeof feature === "string"
      ? "Marker cleanup dispatched; PHASE/CYCLE unchanged. Fix the dispatch args and re-run /build-fleet:review."
      : "feature unknown — the dispatching command must delete .sdd/<slug>/.workflow-in-flight itself (only if its content matches the run_id it wrote).",
  };
}

const ROLES = rolesResult.roles;
const cycleBudget = budgetResult.budget;
const cycleTotalBefore = normalizeCycleTotal(A.cycle_total, cycle);
const nextAdrId = normalizeNextAdrId(A.next_adr_id);
log(`Reviewer roster: [${ROLES.join(", ")}]; cycle budget ${cycleBudget}; cumulative cycles before this run ${cycleTotalBefore}; next feature ADR id ${nextAdrId}.`);
if (budgetResult.clamped) {
  log(`cycle_budget requested ${JSON.stringify(A.cycle_budget)} exceeds the protocol ceiling — capped to ${MAX_CYCLE_BUDGET}.`);
}

// Per-role model: the architect lens and the disposition leg run on opus (today's
// cost profile); the read-only reviewer agent's own default is sonnet.
function modelFor(role) {
  return role === "architect" ? "opus" : undefined;
}

// ---------- schemas (structured agent output) ----------

function concernsSchemaFor(role) {
  return {
    type: "object",
    additionalProperties: false,
    required: ["role", "status", "concerns"],
    properties: {
      role: { type: "string", enum: [role] },
      status: { type: "string", enum: ["concerns-raised", "approved"] },
      concerns: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["id", "severity", "text"],
          properties: {
            id: { type: "string", pattern: findingIdPattern(role) },
            severity: { type: "string", enum: ["blocker", "major", "minor"] },
            text: { type: "string" },
          },
        },
      },
    },
  };
}

const REFUTATION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["role", "refutations"],
  properties: {
    role: { type: "string", enum: ROLES },
    refutations: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["concern_id", "verdict", "reason"],
        properties: {
          concern_id: { type: "string" },
          verdict: { type: "string", enum: ["refute", "affirm"] },
          reason: { type: "string" },
          citation: {
            type: "object",
            additionalProperties: false,
            required: ["file", "locator"],
            properties: {
              file: { type: "string" },
              locator: { type: "string" },
            },
          },
        },
      },
    },
  },
};

const DISPOSITION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["role", "dispositions"],
  properties: {
    role: { type: "string", enum: ["architect"] },
    dispositions: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["id", "action", "reason"],
        properties: {
          id: { type: "string" },
          action: { type: "string", enum: ["adr", "fix"] },
          reason: { type: "string" },
          adr_title: { type: "string" },
          adr_body: { type: "string" },
        },
      },
    },
  },
};

// ---------- Phase 1: fan-out review ----------

phase("Fan-out review");

const reviewerResults = await parallel(
  ROLES.map((role) => () =>
    agent(reviewPrompt(role, feature, cycle, LENS[role]), {
      label: `review:${role}`,
      phase: "Fan-out review",
      agentType: "build-fleet:reviewer",
      model: modelFor(role),
      schema: concernsSchemaFor(role),
    })
  )
);

const reviews = ROLES.map((role, i) => ({ role, payload: reviewerResults[i] }));
for (const r of reviews) {
  if (!r.payload || !Array.isArray(r.payload.concerns)) {
    log(`Review incomplete: ${r.role} returned no usable concerns payload. Cleaning up without advancing state.`);
    const scribeResult = await applyScribe(cleanupEnvelope(feature, now, runId));
    return {
      verdict: "incomplete",
      reason: "missing-reviewer-payload",
      role: r.role,
      feature,
      cycle,
      scribe_apply: scribeResult.ok ? "applied" : "failed",
      scribe_error: scribeResult.error,
      note: "No REVIEW.md entries written; PHASE/CYCLE unchanged. Re-run /build-fleet:review.",
    };
  }
}

const allConcerns = mergeConcerns(reviews);

// ---------- Phase 2: cross-examination ----------

phase("Cross-examination");

const xaResults = await parallel(
  ROLES.map((role) => () =>
    agent(crossExamPrompt(role, allConcerns, feature, cycle), {
      label: `cross-exam:${role}`,
      phase: "Cross-examination",
      agentType: "build-fleet:reviewer",
      model: modelFor(role),
      schema: REFUTATION_SCHEMA,
    })
  )
);

const refutationMap = mergeRefutations(ROLES, xaResults);

// ---------- Phase 3: survival vote (pure JS) ----------

phase("Survival vote");

const surviving = applySurvivalVote(allConcerns, refutationMap);

// ---------- Phase 4: disposition (architect, read-only; scribe writes the ADRs) ----------

phase("Disposition");

const survivingMajors = surviving.filter((c) => c.severity === "major" && !c.refuted);
let dispositionMap = {};
let decisionsAppendix = null;
let adrsWritten = 0;

if (survivingMajors.length === 0) {
  log("No surviving majors — disposition leg skipped.");
} else {
  const exhausting = cycle >= cycleBudget;
  const dispo = await agent(dispositionPrompt(feature, cycle, survivingMajors, nextAdrId, exhausting), {
    label: "disposition:architect",
    phase: "Disposition",
    agentType: "build-fleet:reviewer",
    model: "opus",
    schema: DISPOSITION_SCHEMA,
  });
  const coverage = dispositionCoverage(surviving, dispo && dispo.dispositions);
  if (!dispo || !Array.isArray(dispo.dispositions) || coverage.missing.length > 0) {
    log(`Disposition incomplete: ${dispo ? "missing " + coverage.missing.join(", ") : "no payload"}. Cleaning up without advancing state.`);
    const scribeResult = await applyScribe(cleanupEnvelope(feature, now, runId));
    return {
      verdict: "incomplete",
      reason: "disposition-incomplete",
      missing: coverage.missing,
      feature,
      cycle,
      scribe_apply: scribeResult.ok ? "applied" : "failed",
      scribe_error: scribeResult.error,
      note: "No REVIEW.md entries written; PHASE/CYCLE unchanged. Re-run /build-fleet:review.",
    };
  }
  if (coverage.extra.length > 0) {
    log(`Disposition named ids that are not surviving majors (ignored): ${coverage.extra.join(", ")}.`);
  }
  const kept = dispo.dispositions.filter((d) => coverage.extra.indexOf(d.id) === -1);
  const assigned = assignAdrIds(kept, nextAdrId);
  dispositionMap = assigned.map;
  const adrBlocks = [];
  for (const c of survivingMajors) {
    const d = dispositionMap[c.id];
    if (d && d.action === "adr") {
      adrBlocks.push(formatAdr(d.adr_id, d.adr_title, d.adr_body, cycle, now, c.id, c.raised_by));
    }
  }
  adrsWritten = adrBlocks.length;
  decisionsAppendix = adrBlocks.length > 0 ? adrBlocks.join("\n\n") : null;
  log(`Disposition: ${adrsWritten} accepted via ADR, ${survivingMajors.length - adrsWritten} to fix.`);
}

const ready = computeFinalizeReady(surviving, dispositionMap);
const verdict = decideVerdict(ready.openBlockers.length, ready.openMajors.length, cycle, cycleBudget);

log(
  `Cycle ${cycle}: ${surviving.length} concerns, ${ready.openBlockers.length} open blockers, ${ready.openMajors.length} open majors → verdict=${verdict}, finalize_ready=${ready.finalize_ready}`
);

// ---------- Phase 5: apply via scribe ----------

phase("Apply");

const outputTokens = outputTokensSoFar();
const envelope = buildEnvelope({
  feature, cycle, cycleBudget, cycleTotalBefore, now, reviews, surviving, dispositionMap,
  decisionsAppendix, ready, verdict, outputTokens,
});
const scribeResult = await applyScribe(envelope);

return {
  verdict,
  finalize_ready: ready.finalize_ready,
  feature,
  cycle,
  cycle_total: cycleTotalBefore + 1,
  surviving_concerns: surviving.length,
  surviving_blockers: ready.openBlockers.length,
  open_majors: ready.openMajors.map((c) => c.id),
  adrs_written: adrsWritten,
  output_tokens: outputTokens,
  scribe_apply: scribeResult.ok ? "applied" : "failed",
  scribe_error: scribeResult.error,
  next: scribeResult.ok ? envelope.next_legal_commands : [],
  note: scribeResult.ok
    ? undefined
    : "SCRIBE APPLY FAILED after retry — REVIEW.md/PROGRESS.md/DECISIONS.md did NOT land and the .workflow-in-flight marker may remain. The dispatching command must report failure, not success.",
};

// ================= helpers =================

function reviewPrompt(role, feature, cycle, lens) {
  const files = `Read these files yourself (you have Read/Grep/Glob and NOTHING that writes):
- .sdd/${feature}/spec.md
- .sdd/${feature}/acceptance.md
- .sdd/${feature}/REVIEW.md      (the PREVIOUS cycle only — older cycles are archived in REVIEW-archive.md; do not read the archive)
- .sdd/${feature}/DECISIONS.md   (feature ADRs; may not exist on cycle 1)
Read product ADRs (.sdd/_product/DECISIONS.md) only for the specific ADR ids the spec cites — never the whole file.`;

  const rules = `Finding ids are STABLE across cycles and namespaced to you: "${role}-c<cycle>-<n>"
(e.g. "${role}-c${cycle}-1"). A finding you re-raise from an earlier cycle KEEPS its original id.

DECISIONS.md is dispositive. A [major] with "disposition: adr ADR-N" in REVIEW.md is CLOSED by that
ADR: do not re-raise it. If you believe the accepted trade-off is wrong, raise a NEW [blocker]
arguing against the ADR by id.

Do NOT write, edit, or create any file. Return only the structured object.`;

  const cycleRules = cycle <= 1
    ? `This is cycle 1: a FULL review of the spec through your lens.`
    : `This is cycle ${cycle}: a DELTA review. Two jobs, in order:
1. CLOSURE — for each of YOUR OWN findings from the previous cycle that carries "disposition: fix",
   and each of your own [blocker] findings, check whether the current spec/acceptance closes it.
   Still open ⇒ return it again with its ORIGINAL id (and the same severity). Closed ⇒ omit it.
2. NEW findings — [blocker] severity ONLY (correctness, security, data loss, or a contradiction
   of spec/acceptance — including a regression introduced by a fix). You may add [minor] notes
   (advisory). You may NOT raise a new [major]: the open-major set only shrinks after cycle 1.`;

  return `You are the ${role} reviewer. Cycle ${cycle}. Active feature: ${feature}.

${files}

Review through YOUR lens:
${lens}

The severity rubric (blocker / major / minor) is in your instructions — use those exact words.

${cycleRules}

${rules}

Return the structured object:
- role: "${role}"
- status: "concerns-raised" if you hold any blocker/major, else "approved" (informational — the
  gate reads dispositions, not this line)
- concerns: array of { id, severity, text }. Empty array + "approved" when you have nothing.`;
}

function crossExamPrompt(role, allConcerns, feature, cycle) {
  const peers = allConcerns.filter((c) => c.raised_by !== role);
  return `You are the ${role} reviewer in CROSS-EXAMINATION, cycle ${cycle}. Active feature: ${feature}.

Read .sdd/${feature}/spec.md, .sdd/${feature}/acceptance.md and .sdd/${feature}/DECISIONS.md
yourself if you need to cite them. An ADR that dispositions a peer's concern is a
substantive refutation — cite it by id. Do NOT write any file.

Below are concerns raised by OTHER reviewers (not your own). For each, decide whether to
REFUTE it (you believe it is not a real problem) or AFFIRM it (you agree it stands).

A refutation only counts if it is substantive: at least ~40 characters of reasoning AND a
structured citation pointing at the evidence. On every "refute" entry, set the citation
field to { file, locator } — e.g. { "file": "spec.md", "locator": "§ Constraints" } or
{ "file": "acceptance.md", "locator": "line 12" } or
{ "file": "DECISIONS.md", "locator": "ADR-7" }. A refute without a citation is
discarded by the script. If you cannot substantively refute, AFFIRM — that is the safe
default (no citation needed on an affirm).
You cannot refute your own concerns (the script filters self-refutation).

Peer concerns:
${JSON.stringify(peers, null, 2)}

Return the structured object:
- role: "${role}"
- refutations: array of { concern_id, verdict ("refute"|"affirm"), reason, citation? }.
  citation = { file, locator } and is REQUIRED when verdict is "refute".
  Include one entry per peer concern.`;
}

function dispositionPrompt(feature, cycle, majors, nextAdrId, exhausting) {
  const list = majors.map((c) => ({ id: c.id, raised_by: c.raised_by, text: c.text }));
  return `You are the architect, DISPOSITIONING the surviving [major] findings of review cycle ${cycle}
for feature ${feature}. Read .sdd/${feature}/spec.md, .sdd/${feature}/acceptance.md and
.sdd/${feature}/DECISIONS.md yourself. Do NOT write any file — the scribe records your ADRs.

For EVERY finding below, choose exactly one action:
- "adr" — the finding is a genuine design TRADE-OFF the spec should not absorb: the current
  choice is defensible, and the concern is a cost we accept. Supply adr_title (short imperative:
  what the decision IS, not what triggered it) and adr_body: the four sections of the ADR format
  below, WITHOUT the heading and metadata lines (the scribe adds "## ADR-N: title", Date, Status,
  Cycle). ADR ids are assigned sequentially from ADR-${nextAdrId} in the order you list them.
- "fix" — a missing behaviour, an unsatisfiable or untestable criterion, a contradiction, or
  an under-specification a coder would have to guess at. The product-owner must close it in the
  spec next cycle.
${exhausting ? `
This is the EXHAUSTING cycle of the budget: any "fix" you leave open ESCALATES the feature to a
human. Choose "fix" only where the spec genuinely cannot ship as written.` : ""}
Rule of thumb: if closing it would make the spec LONGER without making the system more correct,
it is an "adr". If a test could fail because of it, it is a "fix".

ADR body format (write these four sections, in this order, as markdown):
### Context
What forced the decision — name the finding id and who raised it.
### Decision
The decision in one or two sentences, stated as a positive choice.
### Alternatives considered
The rejected options with a one-line reason each.
### Consequences
What this makes easier, what harder, what now depends on it. Concrete.

Findings to disposition (cover EVERY id, exactly once):
${JSON.stringify(list, null, 2)}

Return the structured object:
- role: "architect"
- dispositions: array of { id, action ("adr"|"fix"), reason, adr_title?, adr_body? } — adr_title
  and adr_body are REQUIRED when action is "adr".`;
}

function mergeConcerns(reviews) {
  const out = [];
  for (const r of reviews) {
    for (const c of r.payload.concerns || []) {
      out.push({
        id: c.id,
        severity: c.severity,
        raised_by: r.role,
        text: c.text,
        refuted: false,
        refuted_by: null,
        refutation_reason: null,
      });
    }
  }
  return out;
}

function mergeRefutations(roles, xaResults) {
  const map = {};
  roles.forEach((role, i) => {
    const payload = xaResults[i];
    if (!payload || !Array.isArray(payload.refutations)) return;
    for (const ref of payload.refutations) {
      (map[ref.concern_id] ||= []).push({
        role,
        verdict: ref.verdict,
        reason: ref.reason,
        citation: ref.citation || null,
      });
    }
  });
  return map;
}

function validCitation(c) {
  return !!c &&
    typeof c.file === "string" && c.file.trim().length > 0 &&
    typeof c.locator === "string" && c.locator.trim().length > 0;
}

function applySurvivalVote(concerns, refutationMap) {
  const MIN_REFUTATION_CHARS = 40;
  return concerns.map((c) => {
    const refs = (refutationMap[c.id] || []).filter(
      (r) =>
        r.verdict === "refute" &&
        r.role !== c.raised_by &&
        typeof r.reason === "string" &&
        r.reason.length >= MIN_REFUTATION_CHARS &&
        validCitation(r.citation)
    );
    if (refs.length === 0) return c;
    const r = refs[0];
    return { ...c, refuted: true, refuted_by: r.role, refutation_reason: r.reason, refutation_citation: r.citation };
  });
}

function buildEnvelope({ feature, cycle, cycleBudget, cycleTotalBefore, now, reviews, surviving, dispositionMap, decisionsAppendix, ready, verdict, outputTokens }) {
  const reviewEntries = reviews.map((r) => {
    const own = surviving.filter((c) => c.raised_by === r.role);
    const lines = [`## Cycle ${cycle} — ${r.role} — ${now}`];
    for (const c of own) {
      for (const l of formatFindingLines(c, dispositionMap)) lines.push(l);
    }
    lines.push(`status: ${r.payload.status || "concerns-raised"}`);
    return lines.join("\n");
  });

  const escalation_payload =
    verdict === "escalate"
      ? {
          reason: "cycle-budget-exhausted-with-open-findings",
          cycle,
          cycle_budget: cycleBudget,
          surviving_blockers: ready.openBlockers,
          open_majors: ready.openMajors,
          emitted_at: now,
        }
      : null;

  const state_delta = {
    PHASE: verdict === "escalate" ? "ESCALATED" : "REVIEW",
    CYCLE: cycle,
    CYCLE_TOTAL: cycleTotalBefore + 1,
    UPDATED: now,
  };
  if (outputTokens !== null) state_delta.LAST_REVIEW_OUTPUT_TOKENS = outputTokens;

  return {
    build_fleet_version: "0.2",
    feature,
    run_id: runId,
    phase: "REVIEW",
    cycle,
    verdict,
    finalize_ready: ready.finalize_ready,
    surviving_concerns: surviving,
    review_entries: reviewEntries,
    decisions_appendix: decisionsAppendix,
    state_delta,
    next_legal_commands:
      verdict === "escalate" ? [] : ready.finalize_ready ? ["/build-fleet:finalize"] : ["/build-fleet:revise"],
    estimated_cost_actual: { input_tokens: null, output_tokens: outputTokens },
    escalation_payload,
  };
}

function cleanupEnvelope(feature, now, runId) {
  return {
    build_fleet_version: "0.2",
    feature,
    run_id: runId,
    phase: "REVIEW",
    cycle: 0,
    verdict: "incomplete",
    finalize_ready: false,
    surviving_concerns: [],
    review_entries: [],
    decisions_appendix: null,
    state_delta: now ? { UPDATED: now } : {},
    next_legal_commands: ["/build-fleet:review"],
    estimated_cost_actual: { input_tokens: null, output_tokens: null },
    escalation_payload: null,
  };
}

// ---------- verified scribe application ----------

async function applyScribe(envelope) {
  let lastError = "scribe returned no usable result";
  for (let attempt = 1; attempt <= 2; attempt++) {
    let res = null;
    try {
      res = await agent(
        `Apply this build-fleet workflow envelope to .sdd/${envelope.feature}/ exactly per your instructions in agents/scribe.md.

Marker ownership: RELEASE .sdd/${envelope.feature}/.workflow-in-flight by overwriting it with EMPTY content via the Write tool (you have no Bash; an empty marker counts as released and is reaped later) — ONLY if its current content matches the envelope's run_id${envelope.run_id ? ` ("${envelope.run_id}")` : " (null — legacy envelope: release unconditionally, best-effort)"}. If the content differs, leave the marker — it belongs to another run.

Append rules: append to REVIEW.md and DECISIONS.md with an Edit anchored on the file's final non-empty line — never rewrite a whole file. A state_delta key with no matching line in PROGRESS.md is APPENDED as a new line.

Return the structured object {ok, error}: ok=true when the WHOLE envelope landed (your SCRIBE_OK condition), with error=null. ok=false with error="<one-line reason>" otherwise (your SCRIBE_ERROR reason).

ENVELOPE:
${JSON.stringify(envelope, null, 2)}`,
        {
          label: attempt === 1 ? "scribe" : "scribe-retry",
          phase: "Apply",
          agentType: "build-fleet:scribe",
          effort: "low",
          schema: SCRIBE_RESULT_SCHEMA,
        }
      );
    } catch (e) {
      res = null;
      lastError = "scribe agent error: " + (e && e.message ? e.message : String(e));
    }
    if (res && res.ok === true) return { ok: true, error: null };
    if (res && typeof res.error === "string" && res.error) lastError = res.error;
    log(`Scribe apply attempt ${attempt}/2 failed: ${lastError}`);
  }
  return { ok: false, error: lastError };
}
````

- [ ] **Step 5: Run everything green**

Run:
```bash
node --check workflows/review.js && bash scripts/workflow-determinism-lint.sh workflows/review.js
bash scripts/workflow-review-config.test.sh | tail -1        # the 0.7 helpers still extract: passed=19 failed=0
bash scripts/workflow-review-convergence.test.sh | tail -1   # passed=41 failed=0
bash scripts/lens-drift.test.sh | tail -1                    # passed=3 failed=0
bash scripts/run-tests.sh | tail -1                          # suites: 24, failed: 0
```

- [ ] **Step 6: Commit**

```bash
git add workflows/review.js scripts/workflow-review-convergence.test.sh scripts/lens-drift.test.sh
git commit -m "feat(review): convergent workflow — delta review, stable ids, disposition leg, finalize_ready

Cycle >= 2 is a delta review (verify own fix-findings, new findings at
blocker severity only). Surviving majors are dispositioned by an architect
leg as adr (ADR drafted, scribe-written) or fix. finalize_ready = zero
blockers AND zero fix majors, computed here so verdict and gate agree.
Reviewers run as the read-only build-fleet:reviewer agent. Output tokens
recorded from budget.spent(); CYCLE_TOTAL written via state_delta.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LxywtRNJqBvQc4ZP23Deet"
```

---

### Task 4: The scribe learns `decisions_appendix`, the absent-key rule and anchored appends (spec §3.3)

**Files:**
- Modify: `agents/scribe.md`

**Interfaces:**
- Consumes: the Task 3 envelope (`decisions_appendix`, new `state_delta` keys, `escalation_payload.open_majors`).
- Produces: `DECISIONS.md` gains the ADR blocks verbatim; PROGRESS.md gains `CYCLE_TOTAL:` / `LAST_REVIEW_OUTPUT_TOKENS:` lines when absent.

- [ ] **Step 1: Absent-key rule.** In `### 1. Apply state_delta to PROGRESS.md` replace

```markdown
- Replace the matching field in-place (e.g., `PHASE: REVIEW` ← `PHASE: <new value>`).
- Preserve every other field's existing value. Preserve field order.
- Write the result back.
```
with
```markdown
- Replace the matching field in-place (e.g., `PHASE: REVIEW` ← `PHASE: <new value>`).
- **A key with no matching `FIELD:` line is APPENDED** as a new `FIELD: <value>` line at
  the end of the file (v0.9: grandfathered PROGRESS files lack `CYCLE_TOTAL` and
  `LAST_REVIEW_OUTPUT_TOKENS`; the first workflow run on them must still land those).
- Preserve every other field's existing value. Preserve field order.
- Write the result back (a `Read` then an `Edit` of the changed lines; a whole-file
  `Write` is acceptable ONLY for PROGRESS.md, which is small).
```

- [ ] **Step 2: Anchored appends.** In `### 2. Append review_entries to REVIEW.md` replace

```markdown
- Append it verbatim to `.sdd/<feature>/REVIEW.md`.
- Separate entries with one blank line.
- Create REVIEW.md if it does not exist.
```
with
```markdown
- Append it verbatim to `.sdd/<feature>/REVIEW.md` with an **`Edit` anchored on the
  file's final non-empty line** (old_string = that line, new_string = that line + a
  blank line + the entry). Never rewrite the whole file with `Write` — REVIEW.md can
  be large and a whole-file rewrite is the cost the v0.9 rotation exists to remove.
- Separate entries with one blank line.
- Create REVIEW.md (with `Write`) only if it does not exist.
```

- [ ] **Step 3: `decisions_appendix`.** Insert a new subsection after `### 2b. Append impl_notes_appendix to IMPL_NOTES.md` (before `### 3.`):

```markdown
### 2c. Append `decisions_appendix` to DECISIONS.md

If the envelope has a `decisions_appendix` field with a non-empty string value:

- Append it verbatim to `.sdd/<feature>/DECISIONS.md` with an `Edit` anchored on the
  file's final non-empty line; separate from prior content with one blank line.
- If DECISIONS.md does not exist, create it (`Write`) with the `adr` skill's feature
  header first:
  ```
  # Architecture Decisions — <feature>

  Append-only log. Each ADR is immutable; supersede with a new ADR.
  ```
  then the appendix.
- **Append-only.** Never modify or renumber existing ADRs. The review workflow
  assigned the `## ADR-N:` ids from the next free id; you do not check or change them.

If `decisions_appendix` is absent, `null`, or empty, do not create or touch
DECISIONS.md. The envelope field is the sole authorization (same rule as
`impl_notes_appendix`).
```

- [ ] **Step 4: `open_majors` in ESCALATION.md.** In `### 3. Write ESCALATION.md` replace

```markdown
  ## Surviving blockers

  <render payload.surviving_blockers as a markdown list: severity, raised_by, text>

  ## Recommended next step
```
with
```markdown
  ## Surviving blockers

  <render payload.surviving_blockers as a markdown list: severity, id, raised_by, text>

  ## Open majors (disposition: fix)

  <render payload.open_majors the same way; write "- (none)" when the array is empty or absent>

  ## Recommended next step
```

- [ ] **Step 5: Constraints.** Replace

```markdown
- You **never** write `spec.md`, `acceptance.md`, `DECISIONS.md`, `TEST_PLAN.md`, or production source.
- You **may** append to `IMPL_NOTES.md` ONLY via the `impl_notes_appendix` envelope field. You never edit prior IMPL_NOTES.md content; append-only.
```
with
```markdown
- You **never** write `spec.md`, `acceptance.md`, `TEST_PLAN.md`, or production source.
- You **may** append to `IMPL_NOTES.md` ONLY via the `impl_notes_appendix` envelope field, and to `DECISIONS.md` ONLY via the `decisions_appendix` field. You never edit prior content in either; append-only.
```
and in the same list replace
```markdown
- You do not bump `CYCLE`, `CHANGE_CYCLE`, or any field beyond what `state_delta` specifies.
```
with
```markdown
- You do not bump `CYCLE`, `CHANGE_CYCLE`, `CYCLE_TOTAL`, or any field beyond what `state_delta` specifies — but a `state_delta` key absent from PROGRESS.md IS appended (§1).
```

- [ ] **Step 6: Description.** Set the frontmatter to:

```
description: Use this agent only as the final phase of a build-fleet workflow (review, deep-build, plan-review, diagnose) — it is the workflow's single state writer. It receives a structured JSON envelope and applies it verbatim - the state delta to PROGRESS.md (appending keys that do not exist yet), appended review entries to REVIEW.md, disposition ADRs to DECISIONS.md via decisions_appendix, ESCALATION.md when present - then releases the workflow-in-flight marker. Appends are anchored Edits, never whole-file rewrites. Do NOT use it to author content or mutate state outside an envelope.
```

- [ ] **Step 7: Verify and commit**

Run: `bash scripts/run-tests.sh | tail -1` → `suites: 24, failed: 0`.

```bash
git add agents/scribe.md
git commit -m "feat(scribe): decisions_appendix, absent-key append, anchored appends, open majors in escalations

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LxywtRNJqBvQc4ZP23Deet"
```

---

### Task 5: The deterministic finalize gate (spec §3.4)

**Files:**
- Create: `scripts/finalize-gate.sh`, `scripts/finalize-gate.test.sh`
- Modify: `commands/finalize.md`, `commands/status.md`

**Interfaces:**
- Consumes: the REVIEW.md line grammar from Task 3.
- Produces: `bash scripts/finalize-gate.sh <slug> [--roster a,b,c]` → one line `BUILD_FLEET_FINALIZE_GATE: {"feature","cycle","pass","reasons","open_blockers","open_majors","majors_without_adr"}`, exit 0 pass / 2 refuse / 1 usage.

- [ ] **Step 1: Write the harness** at `scripts/finalize-gate.test.sh`:

````bash
#!/usr/bin/env bash
# Tests for scripts/finalize-gate.sh (v0.9 rubric-only gate). Builds a fixture
# workspace per case, asserts the BUILD_FLEET_FINALIZE_GATE line + exit code.
# Run: bash scripts/finalize-gate.test.sh   (exit 0 = all pass)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$DIR/finalize-gate.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass=0; fail=0

# new_proj <name> <cycle> → fixture with feature 'feat' at CYCLE <cycle>, roster default
new_proj() {
  local p="$work/$1"
  mkdir -p "$p/.sdd/feat"
  printf 'PHASE: REVIEW\nCYCLE: %s\nREVIEW_ROLES: architect, qa, coder\n' "$2" > "$p/.sdd/feat/PROGRESS.md"
  printf '# Architecture Decisions — feat\n\n## ADR-4: accept x\n\n- **Status:** accepted\n' > "$p/.sdd/feat/DECISIONS.md"
  printf '# Review Log — feat\n\nAppend-only.\n\n' > "$p/.sdd/feat/REVIEW.md"
  printf '%s' "$p"
}
# block <proj> <cycle> <role> <body-lines…>
block() { local p="$1" c="$2" r="$3"; shift 3; { printf '## Cycle %s — %s — 2026-09-03T00:00:00Z\n' "$c" "$r"; for l in "$@"; do printf '%s\n' "$l"; done; printf 'status: concerns-raised\n\n'; } >> "$p/.sdd/feat/REVIEW.md"; }
# run <proj> → sets rc + out
run() { out=$( cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$GATE" feat 2>/dev/null ); rc=$?; }
assert() { local name="$1" cond="$2"; if eval "$cond"; then pass=$((pass+1)); printf 'ok   %-44s\n' "$name"; else fail=$((fail+1)); printf 'FAIL %-44s (%s) out=%s\n' "$name" "$cond" "${out:-}"; fi; }

# --- pass: all roles present, blocker-free, majors adr'd (ADR exists) or refuted ---
p=$(new_proj ok 2)
block "$p" 2 architect '- [major] (architect-c1-2) accepted' '  disposition: adr ADR-4' '- [minor] (architect-c2-1) nit'
block "$p" 2 qa '- [major] (qa-c1-1) refuted' '  refuted-by: coder — reason: long enough reason here for sure (cites spec.md § A)'
block "$p" 2 coder
run "$p"
assert "pass-rc0" "[ $rc -eq 0 ]"
assert "pass-line" "printf '%s' \"\$out\" | grep -q '\"pass\":true,\"reasons\":\\[\\]'"

# --- refuse: a fix-dispositioned major ---
p=$(new_proj fix 2); block "$p" 2 architect '- [major] (architect-c2-1) open' '  disposition: fix'; block "$p" 2 qa; block "$p" 2 coder
run "$p"
assert "fix-major-refuses" "[ $rc -eq 2 ]"
assert "fix-major-reason" "printf '%s' \"\$out\" | grep -q 'majors-open'"
assert "fix-major-id-listed" "printf '%s' \"\$out\" | grep -q '\"open_majors\":\\[\"architect-c2-1\"\\]'"

# --- refuse: a major with no disposition line at all (legacy block) is open ---
p=$(new_proj legacy 1); block "$p" 1 architect '- [major] legacy text without id or disposition'; block "$p" 1 qa; block "$p" 1 coder
run "$p"
assert "undispositioned-major-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q majors-open"

# --- refuse: adr disposition citing an ADR that does not exist ---
p=$(new_proj noadr 2); block "$p" 2 architect '- [major] (architect-c2-1) x' '  disposition: adr ADR-9'; block "$p" 2 qa; block "$p" 2 coder
run "$p"
assert "missing-adr-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q majors-without-adr"
# zero-padded citation of an existing ADR passes
p=$(new_proj pad 2); block "$p" 2 architect '- [major] (architect-c2-1) x' '  disposition: adr ADR-004'; block "$p" 2 qa; block "$p" 2 coder
run "$p"
assert "zero-padded-adr-passes" "[ $rc -eq 0 ]"

# --- refuse: open blocker ---
p=$(new_proj blk 2); block "$p" 2 architect '- [blocker] (architect-c2-1) b'; block "$p" 2 qa; block "$p" 2 coder
run "$p"
assert "blocker-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q open-blockers"

# --- refuse: a roster role has no current-cycle block (stale cycle only) ---
p=$(new_proj miss 2); block "$p" 1 architect; block "$p" 2 qa; block "$p" 2 coder
run "$p"
assert "missing-role-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q missing-architect"

# --- status lines are ignored: concerns-raised with everything closed still passes ---
p=$(new_proj status 2); block "$p" 2 architect; block "$p" 2 qa; block "$p" 2 coder
run "$p"
assert "status-line-not-evaluated" "[ $rc -eq 0 ]"

# --- last block per role wins (a later same-cycle block supersedes) ---
p=$(new_proj last 2); block "$p" 2 architect '- [blocker] (architect-c2-1) early'; block "$p" 2 qa; block "$p" 2 coder; block "$p" 2 architect
run "$p"
assert "last-block-per-role-wins" "[ $rc -eq 0 ]"

# --- roster override flag ---
p=$(new_proj roster 2); block "$p" 2 architect; block "$p" 2 qa
out=$( cd "$p" && CLAUDE_PROJECT_DIR="$p" bash "$GATE" feat --roster architect,qa 2>/dev/null ); rc=$?
assert "roster-flag-two-roles-pass" "[ $rc -eq 0 ]"

# --- bad input: missing PROGRESS → exit 1 ---
p="$work/noprog"; mkdir -p "$p/.sdd/feat"
out=$( cd "$p" && CLAUDE_PROJECT_DIR="$p" bash "$GATE" feat 2>/dev/null ); rc=$?
assert "no-progress-exit-1" "[ $rc -eq 1 ]"

echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
````

- [ ] **Step 2: Run it red**

Run: `bash scripts/finalize-gate.test.sh | tail -2`
Expected: every case `FAIL` (the script does not exist; `bash` exits 127).

- [ ] **Step 3: Write `scripts/finalize-gate.sh`**:

````bash
#!/usr/bin/env bash
# scripts/finalize-gate.sh — the deterministic finalize gate (v0.9, rubric-only).
#
# /build-fleet:finalize calls this instead of evaluating REVIEW.md in prose, so the
# gate is testable and can never drift from the workflow's finalize_ready rule.
#
# Rule, over the CURRENT cycle's blocks (the LAST block per roster role whose heading
# is "## Cycle <CYCLE> — <role> —"):
#   - every roster role has a block                        else missing-<role>
#   - zero "- [blocker]" lines                             else open-blockers
#   - every "- [major]" line's next line is one of
#       "  refuted-by: …"            (closed by the survival vote)
#       "  disposition: adr ADR-N"   (closed — ADR-N must exist in DECISIONS.md, else majors-without-adr)
#       "  disposition: fix" / none  (OPEN                              → majors-open)
#   `status:` lines are NOT evaluated (informational since v0.9).
#
# Usage: finalize-gate.sh <slug> [--roster a,b,c]
#   ROSTER defaults to REVIEW_ROLES in PROGRESS.md, else architect,qa,coder.
# Output (stdout, exactly one line):
#   BUILD_FLEET_FINALIZE_GATE: {"feature","cycle","pass":bool,"reasons":[…],"open_blockers":[…],"open_majors":[…],"majors_without_adr":[…]}
# Exit: 0 = pass; 2 = refuse; 1 = bad usage / unreadable workspace.
# bash 3.2 + BSD/GNU compatible; read-only. Requires jq for JSON string escaping.
set -uo pipefail

slug="${1:-}"
[ -n "$slug" ] || { echo "usage: finalize-gate.sh <slug> [--roster a,b,c]" >&2; exit 1; }
case "$slug" in */*|..|.) echo "finalize-gate.sh: bad slug '$slug'" >&2; exit 1 ;; esac
shift
roster_arg=""
if [ "${1:-}" = "--roster" ]; then roster_arg="${2:-}"; fi
command -v jq >/dev/null 2>&1 || { echo "finalize-gate.sh: jq is required" >&2; exit 1; }

cd "${CLAUDE_PROJECT_DIR:-.}"
dir=".sdd/${slug}"
progress="${dir}/PROGRESS.md"; review="${dir}/REVIEW.md"; decisions="${dir}/DECISIONS.md"
[ -f "$progress" ] || { echo "finalize-gate.sh: ${progress} not found" >&2; exit 1; }

field() { { grep -m1 "^$1:" "$progress" 2>/dev/null || true; } | sed -E "s/^$1:[[:space:]]*//" | tr -d '\r '; }
cycle=$(field CYCLE)
case "$cycle" in ''|*[!0-9]*) echo "finalize-gate.sh: CYCLE is not an integer ('${cycle}')" >&2; exit 1 ;; esac

roster="$roster_arg"
[ -n "$roster" ] || roster=$(field REVIEW_ROLES)
[ -n "$roster" ] || roster="architect,qa,coder"
roles=$(printf '%s' "$roster" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep . || true)

reasons=""; open_blockers=""; open_majors=""; without_adr=""
add() { eval "$1=\"\${$1}\${$1:+\$'\\n'}\$2\""; }

for role in $roles; do
  [ -f "$review" ] || { add reasons "missing-${role}"; continue; }
  # last block for this role + cycle: heading line number
  start=$({ grep -nE "^##[[:space:]]+Cycle[[:space:]]+${cycle}[[:space:]]+[—–-][[:space:]]+${role}[[:space:]]+[—–-]" "$review" || true; } | tail -1 | cut -d: -f1)
  if [ -z "$start" ]; then add reasons "missing-${role}"; continue; fi
  # block end: next "## " heading after start, or EOF
  next=$({ tail -n +"$((start+1))" "$review" | grep -n '^## ' || true; } | head -1 | cut -d: -f1)
  if [ -n "$next" ]; then end=$((start+next-1)); else end=$(wc -l < "$review" | tr -d ' '); fi
  block=$(sed -n "${start},${end}p" "$review")

  # blockers
  while IFS= read -r l; do
    [ -n "$l" ] && add open_blockers "$l"
  done <<< "$(printf '%s\n' "$block" | grep -E '^-[[:space:]]+\[blocker\]' || true)"

  # majors: examine each major line + its following line
  n=$(printf '%s\n' "$block" | wc -l | tr -d ' ')
  k=1
  while [ $k -le $n ]; do
    line=$(printf '%s\n' "$block" | sed -n "${k}p")
    if printf '%s' "$line" | grep -qE '^-[[:space:]]+\[major\]'; then
      id=$(printf '%s' "$line" | sed -nE 's/^-[[:space:]]+\[major\][[:space:]]+\(([^)]+)\).*/\1/p')
      [ -n "$id" ] || id="$line"
      nextl=$(printf '%s\n' "$block" | sed -n "$((k+1))p")
      if printf '%s' "$nextl" | grep -qE '^[[:space:]]+refuted-by:'; then
        :
      elif printf '%s' "$nextl" | grep -qE '^[[:space:]]+disposition:[[:space:]]+adr[[:space:]]+ADR-0*[0-9]+'; then
        adr=$(printf '%s' "$nextl" | sed -nE 's/.*ADR-0*([0-9]+).*/\1/p')
        if [ -f "$decisions" ] && grep -qE "^##[[:space:]]+ADR-0*${adr}:" "$decisions"; then :; else add without_adr "$id"; fi
      else
        add open_majors "$id"
      fi
    fi
    k=$((k+1))
  done
done

[ -z "$open_blockers" ] || add reasons "open-blockers"
[ -z "$open_majors" ] || add reasons "majors-open"
[ -z "$without_adr" ] || add reasons "majors-without-adr"

tojson() { if [ -z "$1" ]; then printf '[]'; else printf '%s\n' "$1" | jq -R . | jq -sc .; fi; }
pass=true; [ -z "$reasons" ] || pass=false
printf 'BUILD_FLEET_FINALIZE_GATE: {"feature":"%s","cycle":%s,"pass":%s,"reasons":%s,"open_blockers":%s,"open_majors":%s,"majors_without_adr":%s}\n' \
  "$slug" "$cycle" "$pass" "$(tojson "$reasons")" "$(tojson "$open_blockers")" "$(tojson "$open_majors")" "$(tojson "$without_adr")"
[ "$pass" = true ] && exit 0 || exit 2
````

- [ ] **Step 4: Run it green**

Run: `chmod +x scripts/finalize-gate.sh && bash scripts/finalize-gate.test.sh | tail -1`
Expected: `passed=14 failed=0`.

- [ ] **Step 5: Rewire `commands/finalize.md`.** Set the frontmatter to:

```
---
description: Gate: flip the spec to FINALIZED and unlock source
allowed-tools: Read, Edit, Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/finalize-gate.sh":*), Bash(date:*)
---
```

Replace step 4 in full with:

```markdown
4. **Run the gate script.** The gate is deterministic (v0.9) — never evaluate REVIEW.md
   in prose. Run:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/finalize-gate.sh" "<slug>"
   ```

   (add `--roster <r1,r2,...>` only if a `--roles` flag was given; by default the script
   reads `REVIEW_ROLES` from PROGRESS.md). It prints exactly one line:

   ```
   BUILD_FLEET_FINALIZE_GATE: {"feature":"<slug>","cycle":<N>,"pass":true|false,"reasons":[...],"open_blockers":[...],"open_majors":[...],"majors_without_adr":[...]}
   ```

   The rule it enforces, over the LAST block per roster role for the current `CYCLE`:
   - every roster role has a block (else `missing-<role>`);
   - zero `[blocker]` lines (else `open-blockers`);
   - zero `[major]` lines whose disposition is `fix` or absent (else `majors-open`);
   - every `disposition: adr ADR-N` cites an `## ADR-N:` present in the feature
     `DECISIONS.md` (else `majors-without-adr`).
   `status:` lines are informational and NOT evaluated. Exit 0 ⇒ pass (step 6);
   exit 2 ⇒ refuse (step 5), relaying the script's `reasons`; exit 1 ⇒ the workspace
   is unreadable — report it and stop.
```

Replace the reason-code list in step 5 with:

```markdown
   Reason codes (from the gate script; combine as needed):
   - `missing-<role>` — reviewer block absent for the current cycle (one per missing role)
   - `open-blockers` — current cycle has open `[blocker]` items
   - `majors-open` — `[major]` items dispositioned `fix` (or carrying no disposition line)
   - `majors-without-adr` — `[major]` items whose `disposition: adr ADR-N` cites an ADR absent from DECISIONS.md
   - `not-approved` — **no longer emitted since v0.9** (status lines are informational); kept in the grammar for older orchestrators
```
and in the human-readable list replace `- The recommended next command (`/build-fleet:review` to run another cycle, after PO has revised).` with `- The recommended next command: `/build-fleet:revise` (hands the PO exactly the open items), then `/build-fleet:review`.`

In step 6, replace `- Edit PROGRESS.md: set `PHASE: BUILD`, refresh `UPDATED:`. The` with `- Edit PROGRESS.md: set `PHASE: BUILD`, refresh `UPDATED:` with `date -u +%Y-%m-%dT%H:%M:%SZ`. The`.

In "Hard rules" replace
```markdown
- This command **never** writes ADRs. If a `[major]` needs an ADR, the
  refusal output should say so and a subsequent `/build-fleet:review`
  cycle is where architect records it.
```
with
```markdown
- This command **never** writes ADRs. A `[major]` reaches the gate already
  dispositioned by the review workflow's architect leg (`adr` = accepted, ADR
  written by the scribe; `fix` = open). `majors-open` means the PO has not closed a
  `fix` item — run `/build-fleet:revise`, then `/build-fleet:review`.
- This command **never** evaluates REVIEW.md itself — `scripts/finalize-gate.sh` is
  the gate; the command relays its line.
```

- [ ] **Step 6: `commands/status.md`.** In step 4 replace `- Count of `[blocker]`, `[major]`, `[minor]` items.` with:

```markdown
   - Count of `[blocker]`, `[major]`, `[minor]` items — and for each `[major]`, its
     `disposition:` (`fix` = open, `adr ADR-N` = accepted; none = open, legacy block).
   - `finalize_ready`: yes iff zero `[blocker]` lines and zero open majors across the
     current cycle's blocks (this is the finalize gate's rule).
```
In step 2 add after `- CHANGE_CYCLE (change-review cycles consumed).`:
```markdown
   - CYCLE_TOTAL (cumulative spec-review cycles, never reset) against CYCLE_TOTAL_MAX
     (default 6), when present.
   - LAST_REVIEW_OUTPUT_TOKENS, when present.
```
In step 6 replace the two `REVIEW` bullets with:
```markdown
   - `REVIEW` and not finalize-ready → `/build-fleet:revise` (PO closes the open
     blockers and `fix` majors), then `/build-fleet:review`.
   - `REVIEW` and finalize-ready → `/build-fleet:finalize` (the gate), then
     `/build-fleet:build` (the BUILD orchestration).
```

- [ ] **Step 7: Suite and commit**

Run: `bash scripts/run-tests.sh | tail -1` → `suites: 25, failed: 0`.

```bash
git add scripts/finalize-gate.sh scripts/finalize-gate.test.sh commands/finalize.md commands/status.md
git commit -m "feat(finalize): deterministic rubric-only gate script; status reports dispositions + finalize_ready

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LxywtRNJqBvQc4ZP23Deet"
```

---

### Task 6: `/build-fleet:revise` and a real clock in the dispatching commands (spec §3.9, §3.10)

**Files:**
- Create: `commands/revise.md`
- Modify: `commands/plan-review.md:4`, `commands/deep-build.md:4`, `commands/diagnose.md:4` (allowed-tools) and their "Supply `now` yourself" sentences

**Interfaces:**
- Consumes: REVIEW.md line grammar (Task 3); `SPEC_MAX_KB` / `AC_MAX` fields (scaffolded in Task 7, read-with-default here).
- Produces: signal `BUILD_FLEET_REVISE_DISPATCHED: {"feature","cycle","items"}`; refusal reason `nothing-to-revise`.

- [ ] **Step 1: Create `commands/revise.md`**:

````markdown
---
description: Hand the product-owner exactly the open review items to close
allowed-tools: Read, Task
---

# /build-fleet:revise

You are the **orchestrator**. After a `/build-fleet:review` cycle, the open items are
the current cycle's `[blocker]` lines and every `[major]` whose disposition is `fix`
(or missing). This command extracts exactly those, with their ids, and dispatches the
product-owner to close them **in the spec, under the feature's size budget**. It is
the per-cycle ritual's second half: `revise` → `review` → (`finalize` | `revise` …).

It never edits `.sdd/` itself; the product-owner writes `spec.md` / `acceptance.md`.

## What you do

1. **Resolve the active feature.** Read `.sdd/ACTIVE`. If empty, refuse:
   `BUILD_FLEET_REFUSE: {"command":"revise","code":2,"reason":"no-active-feature"}`.

2. **Check phase.** Read `.sdd/<slug>/PROGRESS.md`. `PHASE` must be `REVIEW`; else refuse
   `{"command":"revise","code":2,"reason":"wrong-phase","phase":"<PHASE>"}`. If
   `.sdd/<slug>/ESCALATION.md` exists, refuse `{"code":2,"reason":"escalation-present"}`
   — a human resolves it first.

3. **Extract the open items.** Read `CYCLE` and `REVIEW_ROLES` (default
   `architect, qa, coder`). In `.sdd/<slug>/REVIEW.md`, take the **last** block per
   roster role headed `## Cycle <CYCLE> — <role> —`. From those blocks collect:
   - every `- [blocker] (<id>) <text>` line;
   - every `- [major] (<id>) <text>` line whose next line is `  disposition: fix`, or
     which has no `disposition:` / `refuted-by:` continuation line at all.
   Ignore `[minor]` lines, refuted items, and `disposition: adr ADR-N` majors — those
   are **closed** and must not be handed to the PO.
   If the list is empty, refuse
   `BUILD_FLEET_REFUSE: {"command":"revise","code":2,"reason":"nothing-to-revise","cycle":<CYCLE>}`
   and tell the user the cycle is finalize-ready: run `/build-fleet:finalize`.

4. **Read the size budget.** From PROGRESS.md: `SPEC_MAX_KB` and `AC_MAX` (either may be
   absent — then say "no cap" for that one).

5. **Dispatch the product-owner.** Use the Task tool to spawn `build-fleet:product-owner`
   with this prompt (fill every placeholder):

   > Revise `.sdd/<slug>/spec.md` and `.sdd/<slug>/acceptance.md` to close EXACTLY these
   > open review items from cycle <CYCLE> — nothing else:
   >
   > <the extracted lines, verbatim, one per line, with their ids>
   >
   > Rules:
   > - Close each item in the spec/acceptance text, or push back in `## Self-review notes`
   >   with reasoning a human can audit. Record, per id, what you did.
   > - Items dispositioned `adr` are CLOSED by their ADR — do not touch the text they
   >   concern and do not add prose "also addressing" them.
   > - Size budget: spec.md ≤ <SPEC_MAX_KB> KB, acceptance.md ≤ <AC_MAX> distinct criteria
   >   (hooks refuse writes over budget). If closing these items cannot fit, do NOT compress
   >   rationale: name in `## Self-review notes` which behaviours and criteria move to a
   >   sibling backlog row (a split), and cut them here.
   > - Keep `STATUS: DRAFT`. Do not renumber existing `AC-<n>` ids.
   > - The next review is a delta review: reviewers verify closure by id.

6. **Emit the signal and report.**
   ```
   BUILD_FLEET_REVISE_DISPATCHED: {"feature":"<slug>","cycle":<CYCLE>,"items":<N>}
   ```
   Tell the user how many items were handed over and that the next command is
   `/build-fleet:review` once the PO reports done.

## Hard rules

- Never edit `spec.md`, `acceptance.md`, `REVIEW.md`, `DECISIONS.md` or PROGRESS.md
  yourself — the PO revises; the review workflow records.
- Never hand the PO an `adr`-dispositioned major or a refuted item. Re-opening closed
  items is how specs bloat.
- **Headless contract.** Exactly one `BUILD_FLEET_*` line before any prose; a slash
  command cannot set a process exit code.
````

- [ ] **Step 2: Clock in the other dispatchers.** (`commands/handoff.md` already has unrestricted `Bash` and needs no change; `finalize.md` and `review.md` are handled in Tasks 5 and 8.) In each of `commands/plan-review.md`, `commands/deep-build.md`, `commands/diagnose.md` append `, Bash(date:*)` to the `allowed-tools:` line, and replace the sentence beginning `Supply `now` yourself (the script cannot call `Date`)` with `Compute `now` as `date -u +%Y-%m-%dT%H:%M:%SZ` (the script cannot call `Date`; never guess a timestamp — the pilot's guessed stamps were hours off)` keeping the rest of each sentence intact.

- [ ] **Step 3: Verify the command loads and commit**

Run: `head -4 commands/revise.md && grep -c 'Bash(date:\*)' commands/plan-review.md commands/deep-build.md commands/diagnose.md commands/finalize.md` → each file reports `1`.

```bash
git add commands/revise.md commands/plan-review.md commands/deep-build.md commands/diagnose.md
git commit -m "feat(commands): /build-fleet:revise hands the PO exactly the open items; dispatchers get a real clock

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LxywtRNJqBvQc4ZP23Deet"
```

---

### Task 7: `adr-index.sh`, the product-owner context diet and budget scaffolding (spec §3.7, §3.8)

**Files:**
- Create: `scripts/adr-index.sh`, `scripts/adr-index.test.sh`
- Modify: `commands/new-feature.md`

**Interfaces:**
- Produces: `bash scripts/adr-index.sh <DECISIONS.md>` → `ADR-<N>: <title> [<status>]` lines; `--next` → next free integer (Task 8 passes it as `next_adr_id`). PROGRESS fields `CYCLE_TOTAL: 0`, `CYCLE_TOTAL_MAX: 6`, and by tier `SPEC_MAX_KB` / `AC_MAX` (Task 9's hooks read them).

- [ ] **Step 1: Write the harness** at `scripts/adr-index.test.sh`:

````bash
#!/usr/bin/env bash
# Tests for scripts/adr-index.sh (v0.9 ADR index + --next).
# Run: bash scripts/adr-index.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDX="$DIR/adr-index.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
assert() { local name="$1" cond="$2"; if eval "$cond"; then pass=$((pass+1)); printf 'ok   %-40s\n' "$name"; else fail=$((fail+1)); printf 'FAIL %-40s (%s)\n' "$name" "$cond"; fi; }

f="$work/DECISIONS.md"
printf '# Architecture Decisions — feat\n\nAppend-only log.\n\n## ADR-1: use token bucket\n\n- **Date:** 2026-09-01\n- **Status:** accepted\n\n### Context\nx\n\n## ADR-007: keep Decimal everywhere\n\n- **Status:** superseded by ADR-9\n\n## ADR-9: round once\n' > "$f"
out=$(bash "$IDX" "$f")
assert "index-line-1" "printf '%s\n' \"\$out\" | grep -qx 'ADR-1: use token bucket \\[accepted\\]'"
assert "index-zero-padded-normalised" "printf '%s\n' \"\$out\" | grep -qx 'ADR-7: keep Decimal everywhere \\[superseded by ADR-9\\]'"
assert "index-status-unknown" "printf '%s\n' \"\$out\" | grep -qx 'ADR-9: round once \\[unknown\\]'"
assert "index-count" "[ \$(printf '%s\n' \"\$out\" | wc -l | tr -d ' ') -eq 3 ]"
assert "next-is-max-plus-one" "[ \"\$(bash \"\$IDX\" \"\$f\" --next)\" = 10 ]"
assert "next-absent-file-is-1" "[ \"\$(bash \"\$IDX\" \"\$work/none.md\" --next)\" = 1 ]"
assert "absent-file-index-empty-rc0" "[ -z \"\$(bash \"\$IDX\" \"\$work/none.md\")\" ] && bash \"\$IDX\" \"\$work/none.md\""
printf '# Architecture Decisions — feat\n\nAppend-only log.\n' > "$work/empty.md"
assert "empty-log-next-is-1" "[ \"\$(bash \"\$IDX\" \"\$work/empty.md\" --next)\" = 1 ]"
sed -i.bak $'s/$/\r/' "$f"
assert "crlf-tolerated" "[ \"\$(bash \"\$IDX\" \"\$f\" --next)\" = 10 ]"
rc=0; bash "$IDX" '../x' >/dev/null 2>&1 || rc=$?
assert "traversal-refused" "[ $rc -eq 1 ]"
rc=0; bash "$IDX" >/dev/null 2>&1 || rc=$?
assert "no-arg-usage-exit-1" "[ $rc -eq 1 ]"
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
````

- [ ] **Step 2: Run it red** — `bash scripts/adr-index.test.sh | tail -1` → all `FAIL` (script absent).

- [ ] **Step 3: Write `scripts/adr-index.sh`**:

````bash
#!/usr/bin/env bash
# scripts/adr-index.sh — deterministic ADR index for a DECISIONS.md.
#
# Prints one line per ADR: "ADR-<N>: <title> [<status>]" — the id + title index the
# product-owner receives INSTEAD of the whole product ADR log (it Reads only the ADRs
# it cites), and the source of the disposition leg's next free feature ADR id.
#
# Usage: adr-index.sh <DECISIONS.md>          # the index, in file order
#        adr-index.sh <DECISIONS.md> --next   # next free integer id (1 if none/absent)
# Ids tolerate zero-padding (ADR-007 → 7). Status is the first "- **Status:** X" line
# inside the block, "unknown" when absent. Exit 0 always (an absent file is an empty
# log). bash 3.2 + BSD/GNU compatible; read-only.
set -uo pipefail

file="${1:-}"
mode="${2:-}"
[ -n "$file" ] || { echo "usage: adr-index.sh <DECISIONS.md> [--next]" >&2; exit 1; }
case "$file" in */../*|../*|*/..|..) echo "adr-index.sh: path '$file' contains '..' — refused" >&2; exit 1 ;; esac

if [ ! -f "$file" ]; then
  if [ "$mode" = "--next" ]; then echo 1; fi
  exit 0
fi

awk -v mode="$mode" '
  { gsub(/\r/, "") }
  /^##[[:space:]]+ADR-[0-9]+:/ {
    if (have) flush()
    line = $0
    sub(/^##[[:space:]]+ADR-/, "", line)
    id = line; sub(/:.*/, "", id); id = id + 0
    title = line; sub(/^[0-9]+:[[:space:]]*/, "", title)
    status = "unknown"; have = 1
    if (id > max) max = id
    next
  }
  have && /^-[[:space:]]+\*\*Status:\*\*/ && status == "unknown" {
    s = $0; sub(/^-[[:space:]]+\*\*Status:\*\*[[:space:]]*/, "", s); sub(/[[:space:]]+$/, "", s)
    status = s
  }
  function flush() { if (mode != "--next") printf "ADR-%d: %s [%s]\n", id, title, status }
  END {
    if (have) flush()
    if (mode == "--next") print max + 1
  }
' "$file"
````

- [ ] **Step 4: Run it green** — `chmod +x scripts/adr-index.sh && bash scripts/adr-index.test.sh | tail -1` → `passed=11 failed=0`.

- [ ] **Step 5: `commands/new-feature.md` — allowed-tools.** Append to the `allowed-tools:` line: `, Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/adr-index.sh":*), Bash(date:*)`. Replace every `<iso8601 now>` / `<iso8601>` instruction to stamp `UPDATED:` with the result of `date -u +%Y-%m-%dT%H:%M:%SZ` (steps 1, 3, 7).

- [ ] **Step 6: Scaffold the cumulative counter.** In step 3's PROGRESS template, after `BUILD_CYCLE_BUDGET: 3` insert:

```
   CYCLE_TOTAL: 0
   CYCLE_TOTAL_MAX: 6
```
and extend the sentence after the template: `…reproduces the historical behavior. `CYCLE_TOTAL` is the cumulative spec-review cycle count — written by the review workflow's scribe and **never reset** by resolve-escalation or park; `/build-fleet:review` refuses to dispatch at `CYCLE_TOTAL_MAX` (0 disables). Raising the max is a deliberate, auditable edit.`

- [ ] **Step 7: Scaffold the size budget by tier.** In step 7 ("Write classifier verdict to PROGRESS.md") add after the `UPDATED:` bullet:

```markdown
   - **Size budget (v0.9).** Add two lines by tier — `standard`: `SPEC_MAX_KB: 24` and
     `AC_MAX: 15`; `large`: `SPEC_MAX_KB: 48` and `AC_MAX: 30`; `trivial`: neither.
     The `cap-spec-size` (PreToolUse) and `validate-acceptance-count` (PostToolUse)
     hooks enforce them; an absent field is no cap (grandfathering). Over budget the
     rule is SPLIT the feature into backlog rows, never compress — raising a field is
     a deliberate, auditable edit.
```

- [ ] **Step 8: Context diet.** In step 5b replace

```markdown
   - Read `.sdd/_product/STACK.md` and `.sdd/_product/DECISIONS.md`.
   - Pass both verbatim into the classifier prompt (step 6) and the product-owner
     delegation (step 8) as **inherited, read-only product context**.
```
with
```markdown
   - Read `.sdd/_product/STACK.md`. Build the **ADR index** (id + title + status, one
     line per ADR — never the ADR bodies) with the shared script:
     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}/scripts/adr-index.sh" .sdd/_product/DECISIONS.md
     ```
   - Pass the **binding stack verbatim** and the **ADR index** into the classifier
     prompt (step 6) and the product-owner delegation (step 8) as **inherited,
     read-only product context**. The PO `Read`s only the product ADRs its spec cites,
     by id. (The tap pilot's product ADR log reached 203 KB; a PO handed all of it wrote
     a 554 KB first draft.)
```

In step 8, replace `**Inherited product stack (both tiers — from step 5b).** If `.sdd/_product/STACK.md` exists, **prepend to the PO prompt**, verbatim and labeled "inherited, read-only product context": the **binding** stack and the product `DECISIONS.md`.` with `**Inherited product stack (both tiers — from step 5b).** If `.sdd/_product/STACK.md` exists, **prepend to the PO prompt**, labeled "inherited, read-only product context": the **binding** stack verbatim and the **ADR index** (ids + titles only; instruct the PO to `Read` a product ADR only when the spec cites it).`

Add to step 8, after the tier bullets and before "Inherited product stack":

```markdown
   **Size budget (both non-trivial tiers).** Tell the PO its budget from PROGRESS.md —
   `SPEC_MAX_KB` for `spec.md` and `AC_MAX` distinct criteria for `acceptance.md` — that
   hooks refuse writes over it, and that a feature which cannot fit is a SPLIT signal:
   name the proposed sibling rows in `## Self-review notes` and draft the smaller feature.
   Never compress rationale to fit. Draft to the budget from the first line: the first
   draft sets the review surface.
```

- [ ] **Step 9: Suite and commit**

Run: `bash scripts/run-tests.sh | tail -1` → `suites: 26, failed: 0`.

```bash
git add scripts/adr-index.sh scripts/adr-index.test.sh commands/new-feature.md
git commit -m "feat(new-feature): ADR index instead of the whole product log; size budget + CYCLE_TOTAL scaffolded by tier

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LxywtRNJqBvQc4ZP23Deet"
```

---

### Task 8: REVIEW.md rotation and the review command's new dispatch contract (spec §3.6, §3.8, §3.9)

**Files:**
- Create: `scripts/review-rotate.sh`, `scripts/review-rotate.test.sh`
- Modify: `commands/review.md`, `commands/resolve-escalation.md`

**Interfaces:**
- Consumes: `adr-index.sh --next` (Task 7); review.js args `cycle_total`, `next_adr_id` and return fields (Task 3).
- Produces: `bash scripts/review-rotate.sh <slug> [--roster N]` → `BUILD_FLEET_REVIEW_ROTATED: {"feature","archived_blocks","kept_blocks"}`; new file `REVIEW-archive.md`; refusals `cycle-total-exhausted`, `cost-runaway`; flag `--override-cost`.

- [ ] **Step 1: Write the harness** at `scripts/review-rotate.test.sh`:

````bash
#!/usr/bin/env bash
# Tests for scripts/review-rotate.sh (v0.9 positional REVIEW.md rotation).
# Run: bash scripts/review-rotate.test.sh   (exit 0 = all pass)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROT="$DIR/review-rotate.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass=0; fail=0

new_proj() { local p="$work/$1"; mkdir -p "$p/.sdd/feat"; printf 'REVIEW_ROLES: architect, qa, coder\nCYCLE: 1\n' > "$p/.sdd/feat/PROGRESS.md"; printf '# Review Log — feat\n\nAppend-only.\n\n' > "$p/.sdd/feat/REVIEW.md"; printf '%s' "$p"; }
cyc() { local p="$1" c="$2"; for r in architect qa coder; do printf '## Cycle %s — %s — t\n- [minor] (%s-c%s-1) n\nstatus: approved\n\n' "$c" "$r" "$r" "$c" >> "$p/.sdd/feat/REVIEW.md"; done; }
misc() { printf '## %s — t\nbody\n\n' "$2" >> "$1/.sdd/feat/REVIEW.md"; }
run() { out=$( cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$ROT" feat "${@:2}" 2>/dev/null ); rc=$?; }
assert() { local name="$1" cond="$2"; if eval "$cond"; then pass=$((pass+1)); printf 'ok   %-44s\n' "$name"; else fail=$((fail+1)); printf 'FAIL %-44s (%s) out=%s\n' "$name" "$cond" "${out:-}"; fi; }
headings() { grep -c '^## ' "$1/.sdd/feat/REVIEW.md"; }

# --- no REVIEW.md → no-op signal, exit 0 ---
p="$work/nofile"; mkdir -p "$p/.sdd/feat"; run "$p"
assert "no-file-noop" "[ $rc -eq 0 ] && printf '%s' \"\$out\" | grep -q '\"archived_blocks\":0'"

# --- one cycle only → nothing to archive ---
p=$(new_proj one); cyc "$p" 1; run "$p"
assert "one-cycle-noop" "[ $rc -eq 0 ] && printf '%s' \"\$out\" | grep -q '\"archived_blocks\":0' && [ ! -f '$p/.sdd/feat/REVIEW-archive.md' ]"

# --- two cycles → cycle 1 archived, cycle 2 kept, header preserved ---
p=$(new_proj two); cyc "$p" 1; cyc "$p" 2; run "$p"
assert "two-cycles-archives-3" "printf '%s' \"\$out\" | grep -q '\"archived_blocks\":3,\"kept_blocks\":3'"
assert "two-cycles-keeps-cycle-2" "[ \$(headings '$p') -eq 3 ] && grep -q 'Cycle 2 — architect' '$p/.sdd/feat/REVIEW.md' && ! grep -q 'Cycle 1 — ' '$p/.sdd/feat/REVIEW.md'"
assert "two-cycles-header-kept" "head -1 '$p/.sdd/feat/REVIEW.md' | grep -q '^# Review Log — feat'"
assert "two-cycles-archive-has-cycle-1" "grep -c '^## Cycle 1 — ' '$p/.sdd/feat/REVIEW-archive.md' | grep -q '^3$'"
assert "two-cycles-archive-header" "head -1 '$p/.sdd/feat/REVIEW-archive.md' | grep -q '^# Review Archive — feat'"

# --- idempotent ---
run "$p"
assert "idempotent" "printf '%s' \"\$out\" | grep -q '\"archived_blocks\":0' && [ \$(headings '$p') -eq 3 ]"

# --- post-reset duplicate Cycle 1: the LATER run is kept, the escalation block archived ---
p=$(new_proj reset); cyc "$p" 1; cyc "$p" 2; misc "$p" 'Escalation resolved'; cyc "$p" 1; misc "$p" 'Run failure recorded'; run "$p"
assert "reset-archives-7" "printf '%s' \"\$out\" | grep -q '\"archived_blocks\":7,\"kept_blocks\":4'"
assert "reset-keeps-trailing-note" "grep -q 'Run failure recorded' '$p/.sdd/feat/REVIEW.md'"
assert "reset-archives-escalation" "grep -q 'Escalation resolved' '$p/.sdd/feat/REVIEW-archive.md' && ! grep -q 'Escalation resolved' '$p/.sdd/feat/REVIEW.md'"

# --- second rotation appends to the existing archive ---
cyc "$p" 2; run "$p"
assert "second-rotation-appends" "[ \$(grep -c '^## ' '$p/.sdd/feat/REVIEW-archive.md') -eq 11 ]"

# --- roster from flag: 2 roles keeps last 2 cycle blocks ---
p=$(new_proj flag); cyc "$p" 1; cyc "$p" 2; run "$p" --roster 2
assert "roster-flag" "printf '%s' \"\$out\" | grep -q '\"archived_blocks\":4,\"kept_blocks\":2'"

# --- CRLF headings are still recognised ---
p=$(new_proj crlf); cyc "$p" 1; cyc "$p" 2; sed -i.bak $'s/$/\r/' "$p/.sdd/feat/REVIEW.md"; run "$p"
assert "crlf-tolerated" "printf '%s' \"\$out\" | grep -q '\"archived_blocks\":3'"

# --- bad slug → exit 1 ---
out=$( cd "$work" && bash "$ROT" '../x' 2>/dev/null ); rc=$?
assert "bad-slug-exit-1" "[ $rc -eq 1 ]"

echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
````

- [ ] **Step 2: Run it red** — `bash scripts/review-rotate.test.sh | tail -1` → all `FAIL`.

- [ ] **Step 3: Write `scripts/review-rotate.sh`**:

````bash
#!/usr/bin/env bash
# scripts/review-rotate.sh — bound REVIEW.md to the previous review cycle.
#
# Called by /build-fleet:review BEFORE dispatch (spec review only). Every consumer of
# REVIEW.md keys on the CURRENT cycle's blocks, and cycle >= 2 is a DELTA review that
# needs only the previous cycle — so everything older is moved, verbatim and in
# order, to REVIEW-archive.md (append-only). This bounds every reviewer's input and
# the scribe's append cost without a schema change.
#
# POSITIONAL rule (cycle numbers collide after a resolve-escalation reset, so they
# are never used): a BLOCK is a "## " heading plus every line up to the next "## "
# heading (or EOF). Find the last run of consecutive "## Cycle …" blocks; if it holds
# at least ROSTER blocks, keep its last ROSTER blocks and EVERY block after them
# (escalation archives, run-failure notes, human decisions land after the cycle they
# concern); archive every block before. Fewer than ROSTER cycle blocks ⇒ no-op.
#
# Usage: review-rotate.sh <slug> [--roster N]
#   ROSTER defaults to the count of REVIEW_ROLES in .sdd/<slug>/PROGRESS.md, else 3.
# Output (stdout, one line):
#   BUILD_FLEET_REVIEW_ROTATED: {"feature":"<slug>","archived_blocks":N,"kept_blocks":N}
# Exit: 0 = done (including no-op); 1 = bad usage. Idempotent. bash 3.2 + BSD/GNU.
set -euo pipefail
trap 'echo "build-fleet: review-rotate errored unexpectedly — nothing was changed" >&2; exit 1' ERR

slug="${1:-}"
[ -n "$slug" ] || { echo "usage: review-rotate.sh <slug> [--roster N]" >&2; exit 1; }
case "$slug" in */*|..|.) echo "review-rotate.sh: bad slug '$slug'" >&2; exit 1 ;; esac
shift
roster=""
if [ "${1:-}" = "--roster" ]; then roster="${2:-}"; fi

cd "${CLAUDE_PROJECT_DIR:-.}"
dir=".sdd/${slug}"
review="${dir}/REVIEW.md"
archive="${dir}/REVIEW-archive.md"
progress="${dir}/PROGRESS.md"

emit() { printf 'BUILD_FLEET_REVIEW_ROTATED: {"feature":"%s","archived_blocks":%s,"kept_blocks":%s}\n' "$slug" "$1" "$2"; }

[ -f "$review" ] || { emit 0 0; exit 0; }

if [ -z "$roster" ] && [ -f "$progress" ]; then
  roles=$({ grep -m1 '^REVIEW_ROLES:' "$progress" 2>/dev/null || true; } | sed -E 's/^REVIEW_ROLES:[[:space:]]*//' | tr -d '\r')
  if [ -n "$roles" ]; then
    roster=$(printf '%s' "$roles" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -c . || true)
  fi
fi
case "$roster" in ''|*[!0-9]*|0) roster=3 ;; esac

total_lines=$(wc -l < "$review" | tr -d ' ')
# Heading line numbers (1-based). A file with no "## " heading has nothing to rotate.
starts=$({ grep -n '^## ' "$review" || true; } | cut -d: -f1)
[ -n "$starts" ] || { emit 0 0; exit 0; }

# Arrays of block start/end lines and a per-block "is a Cycle block" flag.
i=0
for s in $starts; do
  bstart[$i]=$s
  if [ $i -gt 0 ]; then bend[$((i-1))]=$((s-1)); fi
  if sed -n "${s}p" "$review" | grep -qE '^##[[:space:]]+Cycle[[:space:]]+[0-9]+[[:space:]]'; then iscycle[$i]=1; else iscycle[$i]=0; fi
  i=$((i+1))
done
nblocks=$i
bend[$((nblocks-1))]=$total_lines
header_end=$((bstart[0]-1))

# Last run of consecutive Cycle blocks: [run_start, run_end].
run_end=-1
j=$((nblocks-1))
while [ $j -ge 0 ]; do
  if [ "${iscycle[$j]}" = 1 ]; then run_end=$j; break; fi
  j=$((j-1))
done
[ $run_end -ge 0 ] || { emit 0 "$nblocks"; exit 0; }
run_start=$run_end
while [ $run_start -gt 0 ] && [ "${iscycle[$((run_start-1))]}" = 1 ]; do run_start=$((run_start-1)); done
run_len=$((run_end-run_start+1))
[ $run_len -ge $roster ] || { emit 0 "$nblocks"; exit 0; }

keep_from=$((run_end-roster+1))
[ $keep_from -gt 0 ] || { emit 0 "$nblocks"; exit 0; }

# Archive blocks [0, keep_from-1] verbatim; keep header + blocks [keep_from, end].
arch_first=${bstart[0]}
arch_last=${bend[$((keep_from-1))]}
keep_first=${bstart[$keep_from]}

tmp_arch=$(mktemp "${TMPDIR:-/tmp}/review-rotate.XXXXXX")
tmp_rev=$(mktemp "${TMPDIR:-/tmp}/review-rotate.XXXXXX")
if [ -f "$archive" ]; then
  cat "$archive" > "$tmp_arch"
else
  printf '# Review Archive — %s\n\nAppend-only. Older review cycles rotated out of REVIEW.md by scripts/review-rotate.sh; REVIEW.md + this file are the audit trail.\n\n' "$slug" > "$tmp_arch"
fi
sed -n "${arch_first},${arch_last}p" "$review" >> "$tmp_arch"
# Guarantee a trailing newline + one blank separator so the next rotation appends cleanly.
[ -n "$(tail -c1 "$tmp_arch")" ] && printf '\n' >> "$tmp_arch"
printf '\n' >> "$tmp_arch"

if [ $header_end -ge 1 ]; then sed -n "1,${header_end}p" "$review" > "$tmp_rev"; else : > "$tmp_rev"; fi
sed -n "${keep_first},\$p" "$review" >> "$tmp_rev"

mv "$tmp_arch" "$archive"
mv "$tmp_rev" "$review"
emit "$keep_from" $((nblocks-keep_from))
exit 0
````

- [ ] **Step 4: Run it green** — `chmod +x scripts/review-rotate.sh && bash scripts/review-rotate.test.sh | tail -1` → `passed=15 failed=0`.

- [ ] **Step 5: `commands/review.md` frontmatter.** Set:

```
---
description: Run the adversarial spec-review workflow
argument-hint: "[--roles <r1,r2,...>] [--cycle-budget <1-3>] [--override-cost]"
allowed-tools: Read, Write, Workflow, Bash(date:*), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-rotate.sh":*), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/adr-index.sh":*)
---
```

- [ ] **Step 6: Two refusals before spending.** Append to step 5 (after the cycle-budget precondition paragraph):

```markdown
   **Cumulative-cycle precondition (v0.9).** Read `CYCLE_TOTAL` (absent ⇒ use `CYCLE`)
   and `CYCLE_TOTAL_MAX` (absent ⇒ `6`; `0` disables). `CYCLE_TOTAL` never resets —
   not on resolve-escalation, not on park — so it is the bound the per-escalation
   budget is not. If `CYCLE_TOTAL >= CYCLE_TOTAL_MAX`, refuse **before dispatch**:
   `BUILD_FLEET_REFUSE: {"command":"review","code":2,"reason":"cycle-total-exhausted","cycle_total":<n>,"max":<m>}`
   and lay out the three options: cut the feature's scope so the open findings stop
   mattering; finalize what exists and file the remainder as a follow-up feature; or
   raise `CYCLE_TOTAL_MAX` in PROGRESS.md deliberately (a recorded decision). This
   refusal is placed at dispatch on purpose — the pilot's post-hoc guard fired only
   after a cycle had already cost ~866k tokens.

   **Cost-runaway precondition (v0.9).** Read `LAST_REVIEW_OUTPUT_TOKENS` (absent ⇒
   skip). Parse the `@cost-ceiling` header's `output_tokens` (step 8). If the last
   value exceeds 3× that ceiling and `--override-cost` is not in `$ARGUMENTS`, refuse:
   `BUILD_FLEET_REFUSE: {"command":"review","code":2,"reason":"cost-runaway","last_output_tokens":<n>,"ceiling":<c>}`
   and say the spec/inputs should shrink (split, or cut) before another cycle; pass
   `--override-cost` to run anyway (recorded by the config line).
```

- [ ] **Step 7: Rotate, then index, then a real `now`.** Insert after step 6 ("Pick the new cycle number"):

```markdown
6b. **Rotate REVIEW.md (v0.9).** If `CYCLE >= 1`, bound the reviewers' input to the
   previous cycle by running the deterministic rotation — never do this by hand:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-rotate.sh" "<slug>"
   ```
   (add `--roster <N>` when a `--roles` flag changed the roster size). It moves every
   block older than the last roster-sized run of `## Cycle` blocks into
   `.sdd/<slug>/REVIEW-archive.md` (append-only) and prints one
   `BUILD_FLEET_REVIEW_ROTATED: {...}` line — relay it. Idempotent; no-op on cycle 0.

6c. **Compute `next_adr_id` and `cycle_total`.**
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/adr-index.sh" ".sdd/<slug>/DECISIONS.md" --next
   ```
   prints the next free feature ADR integer (1 for an empty/absent log); the workflow's
   disposition leg numbers its ADRs from it. `cycle_total` is the `CYCLE_TOTAL` value
   read in step 5 (or `CYCLE` when absent) — the count BEFORE this run.
```

In step 7 replace `Compose a run id: `review-<slug>-c<new_cycle>-<iso8601 now>` (the same `now` you pass to the workflow in step 9).` with `Compute `now` as `date -u +%Y-%m-%dT%H:%M:%SZ` — never guess it — and compose the run id `review-<slug>-c<new_cycle>-<now>` (the same `now` you pass to the workflow in step 9).`

- [ ] **Step 8: Pass the new args and record them.** In step 8's config line, extend the JSON to
`BUILD_FLEET_REVIEW_CONFIG: {"feature":"<slug>","cycle":<N>,"roles":<["..."] | "default">,"cycle_budget":<n | "default">,"roles_source":"flag"|"progress"|"default","budget_source":"flag"|"progress"|"default","cycle_total":<n>,"next_adr_id":<n>,"override_cost":<true|false>}`.

In step 9 replace the `args` bullet with:
```markdown
   - `args`: `{ "feature": "<slug>", "cycle": <new_cycle>, "now": "<now>", "run_id": "<run id from step 7>", "cycle_total": <cycle_total from 6c>, "next_adr_id": <next_adr_id from 6c> }` — **plus** `"roles": [<resolved roster>]` and/or `"cycle_budget": <resolved int>` ONLY when they were resolved from a flag or a `REVIEW_*` PROGRESS.md field in step 5. **Omit those two keys entirely when unset** so the workflow applies its own default.
```
and replace `Supply `now` yourself (the script cannot call `Date`); the workflow refuses to run without it.` with `The `now` is the one you computed with `date -u` in step 7 (the script cannot call `Date`); the workflow refuses to run without it.`

- [ ] **Step 9: Report the new verdict semantics.** Replace the "Next legal command depends on the workflow's verdict" list in step 12 with:

```markdown
    - The run's return object carries `finalize_ready`, `open_majors`, `adrs_written`,
      `cycle_total` and `output_tokens`. Next legal command:
      - `finalize_ready: true` (zero blockers, every major accepted via ADR) →
        `/build-fleet:finalize` (the gate), then `/build-fleet:build`.
      - `finalize_ready: false` with `verdict` `clean` or `revise` → `/build-fleet:revise`
        (hands the PO exactly the open blockers + `fix` majors), then `/build-fleet:review`.
      - `escalate` → human action on the ESCALATION.md the workflow wrote (it lists both
        surviving blockers and open `fix` majors; the exhausting cycle escalates either).
      - `incomplete` / `invalid-args` → a transient agent fault or bad dispatch args;
        PHASE/CYCLE are unchanged and nothing was written — re-run `/build-fleet:review`
        (or fix the dispatch args). `incomplete` with `reason: disposition-incomplete` means
        the architect leg missed a major — re-run.
      Note `verdict: clean` means zero surviving BLOCKERS and is NOT finalize-readiness;
      `finalize_ready` is.
```

In "What this command does NOT do" add: `- Does not evaluate or edit REVIEW.md beyond the deterministic rotation script (which moves whole blocks verbatim into REVIEW-archive.md and never edits a block).`

- [ ] **Step 10: `commands/resolve-escalation.md`.** In step 6 ("Reset state") add a bullet: `- **Never touch `CYCLE_TOTAL`** — the cumulative counter survives every reset by design; `/build-fleet:review` refuses at `CYCLE_TOTAL_MAX`, and raising that max is the human's recorded decision, not a side effect of resolving.` Also add `Bash(date:*)` to its `allowed-tools:` and replace `<iso8601 now>` with the `date -u +%Y-%m-%dT%H:%M:%SZ` result in step 5.

- [ ] **Step 11: Suite and commit**

Run: `bash scripts/run-tests.sh | tail -1` → `suites: 27, failed: 0`.

```bash
git add scripts/review-rotate.sh scripts/review-rotate.test.sh commands/review.md commands/resolve-escalation.md
git commit -m "feat(review): rotate REVIEW.md at dispatch; refuse before spending on cycle-total / cost-runaway; real clock; finalize_ready reporting

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LxywtRNJqBvQc4ZP23Deet"
```

---

### Task 9: The two cap hooks (spec §3.8)

**Files:**
- Create: `hooks/scripts/cap-spec-size.sh`, `hooks/scripts/cap-spec-size.test.sh`, `hooks/scripts/validate-acceptance-count.sh`, `hooks/scripts/validate-acceptance-count.test.sh`
- Modify: `hooks/hooks.json`

**Interfaces:**
- Consumes: PROGRESS fields `SPEC_MAX_KB`, `AC_MAX` (Task 7 scaffolds them); `_lib.sh` helpers `require_jq`, `extract_file_path`, `read_progress_field`.
- Produces: PreToolUse refusal on over-budget spec/acceptance writes; PostToolUse refusal on over-count acceptance.md.

- [ ] **Step 1: Write both harnesses.** `hooks/scripts/cap-spec-size.test.sh`:

````bash
#!/usr/bin/env bash
# Tests for hooks/scripts/cap-spec-size.sh (v0.9 PreToolUse byte cap on spec.md /
# acceptance.md driven by SPEC_MAX_KB; absent field = no cap).
# Run: bash hooks/scripts/cap-spec-size.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/cap-spec-size.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
new_proj() { local p="$work/$1"; mkdir -p "$p/.sdd/feat"; printf 'feat\n' > "$p/.sdd/ACTIVE"; printf 'PHASE: SPEC\nSPEC_MAX_KB: %s\n' "$2" > "$p/.sdd/feat/PROGRESS.md"; printf '%s' "$p"; }
# payload <tool> <path> <content|old> [<new>] [replace_all]
payload() { if [ "$1" = Write ]; then jq -cn --arg p "$2" --arg c "$3" '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}'; else jq -cn --arg p "$2" --arg o "$3" --arg n "${4:-}" --argjson ra "${5:-false}" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n,replace_all:$ra}}'; fi; }
check() { local name="$1" proj="$2" json="$3" want="$4" rc=0; ( cd "$proj" && printf '%s' "$json" | CLAUDE_PROJECT_DIR="$proj" bash "$HOOK" >/dev/null 2>&1 ); rc=$?; if [ "$rc" -eq "$want" ]; then pass=$((pass+1)); printf 'ok   %-40s rc=%s\n' "$name" "$rc"; else fail=$((fail+1)); printf 'FAIL %-40s want=%s got=%s\n' "$name" "$want" "$rc"; fi; }
big=$(head -c 1100 /dev/zero | tr '\0' 'x'); small="hello"

p=$(new_proj w1 1)
check "write-over-budget-blocks" "$p" "$(payload Write .sdd/feat/spec.md "$big")" 2
check "write-under-budget-allows" "$p" "$(payload Write .sdd/feat/spec.md "$small")" 0
check "acceptance-also-capped" "$p" "$(payload Write .sdd/feat/acceptance.md "$big")" 2
check "absolute-path-form" "$p" "$(payload Write "$p/.sdd/feat/spec.md" "$big")" 2
printf '%s' "$big" > "$p/.sdd/feat/acceptance.md"
check "edit-growing-over-blocks" "$p" "$(payload Edit .sdd/feat/acceptance.md x xxxx)" 2
check "edit-shrinking-allows" "$p" "$(payload Edit .sdd/feat/acceptance.md "$(head -c 200 /dev/zero | tr '\0' x)" "")" 0
check "edit-replace-all-counts-occurrences" "$p" "$(payload Edit .sdd/feat/acceptance.md x xx true)" 2
p=$(new_proj g1 1); printf 'PHASE: SPEC\n' > "$p/.sdd/feat/PROGRESS.md"
check "no-field-grandfathered" "$p" "$(payload Write .sdd/feat/spec.md "$big")" 0
p=$(new_proj z1 0)
check "zero-disables" "$p" "$(payload Write .sdd/feat/spec.md "$big")" 0
p=$(new_proj o1 1)
check "other-file-ignored" "$p" "$(payload Write .sdd/feat/DECISIONS.md "$big")" 0
check "product-tier-exempt" "$p" "$(payload Write .sdd/_product/spec.md "$big")" 0
check "traversal-ignored" "$p" "$(payload Write .sdd/feat/../feat/spec.md "$big")" 0
rc=0; ( cd "$p" && printf 'not json' | CLAUDE_PROJECT_DIR="$p" bash "$HOOK" >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 2 ]; then pass=$((pass+1)); echo "ok   malformed-json-fails-closed"; else fail=$((fail+1)); echo "FAIL malformed-json-fails-closed got=$rc"; fi
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
````

`hooks/scripts/validate-acceptance-count.test.sh`:

````bash
#!/usr/bin/env bash
# Tests for hooks/scripts/validate-acceptance-count.sh (v0.9 PostToolUse criterion
# cap driven by AC_MAX; absent field = no cap).
# Run: bash hooks/scripts/validate-acceptance-count.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/validate-acceptance-count.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
new_proj() { local p="$work/$1"; mkdir -p "$p/.sdd/feat"; printf 'feat\n' > "$p/.sdd/ACTIVE"; printf 'PHASE: SPEC\nAC_MAX: %s\n' "$2" > "$p/.sdd/feat/PROGRESS.md"; printf '%s' "$p"; }
check() { local name="$1" proj="$2" fp="$3" want="$4" rc=0; ( cd "$proj" && printf '{"tool_input":{"file_path":"%s"}}' "$fp" | CLAUDE_PROJECT_DIR="$proj" bash "$HOOK" >/dev/null 2>&1 ); rc=$?; if [ "$rc" -eq "$want" ]; then pass=$((pass+1)); printf 'ok   %-40s rc=%s\n' "$name" "$rc"; else fail=$((fail+1)); printf 'FAIL %-40s want=%s got=%s\n' "$name" "$want" "$rc"; fi; }
check_err() { local name="$1" proj="$2" fp="$3" needle="$4" rc=0 err; err=$( cd "$proj" && printf '{"tool_input":{"file_path":"%s"}}' "$fp" | CLAUDE_PROJECT_DIR="$proj" bash "$HOOK" 2>&1 >/dev/null ); rc=$?; if [ "$rc" -eq 2 ] && printf '%s' "$err" | grep -qi "$needle"; then pass=$((pass+1)); printf 'ok   %-40s rc=2\n' "$name"; else fail=$((fail+1)); printf 'FAIL %-40s got=%s (%s)\n' "$name" "$rc" "$err"; fi; }

p=$(new_proj a 3); printf 'AC-1 a\nAC-2 b\nAC-3 c\nAC-3a d\n' > "$p/.sdd/feat/acceptance.md"
check "four-distinct-over-three-blocks" "$p" ".sdd/feat/acceptance.md" 2
check_err "message-says-split" "$p" ".sdd/feat/acceptance.md" "SPLIT"
printf 'AC-1 a\nAC-2 b\nAC-2 repeated\nsee AC-1 again\n' > "$p/.sdd/feat/acceptance.md"
check "repeats-count-once" "$p" ".sdd/feat/acceptance.md" 0
printf 'AC-1 a\nAC-2 b\nAC-3 c\n' > "$p/.sdd/feat/acceptance.md"
check "exactly-at-cap-allows" "$p" ".sdd/feat/acceptance.md" 0
check "spec-file-ignored" "$p" ".sdd/feat/spec.md" 0
check "absent-file-allows" "$p" ".sdd/other/acceptance.md" 0
p=$(new_proj g 3); printf 'PHASE: SPEC\n' > "$p/.sdd/feat/PROGRESS.md"; printf 'AC-1\nAC-2\nAC-3\nAC-4\nAC-5\n' > "$p/.sdd/feat/acceptance.md"
check "no-field-grandfathered" "$p" ".sdd/feat/acceptance.md" 0
p=$(new_proj z 0); printf 'AC-1\nAC-2\nAC-3\nAC-4\n' > "$p/.sdd/feat/acceptance.md"
check "zero-disables" "$p" ".sdd/feat/acceptance.md" 0
p=$(new_proj t 1); mkdir -p "$p/docs"; printf 'AC-1\nAC-2\n' > "$p/docs/acceptance.md"
check "outside-sdd-ignored" "$p" "docs/acceptance.md" 0
rc=0; ( cd "$p" && printf 'not json' | CLAUDE_PROJECT_DIR="$p" bash "$HOOK" >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 2 ]; then pass=$((pass+1)); echo "ok   malformed-json-fails-closed"; else fail=$((fail+1)); echo "FAIL malformed-json-fails-closed got=$rc"; fi
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
````

- [ ] **Step 2: Run both red** — `bash hooks/scripts/cap-spec-size.test.sh | tail -1; bash hooks/scripts/validate-acceptance-count.test.sh | tail -1` → all `FAIL`.

- [ ] **Step 3: Write `hooks/scripts/cap-spec-size.sh`**:

````bash
#!/usr/bin/env bash
# PreToolUse (Write|Edit): refuse a write that would push .sdd/<slug>/spec.md or
# acceptance.md past its byte budget (SPEC_MAX_KB in that feature's PROGRESS.md).
#
# WHY: the review loop can only ADD findings; nothing in it rewards cutting. The tap
# pilot reached a 555 KB spec and a 266 KB spec for a login feature, each costing many
# review cycles. The cap makes cycle N+1 no larger than cycle N — and the refusal
# text says SPLIT, not compress: a spec that cannot fit its budget is a feature that
# should be two backlog rows.
#
# ABSENT FIELD ⇒ NO CAP. Every workspace scaffolded before v0.9 is grandfathered;
# /build-fleet:new-feature scaffolds the field from tier defaults. The product tier
# (.sdd/_product/) is exempt. Ported from the tap pilot's local guard.
set -euo pipefail
trap 'echo "build-fleet: gate script errored unexpectedly — failing closed" >&2; exit 2' ERR

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
. "$DIR/_lib.sh"

require_jq

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
path=$(extract_file_path "$input")
[ -n "$path" ] || exit 0

# Repo-relative form so the .sdd/<slug>/ match works for relative and absolute paths.
rel="$path"
phys=$(pwd -P 2>/dev/null || pwd)
case "$rel" in
  "$PWD"/*) rel="${rel#"$PWD"/}" ;;
  "$phys"/*) rel="${rel#"$phys"/}" ;;
  ./*) rel="${rel#./}" ;;
esac
case "$rel" in */../*|../*|*/..|..) exit 0 ;; esac   # traversal is not inside .sdd/
case "$rel" in
  .sdd/_product/*) exit 0 ;;
  .sdd/*/spec.md|.sdd/*/acceptance.md) ;;
  *) exit 0 ;;
esac

slug="${rel#.sdd/}"; slug="${slug%%/*}"
base="${rel##*/}"
progress=".sdd/${slug}/PROGRESS.md"
[ -f "$progress" ] || exit 0

cap_kb=$(read_progress_field "$slug" SPEC_MAX_KB)
[ -n "$cap_kb" ] || exit 0                          # grandfathering: no field, no cap
case "$cap_kb" in ''|*[!0-9]*) exit 0 ;; esac       # malformed ⇒ treat as absent
[ "$cap_kb" -gt 0 ] || exit 0                       # 0 disables the cap

cap_bytes=$(( cap_kb * 1024 ))
current=0
[ -f "$rel" ] && current=$(wc -c < "$rel" | tr -d ' ')

# Project the resulting size. Bytes, not jq's `length` (codepoints undercount
# em-dash-heavy files). Exact for Write; old/new delta × occurrences for Edit.
case "$tool" in
  Write)
    projected=$(printf '%s' "$input" | jq -j '.tool_input.content // empty' | wc -c | tr -d ' ')
    ;;
  Edit)
    old=$(printf '%s' "$input" | jq -j '.tool_input.old_string // empty' | wc -c | tr -d ' ')
    new=$(printf '%s' "$input" | jq -j '.tool_input.new_string // empty' | wc -c | tr -d ' ')
    n=1
    if [ "$(printf '%s' "$input" | jq -r '.tool_input.replace_all // false')" = "true" ] && [ -f "$rel" ]; then
      oldstr=$(printf '%s' "$input" | jq -j '.tool_input.old_string // empty')
      if [ -n "$oldstr" ]; then
        n=$(grep -Fo "$oldstr" "$rel" 2>/dev/null | wc -l | tr -d ' ')
        [ "$n" -gt 0 ] 2>/dev/null || n=1
      fi
    fi
    projected=$(( current + (new - old) * n ))
    ;;
  *) exit 0 ;;
esac

[ "$projected" -le "$cap_bytes" ] && exit 0

cat >&2 <<MSG
build-fleet: cap-spec-size refused — ${rel} would become ${projected} bytes, over its ${cap_bytes}-byte budget.

  current   : ${current} bytes
  projected : ${projected} bytes
  budget    : ${cap_bytes} bytes (SPEC_MAX_KB: ${cap_kb} in ${progress})
  over by   : $(( projected - cap_bytes )) bytes

A spec that cannot fit its budget is a feature that should be SPLIT, not compressed:
name the split in '## Self-review notes' (which behaviours move to a sibling backlog
row) and draft ${base} for the smaller feature. Move rationale to DECISIONS.md rather
than the spec. Raising SPEC_MAX_KB in ${progress} is a deliberate, auditable decision —
never edit it just to land this write.
MSG
exit 2
````

- [ ] **Step 4: Write `hooks/scripts/validate-acceptance-count.sh`**:

````bash
#!/usr/bin/env bash
# PostToolUse (Write|Edit): when a write touches .sdd/<slug>/acceptance.md, refuse to
# continue if the file now names more distinct acceptance criteria than AC_MAX (in
# that feature's PROGRESS.md). Counts distinct ids of the form AC-<n> or AC-<n><letter>.
#
# WHY: criterion count is the review surface — every criterion is something three
# reviewers can find under-specified. The tap pilot's features carried 56–99 criteria
# and never converged. Over the cap the answer is SPLIT the feature, never renumber.
#
# ABSENT FIELD ⇒ NO CAP (grandfathering); 0 disables. The product tier has no
# acceptance.md. PostToolUse cannot undo the write — exit 2 blocks the model's
# continuation until the file is brought under budget, same as validate-spec-status.
set -euo pipefail
trap 'echo "build-fleet: gate script errored unexpectedly — failing closed" >&2; exit 2' ERR

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
. "$DIR/_lib.sh"

require_jq

input=$(cat)
file_path=$(extract_file_path "$input")
[ -n "$file_path" ] || exit 0
[ "$(basename "$file_path")" = "acceptance.md" ] || exit 0
case "$file_path" in */../*|../*|*/..|..) exit 0 ;; esac
case "$file_path" in *.sdd/*) ;; *) exit 0 ;; esac
[ -f "$file_path" ] || exit 0

# slug = the path segment after ".sdd/"
slug="${file_path##*.sdd/}"; slug="${slug%%/*}"
[ "$slug" = "_product" ] && exit 0
progress=".sdd/${slug}/PROGRESS.md"
[ -f "$progress" ] || exit 0

cap=$(read_progress_field "$slug" AC_MAX)
[ -n "$cap" ] || exit 0
case "$cap" in ''|*[!0-9]*) exit 0 ;; esac
[ "$cap" -gt 0 ] || exit 0

count=$({ grep -oE 'AC-[0-9]+[a-z]?' "$file_path" || true; } | sort -u | grep -c . || true)
[ "$count" -le "$cap" ] && exit 0

cat >&2 <<MSG
build-fleet: validate-acceptance-count refused — ${file_path} names ${count} distinct acceptance criteria, over its AC_MAX of ${cap} (in ${progress}).

Criterion count is the review surface: each one is a thing three reviewers can find
under-specified, and features with 56–99 criteria did not converge. Do NOT renumber or
merge criteria to fit. SPLIT the feature: name in spec.md '## Self-review notes' which
behaviours (and their criteria) move to a sibling backlog row, then cut them here.
Raising AC_MAX in ${progress} is a deliberate, auditable decision — never edit it just
to land this write.
MSG
exit 2
````

- [ ] **Step 5: Run both green** — `chmod +x hooks/scripts/cap-spec-size.sh hooks/scripts/validate-acceptance-count.sh && bash hooks/scripts/cap-spec-size.test.sh | tail -1 && bash hooks/scripts/validate-acceptance-count.test.sh | tail -1` → `passed=13 failed=0` and `passed=10 failed=0`.

- [ ] **Step 6: Register in `hooks/hooks.json`.** In the `PreToolUse` `Write|Edit|NotebookEdit` group append a fourth entry after `require-reproducing-test.sh`:

```json
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/cap-spec-size.sh\""
          }
```
In the `PostToolUse` group append after `validate-diagnosis-status.sh`:
```json
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/validate-acceptance-count.sh\""
          }
```
Extend the top-level `description` with: `, cap spec.md/acceptance.md bytes at SPEC_MAX_KB and distinct acceptance criteria at AC_MAX (absent field = no cap; over budget means split the feature)`.

- [ ] **Step 7: Validate JSON, suite, commit**

Run: `jq -e '.hooks.PreToolUse[0].hooks | length == 4' hooks/hooks.json && jq -e '.hooks.PostToolUse[0].hooks | length == 4' hooks/hooks.json && bash scripts/run-tests.sh | tail -1` → `true`, `true`, `suites: 29, failed: 0`.

```bash
git add hooks/scripts/cap-spec-size.sh hooks/scripts/cap-spec-size.test.sh hooks/scripts/validate-acceptance-count.sh hooks/scripts/validate-acceptance-count.test.sh hooks/hooks.json
git commit -m "feat(hooks): cap spec/acceptance bytes (SPEC_MAX_KB) and criterion count (AC_MAX); refusal says split

Ported from the tap pilot's local guard, with harnesses. Absent field = no cap.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LxywtRNJqBvQc4ZP23Deet"
```

---

### Task 10: Planning — intent bytes and cap, walking skeleton, `split_into` and the split gate (spec §3.11)

**Files:**
- Modify: `scripts/intent-block.sh`, `scripts/intent-block.test.sh`
- Modify: `hooks/scripts/validate-backlog-status.sh`, `hooks/scripts/validate-backlog-status.test.sh`
- Modify: `workflows/plan-review.js`, `scripts/workflow-plan-review-config.test.sh`
- Modify: `commands/new-product.md`, `commands/plan-finalize.md`, `agents/product-owner.md`

**Interfaces:**
- Produces: `INTENT_BYTES: <n>` line from `intent-block.sh`; product PROGRESS field `INTENT_MAX_BYTES`; interrogation finding field `split_into` rendered as `  split-into: a, b`; refusal reason `split-unresolved`.

- [ ] **Step 1: Failing test — `INTENT_BYTES`.** Append to `scripts/intent-block.test.sh` before `echo "-----"`:

```bash
# --- v0.9: INTENT_BYTES (bytes of the dedented intent lines, newline-joined) ---
assert "bytes-single-line" '- [ ] api   PENDING   depends-on: none
      What it is — its boundary.' 'INTENT_BYTES: 28'
assert "bytes-missing-intent-zero" '- [ ] bare   PENDING   depends-on: none' 'INTENT_BYTES: 0'
assert "bytes-before-verdict" '- [ ] api   PENDING   depends-on: none
      a — b.' 'INTENT_BYTES: 8
INTENT_VERDICT: usable'
```

Run: `bash scripts/intent-block.test.sh | tail -4` → three `FAIL`.

- [ ] **Step 2: Replace `scripts/intent-block.sh`** with:

````bash
#!/usr/bin/env bash
# scripts/intent-block.sh — canonical backlog intent-block extractor + quality floor.
#
# THE single implementation of the intent-block grammar that /build-fleet:new-feature
# (step 5) and /build-fleet:next-feature (step 3) previously duplicated in prose
# (audit §3.26). Both commands call this script so they always reach the same verdict.
# The row grammar mirrors scripts/next-feature.sh exactly:
#   row    = "- [ ] <slug>   <PENDING|DONE>   depends-on: ..." ("-"/"*" bullets,
#            "[x]"/"[X]"/"[ ]" marks; the state word must be the SECOND token)
#   intent = the run of INDENTED lines immediately under the row (not starting with
#            "- [" or "##" after the indent), up to the next feature row, the next
#            "## " heading, or a blank line — capped at 3 lines.
#
# Quality floor (the canonical prose definition lives in the sdd-protocol skill):
# an intent is USABLE only if it carries at least 2 of its 3 components —
# what the feature is / its scope boundary / its non-goals. Encoded
# deterministically: components = intent lines, plus extra clauses split on
# "—" (em-dash) or ";" within a line. < 2 components (including a missing or
# empty intent — a bare slug restatement has no boundary clause) = TOO-THIN.
#
# Usage:
#   intent-block.sh [file]                  # input begins AT the feature row
#   intent-block.sh --slug <slug> [file]    # find <slug>'s row in a full backlog
#   (reads stdin when no file is given)
#
# Output (stdout):
#   INTENT_SLUG: <slug>
#   INTENT_STATE: <PENDING|DONE>
#   <intent line(s), dedented — the canonical block; omitted when empty>
#   INTENT_BYTES: <n>            # byte length of the dedented intent lines (newline-joined)
#   INTENT_VERDICT: usable|too-thin
# Exit: 0 = verdict emitted; 1 = malformed/empty input or slug not found
#       (error on stderr, NO verdict line). bash 3.2 compatible; read-only.
set -uo pipefail

slug_filter=""
if [ "${1:-}" = "--slug" ]; then
  slug_filter="${2:-}"
  if [ -z "$slug_filter" ]; then
    echo "intent-block.sh: --slug requires a value" >&2
    exit 1
  fi
  shift 2
fi

input="$(cat "${1:-/dev/stdin}")"
if [ -z "$(printf '%s' "$input" | tr -d '[:space:]')" ]; then
  echo "intent-block.sh: empty input — expected a backlog feature row" >&2
  exit 1
fi

out="$(printf '%s\n' "$input" | awk -v want="$slug_filter" '
  function is_row(l) { return l ~ /^[-*][ \t]+\[[ xX]\][ \t]+/ }
  BEGIN { found = 0; nint = 0 }
  { gsub(/\r/, "") }   # CRLF tolerance, same as next-feature.sh

  !found {
    if (!is_row($0)) {
      if (want == "") { bad = 1; exit }   # row-mode: input must START at a row
      next                                 # slug-mode: scan for the row
    }
    rest = $0
    sub(/^[-*][ \t]+\[[ xX]\][ \t]+/, "", rest)
    ntok = split(rest, tok, /[ \t]+/)
    state = (ntok >= 2) ? tolower(tok[2]) : ""
    if (state != "pending" && state != "done") {
      if (want == "") { bad = 1; exit }   # row-mode: malformed row
      next
    }
    if (want != "" && tok[1] != want) next
    found = 1
    slug = tok[1]
    statew = toupper(state)
    next
  }

  found {
    if ($0 ~ /^[ \t]*$/) exit              # blank line ends the block
    if (is_row($0)) exit                   # next feature row ends the block
    if ($0 ~ /^##/) exit                   # next heading ends the block
    if ($0 !~ /^[ \t]/) exit               # intent lines are indented
    if (nint >= 3) next                    # cap at 3 lines
    line = $0
    gsub(/^[ \t]+|[ \t]+$/, "", line)
    if (line == "") next
    nint++
    intent[nint] = line
  }

  END {
    if (bad || !found) {
      print "intent-block.sh: input is not a backlog feature row" \
            (want != "" ? " (slug \"" want "\" not found)" : "") > "/dev/stderr"
      exit 1
    }
    printf "INTENT_SLUG: %s\n", slug
    printf "INTENT_STATE: %s\n", statew
    components = 0
    for (i = 1; i <= nint; i++) {
      print intent[i]
      components++                          # each line is one component...
      c = intent[i]
      components += gsub(/—/, "—", c)       # ...plus em-dash-separated clauses
      components += gsub(/;/, ";", c)       # ...plus semicolon-separated clauses
    }
    printf "INTENT_VERDICT: %s\n", (components >= 2) ? "usable" : "too-thin"
    exit 0
  }
')" || exit 1
# INTENT_BYTES: measured in bash (bytes, never awk chars — locale-independent) over the
# dedented intent lines, and printed just above the verdict line.
intent_lines="$(printf '%s\n' "$out" | grep -vE '^INTENT_' || true)"
bytes=0
[ -n "$intent_lines" ] && bytes=$(printf '%s' "$intent_lines" | wc -c | tr -d ' ')
printf '%s\n' "$out" | grep -vE '^INTENT_VERDICT:'
printf 'INTENT_BYTES: %s\n' "$bytes"
printf '%s\n' "$out" | grep -E '^INTENT_VERDICT:'
````

Run: `bash scripts/intent-block.test.sh | tail -1` → `passed=22 failed=0`.

- [ ] **Step 3: Failing test — intent cap.** Append to `hooks/scripts/validate-backlog-status.test.sh` before `echo "-----"`:

```bash
# --- v0.9: intent byte cap, only when the product PROGRESS carries INTENT_MAX_BYTES ---
big=$(head -c 700 /dev/zero | tr '\0' 'y')
capped_body() { printf 'PRODUCT: demo\nSTATUS: DRAFT\n\n## Phase 1: f — STATUS: pending\n- [ ] small   PENDING   depends-on: none\n      A tiny intent — with a boundary.\n- [ ] huge   PENDING   depends-on: none\n      %s\n' "$big"; }
p=$(new_proj cap0); capped_body > "$p/.sdd/_product/backlog.md"
check "intent-cap-absent-field-allows" "$p" ".sdd/_product/backlog.md" 0
p=$(new_proj cap1); capped_body > "$p/.sdd/_product/backlog.md"; printf 'SDD_SCHEMA: 1\nPRODUCT: demo\nINTENT_MAX_BYTES: 600\n' > "$p/.sdd/_product/PROGRESS.md"
check_err "intent-cap-over-blocks-names-slug" "$p" ".sdd/_product/backlog.md" 2 "huge"
p=$(new_proj cap2); capped_body > "$p/.sdd/_product/backlog.md"; printf 'INTENT_MAX_BYTES: 0\n' > "$p/.sdd/_product/PROGRESS.md"
check "intent-cap-zero-disables" "$p" ".sdd/_product/backlog.md" 0
p=$(new_proj cap3); body DRAFT > "$p/.sdd/_product/backlog.md"; printf 'INTENT_MAX_BYTES: 600\n' > "$p/.sdd/_product/PROGRESS.md"
check "intent-cap-under-allows" "$p" ".sdd/_product/backlog.md" 0
```

Run: `bash hooks/scripts/validate-backlog-status.test.sh | tail -3` → `FAIL intent-cap-over-blocks-names-slug`.

- [ ] **Step 4: Replace `hooks/scripts/validate-backlog-status.sh`** with:

````bash
#!/usr/bin/env bash
# PostToolUse (Write|Edit): when a write touches .sdd/_product/backlog.md, verify
# the load-bearing structure the product PLAN machine + M3.2 DEVELOPING loop parse:
# a PRODUCT: header, a valid STATUS line, and at least one phase heading.
#
# Keys strictly on basename==backlog.md under .sdd/_product/ — feature dirs have no
# backlog.md, so there is no collision with the feature tier (mirrors how
# validate-spec-status.sh keys on basename==spec.md).
#
# Deliberately lean: structural presence, not per-row grammar. A half-edited row
# should not hard-block the human mid-edit; what must stay intact is enough scaffold
# for resolve_product()/the loop to parse the file.
set -euo pipefail
# Fail CLOSED on any unexpected runtime error (audit §3.5); deliberate allows
# below are explicit exit 0.
trap 'echo "build-fleet: gate script errored unexpectedly — failing closed" >&2; exit 2' ERR

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
. "$DIR/_lib.sh"

require_jq

input=$(cat)
file_path=$(extract_file_path "$input")
[ -n "$file_path" ] || exit 0

base=$(basename "$file_path")
[ "$base" = "backlog.md" ] || exit 0

# Only validate the product backlog (under .sdd/_product/). Anything else named
# backlog.md elsewhere is not ours.
case "$file_path" in
  *.sdd/_product/backlog.md) ;;
  *) exit 0 ;;
esac

[ -f "$file_path" ] || exit 0

# 1. PRODUCT: header.
if ! grep -Eq "^PRODUCT:[[:space:]]*\S" "$file_path"; then
  echo "build-fleet: _product/backlog.md missing 'PRODUCT: <slug>' header." >&2
  exit 2
fi

# 2. STATUS line present + valid.
status_line=$(head -n10 "$file_path" | grep -m1 "^STATUS:" || true)
if [ -z "$status_line" ]; then
  echo "build-fleet: _product/backlog.md missing STATUS line (within the first 10 lines). Must contain 'STATUS: DRAFT|IN_REVIEW|FINALIZED|BLOCKED'." >&2
  exit 2
fi

status_value=$(printf '%s' "$status_line" | sed -E 's/^STATUS:[[:space:]]*//' | tr -d '\r ')
case "$status_value" in
  DRAFT|IN_REVIEW|FINALIZED|BLOCKED) ;;
  *)
    echo "build-fleet: _product/backlog.md STATUS value '${status_value}' is invalid. Must be one of: DRAFT, IN_REVIEW, FINALIZED, BLOCKED." >&2
    exit 2
    ;;
esac

# 3. At least one phase heading: '## Phase <N>: ...'.
if ! grep -Eq "^##[[:space:]]+Phase[[:space:]]+[0-9]+:" "$file_path"; then
  echo "build-fleet: _product/backlog.md has no phase heading. Expected at least one line like '## Phase 1: <name> — STATUS: <state>'." >&2
  exit 2
fi

# 4. Intent byte cap (v0.9) — ONLY when the product PROGRESS carries INTENT_MAX_BYTES
# (absent ⇒ no cap; existing products are untouched; 0 disables). An intent is a
# sketch: what / boundary / non-goals in 1–3 lines. The tap pilot's intents grew to
# 2.5 KB each and seeded 500 KB specs. Measured by the shared extractor so this hook
# and /build-fleet:new-feature can never disagree on what an intent is.
max_bytes=$(read_product_field INTENT_MAX_BYTES)
case "$max_bytes" in ''|*[!0-9]*|0) exit 0 ;; esac
extractor="$DIR/../../scripts/intent-block.sh"
[ -f "$extractor" ] || exit 0
over=""
for slug in $({ grep -E '^[-*][[:space:]]+\[[ xX]\][[:space:]]+[A-Za-z0-9._-]+' "$file_path" || true; } | sed -E 's/^[-*][[:space:]]+\[[ xX]\][[:space:]]+([A-Za-z0-9._-]+).*/\1/'); do
  bytes=$({ bash "$extractor" --slug "$slug" "$file_path" 2>/dev/null || true; } | { grep -m1 '^INTENT_BYTES:' || true; } | sed -E 's/^INTENT_BYTES:[[:space:]]*//')
  case "$bytes" in ''|*[!0-9]*) continue ;; esac
  [ "$bytes" -gt "$max_bytes" ] && over="${over}${over:+, }${slug} (${bytes} bytes)"
done
if [ -n "$over" ]; then
  echo "build-fleet: _product/backlog.md intent block(s) exceed INTENT_MAX_BYTES=${max_bytes}: ${over}. An intent is a 1–3 line sketch (what / scope boundary / non-goals) — behaviour, interfaces and criteria belong in the feature spec. Cut the intent; do not raise the cap to land the write." >&2
  exit 2
fi

exit 0
````

Run: `bash hooks/scripts/validate-backlog-status.test.sh | tail -1` → `passed=20 failed=0`.

- [ ] **Step 5: Failing test — `renderSplitLine`.** In `scripts/workflow-plan-review-config.test.sh`, inside the node driver heredoc, insert before `console.log("-----");`:

```javascript
// ---- v0.9 renderSplitLine ----
check("split-none", renderSplitLine({}) === null);
check("split-empty", renderSplitLine({ split_into: [] }) === null);
check("split-two", renderSplitLine({ split_into: ["a-b", " c-d "] }) === "  split-into: a-b, c-d");
check("split-filters-junk", renderSplitLine({ split_into: ["x", "", 3] }) === "  split-into: x");
```

Run: `bash scripts/workflow-plan-review-config.test.sh | tail -2` → exits non-zero with `ReferenceError: renderSplitLine is not defined`.

- [ ] **Step 6: Replace `workflows/plan-review.js`** with:

````javascript
// SPDX-License-Identifier: MIT
// workflows/plan-review.js
//
// build-fleet v0.4 — M3.1 product-tier PLAN_REVIEW workflow.
//
// FORK of workflows/review.js, deliberately diverged (the M3.0 decision: fork,
// don't parameterize). The product plan is a STRATEGIC BET, not a contract the
// machine can converge — so this workflow INTERROGATES (surfaces questions,
// risks, gaps from each role's lens) and never holds a survival vote. Nothing is
// auto-refuted; nothing auto-escalates. The output is an interrogation report
// appended to .sdd/_product/REVIEW.md and PHASE := PLAN_REVIEW. A human ratifies
// at /build-fleet:plan-finalize — the machine never votes a vision into being.
//
// Divergences from review.js:
//   - reviewers INTERROGATE product artifacts (vision/backlog/STACK/DECISIONS),
//     not spec.md/acceptance.md.
//   - roles are [product-owner, architect, qa] — product lenses, not [architect,qa,coder].
//     Self-interrogation is fine: the act surfaces risk, it does not vote.
//   - NO cross-examination phase. NO survival vote. Findings are consolidated by
//     pure JS (grouped + counted), never killed.
//   - verdict is informational ("interrogated"), never clean/revise/escalate.
//   - scribe writes the PRODUCT workspace via the envelope's workspace_dir.
//
// CONTRACT: docs/v0.2/CONTRACT.md §6 (envelope + workspace_dir).
//
// @cost-ceiling {"input_tokens":90000,"output_tokens":24000}
// (Cost ceiling lives in this header comment, NOT meta. commands/plan-review.md
// parses this line to emit BUILD_FLEET_COST_PREVIEW in headless mode.)

export const meta = {
  name: "build-fleet-plan-review",
  description: "Product-tier PLAN_REVIEW: interrogate the product plan from each role's lens, consolidate findings (no survival vote), scribe appends the report",
  phases: [
    { title: "Interrogate", detail: "the roster interrogates vision/backlog/STACK in parallel (configurable; default product-owner, architect, qa)" },
    { title: "Consolidate", detail: "group + count findings by severity — nothing is auto-killed" },
    { title: "Apply", detail: "scribe appends the interrogation report to _product/REVIEW.md and sets PHASE=PLAN_REVIEW" },
  ],
};

// ---------- args ----------
// { product: "<slug>", cycle: <int>, now: "<iso8601>", run_id: "<marker token>", roles?: string[] }
// `now` is supplied by the command because the script cannot call Date.
// `run_id` is the token the command wrote into .sdd/_product/.workflow-in-flight
// at dispatch; the scribe releases the marker (empties it) only when its content matches.
// `roles` (optional) overrides the interrogation roster — a >=2-element subset of
//   {product-owner, architect, qa} (the lenses defined below). Default is all three.
//   There is NO cycle_budget here: plan-review never votes or escalates.

const A = typeof args === "string" ? JSON.parse(args) : (args || {});

const product = A.product;
const cycle = typeof A.cycle === "string" ? parseInt(A.cycle, 10) : A.cycle;
const now = A.now;
const runId = A.run_id || null;

// Scribe result schema — declared HERE, above the first applyScribe() call site.
// The applyScribe function declaration is hoisted, but SCRIBE_RESULT_SCHEMA is a
// const: if any call site runs before this line, reading the schema throws
// "Cannot access 'SCRIBE_RESULT_SCHEMA' before initialization" (temporal dead
// zone). scripts/workflow-determinism-lint.sh's scribe-schema-tdz rule guards this.
const SCRIBE_RESULT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["ok", "error"],
  properties: {
    ok: { type: "boolean" },
    error: { type: ["string", "null"] },
  },
};

const WORKSPACE = ".sdd/_product/";

// --- LAYER1-PURE-HELPERS START — configurable interrogation roster ---
// Extracted VERBATIM by scripts/workflow-plan-review-config.test.sh, so this MUST
// stay pure: no log()/agent()/args, deterministic, side-effect-free. plan-review has
// NO cycle budget (it never votes or escalates), so ONLY the roster is configurable.
// Allowed roles are exactly those with a LENS entry below — {product-owner, architect,
// qa}; `coder` is not a product-plan lens. >= 2 distinct, so the plan is interrogated
// from more than one lens. Default reproduces the historical roster. The const sits
// ABOVE the first call site (arg validation) to avoid a temporal-dead-zone read.
const ALLOWED_INTERROGATION_ROLES = ["product-owner", "architect", "qa"];
const DEFAULT_INTERROGATION_ROLES = ["product-owner", "architect", "qa"];

// normalizeRoles(raw) → { roles: string[]|null, error: string|null }
function normalizeRoles(raw) {
  if (raw === undefined || raw === null) return { roles: DEFAULT_INTERROGATION_ROLES.slice(), error: null };
  if (!Array.isArray(raw) || raw.length === 0)
    return { roles: null, error: "roles: must be a non-empty array of interrogation roles" };
  const seen = [];
  for (const r of raw) {
    if (typeof r !== "string" || ALLOWED_INTERROGATION_ROLES.indexOf(r) === -1)
      return { roles: null, error: `roles: unknown interrogation role ${JSON.stringify(r)} (allowed: ${ALLOWED_INTERROGATION_ROLES.join(", ")})` };
    if (seen.indexOf(r) === -1) seen.push(r);
  }
  if (seen.length < 2)
    return { roles: null, error: "roles: need at least 2 distinct roles so the plan is interrogated from more than one lens" };
  return { roles: seen, error: null };
}

// v0.9: a finding may propose a SPLIT of an over-scoped feature. Rendered as its own
// indented line so /build-fleet:plan-finalize can grep it:  "  split-into: a, b, c".
// Returns null when the finding carries no usable split_into list.
function renderSplitLine(finding) {
  const list = Array.isArray(finding && finding.split_into)
    ? finding.split_into.filter((x) => typeof x === "string" && x.trim().length > 0).map((x) => x.trim())
    : [];
  if (list.length === 0) return null;
  return "  split-into: " + list.join(", ");
}
// --- LAYER1-PURE-HELPERS END ---

// Validation failures are NEVER a bare throw: a throw would strand the
// .workflow-in-flight marker the command dropped (this script has no filesystem
// access — only the scribe can release it). Dispatch a minimal scribe cleanup
// envelope, then return a structured invalid-args verdict for the orchestrator.
const rolesResult = normalizeRoles(A.roles);

const argErrors = [];
if (!product || typeof product !== "string") argErrors.push("product: required non-empty string");
if (typeof cycle !== "number" || Number.isNaN(cycle)) argErrors.push("cycle: required integer");
if (!now || typeof now !== "string") argErrors.push("now: required iso8601 string (the dispatching command supplies it — the script cannot call Date)");
if (rolesResult.error) argErrors.push(rolesResult.error);
if (argErrors.length > 0) {
  log(`Invalid args: ${argErrors.join("; ")}. No state advanced.`);
  if (product && typeof product === "string") {
    await applyScribe(cleanupEnvelope(product, typeof now === "string" ? now : null, runId));
  }
  return {
    verdict: "invalid-args",
    errors: argErrors,
    note: product && typeof product === "string"
      ? "Marker cleanup dispatched; PHASE/CYCLE unchanged. Fix the dispatch args and re-run /build-fleet:plan-review."
      : "product unknown — the dispatching command must delete .sdd/_product/.workflow-in-flight itself (only if its content matches the run_id it wrote).",
  };
}

// Effective roster (validated above) — drives the fan-out AND the schema role enum.
const ROLES = rolesResult.roles;
log(`Interrogation roster: [${ROLES.join(", ")}].`);

// ---------- schema (structured interrogation output) ----------
//
// One object per interrogating role. `findings` is a flat list across the three
// kinds (question | risk | gap) so the role can weight its lens freely; `kind`
// distinguishes them for the report. No refutation/verdict fields — there is no
// vote here.

const INTERROGATION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["role", "findings"],
  properties: {
    // role enum tracks the configured interrogation roster (Layer 1) — not a fixed list.
    role: { type: "string", enum: ROLES },
    findings: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["id", "kind", "severity", "text"],
        properties: {
          id: { type: "string" },
          kind: { type: "string", enum: ["question", "risk", "gap"] },
          severity: { type: "string", enum: ["blocker", "major", "minor"] },
          text: { type: "string" },
          artifact: { type: "string" }, // optional: vision.md | backlog.md | STACK.md | DECISIONS.md
          split_into: { type: "array", items: { type: "string" } }, // optional (v0.9): proposed sibling slugs for an over-scoped feature
        },
      },
    },
  },
};

// LENS text per interrogating role. Declared ABOVE the fan-out (below) because
// interrogatePrompt() reads LENS[role] and is first invoked inside the parallel()
// dispatch — a const declared after that call site is read in its temporal dead
// zone ("Cannot access 'LENS' before initialization"), the same hazard the
// roster/schema consts near the top of this file are hoisted to avoid.
const LENS = {
  "product-owner":
`- Is the vision coherent and falsifiable? For standard/large, is OUTCOME measurable?
- Is the backlog genuinely PHASED — each phase a shippable increment, not a dumping ground?
- Are depends-on edges real and acyclic? Does phase 1 stand alone?
- Is scope honest, or is this a roadmap that gets abandoned at feature 3? Flag over-ceremony.
- WALKING SKELETON: is Phase 1 the smallest VERTICAL slice that produces the product's
  primary artifact end to end? If the first demonstrable output arrives later than the
  4th feature, that is a [blocker] of kind "gap" — name the slice that should come first.
- INTENT: is each feature's intent line a clear, single-responsibility scope, or vague/
  bloated? Do sibling intents partition the product cleanly — no overlap, no gap?`,
  "architect":
`- Is the stack-of-record sound for the stated goals and scale? Any load-bearing gap?
- Is each ADR justified, or are there silent/unexplained choices?
- Brownfield: is the Baseline captured accurately? Is any PROVISIONAL forward direction
  incremental (migrate/wrap) rather than a rewrite, and is its risk named?
- What failure modes (data integrity, blast radius, coupling) does the plan not address?
- INTENT: do the intents' stated boundaries/deferrals match the stack's module seams,
  and justify the depends-on edges? Is a load-bearing piece deferred into a feature
  whose intent does not actually claim it (a boundary gap)?`,
  "qa":
`- Is the OUTCOME / are the goals actually measurable and testable as written?
- Does each backlog phase have a discernible acceptance shape, or is "done" undefined?
- What observability / verification is the plan silent on?
- Are there cross-feature integration risks the phasing hides?
- INTENT: is each intent concrete enough that a tester could see *that* it's testable
  (not *what* the tests are), or so vague that "done" is undefinable? Flag intents too
  thin to anchor a spec — but never demand acceptance criteria here (that's the spec).
- OVER-SCOPE: an intent that implies more than ~15 acceptance criteria will not converge
  in review. Flag it as a [major] of kind "gap" and NAME the split in split_into
  (two or more sibling slugs) — a split you cannot name is not a finding yet.`,
};

// ---------- Phase 1: fan-out interrogation ----------

phase("Interrogate");

const interrogations = await parallel(
  ROLES.map((role) => () =>
    agent(interrogatePrompt(role, product, cycle), {
      label: `interrogate:${role}`,
      phase: "Interrogate",
      agentType: `build-fleet:${role}`,
      schema: INTERROGATION_SCHEMA,
    })
  )
);

// Post-condition: every role must return a usable structured payload. Unlike the
// feature review, a missing payload does NOT escalate (there is no auto-escalate
// in plan-review) — it halts the workflow with an error the command surfaces, so
// the human re-runs. We never write a partial interrogation report.
const reports = ROLES.map((role, i) => ({ role, payload: interrogations[i] }));
for (const r of reports) {
  if (!r.payload || !Array.isArray(r.payload.findings)) {
    log(`Interrogation incomplete: ${r.role} returned no usable findings payload. Cleaning up without advancing state.`);
    // Do NOT write the report and do NOT advance PHASE/CYCLE — but we still must
    // remove the .workflow-in-flight marker the command dropped, or it orphans
    // until the reaper. The scribe is the only thing that can delete it (the
    // script has no filesystem access). A cleanup envelope whose state_delta
    // carries ONLY `UPDATED` leaves PHASE + CYCLE untouched (the scribe replaces
    // in place, key by key) while still triggering marker removal. Mirrors how
    // review.js always reaches its scribe on the missing-payload path.
    const scribeResult = await applyScribe(cleanupEnvelope(product, now, runId));
    return {
      verdict: "incomplete",
      reason: "missing-interrogator-payload",
      role: r.role,
      product,
      cycle,
      scribe_apply: scribeResult.ok ? "applied" : "failed",
      scribe_error: scribeResult.error,
      note: "No interrogation report written; PHASE/CYCLE unchanged. Re-run /build-fleet:plan-review.",
    };
  }
}

// ---------- Phase 2: consolidate (pure JS — nothing is killed) ----------

phase("Consolidate");

const allFindings = mergeFindings(reports);
const counts = countBySeverity(allFindings);

log(
  `Plan cycle ${cycle}: ${allFindings.length} findings interrogated ` +
  `(${counts.blocker} blocker, ${counts.major} major, ${counts.minor} minor). ` +
  `No survival vote — all findings surfaced for human ratification.`
);

// ---------- Phase 3: apply via scribe ----------

phase("Apply");

const envelope = buildEnvelope({ product, cycle, now, reports, allFindings, counts });
const scribeResult = await applyScribe(envelope);

return {
  verdict: "interrogated",
  product,
  cycle,
  findings: allFindings.length,
  open_blockers: counts.blocker,
  scribe_apply: scribeResult.ok ? "applied" : "failed",
  scribe_error: scribeResult.error,
  next: scribeResult.ok ? envelope.next_legal_commands : [],
  note: !scribeResult.ok
    ? "SCRIBE APPLY FAILED after retry — the interrogation report/PROGRESS did NOT land and the .workflow-in-flight marker may remain. The dispatching command must report failure, not success."
    : counts.blocker > 0
    ? `${counts.blocker} blocker-severity finding(s) open. /build-fleet:plan-finalize will require 'ratify force' to override.`
    : "No blocker-severity findings. /build-fleet:plan-finalize ratify will pass.",
};

// ================= helpers =================

function interrogatePrompt(role, product, cycle) {
  const lens = LENS[role];
  return `You are the ${role}, INTERROGATING the product plan for "${product}". Plan-review cycle ${cycle}.

This is NOT a spec review and NOT a vote. You are surfacing what a strategic plan
must answer before a human commits to it. You cannot kill anyone's finding and no
finding kills the plan — everything you raise is recorded for the human to weigh.

**Do NOT write or edit any file** — even artifacts you normally own (vision/backlog).
This phase is read-only interrogation; you return findings only. The scribe is the
sole writer; the human revises the plan after reading your report.

Read these product artifacts yourself (you have Read/Grep/Glob):
- .sdd/_product/vision.md      (the product vision + goals; OUTCOME for standard/large)
- .sdd/_product/backlog.md     (phased feature backlog + dependencies + per-feature intent lines)
- .sdd/_product/STACK.md       (the binding stack-of-record; brownfield has a Baseline + maybe PROVISIONAL forward)
- .sdd/_product/DECISIONS.md   (product ADRs — the why behind the stack)
- .sdd/_product/REVIEW.md      (prior interrogation cycles; may not exist on cycle 1)

**Pressure-test the per-feature INTENT lines (v0.4 M3.3).** Each backlog row should
have an indented one-to-three-line intent — what the feature is + its scope boundary.
These intents are inherited by /build-fleet:new-feature to seed each spec, so a vague,
overlapping, or wrongly-bounded intent yields a wrong spec downstream. From your lens,
interrogate: is each intent clear enough to drive a spec, or too vague to constrain it?
Are the boundaries between sibling features clean (no two features claiming the same
scope; no scope falling in the gap between them)? Do the stated boundaries/deferrals
justify the depends-on edges? Is any feature under-scoped (a real concern hidden) or
over-scoped (should be split)? A missing intent line on a non-trivial feature is itself
a gap. **But do not demand spec-level detail in the intent** — acceptance criteria,
interfaces, and behavior belong in the feature's own spec.md, not the backlog.

Interrogate through YOUR lens:
${lens}

Honor the brownfield contract: a "## Forward direction (PROVISIONAL — unreviewed)"
section is strategy that does NOT yet bind. Interrogate whether the provisional
direction is justified — but do NOT treat the binding Baseline as a defect for
merely existing. Flag a stack concern as a finding to the human, never as a demand
to rewrite reality.

Return the structured object you are required to produce:
- role: "${role}"
- findings: array of { id, kind, severity, text, artifact? }
  - id: stable "${role}-1", "${role}-2", ...
  - kind: "question" (an unanswered decision the plan must resolve) |
          "risk" (a way this plan plausibly fails) |
          "gap" (something the plan should cover but omits)
  - severity: "blocker" (a human should not ratify until this is addressed) |
              "major" (should be resolved or consciously accepted) |
              "minor" (worth noting; not ratification-blocking)
  - artifact (optional): which file the finding is about.
  - split_into (optional): when a feature is over-scoped, the proposed sibling slugs
    (kebab-case, 2+). The report renders it as its own "split-into:" line, and plain
    `ratify` refuses while a proposed slug is neither a backlog row nor refused by a
    product ADR citing this finding's id.
  If the plan is sound from your lens, return an empty findings array — that is a
  legitimate signal (you found nothing ratification-relevant), not a failure.`;
}

function mergeFindings(reports) {
  const out = [];
  for (const r of reports) {
    for (const f of r.payload.findings || []) {
      out.push({
        id: f.id,
        kind: f.kind,
        severity: f.severity,
        raised_by: r.role,
        text: f.text,
        artifact: f.artifact || null,
        split_into: Array.isArray(f.split_into) ? f.split_into : null,
      });
    }
  }
  return out;
}

function countBySeverity(findings) {
  const c = { blocker: 0, major: 0, minor: 0 };
  for (const f of findings) {
    if (c[f.severity] !== undefined) c[f.severity] += 1;
  }
  return c;
}

function buildEnvelope({ product, cycle, now, reports, allFindings, counts }) {
  // One REVIEW.md block per role, grouped by kind. Append-only; the scribe writes
  // .sdd/_product/REVIEW.md (workspace_dir below routes it there).
  const KIND_ORDER = ["question", "risk", "gap"];
  const KIND_LABEL = { question: "Open questions", risk: "Risks", gap: "Gaps" };

  const reviewEntries = reports.map((r) => {
    const own = allFindings.filter((f) => f.raised_by === r.role);
    const lines = [`## Plan Cycle ${cycle} — ${r.role} interrogation — ${now}`];
    if (own.length === 0) {
      lines.push("- (no ratification-relevant findings from this lens)");
    } else {
      for (const kind of KIND_ORDER) {
        const group = own.filter((f) => f.kind === kind);
        if (group.length === 0) continue;
        lines.push(`### ${KIND_LABEL[kind]}`);
        for (const f of group) {
          const where = f.artifact ? ` (${f.artifact})` : "";
          lines.push(`- [${f.severity}] (${f.id}) ${f.text}${where}`);
          const split = renderSplitLine(f);
          if (split) lines.push(split);
        }
      }
    }
    return lines.join("\n");
  });

  // A consolidated summary block, last, so the human sees totals at the tail.
  reviewEntries.push(
    [
      `## Plan Cycle ${cycle} — interrogation summary — ${now}`,
      `- findings: ${allFindings.length} (blocker: ${counts.blocker}, major: ${counts.major}, minor: ${counts.minor})`,
      counts.blocker > 0
        ? `- ratification: BLOCKED by ${counts.blocker} open blocker-severity finding(s) — /build-fleet:plan-finalize requires 'ratify force' to override.`
        : `- ratification: no blocker-severity findings — /build-fleet:plan-finalize ratify will pass.`,
    ].join("\n")
  );

  return {
    build_fleet_version: "0.2",
    feature: product, // scribe uses this for SCRIBE_OK + any ESCALATION title; carries the product slug
    run_id: runId,
    workspace_dir: WORKSPACE,
    phase: "PLAN_REVIEW",
    cycle,
    verdict: "interrogated", // informational — plan-review never votes
    surviving_concerns: [], // no survival vote in plan-review
    review_entries: reviewEntries,
    state_delta: {
      PHASE: "PLAN_REVIEW",
      CYCLE: cycle,
      UPDATED: now,
    },
    next_legal_commands: ["/build-fleet:plan-finalize", "/build-fleet:plan-review"],
    escalation_payload: null, // plan-review never auto-escalates — the human ratifies
  };
}

// Minimal envelope for the incomplete-interrogation/invalid-args paths: removes
// the workflow marker (ownership-checked against run_id) and refreshes UPDATED
// only. state_delta deliberately OMITS PHASE/CYCLE so the scribe leaves them at
// their pre-run values (it only replaces keys present).
function cleanupEnvelope(product, now, runId) {
  return {
    build_fleet_version: "0.2",
    feature: product,
    run_id: runId,
    workspace_dir: WORKSPACE,
    phase: "PLAN_REVIEW",
    cycle: 0,
    verdict: "incomplete",
    surviving_concerns: [],
    review_entries: [], // nothing appended to REVIEW.md
    state_delta: now ? { UPDATED: now } : {}, // PHASE + CYCLE intentionally preserved
    next_legal_commands: ["/build-fleet:plan-review"],
    escalation_payload: null,
  };
}

// ---------- verified scribe application ----------
// (SCRIBE_RESULT_SCHEMA is declared near the top of this file, above the first
// applyScribe() call site, to avoid a temporal-dead-zone error.)

// The scribe returns a structured {ok, error} aligned with its
// SCRIBE_OK:/SCRIBE_ERROR: contract (agents/scribe.md). One retry on failure;
// if still failing, the caller must surface scribe_apply: "failed" — state did
// NOT land and the dispatching command must refuse/report, never claim success.
async function applyScribe(envelope) {
  let lastError = "scribe returned no usable result";
  for (let attempt = 1; attempt <= 2; attempt++) {
    let res = null;
    try {
      res = await agent(
        `Apply this build-fleet workflow envelope to ${envelope.workspace_dir} exactly per your instructions in agents/scribe.md. Note the workspace_dir field — you write the PRODUCT workspace, not a feature dir.

Marker ownership: RELEASE ${envelope.workspace_dir}.workflow-in-flight by overwriting it with EMPTY content via the Write tool (you have no Bash; an empty marker counts as released and is reaped later) — ONLY if its current content matches the envelope's run_id${envelope.run_id ? ` ("${envelope.run_id}")` : " (null — legacy envelope: release unconditionally, best-effort)"}. If the content differs, leave the marker — it belongs to another run.

Return the structured object {ok, error}: ok=true when the WHOLE envelope landed (your SCRIBE_OK condition), with error=null. ok=false with error="<one-line reason>" otherwise (your SCRIBE_ERROR reason).

ENVELOPE:
${JSON.stringify(envelope, null, 2)}`,
        {
          label: attempt === 1 ? "scribe" : "scribe-retry",
          phase: "Apply",
          agentType: "build-fleet:scribe",
          schema: SCRIBE_RESULT_SCHEMA,
        }
      );
    } catch (e) {
      res = null;
      lastError = "scribe agent error: " + (e && e.message ? e.message : String(e));
    }
    if (res && res.ok === true) return { ok: true, error: null };
    if (res && typeof res.error === "string" && res.error) lastError = res.error;
    log(`Scribe apply attempt ${attempt}/2 failed: ${lastError}`);
  }
  return { ok: false, error: lastError };
}
````

Run: `node --check workflows/plan-review.js && bash scripts/workflow-determinism-lint.sh workflows/plan-review.js && bash scripts/workflow-plan-review-config.test.sh | tail -1` → `BUILD_FLEET_LINT_PASS`, `passed=13 failed=0`.

- [ ] **Step 7: `commands/new-product.md`.** In step 1's PROGRESS scaffold add `INTENT_MAX_BYTES: 600` after `CYCLE: 0`, and after the paragraph explaining `CYCLE: 0` add: `` `INTENT_MAX_BYTES` caps each backlog intent block (the `validate-backlog-status` hook refuses a write over it; absent = no cap, so products scaffolded before v0.9 are untouched). 600 bytes is three dense lines — a sketch, not a spec. ``

In step 2 (PO delegation), after `and a **phased** feature backlog.` insert:

```markdown
   **Phase 1 is a walking skeleton (v0.9):** the smallest VERTICAL slice that produces
   the product's primary artifact end to end — the thing a user would recognise as
   "it works" — with the first demonstrable output within **four features**. Every later
   phase is a shippable increment. Horizontal foundations (schema, auth, deploy) that
   ship no artifact do not qualify as Phase 1; `/build-fleet:plan-review` flags a later
   first output as a `[blocker]`. Keep each intent under `INTENT_MAX_BYTES` (600).
```

- [ ] **Step 8: `agents/product-owner.md` product tier.** After the sentence `Group rows under `## Phase N: <name> — STATUS: pending`. Sequence by dependency: …` add a paragraph:

```markdown
  **Phase 1 is a walking skeleton.** The smallest vertical slice that produces the
  product's primary artifact end to end, first demonstrable output within four
  features; every phase after it a shippable increment. A plan whose first provable
  checkpoint sits eleven features deep buys foundations for weeks and no evidence —
  the plan-review PO lens flags it as a `[blocker]`. Intents stay under the product's
  `INTENT_MAX_BYTES` (600 by default): three dense lines, not a paragraph with ADR cites.
```

- [ ] **Step 9: `commands/plan-finalize.md` split gate.** In step 5 add after the `B` definition:

```markdown
   **Split suggestions (v0.9).** In the same latest-cycle blocks collect every
   `  split-into: a, b, …` line (each sits under the finding it belongs to; the finding
   line carries its id in parentheses). For each proposed slug, it is **resolved** if
   `.sdd/_product/backlog.md` has a row `- [ ] <slug>` / `- [x] <slug>`, OR
   `.sdd/_product/DECISIONS.md` contains an ADR whose text cites that finding's id with
   the word `refuses` (e.g. "refuses product-owner-3: the split would …"). Call the
   count of unresolved split suggestions `S`.
```

In step 6 add a branch between b and c:

```markdown
   **b2. `ratify` (no `force`) with `S > 0`.** Refuse — a split the plan neither made
   nor refused:
   ```
   BUILD_FLEET_PLAN_FINALIZE_REFUSE: {"product":"<slug>","code":2,"reason":"split-unresolved","unresolved_splits":<S>}
   ```
   List each `split-into:` line with its finding id and which proposed slugs are
   missing; tell the user to either add the rows to `backlog.md` (and re-run
   `/build-fleet:plan-review`) or have the architect record a product ADR refusing the
   split by finding id — or override with `ratify force`.
```
and extend branch c to read `**c. `ratify` with `B = 0` and `S = 0`, OR `ratify force` (any B, any S).**`; in the `_PASS` line add `"accepted_splits":<S-if-force-else-0>`; in the dry-run output print `unresolved_splits` next to `open_blockers`.

- [ ] **Step 10: Suite and commit**

Run: `bash scripts/run-tests.sh | tail -1` → `suites: 29, failed: 0`.

```bash
git add scripts/intent-block.sh scripts/intent-block.test.sh hooks/scripts/validate-backlog-status.sh hooks/scripts/validate-backlog-status.test.sh workflows/plan-review.js scripts/workflow-plan-review-config.test.sh commands/new-product.md commands/plan-finalize.md agents/product-owner.md
git commit -m "feat(planning): walking-skeleton rule + lens, split_into with a ratify gate, intent byte cap

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LxywtRNJqBvQc4ZP23Deet"
```

---

### Task 11: Documentation of record (spec §3.12)

**Files:**
- Modify: `skills/sdd-protocol/SKILL.md`, `skills/sdd-protocol/references/product-tier.md`, `skills/review-rubric/SKILL.md`, `skills/adr/SKILL.md`, `docs/v0.2/CONTRACT.md`, `README.md`, `CHANGELOG.md`

- [ ] **Step 1: `skills/sdd-protocol/SKILL.md`.**

Workspace layout — add after the `REVIEW.md` line:
```
    REVIEW-archive.md    # scripts/review-rotate.sh (append-only). Cycles older than the previous one, rotated out of REVIEW.md at dispatch.
```
PROGRESS.md schema — add after `BUILD_CYCLE_BUDGET`:
```
CYCLE_TOTAL: <int>          # cumulative spec-review cycles, scribe-written, NEVER reset (not by resolve-escalation, not by park)
CYCLE_TOTAL_MAX: <int>      # /build-fleet:review refuses to dispatch at this count (default 6; 0 disables)
SPEC_MAX_KB: <int>          # optional — cap-spec-size hook: spec.md + acceptance.md byte budget (absent = no cap)
AC_MAX: <int>               # optional — validate-acceptance-count hook: distinct AC-<n> ids (absent = no cap)
LAST_REVIEW_OUTPUT_TOKENS: <int>   # scribe-written; /build-fleet:review refuses cost-runaway above 3× the header ceiling
```
REVIEW.md entry format — replace the block with:
```
## Cycle <N> — <role> — <iso8601>
- [blocker] (<role>-c<N>-1) <concern>
- [major] (<role>-c<M>-2) <concern>
  disposition: fix | adr ADR-<K>
- [minor] (<role>-c<N>-3) <concern>
status: concerns-raised | approved
```
and add the paragraph: `Finding ids are stable across cycles (`<role>-c<cycle>-<n>`; a re-raised finding keeps its id). Every surviving `[major]` carries a `disposition:` continuation line written by the review workflow's architect leg — `fix` (open: the PO must close it) or `adr ADR-K` (accepted: closed by that feature ADR). `status:` is informational since v0.9.`

REVIEW phase — replace the four numbered phases and the verdict list with:
```markdown
1. **Fan-out** — the read-only `reviewer` agent runs once per roster role (default
   architect, qa, coder) with that role's lens injected. Cycle 1 is a full review.
   **Cycle ≥ 2 is a delta review**: verify closure of your own prior `fix` findings and
   blockers (re-raise by original id if still open); new findings at blocker severity
   only. The open-major set never grows after cycle 1.
2. **Cross-examination** — refute or affirm peers' concerns, citing spec.md,
   acceptance.md or DECISIONS.md (an ADR is a substantive refutation).
3. **Survival vote** — pure script; a concern survives unless refuted by a
   different-role reviewer with substantive, cited reasoning.
4. **Disposition** — when majors survive, one architect leg classifies each as `adr`
   (a design trade-off; ADR text drafted) or `fix` (a gap the spec must close). The
   envelope's `decisions_appendix` carries the ADRs; the scribe writes them.
5. **Apply via scribe** — PROGRESS (`state_delta`, incl. `CYCLE_TOTAL` and
   `LAST_REVIEW_OUTPUT_TOKENS`), REVIEW.md entries, DECISIONS.md appendix,
   ESCALATION.md when non-null; releases `.workflow-in-flight`.

Verdict semantics (blocker meaning unchanged) plus **`finalize_ready`**:
- `finalize_ready: true` — zero open blockers AND zero `fix` majors. Next:
  `/build-fleet:finalize`.
- `clean` / `revise` with `finalize_ready: false` — next: `/build-fleet:revise`
  (hands the PO exactly the open items), then `/build-fleet:review`.
- `escalate` — the exhausting cycle with open blockers **or** open `fix` majors. The
  scribe writes ESCALATION.md (both listed), sets PHASE=ESCALATED, halts.
- `incomplete` / `invalid-args` — nothing written; re-run.

Before dispatch `/build-fleet:review` (a) refuses at `CYCLE_TOTAL_MAX`
(`cycle-total-exhausted`) and on `cost-runaway`, (b) rotates REVIEW.md so it holds only
the previous cycle (`scripts/review-rotate.sh`; older blocks go to `REVIEW-archive.md`),
(c) computes `next_adr_id` (`scripts/adr-index.sh --next`) and a real `now` (`date -u`).
```
FINALIZE — replace `Permitted only when the most recent review cycle is fully approved with no open blockers (`[major]` items each fixed or ADR-recorded).` with `Permitted only when `scripts/finalize-gate.sh` passes: every roster role has a current-cycle block, zero `[blocker]` lines, zero `[major]` lines dispositioned `fix` (or undispositioned), and every `disposition: adr ADR-N` cites an ADR present in the feature DECISIONS.md. `status:` lines are not evaluated. The rule is the rubric's, computed deterministically, and is the same rule the workflow reports as `finalize_ready`.`

State-machine diagram — under the diagram add: `The REVIEW loop's per-cycle ritual is `/build-fleet:review` → `/build-fleet:revise` → `/build-fleet:review` …; the cumulative bound is `CYCLE_TOTAL_MAX`.`

Hard gates — add items 8 and 9:
```
8. spec.md / acceptance.md cannot grow past `SPEC_MAX_KB` while the field is present;
   over budget the answer is a split. *(cap-spec-size, PreToolUse Write|Edit.)*
9. acceptance.md cannot name more than `AC_MAX` distinct criteria while the field is
   present. *(validate-acceptance-count, PostToolUse.)*
```
Escalation section — replace `resets the exhausted cycle counter` with `resets the exhausted cycle counter (never `CYCLE_TOTAL`)`.

Operating principles — after the "Escalate, don't loop forever" bullet add: `- **Converge, don't re-litigate.** Cycle 1 is the only full review. After it, reviewers verify closure and may add blockers only; majors are dispositioned once (`fix` or `adr`) and an accepted trade-off is contested only as a blocker against the ADR by id.`

Also update the `commands/` count in this skill's opening if it names one, and the "Their `AgentDefinition.tools` omits `Write`/`Edit`; `AgentDefinition.skills` preloads `review-rubric`" sentence → `They run as the read-only `reviewer` agent (Read/Grep/Glob — the runtime's `agent()` has no tools option, so isolation lives in the agent definition); the rubric is mirrored in its body.`

- [ ] **Step 2: `skills/sdd-protocol/references/product-tier.md`.** Under "### PLAN_REVIEW" append: `Findings may carry `split_into` (proposed sibling slugs) rendered as a `  split-into:` line; the PO lens flags a Phase 1 that is not a walking skeleton (first demonstrable output later than the 4th feature) as a `[blocker]`, the qa lens flags an intent implying more than ~15 criteria as an over-scope `[major]` that must name its split.` Under "### PLAN_FINALIZE" add a bullet: `- `ratify` also refuses (`split-unresolved`) while a latest-cycle `split-into:` slug is neither a backlog row nor refused by a product ADR citing the finding id; `ratify force` overrides and records it.` Under "Per-feature intent" add: `- **Byte cap.** `intent-block.sh` emits `INTENT_BYTES`; when `_product/PROGRESS.md` carries `INTENT_MAX_BYTES` (scaffolded at 600 for new products), `validate-backlog-status` refuses a backlog write with a longer intent. An intent is a sketch.` Under "Layout and ownership" PROGRESS line mention `INTENT_MAX_BYTES`.

- [ ] **Step 3: `skills/review-rubric/SKILL.md`.** Replace the paragraph beginning `The same table appears verbatim in `architect.md` and `qa.md` prompt bodies` with: `The same table appears verbatim in `architect.md`, `qa.md` and `reviewer.md` prompt bodies — a deliberate duplication. Nothing preloads a skill into a workflow agent (the runtime's `agent()` has no skills option), so the in-body copies are the load-bearing ones on every path; this skill is canonical and `scripts/rubric-drift.test.sh` fails the suite on any drift.` Below the "How a major becomes an ADR" section add:

```markdown
## Delta review and disposition (v0.9)

- **Ids are stable.** `<role>-c<cycle>-<n>`; a re-raised finding keeps its original id.
- **Cycle 1 is the only full review.** From cycle 2 a reviewer verifies closure of its
  own prior `fix` findings and blockers, and may raise new findings at `[blocker]`
  severity only (plus advisory minors). A new `[major]` on a delta cycle is not allowed:
  the open-major set only shrinks.
- **Every surviving major is dispositioned once**, in the workflow, by the architect:
  `disposition: adr ADR-N` (a design trade-off — accepted, closed, ADR written by the
  scribe) or `disposition: fix` (a gap the PO must close in the spec). Rule of thumb: if
  closing it would make the spec longer without making the system more correct, it is
  an `adr`; if a test could fail because of it, it is a `fix`.
- **An accepted trade-off is contested only as a `[blocker]` against the ADR by id.**
- **`status:` is informational.** The finalize gate reads `[blocker]` lines and
  `disposition:` lines (`scripts/finalize-gate.sh`).
```
Also update the entry-shape block to the v0.9 grammar (ids + disposition line) as in Step 1.

- [ ] **Step 4: `skills/adr/SKILL.md`.** In "When to write an ADR" add: `- A review `[major]` dispositioned `adr` by the review workflow's architect leg — the scribe appends the drafted ADR to the **feature** DECISIONS.md (`decisions_appendix`); the REVIEW.md line cites it as `disposition: adr ADR-N`. Disposition ADRs are always feature-scoped.` In the entry format add an optional metadata line after `- **Cycle:**`: `- **Dispositions:** <finding id> (raised by <role>) — accepted as a trade-off at review cycle <N>   ← feature scope, review-workflow ADRs only`.

- [ ] **Step 5: `docs/v0.2/CONTRACT.md` §6.** In the envelope JSONC add after `"verdict"`: `"finalize_ready": false,             // bool — v0.9. zero open blockers AND zero fix-dispositioned majors (the finalize gate's rule)`; after `"review_entries"`: `"decisions_appendix": null,         // string | null — v0.9. ADR blocks the scribe appends verbatim to the workspace DECISIONS.md (mirrors impl_notes_appendix)`; in `state_delta` add `"CYCLE_TOTAL": 3, "LAST_REVIEW_OUTPUT_TOKENS": 41200`; in `estimated_cost_actual` note `input_tokens` may be `null` (runtime exposes output only); in `escalation_payload` note `open_majors`. Under "Workflow return object" add `finalize_ready`, `open_majors`, `adrs_written`, `output_tokens`, `cycle_total`, and the `incomplete` reason `disposition-incomplete`. Add a dated note under "Phase 6 empirical findings": `v0.9 resolves the "verdict vs. majors" observation: `finalize_ready` is computed in-workflow and the gate script enforces the same rule.`

- [ ] **Step 6: `README.md`.** Line ~169: `seven craft skills, ten gate-enforcing hooks` → `seven craft skills, twelve gate-enforcing hooks`; line ~208: `all seven `build-fleet:*` agents` → `all eight `build-fleet:*` agents`; the `review.js` bullet under "Dynamic workflows" → `Fan-out read-only reviewers (architect/qa/coder lenses; cycle ≥ 2 is a delta review) → adversarial **cross-examination** → **survival vote** → architect **disposition** of surviving majors (`adr` or `fix`) → scribe applies the verdict, `finalize_ready` and the ADRs. Between cycles `/build-fleet:revise` hands the PO exactly the open items; REVIEW.md is rotated to the previous cycle at dispatch.`; in the commands table (search for the `/build-fleet:review` row) add a row for `/build-fleet:revise` — "Hand the product-owner exactly the open review items to close" — and bump any "22 commands" mention to 23. Also add `REVIEW-archive.md` wherever the `.sdd/` layout is listed.

- [ ] **Step 7: `CHANGELOG.md`** — insert above `## [0.8.0]`:

```markdown
## [0.9.0] — <today's date>

The **convergent review** release. The REVIEW loop is now bounded and monotone: a
rubric-only finalize gate, delta review from cycle 2, in-workflow ADR disposition of
majors, read-only reviewers, bounded review inputs, spec/criteria/cumulative-cycle caps,
a real clock in the dispatching commands, and walking-skeleton planning. Design:
`docs/history/2026-09-02-convergent-review.md` (grounded in the tap pilot, where a
test-fixture feature took ~7 review cycles and one cycle cost ~866k tokens).

### Added
- **`agents/reviewer.md`** — the read-only reviewer every `review.js` leg runs as (Read/Grep/Glob; lens injected by the workflow). Ends double-written REVIEW.md blocks, fabricated timestamps and ungated writes.
- **Disposition leg** in `workflows/review.js` — surviving majors become `disposition: adr ADR-N` (ADR drafted, scribe-written via the new envelope field `decisions_appendix`) or `disposition: fix`. Finding ids are stable (`<role>-c<cycle>-<n>`).
- **`finalize_ready`** in the review envelope/return, and **`scripts/finalize-gate.sh`** — the deterministic gate `/build-fleet:finalize` now calls (harness: `finalize-gate.test.sh`).
- **`/build-fleet:revise`** — dispatches the PO with exactly the current cycle's blockers + `fix` majors and the size budget.
- **`scripts/review-rotate.sh`** — positional rotation of REVIEW.md into `REVIEW-archive.md` at dispatch; **`scripts/adr-index.sh`** — ADR id/title index and `--next`.
- **Hooks `cap-spec-size` (PreToolUse) and `validate-acceptance-count` (PostToolUse)** — `SPEC_MAX_KB` / `AC_MAX`, scaffolded by tier (standard 24 KB / 15, large 48 KB / 30); absent = no cap; refusal says split.
- **`CYCLE_TOTAL` / `CYCLE_TOTAL_MAX`** — cumulative, never reset; `/build-fleet:review` refuses `cycle-total-exhausted` before dispatch. **`LAST_REVIEW_OUTPUT_TOKENS`** recorded from the runtime budget; `cost-runaway` refusal (override with `--override-cost`).
- **Planning:** walking-skeleton rule for Phase 1; plan-review lenses flag a late first output (`[blocker]`) and over-scoped intents with a named `split_into`; `plan-finalize ratify` refuses `split-unresolved`; `INTENT_MAX_BYTES` (600) intent cap via `validate-backlog-status`; `intent-block.sh` emits `INTENT_BYTES`.
- Tests: `workflow-review-convergence.test.sh`, `lens-drift.test.sh`, `review-rotate.test.sh`, `adr-index.test.sh`, `finalize-gate.test.sh`, `cap-spec-size.test.sh`, `validate-acceptance-count.test.sh`; new cases in the stop-tests, intent-block, backlog-status and plan-review-config harnesses.

### Changed
- **Finalize gate is rubric-only:** zero open blockers AND every major fixed-or-ADR'd. The "every block `status: approved`" requirement is gone; `status:` is informational. `not-approved` is no longer emitted (kept in the grammar).
- **Delta review:** from cycle 2 reviewers verify closure by id and may raise new findings at blocker severity only. Escalation fires on the exhausting cycle when blockers **or** `fix` majors remain (ESCALATION.md lists both).
- **Product-owner context diet:** `new-feature` passes the binding stack + the ADR index, not the whole product DECISIONS.md, and states the size budget.
- Dispatching commands compute `now` with `date -u` (`Bash(date:*)`); the scribe appends with anchored Edits and appends absent `state_delta` keys.
- Role agents' `## Review lens` sections are mirrored in `review.js` (`lens-drift.test.sh`); their REVIEW.md append instructions are scoped to non-workflow paths; descriptions refreshed.

### Fixed
- Workflow reviewers were never tool-restricted (the runtime's `agent()` has no `tools` option), contrary to the protocol text — resolved by the reviewer agent.
- Guessed timestamps in `.sdd/` (commands had no clock).
- The `clean → finalize` recommendation that the gate then refused.
- Ride-along fixes since 0.8.0 (unreleased on `main`): distinct `## Change-Cycle N` heading; bug-lane source unlock at `STATUS=FIXED`; plan-review `LENS` TDZ; stop-tests prefers the project `.venv`; stop-tests stands down in the BUILD tests-first window (now with a harness case).

**Compatibility.** `SDD_SCHEMA` stays `1`. Additive PROGRESS fields (`CYCLE_TOTAL`, `CYCLE_TOTAL_MAX`, `SPEC_MAX_KB`, `AC_MAX`, `LAST_REVIEW_OUTPUT_TOKENS`; product `INTENT_MAX_BYTES`) — all read-with-default; a new optional workspace file `REVIEW-archive.md`; envelope fields `finalize_ready` and `decisions_appendix`; REVIEW.md lines gain `(id)` and `disposition:` (old blocks still parse — an undispositioned legacy major reads as open). Signal grammar: new `BUILD_FLEET_REVIEW_ROTATED`, `BUILD_FLEET_FINALIZE_GATE`, `BUILD_FLEET_REVISE_DISPATCHED`; new refusal reasons `cycle-total-exhausted`, `cost-runaway`, `majors-open`, `nothing-to-revise`, `split-unresolved`; `not-approved` no longer emitted. In-flight 0.8.0 features continue: their next `/build-fleet:review` rotates, dispositions and stamps `CYCLE_TOTAL` from `CYCLE`.
```

- [ ] **Step 8: Suite and commit**

Run: `bash scripts/run-tests.sh | tail -1` → `suites: 29, failed: 0`.

```bash
git add skills/sdd-protocol/SKILL.md skills/sdd-protocol/references/product-tier.md skills/review-rubric/SKILL.md skills/adr/SKILL.md docs/v0.2/CONTRACT.md README.md CHANGELOG.md
git commit -m "docs: v0.9.0 convergent review — protocol, rubric, ADR, contract, README, CHANGELOG

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LxywtRNJqBvQc4ZP23Deet"
```

---

### Task 12: Release v0.9.0 — validate live, bump, merge, tag (spec §4, §6)

**Files:**
- Modify: `.claude-plugin/plugin.json` (`version`, `description`); `.claude-plugin/marketplace.json` carries no version field — verify with `jq . .claude-plugin/marketplace.json` and leave it unchanged.

- [ ] **Step 1: Live validation on the pilot, from the worktree.** With no tap review in flight (check `/workflows` in the tap sessions and that `.sdd/fixture-and-harness/.workflow-in-flight` is empty or absent), start a tap session against the worktree:

```bash
cd ~/Projects/tap && claude --plugin-dir ~/build-fleet-0.9
```
Run `/build-fleet:review`, then `/build-fleet:revise` if not finalize-ready, then `/build-fleet:review` again. Confirm: `BUILD_FLEET_REVIEW_ROTATED` printed and `REVIEW-archive.md` created; the new blocks carry `(id)` and `disposition:` lines with no reviewer-written duplicates; `DECISIONS.md` gained `## ADR-N:` blocks for `adr` dispositions; PROGRESS has `CYCLE_TOTAL` and `LAST_REVIEW_OUTPUT_TOKENS`; the run's `output_tokens` is well under the previous ~866k; `/build-fleet:finalize` relays `BUILD_FLEET_FINALIZE_GATE`. Record the observed `output_tokens` in the CHANGELOG entry's first paragraph.

- [ ] **Step 2: Bump the manifest.** In `.claude-plugin/plugin.json` set `"version": "0.9.0"` and extend `description` with `, a convergent bounded review loop (delta review, in-workflow ADR disposition, rubric-only finalize gate, spec/criteria/cycle caps)`.

- [ ] **Step 3: Final checks**

```bash
for f in workflows/*.js; do node --check "$f" && bash scripts/workflow-determinism-lint.sh "$f"; done
bash scripts/run-tests.sh | tail -1        # suites: 29, failed: 0
grep -n '"version"' .claude-plugin/plugin.json   # 0.9.0
grep -n '^## \[0.9.0\]' CHANGELOG.md
git status --short                          # clean except plugin.json
```

- [ ] **Step 4: Commit the release**

```bash
git add .claude-plugin/plugin.json
git commit -m "release: v0.9.0 — convergent review

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LxywtRNJqBvQc4ZP23Deet"
```

- [ ] **Step 5: Merge to main and tag** — only when no tap session has a review in flight (the main working tree is what they load):

```bash
cd ~/build-fleet
git stash push -m "pre-0.9.0 identical ride-along diff" -- hooks/scripts/stop-tests.sh workflows/review.js
git merge --ff-only release/0.9.0
git stash drop
git tag -a v0.9.0 -m "build-fleet v0.9.0 — convergent review"
git worktree remove ../build-fleet-0.9
git branch -d release/0.9.0
bash scripts/run-tests.sh | tail -1        # suites: 29, failed: 0 on main
```
Pushing `main` and the tag is Ray's call (`git push origin main --tags`); CI pins the tag to `plugin.json`'s version.

---

## Spec coverage map

| Spec section | Task |
|---|---|
| §3.1 ids + line grammar | 3 (helpers), 5 (gate parses), 11 (docs) |
| §3.2 review.js | 3, 8 (args from the command) |
| §3.3 scribe | 4 |
| §3.4 finalize gate + status | 5 |
| §3.5 reviewer agent + role agents | 2, 3 (lens-drift) |
| §3.6 rotation | 8 |
| §3.7 PO context diet + adr-index | 7 |
| §3.8 caps + CYCLE_TOTAL | 7 (scaffold), 8 (dispatch refusal), 9 (hooks) |
| §3.9 clock + cost | 5, 6, 7, 8 |
| §3.10 revise | 6 |
| §3.11 planning | 10 |
| §3.12 docs, §4 release | 11, 12 |
| §5 ride-along + order | 1, task order |
| §6 testing | every task; the finalize-gate harness replaces the spec's smoke-walk (the gate is a script now) |
