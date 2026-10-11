# Proportionate review — the two-role measurement

**Date run:** 2026-10-11  **Spec:** 2026-10-10-proportionate-review.md §6 (D9)
**Feature:** tap `fixture-and-harness`, cycle 1 from the reconstructed pre-run state.
**Plugin:** main at v0.9.0 for both arms (the roster is the only plugin-side difference).

| Arm | Roster | Agents | Wall-clock | output_tokens | Surviving blockers | Surviving `fix` majors | Refutations that discarded a concern |
|---|---|---|---|---|---|---|---|
| three-role (2026-09-06) | architect, qa, coder | 8 | 26.6 min | 274,075 | 0 | 9 | 3 |
| two-role (2026-10-11) | architect, qa | 6 | 3.8 min | 23,448 | 0 | 5 | 0 |

**Two-role run detail.** Workflow run `wf_8d6c80fc-6e8`; launch line 09:42:49Z, Workflow
result 09:46:35Z (workflow-reported duration 218.8 s). Agents `review:architect`,
`review:qa`, `cross-exam:architect`, `cross-exam:qa`, `disposition:architect`, `scribe`:
6 started, 6 completed, 0 errors. Return object: verdict `clean`, finalize_ready `false`,
open_majors `architect-c1-1, architect-c1-2, qa-c1-1, qa-c1-2, qa-c1-3`, adrs_written 0,
output_tokens 23,448, scribe_apply `applied`. Surviving concerns 14 (5 majors, all
`fix`; 9 minors). Cross-examination issued 14 verdicts, all `affirm`, so 0 concerns
were discarded.

**Three-role arm** (its REVIEW.md Cycle 1 blocks): 20 concerns, 11 majors (9 `fix`, 1
`adr ADR-7`, 1 refuted), 9 minors (2 refuted); 3 refutations, all issued by the
architect against qa and coder concerns.

## Findings the two-role arm lacked

Three of the three-role arm's nine `fix` majors have a content match in the two-role arm:
architect-c1-5 (seed loader transaction boundary; two-role architect-c1-2), qa-c1-2
(XlsxWriter import ban asserted by no criterion; two-role qa-c1-1) and qa-c1-3 (the
logging NFR has no test; two-role qa-c1-2). Six have none:

| Three-role id | Finding | Raised by | Evidence, and Ray's call |
|---|---|---|---|
| architect-c1-1 | `COLOR_INDEX` covers indices 0–63, the fixture's own `xl/styles.xml` carries `indexed="64"`, so `project()` raises on the committed fixture | architect | openpyxl 3.1.5 `COLOR_INDEX` has 64 entries; `samples/20260807.xlsm` styles.xml carries `<bgColor indexed="64"/>` twice, and styles.xml is outside the redactor's touched set. Real (evidence). |
| architect-c1-2 | `Difference.left/right = None` is ambiguous between "absent on that side" and a present field whose value is `None` | architect | Real (Ray). |
| architect-c1-3 | the `Difference` shape for a missing coordinate is unpinned while the sibling cases are pinned | architect | Real (Ray). |
| architect-c1-4 | the `Q` column mask is implied three ways (`0.0%`, two decimals, four decimals) and AC-42a names no exact cell | architect | styles.xml carries exactly one percent format, `0.0%`. Real (Ray). |
| qa-c1-1 | the merged-range `Difference` shape is unpinned | qa | Real (Ray). |
| coder-c1-2 | AC-10 has no "nothing else moved" clause for workbook.xml and app.xml, so a parse-and-reserialize substitution ships silently | coder | Not adjudicated. |

Reverse direction: two-role qa-c1-3 (operator UUID symbol and username unpinned, `fix`)
is the three-role arm's qa-c1-4, a minor the architect refuted there. Two-role
architect-c1-1 (PII-bearing temp file location and cleanup, `fix`) has no three-role
counterpart.

## Confounds

- One month of model drift between the arms. The roles pin model aliases (`opus` for the
  architect legs, `sonnet` for qa and the scribe); on 2026-10-11 they resolved to Opus
  5.5 and Sonnet 5.5. The September resolution is not recorded and that transcript no
  longer exists.
- Five of the six lacked findings were raised by architect and qa, roles present in both
  arms. The gap cannot be attributed to the roster alone: the arms differ in reviewer
  depth (7× wall-clock, 12× output tokens) as well as in roster.
- The rotation at dispatch kept three legacy blocks (`## Cycle 2 — coder`, `## Cycle 3 —
  qa`, `## Run failure recorded`); the three-role arm's REVIEW.md also still held `## Cycle
  2 — qa`. Legacy blocks cannot be re-raised by id.

## Decision

**REVERT** (Ray, 2026-10-11). The two-role arm lacked `fix` majors that the three-role arm
kept and that Ray judges real: architect-c1-1 by evidence; architect-c1-2, architect-c1-3,
architect-c1-4 and qa-c1-1 by Ray's call; coder-c1-2 not adjudicated. Under spec §6 step 4
the `standard` + `low` row seeds `architect, qa, coder` with budget `3`. The risk axis and
the seeding mechanism still ship, without the cut.

The result is weaker evidence than D9 anticipated: the lacked findings came mostly from
roles present in both arms, so one run cannot separate roster from model drift. The rule
was pre-registered and is applied as written; a same-model re-measurement is open to a
later release.

**Continuation.** No arm goes back into tap's working tree. The tap at `~/Projects/tap`
(`/Volumes/FastStorage/05_Projects/tap`) is an outdated copy that served as the pilot
sandbox; production tap lives at `~/build-projects/tap` and does not use build-fleet.
`fixture-and-harness` is not being continued. Both arms are preserved at
`~/tap-measurement/{two-role,three-role}`.
