# build-fleet drift gate — design

**Date:** 2026-10-15
**Status:** draft for review (design approved section by section in brainstorming on
2026-10-15); implementation plan follows approval
**Ships as:** part C of build-fleet v0.12.0 ("lite"), with parts A (lite commands, done),
D (lean descriptions and bodies) and B (four files per feature).
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
coder and before the post-build review) and in the user's CI over every shipped feature.

## 2. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | The gate fires in the flow **and** in CI. | In-flow catches a bad plan before coder spends a build; CI catches drift after ship, which is the receipt. |
| D2 | "The test exists" is a **static** check: the location's file exists and contains the test name. | Language-agnostic, no toolchain in CI, deterministic. Skipped tests are already caught by the suite run and the counterfactual. |
| D3 | Gating is **opt-in per feature** via `DRIFT_GATE: on` in PROGRESS.md, written by `new-feature`. | Existing repos don't go red on first run (same grandfathering as `AC_MAX`), and deleting TEST_PLAN.md cannot switch the gate off. |
| D4 | A failure before coder gets **one** automatic qa repair pass; a failure at handoff gets none. | A plan that misses a row is a cheap fix; a test that vanished during the build is something the user should see. |
| D5 | Unreadable matrix rows **fail** the gate. | Fail closed, as every other gate. |

## 3. Design

### 3.1 `scripts/drift-gate.sh <slug>`

Read-only, deterministic, bash 3.2 and BSD/GNU compatible. jq is used only for JSON
string escaping (as in `change-review-gate.sh`). Anchors at the project root the same way
the other scripts do and rejects a slug containing `/` or `..`.

**Gated or not.** If `.sdd/<slug>/PROGRESS.md` has no `DRIFT_GATE: on`, print
`{"feature":"<slug>","pass":true,"unchecked":true}` and exit 0. Any other value of
`DRIFT_GATE` (other than absent, empty or `off`) is refused as `bad-field`.

**Criteria.** The distinct ids matching `AC-[0-9]+[a-z]?` in `.sdd/<slug>/acceptance.md`.
If that file is absent, the ids in the `## Acceptance` section of `spec.md` (from that
heading to the next `## ` heading). This keeps the gate working if part B folds
acceptance into the spec. Zero criteria in a gated feature fails as `no-criteria`.

**Matrix.** The table rows under `## Coverage matrix` in `.sdd/<slug>/TEST_PLAN.md`, up to
the next `## ` heading. The header row and the `|---|` separator are skipped.
- Column 1: one or more criterion ids, separated by commas.
- Column 2: the test name in backticks. A trailing ` (failure)` (outside or inside the
  backticks) is stripped.
- Column 4: the location. The part before the first `::` is the file path, relative to
  the project root.

A location with no `::` is a bare file path. A row with fewer than four cells, no backticked name, no id in column 1, or an empty
location is `unparsed`.

**Checks.** The gate fails when any of these holds:

| Reason | When |
|---|---|
| `bad-field` | `DRIFT_GATE` has a value other than absent, empty, `on` or `off` |
| `no-test-plan` | the feature is gated but TEST_PLAN.md does not exist |
| `no-criteria` | the feature is gated but has no criteria |
| `untested` | a criterion has no matrix row |
| `unknown-criterion` | a row names an id that is not a criterion |
| `missing-file` | the row's file does not exist, or its path is absolute or contains `..` |
| `missing-test` | the file does not contain the name. A name made only of `[A-Za-z0-9_]` must match as a whole word (`test_retry` does not match `test_retry_backoff`); any other name must match as an exact substring (`it('retries 3 times')`). |
| `gaps-open` | `## Gaps` has any non-blank line other than its heading |
| `unparsed` | a matrix row could not be read |

**Output.** Exactly one stdout line:

```
BUILD_FLEET_DRIFT_GATE: {"feature":"<slug>","pass":<bool>,"reasons":[…],"untested":["AC-3"],"unknown":["AC-9"],"missing":[{"criterion":"AC-1","test":"…","location":"…","why":"missing-file|missing-test"}],"unparsed":["<row text>"],"gaps":<bool>}
```

`reasons` is the distinct set of reasons above, in table order. Exit 0 = pass, 2 = fail,
1 = bad usage or unreadable workspace (machine consumers dispatch on the line; the exit
code exists for CI).

### 3.2 `--all` (CI mode)

`drift-gate.sh --all` runs the single-feature check for every `.sdd/*/` that has a
PROGRESS.md, skipping `_product` and any item with `LANE: bug`, in sorted order. It prints
each feature's line, then:

```
BUILD_FLEET_DRIFT_GATE_SUMMARY: {"checked":N,"unchecked":M,"failed":["<slug>",…]}
```

and exits 2 if any feature failed, 0 otherwise. No `.sdd/` directory → summary with
zeros, exit 0. A shipped feature keeps `DRIFT_GATE: on`, so it stays gated for good.

### 3.3 Where it fires in the flow

- **`new-feature`** adds `DRIFT_GATE: on` to the PROGRESS.md it initialises. Not for bugs
  (no acceptance criteria) or the product tier.
- **`implement`, step b.** After qa's failing suite is verified and before
  `BUILD_STATE: started` is set, run the gate.
  - Fail → re-dispatch qa once with the gate's line: fix TEST_PLAN.md or the test names so
    every criterion maps to a named test; change nothing else. Re-verify the suite (same
    rules as step b) and re-run the gate.
  - Still failing → set `QA_FAIL: drift` in PROGRESS.md, emit
    `BUILD_FLEET_QA_VERIFY_FAIL: {"feature":"<slug>","reason":"drift","gate":<the gate's JSON>}`
    and stop. Coder is not dispatched; `BUILD_STATE` stays unset.
  - Pass → clear `QA_FAIL` if present and continue to step c.
- **`implement` re-run after a drift failure.** The re-run guard (precondition 4) admits
  the run when `QA_FAIL: drift` is set. That run skips qa's authoring pass: it re-verifies
  the existing suite and runs the gate, with the same one repair pass and the same stop.
  So after the user fixes the rows, `build` again continues.
- **`handoff`** (driven by `ship`) runs the gate before it dispatches the post-build
  review. Fail → `BUILD_FLEET_HANDOFF_REFUSE: {"feature":"<slug>","code":2,"reason":"drift","gate":<the gate's JSON>}`.
  No automatic repair.
- **Router.** `lite-next.sh build` with `QA_FAIL: drift` still routes to `implement`; its
  hint reads "repair the test plan". No new stop: the lite drivers already end on any
  `_FAIL`/`_REFUSE` line and relay it verbatim, which shows the user the failing rows.
- **Deep-build** reaches `handoff` the same way, so it is covered without changes.
- **The post-build review's qa** keeps its coverage lens: the gate proves the test
  exists; qa judges whether it really tests the criterion.

### 3.4 Docs

- `skills/test-plan/SKILL.md` states the matrix grammar the gate reads (3.1) and that the
  gate enforces it.
- `agents/qa.md` gains one sentence on the gate; its `description:` changes to match.
- `skills/sdd-protocol/SKILL.md` lists `DRIFT_GATE` and `QA_FAIL` in the PROGRESS schema
  and names the two firing points.
- `docs/v0.2/CONTRACT.md` documents `BUILD_FLEET_DRIFT_GATE`,
  `BUILD_FLEET_DRIFT_GATE_SUMMARY` and the `drift` reasons.
- README gains a short "Use it in CI" snippet:
  `bash <path-to-build-fleet>/scripts/drift-gate.sh --all`.
- CLAUDE.md's scripts list gains `drift-gate`; CHANGELOG's 0.12.0 entry gains the gate.

## 4. Testing

TDD. `scripts/drift-gate.test.sh`, hermetic mktemp fixtures in the existing harness
style:
- pass; unchecked (no field); `DRIFT_GATE: off`; a bad field value;
- one case per reason in 3.1;
- the spec.md `## Acceptance` fallback; multi-id cells; the `(failure)` suffix inside and
  outside the backticks;
- whole-word vs substring matching (`test_retry` vs `test_retry_backoff`; a name with
  spaces and quotes);
- `../` and absolute locations; a location with no `::`;
- `--all`: mixed pass/fail/unchecked/bug/_product, summary counts, exit code; no `.sdd/`.

Also:
- `lite-next.test.sh`: `QA_FAIL: drift` routes `build` to `implement` with the repair hint.
- The smoke test walks one gated feature through the gate (pass), then deletes a test and
  expects `drift-gate.sh --all` to fail.
- The live run on `/tmp/bf-lite` repeats the feature path on a fresh feature and checks
  that the gate line appears at `implement` and at `handoff`.

## 5. Success criteria

1. Every case in section 4 passes on macOS bash 3.2 and Linux; the full suite is green.
2. A fresh feature built with `start`/`build`/`ship` carries `DRIFT_GATE: on` and passes
   the gate at both firing points.
3. Removing a mapped test from a shipped feature makes `drift-gate.sh --all` exit 2 and
   name the criterion.
4. A repo with only pre-gate features reports every one as unchecked and exits 0.

## 6. Out of scope

- A runner-backed check (`pytest --collect-only` and the like).
- Mutation testing and audited test-first (the measurement step).
- The GitHub Action (the launch step).
- Backfilling `DRIFT_GATE: on` into existing features.
- Checking that a test actually exercises its criterion (qa's review lens keeps that).
