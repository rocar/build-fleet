# build-fleet drift gate — design

**Date:** 2026-10-15
**Status:** draft for review (design approved section by section in brainstorming on
2026-10-15); implementation plan follows approval
**Ships as:** part C of build-fleet v0.12.0 ("lite"), with parts A (lite commands, done),
D (lean descriptions and bodies) and B (four files per feature).
**Revised:** 2026-10-15 after an independent Gemini review (§7).
**Evidence:** roadmap review, step 1 and section 7 ("every AC-n maps to a named test; CI
fails on drift") — https://claude.ai/artifact/RjjQEmAJ6woyP1aGQXdK4j

## 1. Problem

qa writes `.sdd/<feature>/TEST_PLAN.md`, whose coverage matrix maps each acceptance
criterion to a named test. The `test-plan` skill says every criterion must appear and
every named test must exist, but only reviewers check that, by reading. Nothing
deterministic does, and nothing checks again after a feature ships, so a test can be
renamed or deleted later and the spec silently stops being enforced.

The drift gate is a script that proves, with no model, that every acceptance criterion of
a gated feature maps to a test that exists in the repo. It runs inside the flow (before
and after coder, and before the post-build review) and in the user's CI over every built
feature.

## 2. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | The gate fires in the flow **and** in CI. | In-flow catches a bad plan before coder spends a build; CI catches drift after ship, which is the receipt. |
| D2 | "The test exists" is a **static** check: the location's file exists and contains the test name. | Language-agnostic, no toolchain in CI, deterministic. Known limit: a skipped or commented-out test still passes (§3.1). The suite run and the counterfactual catch skipped tests inside the flow; CI does not. |
| D3 | Gating is **opt-in per feature** via `DRIFT_GATE: on` in PROGRESS.md, written by `new-feature`. | Existing repos don't go red on first run (same grandfathering as `AC_MAX`), and deleting TEST_PLAN.md cannot switch the gate off. New work is gated by default. |
| D4 | Every gate failure inside `implement` gets **one** qa repair pass in that run. A failure at `handoff` gets none: it marks the feature and `build` repairs it. | A missed row is a cheap fix; a test that vanished during the build is something the user should see before it is repaired. |
| D5 | Unreadable matrix rows **fail** the gate. | Fail closed, as every other gate. |
| D6 | CI (`--all`) gates only features that are **built**. | A feature still in spec or mid-build has no complete test plan yet; failing CI on it would be a false alarm on every work-in-progress branch. |

## 3. Design

### 3.1 `scripts/drift-gate.sh <slug>`

Read-only, deterministic, bash 3.2 and BSD/GNU compatible: no `declare -A`, no `\b` in
grep patterns, no `grep -F -w` together; fixed-string matching uses `grep -F`, whole-word
matching uses awk. jq is used only for JSON string escaping (as in
`change-review-gate.sh`). Anchors at the project root the same way the other scripts do
and rejects a slug containing `/` or `..`.

**Gated or not.** `DRIFT_GATE` absent, empty or `off` → print
`BUILD_FLEET_DRIFT_GATE: {"feature":"<slug>","pass":true,"unchecked":true}` and exit 0.
`on` → run the checks. Any other value fails as `bad-field`.

**Criteria.** The distinct ids matching `AC-[0-9]+[a-z]?` in `.sdd/<slug>/acceptance.md`
(the same pattern `validate-acceptance-count.sh` counts, so the two always agree). If
that file is absent, the ids in the `## Acceptance` section of `spec.md` (from that
heading to the next `## ` heading). This keeps the gate working if part B folds
acceptance into the spec.

**Matrix.** The table rows under `## Coverage matrix` in `.sdd/<slug>/TEST_PLAN.md`, up to
the next `## ` heading. Every cell is trimmed of surrounding whitespace and one pair of
surrounding backticks.
- Skipped: a separator row (only `|`, `-`, `:` and spaces, so `| --- | :--- |` counts) and
  any header row (its first cell is `Criterion`). A matrix split into several tables
  therefore parses.
- Column 1: one or more criterion ids, separated by commas (each trimmed).
- Column 2: the test name **as declared in source**: a function or method name
  (`test_retry`), or a test's description string without the runner call or quotes
  (`retries 3 times`, not `it('retries 3 times')`). A trailing ` (failure)` is stripped,
  then a trailing `[…]` parametrize id (`test_eval[case1]` → `test_eval`).
- Column 4: the location. The part before the first `::` is the file path, relative to
  the project root; a location with no `::` is a bare file path.

A row with fewer than four cells, an empty name, no id in column 1, or an empty location
is `unparsed`.

**Checks.** The gate fails when any of these holds:

| Reason | When |
|---|---|
| `bad-field` | `DRIFT_GATE` has a value other than absent, empty, `on` or `off` |
| `no-test-plan` | the feature is gated but TEST_PLAN.md does not exist |
| `no-criteria` | the feature is gated but has no criteria |
| `untested` | a criterion has no matrix row |
| `unknown-criterion` | a row names an id that is not a criterion |
| `missing-file` | the row's file does not exist; or its path is absolute, contains `..`, is under `.sdd/`, or ends in `.md` |
| `missing-test` | the file does not contain the name. A name made only of `[A-Za-z0-9_]` must match as a whole word (`test_retry` does not match `test_retry_backoff`). A name containing `/` (a Go subtest, `TestProcess/invalid_input`) needs each `/`-separated segment to appear, the same way. Any other name must appear as an exact substring. |
| `gaps-open` | `## Gaps` holds at least one `- ` bullet (the skill's gap format); prose such as `None.` is not a gap |
| `unparsed` | a matrix row could not be read |

**Known limit (D2).** The check reads text. A name left in a comment, or a test marked
skip, still passes. The flow catches skipped tests through the suite run and the
counterfactual; CI mode does not. A runner-backed check is out of scope (§6).

**Output.** Exactly one stdout line, in every case:

```
BUILD_FLEET_DRIFT_GATE: {"feature":"<slug>","pass":<bool>,"reasons":[…],"untested":["AC-3"],"unknown":["AC-9"],"missing":[{"criterion":"AC-1","test":"…","location":"…","why":"missing-file|missing-test"}],"unparsed":["<row text>"],"gaps_open":<bool>}
```

`reasons` is the distinct set of reasons above, in table order. A row with several ids
whose test is missing yields one `missing` entry per id. Exit 0 = pass, 2 = fail, 1 = bad
usage or unreadable workspace (machine consumers dispatch on the line; the exit code
exists for CI).

### 3.2 `--all` (CI mode)

`drift-gate.sh --all` visits every `.sdd/*/` that has a PROGRESS.md, in sorted order,
skipping `_product` and any item with `LANE: bug`. A visited feature is **built** when
`BUILD_STATE: done`, or `BUILD_STATE` is unset and `PHASE` is `CHANGE_REVIEW` or `HANDOFF`
(a shipped feature stays at `HANDOFF`). Built features get the single-feature check and
its line. Any other feature gets
`BUILD_FLEET_DRIFT_GATE: {"feature":"<slug>","pass":true,"in_progress":true}`. Then:

```
BUILD_FLEET_DRIFT_GATE_SUMMARY: {"checked":N,"unchecked":M,"in_progress":K,"failed":["<slug>",…]}
```

Exit 2 if any feature failed, 0 otherwise. No `.sdd/` directory → a summary of zeros,
exit 0. A shipped feature keeps `DRIFT_GATE: on`, so it stays gated for good.

### 3.3 Where it fires in the flow

**New PROGRESS field.** `QA_FAIL: drift` marks a feature whose test plan failed the gate
and still needs repair. It is cleared by the run that passes the gate.

- **`new-feature`** adds `DRIFT_GATE: on` to the PROGRESS.md it initialises. Not for bugs
  (no acceptance criteria) or the product tier.

- **`implement`, before coder (step b).** After qa's failing suite is verified and before
  `BUILD_STATE: started` is set, run the gate.
  - Pass → continue to step c.
  - Fail → the **repair pass**: re-dispatch qa once with the gate's line and this brief:
    fix TEST_PLAN.md, or add or rename tests, so every criterion maps to a named test;
    no source; end with `BUILD_FLEET_QA_TESTS_READY: <count> failing tests in tests/`
    giving the new count. Re-verify the suite against that count (step b's rules) and
    re-run the gate.
  - Still failing → set `QA_FAIL: drift`, emit
    `BUILD_FLEET_QA_VERIFY_FAIL: {"feature":"<slug>","reason":"drift","gate":<the gate's JSON>}`
    and stop. Coder is not dispatched; `BUILD_STATE` stays unset.

- **`implement`, after coder (step e).** Before `BUILD_STATE: done` is set, run the gate.
  - Pass → set `BUILD_STATE: done` as today.
  - Fail → one repair pass, with the brief changed for a built feature: restore or rename
    the tests or fix TEST_PLAN.md so every criterion maps to a named test; no source; the
    suite must stay green. Re-run the suite and the gate.
    - Suite green and gate passes → set `BUILD_STATE: done`.
    - Suite red (a restored test fails, so behaviour is missing) → set
      `BUILD_STATE: needs-iteration`; the next `build` resumes coder through deep-build.
    - Gate still failing → set `QA_FAIL: drift`, emit the `drift` VERIFY_FAIL line, stop.

- **`implement` in repair mode.** When PROGRESS.md has `QA_FAIL: drift`, the re-run guard
  (precondition 4) admits the run whatever the BUILD_STATE, and the run does only the
  repair pass: no authoring pass, no coder. Whether the suite must be red or green follows
  `BUILD_STATE` (unset → red, as before coder; `started` or `done` → green, as after
  coder). Outcomes are those of the matching step above, and passing clears `QA_FAIL`.
  Unset `BUILD_STATE` continues to step c and coder, as a normal build.

- **`handoff`** (driven by `ship`) runs the gate in step 4, with the test pre-flight,
  before the change-cycle budget check and before `CHANGE_CYCLE` increments. So a drift
  failure never spends a review cycle. The `PHASE: HANDOFF` resume in step 2 runs it too,
  before it skips to devops. Fail → set `QA_FAIL: drift` and emit a new signal
  `BUILD_FLEET_HANDOFF_REFUSE: {"feature":"<slug>","code":2,"reason":"drift","gate":<the gate's JSON>}`.
  No repair here.

- **Router (`scripts/lite-next.sh`).** Reads `QA_FAIL`:
  - `build` with `QA_FAIL: drift` → `implement`, hint "repair the test plan", before the
    `BUILD_STATE` branches.
  - `ship` with `QA_FAIL: drift` → stop `drift`, next `build`, why "the test plan has
    drifted; build repairs it".

  The drivers already end on any `_FAIL`/`_REFUSE` line and relay it verbatim, so the user
  sees the failing rows.

- **Deep-build** is not changed: a test it loses is caught by `handoff`, then repaired by
  `build`.

- **The post-build review's qa** keeps its coverage lens: the gate proves the test
  exists; qa judges whether it really tests the criterion.

### 3.4 Files and docs

- New: `scripts/drift-gate.sh`, `scripts/drift-gate.test.sh`.
- Changed: `commands/new-feature.md`, `commands/implement.md`, `commands/handoff.md`,
  `scripts/lite-next.sh`, `scripts/lite-next.test.sh`, the smoke test.
- `skills/test-plan/SKILL.md` states the matrix grammar the gate reads (3.1), including
  "name as declared in source", and that the gate enforces it.
- `agents/qa.md` gains the gate and the repair pass; its `description:` changes to match.
- `skills/sdd-protocol/SKILL.md` lists `DRIFT_GATE` and `QA_FAIL` in the PROGRESS schema
  and names the firing points.
- `docs/v0.2/CONTRACT.md` documents `BUILD_FLEET_DRIFT_GATE`,
  `BUILD_FLEET_DRIFT_GATE_SUMMARY`, `BUILD_FLEET_HANDOFF_REFUSE` and the `drift` reasons.
- README gains a short "Use it in CI" snippet:
  `bash <path-to-build-fleet>/scripts/drift-gate.sh --all`.
- CLAUDE.md's scripts list gains `drift-gate`; CHANGELOG's 0.12.0 entry gains the gate.

## 4. Testing

TDD. `scripts/drift-gate.test.sh`, hermetic mktemp fixtures in the existing harness
style:
- pass; unchecked (no field, empty, `off`); a bad field value; unchecked output carries
  the `BUILD_FLEET_DRIFT_GATE:` prefix;
- one case per reason in 3.1;
- the spec.md `## Acceptance` fallback; multi-id cells with spaces; the `(failure)`
  suffix inside and outside the backticks; a backticked location; aligned separators
  (`| :--- |`); two tables under one heading;
- whole-word vs substring matching (`test_retry` vs `test_retry_backoff`; a description
  with spaces and quotes; a name with regex characters `(`, `[`, `*`); a `[case1]`
  parametrize suffix; a Go subtest `Parent/child`;
- locations: `../`, absolute, under `.sdd/`, a `.md` file, no `::`;
- `## Gaps` with a bullet (fails) and with `None.` (passes);
- `--all`: a mix of built pass and fail, in-progress, unchecked, bug and `_product`;
  summary counts; exit code; no `.sdd/`.

Also:
- `lite-next.test.sh`: `QA_FAIL: drift` routes `build` to `implement` at each
  BUILD_STATE, and stops `ship` with `drift`.
- The smoke test walks one gated feature through the gate (pass), then deletes a test and
  expects `drift-gate.sh --all` to fail.
- The live run on `/tmp/bf-lite` repeats the feature path on a fresh feature and checks
  that the gate line appears at `implement` (both points) and at `handoff`.

## 5. Success criteria

1. Every case in section 4 passes on macOS bash 3.2 and Linux; the full suite is green.
2. A fresh feature built with `start`/`build`/`ship` carries `DRIFT_GATE: on` and passes
   the gate at all three firing points.
3. Removing a mapped test from a shipped feature makes `drift-gate.sh --all` exit 2 and
   name the criterion; `ship` then stops with `drift` and `build` repairs it.
4. A repo with only pre-gate features reports every one as unchecked and exits 0; a
   feature still in spec reports in-progress and does not fail CI.

## 6. Out of scope

- A runner-backed check (`pytest --collect-only` and the like), which would close the
  skipped-test limit.
- Protecting `DRIFT_GATE` from being removed. It has the same standing as `AC_MAX`: an
  edit to PROGRESS.md, visible in the PR diff.
- Mutation testing and audited test-first (the measurement step).
- The GitHub Action (the launch step).
- Backfilling `DRIFT_GATE: on` into existing features.
- Checking that a test actually exercises its criterion (qa's review lens keeps that).

## 7. Review record

An independent Gemini 3.8 Flash (High) review of the first draft (pro tier unavailable)
returned 17 findings. Fixed above:
- A coder that broke a mapping after the build deadlocked the lite flow (`ship` refused,
  `build` said "built"). Now the gate runs after coder too, `handoff` sets `QA_FAIL`,
  and `build` routes to a repair pass whatever the BUILD_STATE.
- `--all` failed CI on every feature still in spec. Now only built features are gated (D6).
- Backticked locations (the skill's own example) would have read as missing files.
- The repair pass did not say qa must re-emit its ready signal with a new count, and the
  re-run had no count to verify against. Repair mode now always dispatches qa.
- The `handoff` firing point was unspecified and could spend a review cycle or be skipped
  on resume. Now step 4 and the step-2 resume, before the cycle increments.
  `BUILD_FLEET_HANDOFF_REFUSE` is named as a new signal.
- The router change was missing from the files list.
- Test names: the "as declared in source" rule, `[…]` suffixes, Go subtests, and the
  example that wrongly included `it('…')`.
- Locations under `.sdd/` or in `.md` files are refused.
- `None.` under `## Gaps` no longer fails; gaps are bullets.
- Portability constraints are named. Unchecked output carries the signal prefix.
  Aligned separators, header rows, multi-table matrices and spaced id lists parse.
  `gaps_open` and per-id `missing` entries are defined.

Rejected:
- Phantom criteria from cross-references in acceptance.md: any id mentioned there is a
  criterion id already, and the pattern must stay identical to the AC_MAX hook's.
  Uppercase suffixes (`AC-1A`) are not the project's id format.
- A `## Coverage gaps` heading mismatch: that is the skill's own section title; the file
  template it documents uses `## Gaps`.
- Deep-build burning cycles on a drifted plan: the plan is gated before deep-build starts,
  and a test lost during it is caught at `handoff`.

Kept as known limits: skipped or commented-out tests pass the static check (D2), and a
model could remove `DRIFT_GATE` (§6).
