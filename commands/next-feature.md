---
description: Resolve the next unblocked backlog feature and gate it for start — the deterministic next (first PENDING in the lowest phase whose depends-on are all DONE), pre-checked for readiness, emitted as a dispatch signal. A convenience over reading /status then typing the slug; adds NO prioritization policy. (v0.4 M4, optional)
argument-hint: ""
allowed-tools: Read, Bash
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
   BUILD_FLEET_NEXT_FEATURE_REFUSE: {"reason":"feature-in-flight","active":"<slug>"}
   ```
   Exit 2.

2. **Resolve the next feature.** Run the shared resolver (the single source of truth; do
   not re-derive in prose):
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-feature.sh"
   ```
   Branch on its `status`:
   - `no-backlog` → no product tier exists; there is nothing to advance. Tell the user to
     use `/build-fleet:new-feature <slug>` directly. Emit
     `BUILD_FLEET_NEXT_FEATURE: {"status":"no-backlog"}`. Exit 0 (informational no-op).
   - `complete` → the product backlog is fully shipped (`done/total`). Nothing to advance;
     congratulate; note that appending features re-opens the loop. Emit
     `BUILD_FLEET_NEXT_FEATURE: {"status":"complete","done":<n>,"total":<n>}`. Exit 0.
   - `deadlocked` → `<pending>` features remain but none are unblocked. Refuse and warn the
     user to check `depends-on` / cycles in `backlog.md`. Emit
     `BUILD_FLEET_NEXT_FEATURE_REFUSE: {"reason":"deadlocked","pending":<k>}`. Exit 2.
   - `empty` → the backlog has no parseable feature rows. Refuse; tell the user to check its
     format. Emit `BUILD_FLEET_NEXT_FEATURE_REFUSE: {"reason":"empty-backlog"}`. Exit 2.
   - `next` → continue to step 3 with the resolved `slug` + `phase`.

3. **Pre-check the intent (headless-safe gate).** Read the resolved slug's **intent block**
   from `.sdd/_product/backlog.md` — and read it **exactly as `/build-fleet:new-feature`
   step 5 does**, so the two reach the same verdict: the run of indented lines (NOT starting
   with `- [` or `##`) immediately under the `- [ ] <slug>` row, up to the next feature row,
   the next `## Phase` heading, or a blank line, whichever comes first (1–3 lines). Apply the
   **M3.3 quality floor**: the intent is *usable* only if it states *what the feature is + its
   scope boundary*. A missing intent, or a thin slug-restatement with no boundary, is **not**
   usable. *(M4 and new-feature MUST use the identical block definition + floor — a mismatch
   would either refuse a feature new-feature would start, or advance one new-feature then
   STOP-and-asks on, defeating this gate.)*

   If the intent is not usable, **do NOT advance** — `/build-fleet:new-feature` would
   STOP-and-ask for a description, which deadlocks an unattended (headless) run. Emit:
   ```
   BUILD_FLEET_NEXT_FEATURE_NEEDS_DESC: {"slug":"<slug>","reason":"intent-too-thin"}
   ```
   Tell the user: the next feature's backlog intent is too thin to start unattended — run
   `/build-fleet:new-feature <slug>` interactively and provide a description (new-feature
   will prompt). Exit 2. *(This honors new-feature's own STOP-and-ask floor up front, instead
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

   Exit 0.

## Hard rules

- **No prioritization policy.** Resolver only; never reorder/skip/judge importance.
- **Never duplicate new-feature.** M4 resolves + gates + signals; new-feature starts.
- **Never run `/build-fleet:new-feature` inline** — the dispatcher does that (preserves
  caller-side control; keeps M4 mode-agnostic without needing to detect headless vs interactive).
- **Never advance past a thin intent** (would force new-feature to STOP-and-ask).
- **Headless contract.** Every branch emits exactly one `BUILD_FLEET_NEXT_FEATURE*:` line
  before any prose.

## Exit codes

| Exit | Meaning |
|---|---|
| 0 | Resolved + signalled `next` (dispatcher starts it); OR informational no-op (`complete` / `no-backlog`) |
| 2 | Refused — feature in flight, `deadlocked`/`empty` backlog, or intent too thin to start unattended |
