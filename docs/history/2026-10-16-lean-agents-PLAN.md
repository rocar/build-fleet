# Lean Agents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Routing-only descriptions (≤40 words) for the 8 agents and 7 skills, agent bodies cut to about 800 words without losing a single rule, and a guard test that keeps it that way.

**Architecture:** A guard test (`scripts/agent-surface.test.sh`) checks descriptions, body caps, pinned `tools:` lists and a rules inventory (`docs/history/2026-10-16-lean-agents-RULES.md`) in which every rule of every agent is quoted before the cut and re-quoted from the new body after it. Agents are cut one per task; a `PENDING` list in the test exempts agents not yet cut. Judgement is checked by a planted-defect review run before and after.

**Tech Stack:** markdown agent/skill files with YAML frontmatter; bash 3.2 + BSD/GNU awk/sed/grep; `claude -p` for live runs.

**Spec:** `docs/history/2026-10-16-lean-agents.md` (approved 2026-10-16).

## Global Constraints

- **Rules are never cut, only narration** (spec D3a). A rule: an imperative (must, never, refuse, only, always, do not), a signal line, an ownership line. Rewording a rule's prose is allowed; dropping or weakening it is not.
- **Kept verbatim:** the severity-rubric table (architect, qa, reviewer); the text between `<!-- verified-rule:start -->` and `<!-- verified-rule:end -->`; every `## Review lens` section; every signal line in its exact format. `scripts/rubric-drift.test.sh` and `scripts/lens-drift.test.sh` stay green after every task.
- Descriptions: one line, ≤40 words, no `/build-fleet:`; agents' contain `Do NOT use`. Use the exact descriptions given in each task.
- Body cap 800 words (frontmatter excluded, a bare `|` not counted). An agent that cannot fit gets `name:cap:reason` in the test's `CAPS`, with cap = (body words after the cut) × 1.1 rounded up, never above today's length.
- `tools:` and `model:` lines are not edited.
- No command or workflow edits, except a one-line dispatch hint the task names (spec §3.2 "Not moved"); this plan names none.
- No milestone jargon in descriptions or bodies.
- Agent body and description change in the same commit (CLAUDE.md hard rule).
- Commit attribution line: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Work on `release/0.12.0` in `~/build-fleet-0.12`; no merge, tag or push.

## Review Focus

1. **A rule reworded into something weaker** ("must" → "should", "never" → "avoid"). The inventory's quote check passes on the new wording; only reading catches it. Expected: no rule weakens. The final reviewer reads every `→` pair in RULES.md (Task 12).
2. **A rule that lived in a worked example** (a REVIEW.md block shown as an example carries the `disposition:` grammar). Cutting the example drops the rule. Expected: the grammar survives as a stated rule. Pinned by inventory lines for each `disposition`/`refuted-by` grammar item (Task 3).
3. **Workflow-mode prompts quote agent text.** `workflows/*.js` may name an agent section ("per agents/scribe.md step 4"). Expected: every section a workflow names still exists. Test: Task 3 Step 3's grep, re-run in Task 11.
4. **Routing by description in a user's session**: "write tests for X" must still pick qa, not coder. Expected: coder's says "tests (use qa)". Checked by reading in Task 12.
5. **A single planted-defect run per side is noisy.** Expected: report both runs' findings side by side; a defect lost is a regression only if the "before" run raised it. Task 2 and Task 12.

---

## File structure

| File | Responsibility | Task |
|---|---|---|
| `scripts/agent-surface.test.sh` (new) | the guard | 1 (then each agent task edits `PENDING`/`CAPS`) |
| `docs/history/2026-10-16-lean-agents-EVAL.md` (new) | planted-defect answer key and both runs' results; live-run results | 2, 12 |
| `docs/history/2026-10-16-lean-agents-RULES.md` (new) | the rules inventory | 3, then each agent task |
| `agents/*.md` | descriptions and bodies | 4–10 |
| `skills/*/SKILL.md` | descriptions only | 11 |
| `scripts/drift-wiring.test.sh` | qa's description phrase | 6 |
| `CHANGELOG.md`, `CLAUDE.md` | release notes, layout line | 11 |

---

### Task 1: The guard test

**Files:** Create `scripts/agent-surface.test.sh`.

**Interfaces:**
- Produces: `PENDING` (space-separated agent names and `skill:<name>` entries exempt from the description/body/inventory checks; `tools:` is always checked) and `CAPS` (lines `name:cap:reason`), both edited by later tasks. Inventory line grammar: `- [ ] <agent> R<n>: "<old quote>"` and `- [x] <agent> R<n>: "<old quote>" → "<new quote>"`; the `<new quote>` must appear verbatim on one line of `agents/<agent>.md`.

- [ ] **Step 1: Write the test**

Create `scripts/agent-surface.test.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# Agent and skill surface guard (docs/history/2026-10-16-lean-agents.md §3.3):
#   descriptions are one line, at most 40 words, name no hidden step, and (agents) say
#   "Do NOT use"; agent bodies fit their word cap; tools: allowlists never widen; every
#   line of the rules inventory is checked off.
# Run: bash scripts/agent-surface.test.sh   (exit 0 = all pass)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
ok() { pass=$((pass+1)); printf 'ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf 'FAIL %s — %s\n' "$1" "$2"; }

# Agents whose bodies and descriptions are not cut yet; each lean task removes its name.
PENDING="architect classifier coder devops product-owner qa reviewer scribe skill:adr skill:review-rubric skill:sdd-diagnosis-template skill:sdd-protocol skill:sdd-spec-template skill:skill-routing skill:test-plan"

# Body caps: name:cap:reason. Absent ⇒ 800.
CAPS="
"
# Recorded allowlists (exact, order included). A deliberate change edits this line too.
TOOLS="
architect:Read, Grep, Glob, Edit
classifier:Read, Grep, Glob
coder:Read, Grep, Glob, Edit, Write, Bash
devops:Read, Grep, Glob, Edit, Write, Bash
product-owner:Read, Grep, Glob, Edit, Write
qa:Read, Grep, Glob, Edit, Write, Bash
reviewer:Read, Grep, Glob
scribe:Read, Write, Edit
"
fm() { awk -v k="$2" '/^---$/{n++; next} n==1 && index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); print v; exit }' "$1"; }
words() { printf '%s\n' "$1" | awk '{ for (i = 1; i <= NF; i++) if ($i != "|") w++ } END { print w + 0 }'; }
body_words() { awk '/^---$/{n++; next} n>=2' "$1" | awk '{ for (i = 1; i <= NF; i++) if ($i != "|") w++ } END { print w + 0 }'; }
pending() { case " $PENDING " in *" $1 "*) return 0 ;; esac; return 1; }

check_desc() {  # <file> <name> <agent?>
  local d n; d=$(fm "$1" description)
  case "$d" in ''|'>'*|'|'*) no "$2 description one line" "missing or folded"; return ;; esac
  n=$(words "$d")
  if [ "$n" -le 40 ]; then ok "$2 description <= 40 words ($n)"; else no "$2 description <= 40 words" "$n words"; fi
  case "$d" in *'/build-fleet:'*) no "$2 description names no hidden step" "contains /build-fleet:" ;; *) ok "$2 description names no hidden step" ;; esac
  if [ "$3" = agent ]; then
    case "$d" in *'Do NOT use'*) ok "$2 description says Do NOT use" ;; *) no "$2 description says Do NOT use" "missing" ;; esac
  fi
}

for f in "$ROOT"/agents/*.md; do
  a=$(basename "$f" .md)
  want=$(printf '%s\n' "$TOOLS" | awk -F: -v a="$a" '$1 == a { print substr($0, length(a) + 2) }')
  got=$(fm "$f" tools)
  if [ -n "$want" ] && [ "$got" = "$want" ]; then ok "$a tools pinned"; else no "$a tools pinned" "want [$want] got [$got]"; fi
  if pending "$a"; then continue; fi
  check_desc "$f" "$a" agent
  cap=$(printf '%s\n' "$CAPS" | awk -F: -v a="$a" '$1 == a { print $2 }'); [ -n "$cap" ] || cap=800
  n=$(body_words "$f")
  if [ "$n" -le "$cap" ]; then ok "$a body <= $cap words ($n)"; else no "$a body <= $cap words" "$n words"; fi
done
for f in "$ROOT"/skills/*/SKILL.md; do
  s=$(basename "$(dirname "$f")")
  pending "skill:$s" && continue
  check_desc "$f" "skill $s" skill
done
# Rules inventory: "- [ ] <agent> R<n>: "<old>"" before the cut; "- [x] <agent> R<n>:
# "<old>" → "<new>"" after it. Every [x] line's <new> quote must appear verbatim on one
# line of that agent's file; no [ ] line may remain for an agent that is not pending.
inv="$ROOT/docs/history/2026-10-16-lean-agents-RULES.md"
if [ -f "$inv" ]; then
  bad=0; n=0
  while IFS= read -r line; do
    a=$(printf '%s' "$line" | sed -E 's/^- \[[ x]\] ([^ ]+) .*/\1/')
    case "$line" in
      '- [ ] '*) pending "$a" || { no "rule kept: $line" "unchecked"; bad=1; } ;;
      '- [x] '*)
        n=$((n+1))
        q=$(printf '%s' "$line" | sed -n 's/.*→ "\(.*\)"[[:space:]]*$/\1/p')
        if [ -z "$q" ] || [ ! -f "$ROOT/agents/$a.md" ] || ! grep -qF -- "$q" "$ROOT/agents/$a.md"; then
          no "rule kept: $line" "new quote not found in agents/$a.md"; bad=1
        fi ;;
    esac
  done < "$inv"
  [ "$bad" -eq 0 ] && ok "rules inventory: $n checked, all found"
fi

printf '\npassed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Watch it pass with everything pending, and fail without**

Run: `bash scripts/agent-surface.test.sh | tail -1`
Expected: `passed=8 failed=0` (the eight `tools pinned` checks).

Then prove it can fail: `sed 's/^PENDING=".*"/PENDING=""/' scripts/agent-surface.test.sh > /tmp/as.sh && bash /tmp/as.sh | tail -1`
Expected: `passed=26 failed=28` against today's files. And widen one list in a copy (`tools: Read, Grep, Glob, Edit, Bash` for architect) to see `FAIL architect tools pinned`. Restore nothing in the repo (only `/tmp` copies were changed).

- [ ] **Step 3: Commit**

```bash
chmod +x scripts/agent-surface.test.sh
git add scripts/agent-surface.test.sh
git commit -m "test(agents): surface guard — description length and shape, body caps, pinned tools, rules inventory

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Planted-defect baseline (before any agent edit)

**Files:** Create `docs/history/2026-10-16-lean-agents-EVAL.md`. Scratch: `$SCRATCH/lean/` (the session scratchpad), `/tmp/bf-lean-before`.

**Interfaces:**
- Produces: the "before" findings table that Task 12 compares against, and `$SCRATCH/lean/make-fixture.sh` (reused in Task 12).

- [ ] **Step 1: Snapshot the plugin as it is now**

```bash
SC=/private/tmp/claude-502/-Users-rocconno-build-fleet/fd249f92-d7b5-4f4f-95ce-8f535743c836/scratchpad/lean
mkdir -p "$SC/plugin-before" && git -C ~/build-fleet-0.12 archive HEAD | tar -x -C "$SC/plugin-before"
```

- [ ] **Step 2: Write the fixture builder**

Create `$SC/make-fixture.sh` with exactly this content (it is scratch, not committed; its answer key goes into EVAL.md):

```bash
#!/usr/bin/env bash
# make-fixture.sh <dir> — a fresh repo with one draft feature, csv-import, whose spec
# carries three planted defects (answer key in the lean-agents plan, Task 2):
#   D1  AC-2 and AC-3 contradict (empty rows skipped vs. empty rows are an error)
#   D2  no behaviour stated for a missing or unreadable input file
#   D3  AC-4 is untestable ("imports quickly")
set -euo pipefail
d="$1"; rm -rf "$d"; mkdir -p "$d"; cd "$d"
git init -q; git config user.email fixture@example.com; git config user.name fixture
cat > importer.py <<'PY'
def import_csv(path):
    raise NotImplementedError
PY
mkdir -p tests; printf 'def test_placeholder():\n    assert True\n' > tests/test_placeholder.py
s=csv-import; mkdir -p .sdd/$s
cat > .sdd/$s/spec.md <<'MD'
STATUS: DRAFT

# Spec: csv-import

## Overview

`import_csv(path)` reads a CSV file of contacts (name, email) and returns a list of
`{"name": str, "email": str}` dicts, for the address-book CLI.

## Goals

- Turn a contacts CSV into records the CLI can store.

## Non-goals

- Writing CSV. De-duplicating contacts.

## Behavior

- The first row is a header and is not returned.
- Each later row becomes one record, in file order.
- Empty rows are skipped.
- A row whose email has no `@` raises `ValueError` naming the row number.

## Interfaces / Contracts

- `import_csv(path: str) -> list[dict]` in `importer.py`.

## Constraints

- Standard library only.

## Risks

- Large files.

## Acceptance Criteria

See [acceptance.md](./acceptance.md).
MD
cat > .sdd/$s/acceptance.md <<'MD'
# Acceptance Criteria — csv-import

- **AC-1**: A file with a header and two valid rows returns two records in file order.
- **AC-2**: Empty rows are skipped; they produce no record and no error.
- **AC-3**: Any empty row raises `ValueError` naming its row number.
- **AC-4**: `import_csv` imports quickly.
- **AC-5**: A row whose email has no `@` raises `ValueError` naming its row number.
MD
printf '# Architecture Decisions — %s\n\nAppend-only log.\n' $s > .sdd/$s/DECISIONS.md
printf '# Test Plan — %s\n' $s > .sdd/$s/TEST_PLAN.md
printf '# Implementation Notes — %s\n' $s > .sdd/$s/IMPL_NOTES.md
printf '# Review Log — %s\n\nAppend-only.\n' $s > .sdd/$s/REVIEW.md
cat > .sdd/$s/PROGRESS.md <<MD
SDD_SCHEMA: 1
FEATURE: $s
PHASE: SPEC
CYCLE: 0
CHANGE_CYCLE: 0
BUILD_CYCLE: 0
TIER: standard
BUILD_MODE: standard
RISK: low
REVIEW_ROLES: architect, qa, coder
REVIEW_CYCLE_BUDGET: 3
BUILD_CYCLE_BUDGET: 3
CYCLE_TOTAL: 0
CYCLE_TOTAL_MAX: 6
DRIFT_GATE: on
UPDATED: 2026-10-16T00:00:00Z
MD
printf '%s\n' $s > .sdd/ACTIVE
git add -A; git commit -qm fixture
```

- [ ] **Step 3: Run the review once on the fixture with the old plugin**

```bash
bash "$SC/make-fixture.sh" /tmp/bf-lean-before
cd /tmp/bf-lean-before && env -u ANTHROPIC_API_KEY claude -p --plugin-dir "$SC/plugin-before" --add-dir "$SC/plugin-before" \
  --permission-mode acceptEdits --allowedTools=Bash,Read,Write,Edit,Task,Skill,Workflow \
  "Use the Skill tool to run build-fleet:review once for the active feature (csv-import), wait for the workflow to finish, report its return object, and stop. Do not revise or finalize." \
  > /tmp/bf-lean-before/run.log 2>&1
```

Expected: `.sdd/csv-import/REVIEW.md` holds `## Cycle 1 — <role> —` blocks for architect, qa and coder, and `PROGRESS.md` has `CYCLE: 1`. If the workflow cannot load from the plugin dir, rerun once (the run already passes `--add-dir`); if it fails twice, record the failure in EVAL.md and stop the task as blocked.

- [ ] **Step 4: Score it and write EVAL.md**

Create `docs/history/2026-10-16-lean-agents-EVAL.md`:

````markdown
# Lean agents — evaluation record

## Planted-defect review

Fixture: `make-fixture.sh` (feature `csv-import`, draft spec, debate review, roster
architect, qa, coder). Answer key:

| Id | Planted defect | Raised when a finding… |
|---|---|---|
| D1 | AC-2 and AC-3 contradict (empty rows skipped vs. an error) | names AC-2 or AC-3 and the conflict between them |
| D2 | No behaviour for a missing or unreadable input file | names the missing/unreadable file case |
| D3 | AC-4 "imports quickly" is untestable | names AC-4's vagueness or untestability |

| Defect | Before: raised by (severity) | After: raised by (severity) |
|---|---|---|
| D1 | <roles and severities from REVIEW.md, or "not raised"> | (Task 12) |
| D2 | … | (Task 12) |
| D3 | … | (Task 12) |

Other findings before: <count by severity>. After: (Task 12).
````

Fill the "Before" column from `/tmp/bf-lean-before/.sdd/csv-import/REVIEW.md` (surviving findings only, i.e. the ones the review's summary/return object lists as surviving; record each role that raised it and its severity).

- [ ] **Step 5: Commit**

```bash
git add docs/history/2026-10-16-lean-agents-EVAL.md
git commit -m "docs(eval): lean agents — planted-defect answer key and the before run

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The rules inventory

**Files:** Create `docs/history/2026-10-16-lean-agents-RULES.md`.

**Interfaces:**
- Consumes: Task 1's inventory grammar.
- Produces: one `- [ ] <agent> R<n>: "<quote>"` line per rule, grouped under `## <agent>`; agent tasks tick them.

- [ ] **Step 1: List candidate rule lines per agent**

```bash
for a in architect classifier coder devops product-owner qa reviewer scribe; do
  echo "== $a"
  /usr/bin/grep -nE '(must|MUST|never|Never|NEVER|refuse|Refuse|REFUSE|only|ONLY|always|Always|Do NOT|do not|not allowed|forbidden|BUILD_FLEET_|SCRIBE_|disposition:|refuted-by:|status:)' "agents/$a.md"
done > /tmp/rule-candidates.txt; wc -l /tmp/rule-candidates.txt
```

- [ ] **Step 2: Curate into RULES.md**

Read each agent body in full (not only the grep hits: a rule can be phrased without a keyword, e.g. a numbered procedure step or a table row). Write `docs/history/2026-10-16-lean-agents-RULES.md`:

```markdown
# Lean agents — rules inventory

Every rule in each agent body before the cut (spec D3a). After an agent's cut, each line
becomes `- [x] <agent> R<n>: "<old quote>" → "<new quote>"`, where the new quote is
copied from one line of the new body. `scripts/agent-surface.test.sh` checks every new
quote is present. Rewording is allowed; weakening is not.

## architect

- [ ] architect R1: "<short exact quote from today's body>"
…
```

One line per rule. A quote is a short exact fragment (enough to identify the rule, on one line of today's file). Mirrored sections (rubric table, verified rule, review lens) get one line each naming the section, since the drift tests already pin their text. Include, by name (spec §3.2): qa's `git stash create` snapshot and its "never a bare `git checkout`"; coder's refuse-to-begin and `BUILD_FLEET_CODER_REFUSE`; the CHANGE_REVIEW disposition contract in product-owner, qa and architect; architect's brownfield baseline rules; qa's drift-gate repair duties; every signal line each agent emits; every "files you may / must never write" line.

- [ ] **Step 3: Note every agent section a workflow or command names**

```bash
/usr/bin/grep -noE 'agents/[a-z-]+\.md[^`"]{0,60}' workflows/*.js commands/*.md | sort -u > /tmp/agent-refs.txt; cat /tmp/agent-refs.txt
```

For each reference that names a section or step ("agents/scribe.md step 4", "agents/devops.md → Completion signal"), add an inventory line for that section's heading text (e.g. `- [ ] devops R12: "## Completion signal"`), so the heading must survive.

- [ ] **Step 4: Verify and commit**

Run: `bash scripts/agent-surface.test.sh | tail -1`
Expected: `passed=8 failed=0` (all agents pending, so unchecked lines are allowed).

```bash
git add docs/history/2026-10-16-lean-agents-RULES.md
git commit -m "docs(agents): rules inventory of every agent body before the cut

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Agent tasks (4–10): the common procedure

Each agent task below gives the agent's new description and its cut map. Every agent task follows these steps:

- [ ] **A. RED.** Remove the agent from `PENDING` in `scripts/agent-surface.test.sh`. Run `bash scripts/agent-surface.test.sh | grep -E '^FAIL|passed'`. Expected: FAIL lines for that agent's description (unless it is already ≤40 words and shaped), body (if over 800) and each of its unchecked inventory lines.
- [ ] **B. Description.** Replace the `description:` line in the frontmatter with the exact text the task gives (one line).
- [ ] **C. Body.** Rewrite the body per the task's cut map and the Global Constraints. Keep mirrored sections byte-for-byte. Keep every heading listed in the inventory. Keep every signal line in its exact format.
- [ ] **D. Inventory.** Tick each of the agent's lines in RULES.md: `- [x] <agent> R<n>: "<old>" → "<new>"`, with `<new>` copied from one line of the new body. A rule you cannot find in the new body means step C dropped it: put it back.
- [ ] **E. Cap.** Run `awk '/^---$/{n++; next} n>=2' agents/<a>.md | awk '{for(i=1;i<=NF;i++) if($i!="|") w++} END{print w}'`. Over 800 → add `<a>:<ceil(words*1.1)>:<one-line reason>` to `CAPS` (never above the "today" figure in the task).
- [ ] **F. GREEN.** Run `bash scripts/agent-surface.test.sh | tail -1; bash scripts/rubric-drift.test.sh | tail -1; bash scripts/lens-drift.test.sh | tail -1; bash scripts/run-tests.sh 2>&1 | tail -1`. Expected: guard `failed=0`; rubric-drift and lens-drift green; `suites: 48, failed: 0`.
- [ ] **G. Commit** `refactor(agents): lean <agent> — routing description, role-only body` with the attribution line, adding the agent file, the test and RULES.md.

---

### Task 4: reviewer and devops (descriptions; bodies already under 800)

Today: reviewer 83 / 791 words; devops 61 / 652.

New descriptions:
- reviewer: `Use only as the read-only reviewer inside the spec-review workflow, which injects the role lens or verifier brief. Do NOT dispatch it directly, for post-build review (use architect, qa or product-owner), or for any writing.`
- devops: `Use when shipping a change that passed post-build review, or a verified bug fix: CI/CD wiring, infrastructure as code, release notes and the release. Do NOT use before those gates pass; it refuses any other phase.`

Cut map: bodies stay as they are unless a sentence retells a command's sequence; no cut is required. Run steps A–G once for both agents (remove both from `PENDING`), one commit.

---

### Task 5: coder

Today: 96 / 990 words.

New description: `Use when implementing source against a finalized spec and qa's failing tests, closing findings a post-build review returns, or applying a confirmed bug fix. Do NOT use for specs, tests (use qa), ADRs, review verdicts, or before finalize.`

Cut map:
- Keep verbatim: `## Review lens`.
- Keep, tightened: Authority; "When you may write source"; files you write; REVIEW-time read-only rule; the refuse-to-begin check and its `BUILD_FLEET_CODER_REFUSE` line; the self-review checklist (as a short list); bug-lane duties; every signal line (`BUILD_FLEET_FIX_DONE` etc.).
- Cut: `## During BUILD` prose that retells implement's sequence (qa first, then you, then handoff); the example `## Cycle <N> — coder —` block, keeping its format rule as one sentence; Style tips that restate the rubric.
- Target ≤800, no cap expected.

---

### Task 6: qa

Today: 113 / 1,552 words.

New description: `Use when writing a test plan and failing suite from acceptance criteria, repairing it after a drift-gate failure, reviewing a built diff's coverage by revert check, or writing a bug's reproduction test. Do NOT use for source, specs, ADRs.`

Also: in `scripts/drift-wiring.test.sh`, change the `qa-description` assertion's string from `and its repair pass when the drift gate fails` to `repairing it after a drift-gate failure` (same commit).

Cut map:
- Keep verbatim: severity-rubric table, verified-rule block, `## Review lens`.
- Keep, tightened: files you write; the tests-first rules (fail before source, pass after, failure paths); the drift-gate paragraph (gate checks, name-as-declared rule, repair pass duties; it must still contain the exact text ``The drift gate (`scripts/drift-gate.sh`)``, which `drift-wiring.test.sh` checks); the CHANGE_REVIEW counterfactual procedure in full (`git stash create`, the SHA in IMPL_NOTES.md, never a bare `git checkout`); `disposition: fix` on qa's majors; the ready signal `BUILD_FLEET_QA_TESTS_READY: <count> failing tests in tests/`; bug-lane duties (reproduction test, revert counterfactual).
- Cut: `## During BUILD` and `## During CHANGE_REVIEW` prose retelling stage order; the example `## Change-Cycle 1 — qa —` block (keep its grammar as rules); repeated restatements of the test-plan skill.
- Target ≤800; a cap is likely (mirrored text ≈ 300 words). Today's figure: 1,552.

---

### Task 7: architect

Today: 116 / 1,527 words.

New description: `Use when reviewing a built diff for design, failure modes, data integrity, security and blast radius; authoring ADRs; setting a product's stack of record; or challenging a bug hypothesis. Do NOT use for source, tests, specs or spec review.`

Cut map:
- Keep verbatim: severity-rubric table, verified-rule block, `## Review lens`.
- Keep, tightened: Authority; files you may write; ADR rules; the CHANGE_REVIEW contract (runs on peers' blocks, converts a peer's trade-off major to `disposition: adr ADR-N` by writing the ADR, defects stay `fix`, no new majors on a delta cycle); product-tier stack-of-record rules including the brownfield `## Baseline (current)` / `## Forward direction (PROVISIONAL — unreviewed)` contract; hard "no"s; bug-lane duties.
- Cut: the example `## Change-Cycle 2 — architect —` block (keep its grammar as rules); prose retelling handoff's stage order; rationale.
- Target ≤800; a cap is likely. Today's figure: 1,527.

---

### Task 8: product-owner

Today: 79 / 1,623 words.

New description: `Use when writing or revising a feature spec and its acceptance criteria, signing off a built change against them, or writing and questioning a product's vision and phased backlog. Do NOT use for source, tests or ADRs (use architect).`

Cut map:
- Keep, tightened: files you own; the spec-size budget rule; self-review checklist (short list); REVIEW duties (closing blockers and fix majors in `revise`); CHANGE_REVIEW sign-off against acceptance.md with `disposition: fix` majors; product-tier vision/backlog grammar that `next-feature.sh` and `plan-review` depend on (backlog row format, phase headers, `depends-on:`); never writes source, tests or ADRs.
- Cut: the example `## Change-Cycle 1 — product-owner —` block (keep grammar as rules); "What good looks like" prose that duplicates the spec template skill; stage-order narration.
- Target ≤800; a cap is likely for the product-tier grammar. Today's figure: 1,623.

---

### Task 9: classifier

Today: 92 / 1,654 words.

New description: `Use when a new feature needs sizing (trivial, standard, large), a risk rating and a skill manifest, or a new bug needs severity and cause-known triage. Returns a JSON verdict only. Do NOT use to draft specs or change state.`

Cut map:
- Keep, tightened: the three tier definitions and their criteria; the risk rules and reason slugs (reversibility, blast radius, the never-trivial list); the JSON verdict shape exactly; the skill-manifest emission rules; bug-mode triage (`{severity, cause_known}` and their definitions); "never modifies state".
- Cut: "On being wrong" rationale (keep any rule in it); stage-order narration; repetition between tier sections.
- Target ≤800; a cap is likely. Today's figure: 1,654.

---

### Task 10: scribe

Today: 99 / 1,588 words.

New description: `Use only as the final step of a build-fleet workflow, to apply its JSON envelope to the .sdd/ files verbatim and release the in-flight marker. Do NOT use to author content or change state outside an envelope.`

Cut map:
- Keep, tightened: the numbered procedure 1–5 (PROGRESS delta incl. appending absent keys; REVIEW appends anchored on the final block; IMPL_NOTES and DECISIONS appendices; ESCALATION; the ownership-checked marker release by empty overwrite; the confirm line / object), error handling, constraints (no Bash; never whole-file rewrites).
- Cut: `## Why this design`; examples that repeat a rule already stated.
- Target ≤800; a cap is likely (the procedure is the contract). Today's figure: 1,588.

---

### Task 11: Skill descriptions, docs, and the PENDING list emptied

**Files:** `skills/*/SKILL.md` (description lines only), `scripts/agent-surface.test.sh`, `CHANGELOG.md`, `CLAUDE.md`.

- [ ] **Step 1: RED.** Set `PENDING=""` in the test. Run it. Expected: FAIL for each skill whose description is over 40 words or names `/build-fleet:` (sdd-protocol, skill-routing, sdd-spec-template, review-rubric).
- [ ] **Step 2: Replace each skill's `description:` line** with exactly:
  - `adr`: `The ADR format for a feature's or product's DECISIONS.md: append-only entries, one per decision that survived review; product ADRs stay provisional until ratified. Consult when recording, citing or reviewing an ADR.`
  - `review-rubric`: `The blocker, major and minor severity definitions and their gate effects, shared by every reviewer writing REVIEW.md. Consult whenever assigning or checking a finding's severity.`
  - `sdd-diagnosis-template`: `The diagnosis.md structure for a bug: the STATUS line, the required sections, and what the diagnosis hook enforces. Consult when drafting, advancing or reviewing a diagnosis.`
  - `sdd-protocol`: `The build-fleet rulebook: phases and gates, the .sdd/ layout and file ownership, review budgets, escalation, the bug lane and the product tier. Consult whenever orchestrating, changing phase, reviewing, finalizing, handing off or escalating.`
  - `sdd-spec-template`: `The spec.md structure: the STATUS line, the required sections in order, what each must contain, and what the spec hook enforces. Consult when drafting, revising or reviewing a spec.`
  - `skill-routing`: `How domain skills reach role agents: the SKILL_MANIFEST schema, the stack-to-skill table, the classifier's emission rules and load-if-available semantics. Consult when emitting, persisting or honouring a skill manifest.`
  - `test-plan`: `The TEST_PLAN.md structure: each acceptance criterion mapped to named tests and a coverage type, in the matrix grammar the drift gate reads. Consult when drafting a test plan or reviewing coverage.`
- [ ] **Step 3: Re-run Task 3 Step 3's grep** and check every agent section a workflow or command names still exists (`grep -n '<heading>' agents/<a>.md`).
- [ ] **Step 4: Docs.** CHANGELOG `## [Unreleased] — 0.12.0 (lite)` → `### Changed`, add:
  ```
  - **Lean agents** — every agent and skill description is one line of at most 40 words that says
    when to use it and when not to; agent bodies describe the role, not the workflow, at about 800
    words (a few have a named cap). No rule was cut: `docs/history/2026-10-16-lean-agents-RULES.md`
    quotes each one before and after. `scripts/agent-surface.test.sh` guards description length,
    body caps, the inventory, and pins every agent's `tools:` list.
  ```
  CLAUDE.md layout block: change `                              #   lite-next — the lite commands' router, drift-gate)` to `                              #   lite-next — the lite commands' router, drift-gate,`, and add the line `                              #   agent-surface — the agent/skill surface guard)` after it.
- [ ] **Step 5: GREEN and commit.** Guard `failed=0`; `bash scripts/run-tests.sh` → `suites: 48, failed: 0`. Commit `refactor(skills): routing-only skill descriptions; lean-agents docs`.

---

### Task 12: After-runs and the record

**Files:** `docs/history/2026-10-16-lean-agents-EVAL.md`. Scratch: `/tmp/bf-lean-after`, `/tmp/bf-lite`.

- [ ] **Step 1: Planted-defect review with the new agents.** Same as Task 2 Step 3 with `bash "$SC/make-fixture.sh" /tmp/bf-lean-after` and `--plugin-dir ~/build-fleet-0.12 --add-dir ~/build-fleet-0.12`. Fill the "After" column. Expected: every defect the before run raised is raised after at the same or a higher severity. A loss → find the rule or lens text that carried it, restore it (Task 4–10 procedure, steps C–G), and rerun once.
- [ ] **Step 2: Feature live run.** On `/tmp/bf-lite`: `start` "add a divide(a, b) function to calc: returns a / b for ints and floats, raises ZeroDivisionError when b is 0 and TypeError for non-numbers; no further clarification needed", then `build`, then `ship` (each with `--plugin-dir ~/build-fleet-0.12 --add-dir ~/build-fleet-0.12`, the same flags as Task 2). Expected: ends `BUILD_FLEET_LITE_DONE: {"stop":"shipped"}`; the transcript shows `BUILD_FLEET_QA_TESTS_READY`, the drift gate passing three times, a passing change-review gate line, `BUILD_FLEET_DEVOPS_OK`; no write-gate refusals of a role writing outside its files.
- [ ] **Step 3: Bug live run.** Plant `return a - b` in `calc.add` (commit it), then `fix "calc.add returns the wrong result"`. Expected: ends at devops' OK (`shipped`) or a documented human stop; the bug lane's signals appear in order (reproduce, diagnose, apply-fix, verify, ship-fix).
- [ ] **Step 4: Record and commit.** Add a "Live runs" section to EVAL.md (each run's final line and any regression found and fixed), and the body word totals before (10,377) and after. Commit `docs(eval): lean agents — after runs`.
- [ ] **Step 5: Suite.** `bash scripts/run-tests.sh` → `suites: 48, failed: 0`.
