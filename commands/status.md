---
description: Print the current state of the active build-fleet feature — phase, cycles, open concerns, escalation
argument-hint: ""
---

# /build-fleet:status

You are the **orchestrator**. Read-only command. You report state; you do
not mutate anything.

## What you do

1. **Read `.sdd/ACTIVE`.** If empty or absent:
   - If `.sdd/_product/backlog.md` exists, there is a product tier with no feature
     in flight — skip the feature-detail steps (2–5) and go straight to the
     **Product backlog** section (step 5b), which surfaces the backlog and names the
     next unblocked feature to scaffold.
   - Otherwise report "no active feature" and stop. Suggest
     `/build-fleet:new-feature <slug>`.

1b. **Bug lane (v0.5 M4).** Read `.sdd/<active>/PROGRESS.md`. If it carries `LANE: bug`, the
   active item is a troubleshoot-fix **bug**, not a forward feature — report the **bug view** and
   **skip steps 2–4** (a bug has no `spec.md` or spec-review cycle):
   - Bug slug; `PHASE` (`REPORT|REPRODUCE|DIAGNOSE|FIX|VERIFY|HANDOFF|ESCALATED`); `SEV`.
   - `diagnosis.md` STATUS (`REPORTED|REPRODUCING|DIAGNOSED|CONFIRMED|FIXED`).
   - `CYCLE` (diagnose-confirmation cycles) and `FIX_CYCLE` (verify→fix bounces); `UPDATED`.
   - The count of test files under `tests/` (read-only — status never runs the suite; the
     `diagnosis.md` STATUS conveys the red→green lifecycle).
   - The most recent `.sdd/<slug>/REVIEW.md` diagnose block(s), if any (verbatim verdict lines).
   - Then do the ESCALATION check (step 5) and recommend the next bug-lane command by `PHASE`:
     `REPORT`→`/build-fleet:reproduce`; `REPRODUCE`→record a hypothesis, then `/build-fleet:diagnose`;
     `DIAGNOSE`→`/build-fleet:diagnose` again (if refuted) or `/build-fleet:fix` (if confirmed —
     PHASE will read `FIX`); `FIX`→`/build-fleet:fix` then `/build-fleet:verify`;
     `VERIFY`→`/build-fleet:verify`; `HANDOFF`→`/build-fleet:ship-fix`; `ESCALATED`→human only.
   Then **stop** — do not run the forward-feature steps below.

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

5b. **Product backlog (v0.4 M2), if a product tier exists.** If
   `.sdd/_product/backlog.md` exists, summarize it:
   - For each `## Phase N: <name> — STATUS:` line, print the phase name + its STATUS.
   - Under each phase, print every feature row with its state: `PENDING`, or `DONE`
     (with its `handoff:` date) — and if a row's slug matches `.sdd/ACTIVE`, annotate
     it `← active (in flight, PHASE=<phase>)`. Active is **derived from `.sdd/ACTIVE`**,
     not a backlog marker.
   - A roll-up line: `<done>/<total> features done across <N> phases`.
   - **If no feature is active, resolve what's next via the shared resolver** (v0.4 M3.2)
     — the same read-only helper `/build-fleet:handoff` uses, so status and the loop never
     disagree:
     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-feature.sh"
     ```
     It emits one JSON line; report from its `status`:
     - `next` → name the slug + phase and suggest `/build-fleet:new-feature <slug>`.
     - `complete` → "product backlog complete (`done/total`)" — nothing to start.
     - `deadlocked` → "`<pending>` features remain but none are unblocked — check
       `depends-on` / cycles in `backlog.md`."
     - `empty` → "backlog has no parseable feature rows — check its format" (not
       "complete"; `total=0`).
     Do **not** re-derive the next feature in prose; use the resolver output verbatim.
   Read-only, like the rest of status (the resolver only reads `backlog.md`).

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

## Machine-readable snapshot (orchestrators / polling)

For a non-interactive caller (an external orchestrator polling project state), the
human report above is the wrong shape and too costly — it spawns a model. Use the
deterministic, LLM-free resolver instead:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/status-snapshot.sh"
```

It reads the same `.sdd/` state this command narrates and emits **exactly one JSON
object** (`schema: build-fleet/status-snapshot@1`) on stdout — the product tier
(vision/stack one-liners, backlog counts + per-feature rows, next unblocked feature)
and the active item (feature or bug lane: phase, status, cycles, escalation).
Read-only; run from the repo root. `product` is `null` with no product tier;
`active` is `null` with nothing in flight. Backlog resolution + counts reuse
`scripts/next-feature.sh` (one source of truth). **build-fleet ships no publishing
path** — where (or whether) the snapshot goes is the orchestrator's concern
(orchestrator-agnostic).

## Hard rules

- This command **never** writes any file. Read-only. (It may invoke the read-only
  `scripts/next-feature.sh` resolver, which only reads `backlog.md` and writes nothing.)
- This command **never** runs tests or invokes subagents.
- If any of the expected `.sdd/<active>/` files are missing or malformed,
  report which and stop — recovery is the user's call (probably
  hand-edit PROGRESS.md, or `/build-fleet:new-feature` with a fresh slug
  if the workspace is irrecoverable).
