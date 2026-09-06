---
description: Hand the product-owner exactly the open review items to close
allowed-tools: Read, Task
---

# /build-fleet:revise

You are the **orchestrator**. After a `/build-fleet:review` cycle, the open items are
the current cycle's `[blocker]` lines and every `[major]` whose disposition is `fix`
(or missing). This command extracts exactly those, with their ids, and dispatches the
product-owner to close them **in the spec, under the feature's size budget**. It is
the per-cycle ritual's second half: `revise` → `review` → (`finalize` | `revise` …).

It never edits `.sdd/` itself; the product-owner writes `spec.md` / `acceptance.md`.

## What you do

1. **Resolve the active feature.** Read `.sdd/ACTIVE`. If empty, refuse:
   `BUILD_FLEET_REFUSE: {"command":"revise","code":2,"reason":"no-active-feature"}`.

2. **Check phase.** Read `.sdd/<slug>/PROGRESS.md`. `PHASE` must be `REVIEW`; else refuse
   `{"command":"revise","code":2,"reason":"wrong-phase","phase":"<PHASE>"}`. If
   `.sdd/<slug>/ESCALATION.md` exists, refuse `{"command":"revise","code":2,"reason":"escalation-present"}`
   — a human resolves it first.

3. **Extract the open items.** Read `CYCLE` and `REVIEW_ROLES` (default
   `architect, qa, coder`). In `.sdd/<slug>/REVIEW.md`, take the **last** block per
   roster role headed `## Cycle <CYCLE> — <role> —`. From those blocks collect:
   - every `- [blocker] (<id>) <text>` line whose next line is NOT an indented `refuted-by:` continuation (a refuted blocker is closed);
   - every `- [major] (<id>) <text>` line whose next line is `  disposition: fix`, or
     which has no `disposition:` / `refuted-by:` continuation line at all.
   Ignore `[minor]` lines, refuted items, and `disposition: adr ADR-N` majors — those
   are **closed** and must not be handed to the PO.
   If the list is empty, refuse
   `BUILD_FLEET_REFUSE: {"command":"revise","code":2,"reason":"nothing-to-revise","cycle":<CYCLE>}`
   and tell the user no blocker or `fix` major is open; run `/build-fleet:finalize`
   (the gate still checks that every `adr` disposition cites an existing ADR).

4. **Read the size budget.** From PROGRESS.md: `SPEC_MAX_KB` and `AC_MAX` (either may be
   absent — then say "no cap" for that one).

5. **Dispatch the product-owner.** Use the Task tool to spawn `build-fleet:product-owner`
   with this prompt (fill every placeholder):

   > Revise `.sdd/<slug>/spec.md` and `.sdd/<slug>/acceptance.md` to close EXACTLY these
   > open review items from cycle <CYCLE> — nothing else:
   >
   > <the extracted lines, verbatim, one per line, with their ids>
   >
   > Rules:
   > - Close each item in the spec/acceptance text, or push back in `## Self-review notes`
   >   with reasoning a human can audit. Record, per id, what you did.
   > - Items dispositioned `adr` are CLOSED by their ADR — do not touch the text they
   >   concern and do not add prose "also addressing" them.
   > - Size budget: spec.md ≤ <SPEC_MAX_KB> KB, acceptance.md ≤ <AC_MAX> distinct criteria
   >   (hooks refuse writes over budget). If closing these items cannot fit, do NOT compress
   >   rationale: name in `## Self-review notes` which behaviours and criteria move to a
   >   sibling backlog row (a split), and cut them here.
   > - Keep `STATUS: DRAFT`. Do not renumber existing `AC-<n>` ids.
   > - The next review is a delta review: reviewers verify closure by id.

6. **Emit the signal and report.**
   ```
   BUILD_FLEET_REVISE_DISPATCHED: {"feature":"<slug>","cycle":<CYCLE>,"items":<N>}
   ```
   Tell the user how many items were handed over and that the next command is
   `/build-fleet:review` once the PO reports done.

## Hard rules

- Never edit `spec.md`, `acceptance.md`, `REVIEW.md`, `DECISIONS.md` or PROGRESS.md
  yourself — the PO revises; the review workflow records.
- Never hand the PO an `adr`-dispositioned major or a refuted item. Re-opening closed
  items is how specs bloat.
- **Headless contract.** Exactly one `BUILD_FLEET_*` line before any prose; a slash
  command cannot set a process exit code.
