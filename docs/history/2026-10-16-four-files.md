# build-fleet four files per feature — design

**Date:** 2026-10-16
**Status:** draft for review (design approved section by section in brainstorming on
2026-10-16); implementation plan follows approval
**Ships as:** part B of build-fleet v0.12.0 ("lite"), with parts A (lite commands, done),
C (drift gate, done) and D (lean agents, done).
**Evidence:** roadmap review, step 1 ("four files per feature, line budgets") —
https://claude.ai/artifact/RjjQEmAJ6woyP1aGQXdK4j

## 1. Problem

A forward feature today scaffolds seven files under `.sdd/<slug>/`: `spec.md`,
`acceptance.md`, `TEST_PLAN.md`, `IMPL_NOTES.md`, `DECISIONS.md`, `REVIEW.md`,
`PROGRESS.md` (plus `SKILL_MANIFEST.md` when the classifier routes skills). A reader —
human or agent — has to know which of seven files holds a fact, and three of them
restate one another: acceptance criteria live apart from the spec they belong to, and
TEST_PLAN's coverage matrix restates, by hand, a mapping the tests themselves can carry.
The plugin pays for this in reach: `acceptance.md` is named in 37 plugin files (114
mentions), `TEST_PLAN.md` in 19 (38), `IMPL_NOTES.md` in 21 (55), `SKILL_MANIFEST.md` in
8 (14). Every name is prose an agent must read and a rule a reviewer must keep in sync.

Part B cuts a feature to four files and removes the old layout outright. There are no
external users of build-fleet yet, so there is no compatibility path: the old layout's
code and prose are deleted, not branched.

## 2. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | Four files per feature: `spec.md` (with an acceptance section), `REVIEW.md`, `PROGRESS.md`, `DECISIONS.md`. `IMPL_NOTES.md` exists only once something is written to it. | The roadmap target. Each remaining file has one owner and one purpose. |
| D2 | **No backward compatibility.** Every reference to `acceptance.md`, `TEST_PLAN.md` and `SKILL_MANIFEST.md` is deleted. New features are stamped `SDD_SCHEMA: 2`; any other forward-feature schema is refused at the entry points with `unsupported-schema`. | A dual-schema switch would carry two paths through every gate, command, workflow and agent — roughly as much added as removed, against the point of the lite release. No users depend on the old layout (Ray, 2026-10-16). |
| D3 | Line budget and layout are part B; read instrumentation waits for 0.13 with the dashboard. | Instrumentation has no reader until the dashboard exists. |
| D4 | The test plan lives **in the tests**: each test carries its criterion id in a marker comment (`# AC-3`, `// AC-3`) on or above it. The drift gate requires every criterion to appear in at least one test file. | One source of truth, kept next to the code it describes; nothing to hand-maintain. Known limit: a stale marker still counts. |
| D5 | REVIEW.md blocks are **findings-only**: a role heading plus finding lines (with their indented disposition / refutation / verification lines). The `status: concerns-raised \| approved` line is removed. | No gate has read the line since 0.9; it is the only non-finding content. A role with no findings writes its heading alone, so the gates still see that it reviewed. |
| D6 | `IMPL_NOTES.md` is created by its first writer. The two readers that used it as a "coder has started" signal key on `BUILD_STATE` instead. | A clean coder run has nothing to note; an empty scaffold is noise. `BUILD_STATE` is set before coder runs (implement step c) and is the honest signal. |
| D7 | Skill routing moves into PROGRESS as two fields, `CODER_SKILLS: <csv>` and `QA_SKILLS: <csv>`, written only when non-empty. | Only the skill lists were ever consumed. `feature_type`, `derived_from`, `rationale` and `tools_recommended` (binds nothing, by its own spec) stay in the classifier's `BUILD_FLEET_SKILL_MANIFEST:` signal line only. |
| D8 | One size budget: `SPEC_MAX_LINES` (150 standard, 400 large, none for trivial) replaces `SPEC_MAX_KB`. `AC_MAX` stays, counted in the spec's acceptance section. REVIEW, PROGRESS, DECISIONS and IMPL_NOTES are uncapped. | Lines are what a reader pays. REVIEW is bounded by the 0.9 rotation; PROGRESS is field lines; capping the append-only files would refuse a scribe write mid-workflow and wedge the run. |
| D9 | The drift gate is **on by default**: `DRIFT_GATE` absent = gated, `off` = unchecked. new-feature no longer writes the field. | The opt-in existed to grandfather existing workspaces (part C D3); with D2 there are none. `off` stays as the escape hatch for a feature with no tests (docs-only). |
| D10 | Retired names are kept out by a **static test**, not a runtime hook: `agent-surface.test.sh` fails the suite if any agent, command, skill, workflow, hook or script (tests excluded) names `acceptance.md`, `TEST_PLAN.md` or `SKILL_MANIFEST`. | Once no prompt or template names an old file, nothing recreates it. A test costs nothing at runtime and keeps the gate script count at 12. |
| D11 | The `test-plan` skill is retired; the marker convention is stated in qa's body and `sdd-protocol`. | The skill's substance was the matrix grammar, which is gone. The convention is three lines. Skills go 7 → 6. |
| D12 | The bug lane and the product tier are unchanged and stay `SDD_SCHEMA: 1`. | The bug lane already has no spec, acceptance or test plan; its files are diagnosis, PROGRESS, REVIEW, IMPL_NOTES. |

## 3. Design

### 3.1 The layout

`/build-fleet:new-feature` scaffolds three files and stamps the schema:

```
.sdd/<slug>/
  spec.md        # product-owner. Ends with `## Acceptance criteria` (AC-<n>[a-z] ids).
  PROGRESS.md    # orchestrator + scribe. SDD_SCHEMA: 2.
  DECISIONS.md   # architect (+ scribe appendix). Append-only.
  REVIEW.md      # created by the first review. Findings-only blocks.
  IMPL_NOTES.md  # created on first write (coder gaps/deviations/todos, snapshot SHAs,
                 #   skill-unavailable lines, scribe impl_notes_appendix).
```

- **spec.md** keeps its owner (product-owner), its `STATUS:` lifecycle and its freeze at
  FINALIZED. The acceptance section uses today's acceptance grammar unchanged (ids
  `AC-<n>` or `AC-<n><letter>`, one criterion per item). The `sdd-spec-template` skill
  gains the section; a criterion that cannot be tested is a spec defect product-owner
  fixes (there is no `## Gaps` section anywhere).
- **PROGRESS.md** loses `SPEC_MAX_KB` and `DRIFT_GATE: on`, gains `SPEC_MAX_LINES`
  (standard/large only) and, when routed, `CODER_SKILLS` / `QA_SKILLS`. An optional
  `TEST_ROOTS: <csv>` (§3.3) is documented but not scaffolded.
- **REVIEW.md** block grammar: the `## Cycle <n> — <role> — <iso8601>` heading, then finding
  lines exactly as today. The scribe, `review.js` and `deep-build.js` stop rendering
  `status:`; the `status` field leaves both workflows' payload schemas and
  `docs/v0.2/CONTRACT.md`. The finalize and change-review gates already end a finding's
  indented run at any non-indented line and never evaluate `status:`, so removing it
  needs no gate change (pinned by a test).
- **Schema check.** `SDD_SCHEMA: 2` is stamped by new-feature. `lite-next.sh` (the router
  behind every lite command) and `block-source-before-finalized.sh` (the backstop every
  source write passes) refuse an active forward feature whose `SDD_SCHEMA` is not exactly
  `2`, with reason `unsupported-schema` and the text "this feature was started by an older
  build-fleet — park it and start it again". The bug lane (`LANE: bug`) and
  `.sdd/_product/` are exempt. `drift-gate.sh --all` reports such a feature with the same
  reason and fails.

### 3.2 Hooks

Each change gets its failing test first, in the hook's existing harness.

- **`cap-spec-size.sh`** (PreToolUse Write|Edit|NotebookEdit) — matches `.sdd/<slug>/spec.md`
  only; reads `SPEC_MAX_LINES`; projects the resulting line count:
  - Write: lines of `tool_input.content` (a final line without a newline counts);
  - Edit: current lines + (lines(new) − lines(old)) × occurrences, with the existing
    `replace_all` occurrence counting;
  - NotebookEdit: refused closed, as today.
  Absent/empty = no cap; `0` = disabled; non-integer = refused (exit 2). Refusal text keeps
  the SPLIT-not-compress wording, now in lines. Product tier exempt.
- **`validate-acceptance-count.sh`** (PostToolUse) — fires on `.sdd/<slug>/spec.md` writes;
  counts distinct ids in the `## Acceptance…` section with the awk the drift gate uses
  (moved to a shared helper so the two cannot disagree).
- **`stop-tests.sh`** — the tests-first window becomes `PHASE: BUILD` with `BUILD_STATE`
  absent or `started`. Cost: a coder run interrupted mid-build with a red suite no longer
  blocks the session's stop; that state already resumes through `/build-fleet:deep-build`.
- **`block-source-before-finalized.sh`** — gains the `unsupported-schema` refusal (§3.1).

### 3.3 Scripts

- **`drift-gate.sh <slug> | --all`**:
  - Criteria: distinct ids in the spec's `## Acceptance…` section.
  - Coverage: every criterion id occurs as a whole token in at least one regular, non-`.md` file under
    the test roots (a `tests/README.md` listing criteria must not cover them — part C refused `*.md` locations for the same reason). Whole token = not preceded or followed by `[A-Za-z0-9_-]`, so `AC-3`
    does not match `AC-30` or `AC-3a`, and `AC-3a` does not count for `AC-3`.
  - Test roots: `TEST_ROOTS` from PROGRESS (comma-separated, project-relative), else
    `tests`. A root that is absolute, contains `..`, or lies under `.sdd/` is `bad-field`;
    a root that does not exist is `no-test-roots`.
  - Reasons, in order: `bad-field`, `unsupported-schema`, `no-criteria`, `no-test-roots`,
    `untested` (a criterion with no marker), `unknown-criterion` (a marker in the test
    roots naming an id the spec does not have — catches markers left stale by a revision).
  - Signal line: `BUILD_FLEET_DRIFT_GATE: {"feature","pass","reasons","untested","unknown"}`
    (plus `"unchecked":true` for `DRIFT_GATE: off`, `"in_progress":true` under `--all`).
    The removed fields (`missing`, `unparsed`, `gaps_open`) go; exit codes are unchanged.
  - Static and model-free, as today; no test runner, no language parsing.
  The firing points (implement b2/e2, handoff step 4) and `QA_FAIL: drift` repair mode are
  unchanged; repair now means adding or fixing markers or tests.
- **`lite-next.sh`** — drops its `acceptance.md` freshness check (`spec.md` covers it);
  gains the schema refusal.
- **`scripts/lib/review-blocks.sh`**, quote-check, verified-review pins — drop
  `acceptance.md` from the allow-listed sources. Quotes from the acceptance section are
  quotes from `spec.md`.
- **`status-snapshot.sh`, `finalize-gate.sh`, `change-review-gate.sh`, `review-carry.sh`,
  `review-rotate.sh`** — audited in the plan for file-existence and `status:` assumptions;
  changed only where the audit finds one.

### 3.4 Agents, commands, workflows, skills

Every edit names the new location only.

- **product-owner** — writes acceptance criteria as the spec's last section; self-review
  and the PLAN_REVIEW criteria point there.
- **qa** — no TEST_PLAN: tags each test with its criterion id, runs the drift gate as today;
  repair edits markers or tests; reads `QA_SKILLS`.
- **coder** — creates IMPL_NOTES on first write; reads `CODER_SKILLS`; review format loses
  `status:`.
- **scribe** — `impl_notes_appendix` already creates the file if absent; loses the
  `status:` render.
- **architect, reviewer, devops, classifier** — ownership lists, file pointers, `status:`.
- **Workflows** — `review.js`, `plan-review.js`, `deep-build.js`, `diagnose.js`: drop
  `acceptance.md` / `TEST_PLAN.md` / `SKILL_MANIFEST.md` from read lists and quote-file
  enums; `deep-build.js` reads the skill fields; `status` leaves the payload schemas.
  `node --check` and the determinism lint after each.
- **Commands** — `new-feature` (scaffold, stamp, skill fields, budget, no `DRIFT_GATE`),
  `implement` (re-run guard on `BUILD_STATE`, skills, TEST_PLAN mentions), `handoff`,
  `finalize`, `revise`, `status`, `deep-build`, `dispatch`, `triage` (its entry text names
  the forward files). Bug-lane commands change only where they name a retired file.
- **Skills** — `sdd-protocol` (layout, fields, marker convention), `sdd-spec-template`
  (acceptance section), `skill-routing` (field format), `review-rubric` (no `status:`);
  `test-plan` deleted.
- **Docs** — `docs/v0.2/CONTRACT.md`, README (skill count 7 → 6, layout), CHANGELOG
  (breaking: features started before 0.12.0 must be restarted), `CLAUDE.md` layout list.

### 3.5 The part D guards

- Every agent rule an edit changes gets an inventory line in
  `docs/history/2026-10-16-lean-agents-RULES.md`: `- [x] agent Rn: "old" → "new"`.
  A rule whose subject no longer exists (e.g. drafting TEST_PLAN) is retired with a new
  form, `- [x] agent Rn: "old" → retired: <reason>`, which `agent-surface.test.sh` learns
  to accept. New rules are appended and `RULES_COUNT` is updated.
- Each agent stays under its part D cap; a cap is raised only with a named reason.
- `rubric-drift`, `lens-drift`, `drift-wiring` and `agent-surface` stay green; agents whose
  bodies change get their descriptions reviewed (CLAUDE.md release rule).

## 4. Testing

- **Hooks and scripts, test-first:** `cap-spec-size` line projection (Write, Edit,
  `replace_all`, no trailing newline, absent/0/garbage, product tier);
  `validate-acceptance-count` on `spec.md`; `stop-tests` window on `BUILD_STATE`;
  `block-source-before-finalized` and `lite-next` `unsupported-schema` (forward refused,
  bug lane and product tier exempt); `drift-gate` — every reason, whole-token cases
  (`AC-3` vs `AC-30`, `AC-3a`, `xAC-3`), `TEST_ROOTS` (csv, absolute, `..`, `.sdd/`,
  missing), `DRIFT_GATE` absent/off/garbage, `--all` with a schema-1 feature.
- **Static guard:** `agent-surface.test.sh` retired-name scan (and a planted mention must
  fail it); the `retired:` inventory form.
- **Fixtures:** the verified-review fixture and the smoke test (`docs/v0.5/smoke/smoke.sh`)
  move to the four-file layout.
- **Live runs** on a fresh scratch repo (not /tmp/bf-lite, whose workspaces are schema 1):
  a feature taken start → build → ship, checking the scaffold, IMPL_NOTES only if written,
  markers in the tests, the drift gate passing and no retired file created; then a planted
  missing marker the gate must catch.
- **Review regression:** the csv-import planted-defect fixture (D1 AC-2/AC-3 contradiction,
  D2 missing file, D3 AC-4 untestable) converted to the four-file layout must find the same
  three defects as the part D baseline.
- CI runs the Linux leg.

## 5. Success criteria

1. A new feature's `.sdd/<slug>/` holds at most `spec.md`, `PROGRESS.md`, `DECISIONS.md`,
   `REVIEW.md` and, only when written, `IMPL_NOTES.md`.
2. `grep` for `acceptance.md`, `TEST_PLAN.md` and `SKILL_MANIFEST` across agents, commands,
   skills, workflows, hooks and scripts (tests excluded) returns nothing — enforced by the
   suite.
3. The spec's line budget is enforced by `cap-spec-size`; `SPEC_MAX_KB` no longer exists.
4. The drift gate passes on a marked suite and fails `untested` / `unknown-criterion` on
   the planted cases, with no TEST_PLAN.
5. The review regression finds D1–D3.
6. `bash scripts/run-tests.sh` is green on macOS and Linux.
7. Net lines across `agents/ commands/ skills/ workflows/ hooks/ scripts/` (tests
   excluded) go down; the number is recorded in the eval note and the CHANGELOG.

## 6. Out of scope

- Read instrumentation (0.13, with the dashboard).
- Migrating existing workspaces (D2).
- Any bug-lane or product-tier layout change (D12).
- Detecting skipped or commented-out tests (part C's known limit stands; the suite run
  and the counterfactual cover it inside the flow).
- Language-aware marker parsing: a marker is a token in a test-root file, not a parsed
  comment.

## 7. Review record

(Filled after review.)
