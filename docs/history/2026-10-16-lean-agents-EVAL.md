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
| D1 | architect (blocker), qa (blocker), coder (blocker) | (Task 12) |
| D2 | qa (major, qa-c1-4), architect (minor, architect-c1-5) | (Task 12) |
| D3 | architect (major), qa (major), coder (major) | (Task 12) |

Other findings before (16 surviving in all; 3 blockers, 8 majors, 5 minors): beyond
D1–D3, 4 majors (row numbering ×2, column mapping, what counts as an empty row) and 4
minors. After: (Task 12).

Before run: plugin at d1f95ff (the branch before any agent edit), 2026-10-15, one
cycle, `output_tokens` 10,212, `scribe_apply: applied`.
