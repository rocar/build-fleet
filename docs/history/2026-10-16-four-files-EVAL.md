# Four files per feature — evaluation record

Plugin at d804f7c (release/0.12.0, Tasks 1–11 applied), 2026-10-15/16.

## Live run (fresh repo `/tmp/bf-four`, lite commands, headless)

Feature: "a `stats.py` module with `mean(values)` and `median(values)`" (classified
standard, low risk).

| Step | Result |
|---|---|
| `start` | `.sdd/<slug>/` = `spec.md`, `PROGRESS.md`, `DECISIONS.md`, `REVIEW.md`. `PROGRESS.md` carries `SDD_SCHEMA: 2`, `SPEC_MAX_LINES: 150`, `AC_MAX: 15`, no `DRIFT_GATE`. Spec 144 lines, 14 criteria, all in its `## Acceptance Criteria`. Review cycle 1: three findings-only blocks, no `status:` line; clean, `stop: spec-ready`. |
| `build` | qa wrote 23 tests in `tests/test_stats.py` carrying 14 `<slug>/AC-n` markers (one per criterion); all failed before source. Drift gate passed before and after coder; suite 25 passed; `BUILD_STATE: done`; `stop: built`. Coder created `IMPL_NOTES.md` on its own write (a criterion-to-code map plus `gaps: none` lines). |
| `ship` | Drift gate passed at handoff; change review (product-owner, qa, architect) wrote three `## Change-Cycle 1` blocks with no `status:` line, four minors, gate `pass:true`; devops shipped; `stop: shipped`. |

No `acceptance.md`, `TEST_PLAN.md` or `SKILL_MANIFEST.md` was created at any point.

**Finding from the run:** handoff appends a `## Implementation` section to the FINALIZED
spec (`commands/handoff.md` step ~183). Here it took the spec from 144 to 148 of 150
lines. A spec drafted to its budget would have that write refused by `cap-spec-size` at
ship. Carried to the final review.

## Planted missing marker

On the shipped feature, the `<slug>/AC-7` marker line removed from `tests/test_stats.py`:
`drift-gate.sh <slug>` → `{"pass":false,"reasons":["untested"],"untested":["AC-7"],"unknown":[]}`, exit 2;
`--all` → summary `{"checked":1,"unchecked":0,"in_progress":0,"failed":["<slug>"]}`, exit 2. Marker restored.

## Review regression (planted defects)

Fixture `make-fixture-4.sh`: part D's csv-import fixture in the four-file layout (its
acceptance criteria folded into `spec.md`, no `acceptance.md`/`TEST_PLAN.md`/
`IMPL_NOTES.md`/`REVIEW.md`, `SDD_SCHEMA: 2`). One debate review cycle.

| Defect | Part D after (baseline) | Four files |
|---|---|---|
| D1 AC-2/AC-3 contradiction | architect, qa, coder (blocker) | architect, qa, coder (blocker) |
| D2 missing/unreadable file | qa (major), architect (minor) | qa (major, qa-c1-3 (d) "a file that does not exist"), architect (minor, architect-c1-7) |
| D3 AC-4 untestable | architect, qa, coder (major) | architect, qa (major), coder (blocker) |

17 surviving (4 blockers, 8 majors, 5 minors), `output_tokens` 9,554, `scribe_apply:
applied`, REVIEW.md created by the scribe, no `status:` lines. **No regression:** every
planted defect was raised, by the same roles, at the same or higher severity. Same limit as
part D: the spec-review workflow runs the reviewer agent with review.js's lenses, so this
checks the reviewer path and the quote/criteria plumbing, not the agent bodies; the live run
exercises those.

## Net lines (spec commit 6e81a13 → HEAD)

| Surface | Added | Deleted | Net |
|---|---|---|---|
| agents, commands, skills, workflows, hooks, scripts (tests excluded) | 431 | 575 | −144 |
| test harnesses | 421 | 418 | +3 |

Agent bodies: 8,957 words (part D: 8,908), +49 — the marker rules in qa and the reworded
ownership lines cost slightly more than the TEST_PLAN prose they replaced. Every agent is
under its cap.
