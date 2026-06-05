---
description: HANDOFF of the bug lane — devops ships the verified fix (hotfix urgency for sev0); on a successful ship, clears .sdd/ACTIVE so the next item can start
argument-hint: ""
allowed-tools: Read, Write, Edit, Bash, Task
---

# /build-fleet:ship-fix

You are the **orchestrator**. The bug-lane HANDOFF — devops takes the verified fix to release.
Mirrors `/build-fleet:handoff`'s devops leg and its lock-clear, **without** the product-backlog
flip or DEVELOPING-loop advance (a bug is not a backlog feature).

Rulebook: the `sdd-protocol` skill (bug-lane sections); `agents/devops.md` for the completion signal.

## What you do

1. **Resolve the active bug.** `.sdd/ACTIVE` non-empty; PROGRESS `LANE == bug`. Else refuse.

2. **Check phase + status.** `PHASE` must be `HANDOFF`; `diagnosis.md` STATUS must be `FIXED`.
   `ESCALATION.md` absent. Otherwise refuse and name the actual state. Exit 2.

3. **Pre-flight.** Tests exist and the full suite passes. If not → refuse (re-run
   `/build-fleet:verify`). Exit 2.

4. **Delegate to devops.** Use the Task tool to invoke `build-fleet:devops`:

   > HANDOFF for bug `<slug>` (severity `<SEV>`). Read `.sdd/<slug>/diagnosis.md` and
   > `IMPL_NOTES.md`. Ship the verified fix: CI/CD as applicable + release notes. For `sev0`,
   > treat this as a **hotfix** (expedited release notes / cherry-pick guidance — no new
   > infrastructure in this lane). Refuse if `PHASE` isn't `HANDOFF` (defense in depth). End
   > with your completion signal: `BUILD_FLEET_DEVOPS_OK` on a genuine ship, else
   > `BUILD_FLEET_DEVOPS_REFUSED`.

5. **Branch on the devops signal (key off the machine line; a missing/ambiguous return counts
   as failure — the safe default is "not shipped").**

   - **`BUILD_FLEET_DEVOPS_OK`** → the fix shipped. Emit:
     ```
     BUILD_FLEET_SHIP_FIX: {"slug":"<slug>","severity":"<sev0|sev1|sev2>"}
     ```
     Then **clear `.sdd/ACTIVE`** — empty the file (zero bytes / a single empty line; do not
     delete it) so the next `/build-fleet:triage` or `/build-fleet:new-feature` is unblocked.
     **No backlog flip / next-feature resolve** — a bug has no backlog row (if the slug happens
     to match one, skip it; bugs are not backlog features). Report: fix shipped, lock cleared;
     for a `sev0` whose adversarial confirmation was skipped, remind that the post-hoc
     diagnosis confirmation is still owed.

   - **`_REFUSED` / no signal** → emit:
     ```
     BUILD_FLEET_SHIP_FIX_FAIL: {"slug":"<slug>","reason":"<refused|deploy-failed|no-signal>"}
     ```
     Leave `PHASE: HANDOFF` and `.sdd/ACTIVE` untouched, surface devops' output, and stop. The
     fix is not shipped; the user resolves the devops issue and re-runs `/build-fleet:ship-fix`.

## Refusal cases

- No active bug / active item is a forward feature.
- `PHASE` ≠ `HANDOFF`, or `diagnosis.md` STATUS ≠ `FIXED`, or `ESCALATION.md` present.
- No tests, or the suite fails.
