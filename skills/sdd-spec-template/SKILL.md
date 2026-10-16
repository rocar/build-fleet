---
name: sdd-spec-template
description: The spec.md structure: the STATUS line, the required sections in order, what each must contain, and what the spec hook enforces. Consult when drafting, revising or reviewing a spec.
---

# SDD Spec Template

This skill defines the **only** acceptable structure for `.sdd/<feature>/spec.md`.
The `validate-spec-status` hook parses for the STATUS line and the required
section headings; a write that omits any of them is rejected.

The product-owner is the sole author. Reviewers reference this skill to
flag missing structure as a `[blocker]`.

## STATUS line

`spec.md` MUST contain a line that **starts** with `STATUS:` **within the
first 30 lines** of the file — exactly the window the `validate-spec-status`
hook scans:

```
STATUS: DRAFT
```

The value MUST be one of: `DRAFT`, `IN_REVIEW`, `FINALIZED`, `BLOCKED`.
No other tokens. No prefix before `STATUS:` on that line. No trailing
comment. Put it first when you can; a short `## Self-review notes` block
from product-owner may precede it, as long as the STATUS line stays inside
the first 30 lines and starts its line.

## Required sections (in this order)

```markdown
STATUS: <DRAFT|IN_REVIEW|FINALIZED|BLOCKED>

# <Feature title>

## Overview
One paragraph. The problem this feature exists to solve. The user it
serves. Why now.

## Goals
A short list of outcomes that this feature must deliver. Outcome-level,
not implementation-level.

## Non-goals
Explicit scope boundary. Reviewers will challenge anything that looks like
scope creep; pre-empt them.

## Behavior
The substantive description of what the system does. Prose preferred over
bullet soup. Where there are branching cases, state them. Where ordering
matters, state it.

## Interfaces / Contracts
Function signatures, API shapes, event schemas, CLI args — whatever the
feature exposes externally. Include error envelopes.

## Constraints
Performance, security, compatibility, regulatory, or operational
constraints the implementation must respect.

## Risks
Known unknowns, failure modes, blast radius, things-we-don't-yet-know-how-
to-do. Naming a risk here is not a failure; hiding one is.

## Acceptance Criteria
The spec's last section; frozen with it at FINALIZED. One observable criterion
per item, each with a stable id:
- **AC-1**: <observable behaviour, testable as written>
- **AC-2**: <…>
Never renumber an existing id. qa marks each test with `<slug>/AC-<n>` for the
criteria it covers; a criterion that cannot be tested is a spec defect.
```

## What the validator checks

`validate-spec-status` (PostToolUse on `spec.md`) rejects the write if:

- STATUS line is missing or malformed.
- Any of these section headings is absent: `## Overview`, `## Goals`,
  `## Non-goals`, `## Behavior`, `## Interfaces / Contracts`,
  `## Constraints`, `## Risks`, `## Acceptance Criteria`.
- The file is empty or has no content under any required section.

The validator is intentionally syntactic — semantic correctness
(testable acceptance, non-trivial behavior) is what the REVIEW phase exists
to enforce.

## What "good" looks like

- Behavior described concretely enough that coder could start without
  guessing.
- Acceptance criteria 1:1 with behavior described.
- Non-goals listed explicitly.
- Risks acknowledged, not hidden.
- STATUS line correct for the current phase.

## What "bad" looks like (flag as `[blocker]`)

- Vague goals ("make X better").
- Behavior described only in pseudocode.
- "Acceptance criteria: TBD."
- Hidden assumptions ("we'll figure out auth later").
- A `## Non-goals` section that's empty or says "n/a" — every feature has
  scope it's *not* covering; if PO can't articulate them, the spec is
  unfinished.
