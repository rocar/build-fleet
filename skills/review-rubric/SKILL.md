---
name: review-rubric
description: The shared severity vocabulary every reviewer uses in .sdd/<feature>/REVIEW.md — blocker, major, minor — with exact definitions and gate effects. Consult during /build-fleet:review and /build-fleet:handoff, and whenever assigning a severity to a finding.
---

# Review Rubric

This skill is the canonical severity vocabulary used by architect, qa, and
coder in `.sdd/<feature>/REVIEW.md`. The `/build-fleet:finalize` and
`/build-fleet:handoff` gates parse the severity tags to decide whether a
phase may advance.

The same table appears verbatim in `architect.md`, `qa.md` and `reviewer.md` prompt
bodies — a deliberate duplication. Nothing preloads a skill into a workflow agent
(the runtime's `agent()` has no skills option), so the in-body copies are the
load-bearing ones on every path; this skill is canonical and
`scripts/rubric-drift.test.sh` fails the suite on any drift.

## The vocabulary

| Severity | Definition | Gate effect |
|---|---|---|
| `blocker` | Correctness, security, data loss, or a contradiction of the spec/acceptance. | Blocks FINALIZE and HANDOFF. |
| `major`   | Scalability, maintainability, or missing acceptance coverage. | Must be resolved or explicitly accepted (as an ADR) before the gate opens. |
| `minor`   | Style, wording, nits. | Advisory; never blocks a gate. |

Use the exact strings `[blocker]`, `[major]`, `[minor]` — including the
square brackets — as item prefixes in REVIEW.md. The finalize gate uses a
literal substring search.

<!-- verified-rule:start -->
In a verified review (`REVIEW_SHAPE: verified`), a `[blocker]` or `[major]` carries an anchor and a test,
or it is recorded as a `[minor]`. The anchor is a quote of 10–500 characters copied verbatim from
`spec.md`, `acceptance.md`, `DECISIONS.md` or `_product/DECISIONS.md`, or a named absence (the file, an
existing section heading, and what is missing). The test is one sentence naming a test that would fail
if the finding is real. Quotes are checked word for word after the review: a finding whose anchor quote
is not found is demoted, and a verifier's vote whose quote is not found does not count.
<!-- verified-rule:end -->

## REVIEW.md entry shape

```markdown
## Cycle <N> — <role> — <iso8601>
- [blocker] (<role>-c<N>-1) <one-line concern; expand below if needed>
- [major] (<role>-c<M>-2) <concern>
  disposition: fix | adr ADR-<K>
- [minor] (<role>-c<N>-3) <concern>
status: concerns-raised | approved
```

The `status:` line is mandatory (its presence is required by the block shape;
since v0.9 its value is informational — the finalize gate reads dispositions and
blockers, see "Delta review and disposition (v0.9)" below). In workflow REVIEW
the reviewer subagents return structured concerns payloads which the workflow merges into the
canonical block shape above; the scribe appends them. On non-workflow paths
(CHANGE_REVIEW, direct invocation) the `check-review-written` SubagentStop hook
rejects a reviewer that stops without writing a block of this shape attributed
to its own role for the current cycle.

## How to choose a severity

Ask yourself, in order:

1. **Does this make the system wrong, unsafe, or contradict the spec?**
   → `[blocker]`.
2. **Does this make the system harder to scale, maintain, or extend?
   Or is there acceptance coverage missing?** → `[major]`.
3. **Otherwise (style, prose, naming, nits):** → `[minor]`.

If you're tempted to add a fourth category ("critical", "important"),
don't. Pick from the three above. Three is enough.

## How a major becomes an ADR

This describes the non-workflow paths (CHANGE_REVIEW and direct invocation). In
workflow REVIEW the architect disposition leg records the ADR — see "Delta review
and disposition (v0.9)" below.

In CHANGE_REVIEW the same grammar applies, read by `scripts/change-review-gate.sh`:

- Ids `<role>-cc<K>-<n>`, `K` the change cycle the finding was first raised in; a
  re-raised finding keeps its id.
- Every `[major]` carries `disposition: fix` (the default; coder closes it) or
  `disposition: adr ADR-N` (architect only, ADR appended first).
- **Closed-by-id.** The architect runs after product-owner and qa and may accept a
  peer's open major as a trade-off by listing the peer's id under its own block with
  an ADR disposition. An id closed by an ADR in any block is closed in every block.
- **Delta rule.** From change cycle 2, new findings are `[blocker]` only; a new
  `[major]` is advisory (the gate reports it as demoted). Blockers are never demoted,
  and qa's change-review lens rates a missing acceptance test as a blocker, so
  demotion touches maintainability-class findings in fix code only.

A `[major]` that gets quietly dropped between cycles without a fix or an ADR is a
finding the next reviewer should re-raise by id — same content, elevated to
`[blocker]` for lack of audit trail.

## Delta review and disposition (v0.9)

- **Ids are stable.** `<role>-c<cycle>-<n>`; a re-raised finding keeps its original id.
- **Cycle 1 is the only full review.** From cycle 2 a reviewer verifies closure of its
  own prior `fix` findings and blockers, and may raise new findings at `[blocker]`
  severity only (plus advisory minors). A new `[major]` on a delta cycle is not allowed:
  the open-major set only shrinks. This is enforced in code, not only asked for in the
  prompt — the workflow demotes any surviving major whose id originates at cycle ≥ 2 to
  `[minor]` (with a prefixed explanatory text) before the survival vote runs.
- **Every surviving major is dispositioned once**, in the workflow, by the architect:
  `disposition: adr ADR-N` (a design trade-off — accepted, closed, ADR written by the
  scribe) or `disposition: fix` (a gap the PO must close in the spec). Rule of thumb: if
  closing it would make the spec longer without making the system more correct, it is
  an `adr`; if a test could fail because of it, it is a `fix`. A disposition with an
  empty ADR body, a duplicate id, or a missing id makes the whole run `incomplete`
  (`disposition-incomplete`) — nothing is written, and the run must be retried.
- **An accepted trade-off is contested only as a `[blocker]` against the ADR by id.**
- **A `refuted-by:` continuation closes a blocker or a major** — the survival vote
  refutes any severity; a blocker with no such continuation stays open only until a
  later cycle simply does not re-raise it.
- **`status:` is informational.** The finalize gate reads `[blocker]` lines and
  `disposition:` / `refuted-by:` lines (`scripts/finalize-gate.sh`).

## Verified review

When `REVIEW_SHAPE: verified` is set, the cross-examination and survival vote are replaced:

- **A panel of three fresh verifiers** judges every blocker and major, and every closure claim, without
  seeing who raised it, the reviewer's reasoning, or each other. Each returns `uphold`/`refute`
  (closures: `confirm`/`reject`), a severity, a reason, and a quote when refuting or lowering severity.
- **A finding is killed by two valid refutations** (quote + a reason of at least 40 characters). One
  refutation is never enough.
- **Severity is the median vote**, capped at the raised severity; a lower vote counts only with quoted
  evidence. A majority `test_invalid` (the named test could not exercise the claim) demotes to minor.
- **Quotes are checked after the review** (`scripts/quote-check.sh`); the finalize gate recomputes
  every vote from the recorded verdicts and that check. A quote that is not found voids its vote; a
  finding that loses its kill this way is reopened, and that cycle does not count against the budget.
- **Open findings carry forward**: an open finding of the previous cycle is closed only by a quoted
  closure the panel confirms; otherwise it is carried unchanged (`carried:` line), whether or not its
  reviewer re-lists it.
- **Limit:** the quote check catches invented quotes, not a real quote used to argue a wrong point; the
  majority vote is the defence against that.

## Hard rules

- One block per reviewer per cycle. Append; never edit prior blocks.
- A reviewer approving its own prior `[blocker]` without explanation is a
  red flag — the resolving fix should be visible (a spec revision, an
  ADR, or an explicit comment in the new block).
- `[minor]` items never block a gate. If you find yourself promoting a
  minor to a major to force resolution, the right move is to write it as
  what it actually is and accept that it won't gate.
