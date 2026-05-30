---
description: Print the current state of the active build-fleet feature — phase, cycles, open concerns, escalation
argument-hint: ""
---

# /build-fleet:status

You are the **orchestrator**. Read-only command. You report state; you do
not mutate anything.

## What you do

1. **Read `.sdd/ACTIVE`.** If empty or absent, report "no active feature"
   and stop. Suggest `/build-fleet:new-feature <slug>`.

2. **Read `.sdd/<active>/PROGRESS.md`.** Print:
   - Feature slug.
   - PHASE.
   - CYCLE (spec-review cycles consumed).
   - CHANGE_CYCLE (change-review cycles consumed).
   - UPDATED timestamp.

3. **Read `.sdd/<active>/spec.md` first line.** Print the STATUS value.

4. **Summarize the most recent REVIEW.md cycle.** Find every block tagged
   with the current `CYCLE` (if PHASE is in spec-review territory) or
   `CHANGE_CYCLE` (if PHASE is in change-review territory). For each
   reviewer block, print:
   - Reviewer name.
   - `status:` line value.
   - Count of `[blocker]`, `[major]`, `[minor]` items.
   - Verbatim text of every `[blocker]` item (so the user sees what's
     actually open).

5. **Check for `.sdd/<active>/ESCALATION.md`.** If it exists, print a
   prominent banner: the feature is escalated. Then print the file's
   contents — phase, cycle count, unresolved blockers, conflicting
   positions. Skip the "next command" recommendation; only a human
   unblocks an escalation.

6. **Recommend the next command** based on PHASE:
   - `SPEC` → product-owner is drafting; run `/build-fleet:review` when
     PO signals ready.
   - `REVIEW` with open blockers → PO is revising; re-run
     `/build-fleet:review` once revisions land.
   - `REVIEW` with all approvals → `/build-fleet:finalize`.
   - `BUILD` → coder + qa working; run `/build-fleet:handoff` when both
     signal done.
   - `CHANGE_REVIEW` with open blockers → coder is fixing; re-run
     `/build-fleet:handoff` once fixes land.
   - `HANDOFF` → devops shipping; no command needed.
   - `ESCALATED` → human-in-the-loop required; no command can advance.

## Hard rules

- This command **never** writes any file. Read-only.
- This command **never** runs tests or invokes subagents.
- If any of the expected `.sdd/<active>/` files are missing or malformed,
  report which and stop — recovery is the user's call (probably
  hand-edit PROGRESS.md, or `/build-fleet:new-feature` with a fresh slug
  if the workspace is irrecoverable).
