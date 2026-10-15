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
| D1 | architect (blocker), qa (blocker), coder (blocker) | architect (blocker), qa (blocker), coder (blocker) |
| D2 | qa (major, qa-c1-4), architect (minor, architect-c1-5) | qa (major, qa-c1-4 "a nonexistent path"), architect (minor, architect-c1-7) |
| D3 | architect (major), qa (major), coder (major) | architect (major), qa (major), coder (major) |

Other findings before (16 surviving in all; 3 blockers, 8 majors, 5 minors): beyond
D1–D3, 4 majors (row numbering ×2, column mapping, what counts as an empty row) and 4
minors. After: 18 surviving (3 blockers, 9 majors, 6 minors); beyond D1–D3, 5 majors
(row numbering ×3, column mapping, what counts as an empty row) and 5 minors.

**Result: no regression.** Every planted defect was raised after the cut by the same
roles at the same severity. After run: plugin at f6c39da, `output_tokens` 11,037,
`scribe_apply: applied`. One run per side: this rules out a gross loss of judgement,
not a small one.

Before run: plugin at d1f95ff (the branch before any agent edit), 2026-10-15, one
cycle, `output_tokens` 10,212, `scribe_apply: applied`.

## Live runs (plugin f6c39da, /tmp/bf-lite, 2026-10-15)

| Run | Path | Result |
|---|---|---|
| Feature `add-a-divide-a-b-function-to` | `start` → `build` → `ship` | Classified trivial/low (review skipped by tier); qa's 6 tests failed first; drift gate passed before and after coder and at handoff; change review cycle 1 approved by product-owner, qa and architect (3 minors); devops committed; ends `{"stop":"shipped"}`. |
| Bug `bug-add-returns-negative-one` (planted `a - b`) | `fix` | Reproduce → hypothesis → diagnose (3 refuters, hypothesis survived) → apply-fix → verify (both reproduction tests fail with the fix reverted) → ship-fix; ends `{"stop":"shipped"}`, 26/26 tests. |

No regression found: every agent emitted its signals, no write gate refused a role, and the
review gates parsed every block. Product-owner and architect again wrote invented heading
timestamps (they have no Bash), a known issue from before this change.

## Word counts

Agent bodies: 10,377 words before, 8,702 after (−16%). Descriptions: 8 agents from
61–116 words to 35–40; 7 skills from 33–99 to 25–33. Caps: coder, devops and reviewer at
800; qa 1,433, architect 1,359, product-owner 1,275, classifier 1,492, scribe 1,571.
Most of what remained is rules, which the inventory keeps.
