---
description: Resolve the next unblocked backlog feature and gate it for start — the deterministic next (first PENDING in the lowest phase whose depends-on are all DONE), pre-checked for readiness, emitted as a dispatch signal. A convenience over reading /status then typing the slug; adds NO prioritization policy. (v0.4 M4, optional)
allowed-tools: Read, Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-feature.sh":*), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/intent-block.sh":*)
---

# /build-fleet:next-feature

You are the **orchestrator**. The runtime rulebook is the `sdd-protocol` skill
(**DEVELOPING loop**). This is the v0.4 **M4 advancement convenience**: it resolves the
next unblocked backlog feature, confirms it is ready to start, and emits a dispatch
signal — collapsing the manual "read `/build-fleet:status` → type
`/build-fleet:new-feature <slug>`" into one focused, gated step.

**It is convenience, not policy.** M4 uses **only** the deterministic resolver
(`scripts/next-feature.sh` — first PENDING in the lowest phase whose `depends-on` are all
DONE). It never reorders, skips, or judges importance. Any real prioritization is yours:
reorder `backlog.md`, or run `/build-fleet:new-feature <slug>` directly. M4 is the
no-policy fast path.

**It does NOT run `/build-fleet:new-feature` itself.** M4 resolves + gates + signals; the
**dispatcher** starts the feature — the upstream caller in headless mode, you in
interactive mode. This keeps dispatch (and any caller-side policy/description) with the
orchestrator, and means M4 never duplicates new-feature's scaffolding/classifier/inheritance
logic (new-feature owns that, and self-seeds its description from the backlog intent via its
step 5).

## What you do

1. **Refuse if a feature is already in flight.** Read `.sdd/ACTIVE`. If non-empty, refuse —
   the protocol allows one feature at a time; finish it (through `/build-fleet:handoff`,
   which clears `.sdd/ACTIVE` on ship) before advancing:
   ```
   BUILD_FLEET_NEXT_FEATURE_REFUSE: {"code":2,"reason":"feature-in-flight","active":"<slug>"}
   ```

2. **Resolve the next feature.** Run the shared resolver (the single source of truth; do
   not re-derive in prose):
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-feature.sh"
   ```
   Branch on its `status`:
   - `no-backlog` → no product tier exists; there is nothing to advance. Tell the user to
     use `/build-fleet:new-feature <slug>` directly. Emit
     `BUILD_FLEET_NEXT_FEATURE: {"status":"no-backlog"}` (informational no-op).
   - `complete` → the product backlog is fully shipped (`done/total`). Nothing to advance;
     congratulate; note that appending features re-opens the loop. Emit
     `BUILD_FLEET_NEXT_FEATURE: {"status":"complete","done":<n>,"total":<n>}`.
   - `deadlocked` → `<pending>` features remain but none are unblocked. Refuse and warn the
     user to check `depends-on` / cycles in `backlog.md`. Emit
     `BUILD_FLEET_NEXT_FEATURE_REFUSE: {"code":2,"reason":"deadlocked","pending":<k>}`.
   - `empty` → the backlog has no parseable feature rows. Refuse; tell the user to check its
     format. Emit `BUILD_FLEET_NEXT_FEATURE_REFUSE: {"code":2,"reason":"empty-backlog"}`.
   - `next` → continue to step 3 with the resolved `slug` + `phase`.

3. **Pre-check the intent (headless-safe gate).** Run the shared intent-block extractor —
   the SAME script `/build-fleet:new-feature` step 5 uses, so the two always reach the same
   verdict (one grammar, one quality floor, one implementation):
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/intent-block.sh" --slug "<slug>" .sdd/_product/backlog.md
   ```
   It prints the canonical intent block (the 1–3 indented lines under the feature row) and a
   final `INTENT_VERDICT: usable|too-thin` line. The quality floor it encodes: an intent is
   *usable* only with at least 2 of its 3 components (what / scope boundary / non-goals); a
   missing intent or a thin slug-restatement is `too-thin`. (The canonical prose definition
   of the floor lives in the `sdd-protocol` skill.)

   If the verdict is `too-thin` (or the script errors), **do NOT advance** —
   `/build-fleet:new-feature` would STOP-and-ask for a description, which deadlocks an
   unattended (headless) run. Emit:
   ```
   BUILD_FLEET_NEXT_FEATURE_NEEDS_DESC: {"code":2,"slug":"<slug>","reason":"intent-too-thin"}
   ```
   Tell the user: the next feature's backlog intent is too thin to start unattended — run
   `/build-fleet:new-feature <slug>` interactively and provide a description (new-feature
   will prompt). *(This honors new-feature's own STOP-and-ask floor up front, instead
   of discovering it mid-dispatch.)*

4. **Emit the dispatch signal and hand off.** The next feature is unblocked, ready, and has
   a usable intent. Emit exactly one line:
   ```
   BUILD_FLEET_NEXT_FEATURE: {"status":"next","slug":"<slug>","phase":"<phase>"}
   ```
   Then tell the **dispatcher** the next move — **do not run it here**:
   - **Interactive:** "Next is `<slug>` (`<phase>`), ready to start. **Nothing is started
     yet — this command only resolves and gates.** Run `/build-fleet:new-feature <slug>` to
     begin — it will inherit the backlog intent + the product stack automatically."
   - **Headless:** the upstream caller reads `BUILD_FLEET_NEXT_FEATURE` and dispatches
     `/build-fleet:new-feature <slug>` itself.

## Hard rules

- **No prioritization policy.** Resolver only; never reorder/skip/judge importance.
- **Never duplicate new-feature.** M4 resolves + gates + signals; new-feature starts.
- **Never run `/build-fleet:new-feature` inline** — the dispatcher does that (preserves
  caller-side control; keeps M4 mode-agnostic without needing to detect headless vs interactive).
- **Never advance past a thin intent** (would force new-feature to STOP-and-ask).
- **Headless contract.** Every branch emits exactly one `BUILD_FLEET_NEXT_FEATURE*:` line
  before any prose.

## Refusal contract (machine-readable)

A slash command runs inside the model session and **cannot set a process exit
code** — the session exits 0 either way. The `BUILD_FLEET_NEXT_FEATURE*` signal
lines on stdout are the **sole machine contract**: `BUILD_FLEET_NEXT_FEATURE`
(status `next` / `complete` / `no-backlog`) = resolved or informational no-op;
`_REFUSE` / `_NEEDS_DESC` = refused, the JSON carrying `"code"` (an integer
preserving the legacy exit-code semantics: `2` = refused) and `"reason"` (a
kebab-case slug). Orchestrators dispatch on the signal line, never on the
process exit status.
