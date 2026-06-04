---
name: sdd-protocol
description: The canonical spec-driven development protocol for the build-fleet agent software house. Defines the SPEC → REVIEW → FINALIZE → BUILD → CHANGE-REVIEW → HANDOFF state machine, the .sdd/ workspace layout and file ownership, the deterministic phase gates, the bounded review-cycle and human-escalation policy, and the blocker/major/minor severity rubric. This is the single source of truth for how the fleet runs. Consult it whenever orchestrating a feature, transitioning phases, running a review, finalizing a spec, handing off to devops, or deciding whether to escalate — and any time a build-fleet command or role agent (product-owner, architect, coder, qa, devops) needs the workflow rules.
---

# SDD Protocol

This skill governs the runtime behaviour of the **build-fleet** software house. Commands
and role agents defer to it for the workflow, gates, and escalation rules. It is the
authority: where any agent prompt, command body, or stale CLAUDE.md disagrees with this
file, this file wins.

## Operating principles

- **Spec is the contract.** No source is written until the active spec is `FINALIZED`.
- **Gates are deterministic; judgments are adversarial.** Binary phase transitions are
  enforced by hooks (exit code 2 = block + feedback). Convergence judgments (e.g., "is
  the spec sound enough to finalize?") run as workflow cross-examination + survival vote
  (see REVIEW phase). The category error to avoid is hook-enforcing a judgment.
- **Filesystem is shared memory.** Subagent context is isolated and does not sync between
  roles. Everything that must cross roles lives as a file in `.sdd/<feature>/`. There is
  no per-agent persistent memory layer.
- **Escalate, don't loop forever.** Each review gate is bounded (default **3** cycles).
  In v0.2, one `/build-fleet:review` workflow run = one cycle. Cross-examination rounds
  inside a single workflow run do NOT bump the cycle counter. The 4th unresolved cycle
  writes `ESCALATION.md` and halts that phase for a human.
- **The orchestrator routes, it does not build.** The main session assigns work, runs
  gates, and synthesizes. It never writes production source itself.
- **One feature in flight.** `.sdd/ACTIVE` names the single active feature.

## Workspace layout and ownership

```
.sdd/
  ACTIVE                 # one line: the active feature slug. Empty = no active feature.
  <feature>/
    spec.md              # product-owner. STATUS line + spec body. Source of truth.
    acceptance.md        # product-owner. Testable acceptance criteria.
    DECISIONS.md         # architect. Append-only ADR log.
    TEST_PLAN.md         # qa. Test design mapped to acceptance criteria.
    IMPL_NOTES.md        # coder. Implementation notes and deviations.
    REVIEW.md            # reviewers. Append-only review log (see format below).
    PROGRESS.md          # orchestrator. Phase + cycle state (schema below).
    SKILL_MANIFEST.md    # orchestrator (from classifier). OPTIONAL (v0.4 M1). Per-role domain skills to load at BUILD.
    ESCALATION.md        # exists only when a gate has exhausted its cycles.
```

Write boundaries (enforced by hooks):
- `product-owner` writes `spec.md`, `acceptance.md`.
- `architect` and `qa` are reviewers: they may write **only inside `.sdd/<active>/`**
  (ADRs, REVIEW.md, TEST_PLAN.md). They never write source.
- `coder` writes source + `IMPL_NOTES.md`, only while `PHASE` is `BUILD`.
- `devops` writes CI/CD, IaC, release artifacts, only after CHANGE-REVIEW approval.

`.sdd/ACTIVE` empty (or absent) means no feature is active; all write-gating hooks then
allow operations through. Every hook resolves the active feature by reading this file —
never an environment variable.

## Product tier (v0.4 M0) — inherited context only

A repo may optionally carry a **product tier** above the flat feature dirs. It lives in a
reserved `.sdd/_product/` namespace (the underscore prevents collision with any feature
slug). A repo with no `.sdd/_product/` is a plain feature-first repo — the product tier is
**purely additive**; its absence changes nothing.

```
.sdd/
  _product/              # the product tier. Created by /build-fleet:new-product.
    vision.md            # product-owner. Overview/Goals (+ Non-goals/FAQ/OUTCOME for standard|large).
    backlog.md           # product-owner. Phased feature list + completion markers.
    STACK.md             # architect. The stack-of-record — inherited READ-ONLY by every feature.
    DECISIONS.md         # architect. Append-only product ADR log (the *why* behind STACK.md).
    PROGRESS.md          # orchestrator. PRODUCT / SIZE / UPDATED (PHASE added by M3.1).
  PRODUCT                # v0.4 M3.0 — one-line product slug marker (mirrors ACTIVE). resolve_product() reads it.
  ACTIVE                 # unchanged — the single active feature.
  <feature>/             # unchanged — features stay flat, NOT nested under _product/.
```

**Product-tier foundations (v0.4 M3.0).** Two behavior-preserving primitives are
in place ahead of the outer state machine (M3.1+):
- `resolve_product()` (`hooks/scripts/_lib.sh`) echoes the product slug from the
  `.sdd/PRODUCT` marker (or the `_product/PROGRESS.md` `PRODUCT:` field). **Dormant
  in M3.0** — no gate keys off it yet; it mirrors `resolve_active()` for the
  product tier.
- The scribe accepts an optional envelope `workspace_dir` (CONTRACT §6): when set
  (e.g. `.sdd/_product/`) it writes there instead of `.sdd/<feature>/`, so
  product-scope workflows (M3.1's `plan-review`) can apply state — including
  `.sdd/_product/ESCALATION.md`. Absent ⇒ byte-identical v0.2 feature-scope behavior.

**M0 is inherited context only.** There is no product state machine, no product review
gate, no scribe, and no new hook. The files are plain DRAFT artifacts edited directly.
The outer PLAN → PLAN_REVIEW → PLAN_FINALIZE → DEVELOPING machine, CLAUDE.md generation,
and the phased build loop are later v0.4 milestones (see ROADMAP).

**Greenfield vs brownfield.** `/build-fleet:new-product` works on both. On a
greenfield repo the architect *ratifies* a new stack from the product description.
On a **brownfield** repo (real source/manifests already present) the architect
*infers and records the actual stack* from the code as the **binding
stack-of-record** (a `## Baseline (current)` section) — never hallucinating or
silently rewriting it. A forward/migration direction is allowed only as an
explicitly **`PROVISIONAL` (unreviewed)** section + ADRs tagged
`STATUS: PROVISIONAL`; because M0 has no product review gate, provisional forward
entries are strategy that **do not bind features** until ratified (M3 plan-review,
or an explicit human edit promoting the ADR). `/build-fleet:new-product` writes
only `.sdd/_product/`, never source, so it is safe to run against an existing
codebase; an existing root `CLAUDE.md` is untouched (M0 does not generate one —
that is M3).

**The inheritance contract:**
- `.sdd/_product/STACK.md` is the product's stack-of-record. When `/build-fleet:new-feature`
  runs and this file exists, it is read into the classifier + product-owner prompts as
  read-only context. Features inherit the **binding** stack — everything in STACK.md
  not marked provisional (a `## Forward direction (PROVISIONAL — unreviewed)` section,
  or per-line `PROVISIONAL` tags); if nothing is marked provisional, the whole stack
  binds (greenfield, or a fully-adopted brownfield). Any provisional forward entries are
  advisory and do **not** constrain a feature until promoted. A feature's own
  `DECISIONS.md` must not contradict the binding product stack.
  A genuine need for a different stack is a signal to **revise the product tier** (edit
  STACK.md + append a product ADR), not a feature-local override. This is the fix for the
  latent bug where two features could independently pick conflicting stacks (feature-scoped
  `DECISIONS.md` has no cross-feature authority; product `DECISIONS.md` does).

**Hook interactions (M0):**
- `block-source-before-finalized` permits all `.sdd/_product/*` writes (any path under
  `.sdd/` is allowed; and it exits early when there is no active feature).
- `restrict-reviewer-writes` confines **all** writes to `.sdd/<active>/` while the active
  feature's `PHASE` is `REVIEW` or `CHANGE_REVIEW` (phase-based, not role-based). Therefore
  `/build-fleet:new-product` **refuses to run** while a feature is in those two phases —
  the product foundation is not reshaped mid-review. All other active-feature phases are
  fine; `/build-fleet:new-product` never touches `.sdd/ACTIVE`.
- No hook validates `vision.md`/`STACK.md` STATUS in M0 (`validate-spec-status` fires only
  on files named `spec.md`). Their STATUS lines are forward-compat for the M3 gate.

## Product tier — PLAN state machine (v0.4 M3.1)

The product tier gains an **outer state machine**, mirroring the feature tier one level
up but with an inverted temperament. A feature spec is a contract the machine can
**adversarially converge** (REVIEW's survival vote kills concerns refuted with a section
cite). A product plan is a **strategic bet** the machine must not converge — it surfaces
risk and a human chooses. So:

```
feature:   SPEC  →  REVIEW (survival vote)        →  FINALIZE (deterministic gate)  →  BUILD
product:   PLAN  →  PLAN_REVIEW (interrogation)    →  PLAN_FINALIZE (human ratifies)  →  DEVELOPING
```

`.sdd/_product/PROGRESS.md` carries `PHASE: PLAN | PLAN_REVIEW | DEVELOPING | ESCALATED`
and a `CYCLE` counter (the plan-review cycle; mirrors the feature `CYCLE`).
`/build-fleet:new-product` seeds `PHASE: PLAN`, `CYCLE: 0`. *(`PLAN_FINALIZE` names the
ratification **gate**, not a persisted resting phase — the gate is synchronous and writes
`PLAN_REVIEW → DEVELOPING` directly; PROGRESS never rests at `PLAN_FINALIZE`.)*

**PLAN_REVIEW (`/build-fleet:plan-review` → `workflows/plan-review.js`).** A **fork** of
`review.js` (the M3.0 decision: fork, don't parameterize). Roles `[product-owner,
architect, qa]` **interrogate** the product artifacts (`vision/backlog/STACK/DECISIONS.md`)
from their lenses, each returning structured `findings` (`kind: question|risk|gap`,
`severity: blocker|major|minor`). The workflow **consolidates by pure JS** (groups + counts)
— there is **no cross-examination, no survival vote, nothing auto-killed** — and the scribe
appends an interrogation report to `.sdd/_product/REVIEW.md`, setting `PHASE=PLAN_REVIEW`.
The scribe writes the product workspace via the envelope's `workspace_dir=".sdd/_product/"`
(CONTRACT §6). plan-review **never auto-escalates**: a missing interrogator payload halts the
run *without writing* (re-run), and the only thing that writes `_product/ESCALATION.md` is a
human. Self-interrogation by the artifact's author (PO interrogating its own vision) is fine —
the act surfaces risk, it does not vote.

**PLAN_FINALIZE (`/build-fleet:plan-finalize`) — the ratification gate.** A product plan is
**ratified, never auto-decided**, so this gate **never auto-passes — even with zero findings**:
- *Bare* `/build-fleet:plan-finalize` is a **dry-run**: it prints the latest interrogation
  report + open `[blocker]` count and **halts**. In headless mode (`claude -p`) this is the
  whole safety story — it cannot ratify itself.
- `ratify` flips state **iff** zero open blocker-severity findings; open blockers → refuse.
- `ratify force` flips over open blockers, recording them as consciously accepted.
- Small fast-path: `SIZE=small` + `PHASE=PLAN` + `CYCLE=0` may ratify without a prior
  plan-review (mirrors the trivial-feature fast-path; treats open-blocker count as 0).

On ratification it edits `vision.md` + `backlog.md` `STATUS: FINALIZED` and sets
`PHASE: DEVELOPING`. It also flips `STACK.md` `STATUS: FINALIZED` **conditionally** — only
when the stack is **fully binding** (no `## Forward direction (PROVISIONAL — unreviewed)`
section and no `PROVISIONAL`-tagged lines); when provisional/forward content is present,
`STACK.md` STATUS is **left untouched** (the file still holds un-ratified strategy, so
labelling it `FINALIZED` would be dishonest). Either way it **does NOT promote** any forward
direction or `STATUS: PROVISIONAL` ADR — ratification finalizes the plan **as written**; the
binding stack stays whatever is currently un-tagged. Auto-promoting provisional strategy would
be the machine choosing direction, which this gate must never do. `DECISIONS.md` (per-ADR
STATUS, architect-owned) is never edited by the gate.

**Ratification is advisory (M3.1 decision).** Setting `PHASE=DEVELOPING` does **not** gate
`/build-fleet:new-feature` — features build against the binding stack regardless of product
phase, preserving the M0/M1 inheritance behavior. The product machine's "teeth" are the M3.2
**DEVELOPING loop** (which clears `.sdd/ACTIVE` on completion and arms the next backlog
feature — see the DEVELOPING-loop section), not a feature-creation block.

### Product memory — root CLAUDE.md generation (v0.4 M3.1.1)

On ratification, build-fleet seeds the repo's Claude memory with the ratified product so
**any** Claude Code session (not just build-fleet commands) inherits the vision + **binding**
stack. The generation is owned by this skill (one algorithm, two callers): `/build-fleet:plan-finalize`
triggers it on the ratify-flip (best-effort), and `/build-fleet:product-memory` is the
standalone (re)generation path (refresh after editing the plan, or recover a deferred write).

**The block** — a single delimited region in the repo-root `./CLAUDE.md`:

```
<!-- BEGIN build-fleet:product -->
## Product: <slug>
_Generated by build-fleet (`/build-fleet:plan-finalize` · `/build-fleet:product-memory`) — edits between these markers are overwritten on regeneration; edit `.sdd/_product/` instead. Add your own notes outside the markers; they're preserved._

<vision one-liner: first sentence of vision.md ## Overview, or the OUTCOME: line if present>

**Binding stack** (the stack-of-record every feature inherits — see `.sdd/_product/STACK.md`):
- <concise bullets distilled from STACK.md's sections>
_Provisional/forward-direction entries are excluded — they do not bind._

**Conventions**: <distilled from STACK.md ## Conventions, or "see .sdd/_product/STACK.md">

**Source of truth**: the product tier lives in `.sdd/_product/` (vision, backlog, STACK,
DECISIONS); the feature backlog + phases are in `.sdd/_product/backlog.md`. build-fleet
commands drive features against this plan. This block is a generated summary — edit the
`.sdd/_product/` files, then re-run `/build-fleet:product-memory` to refresh it.
<!-- END build-fleet:product -->
```

**Generation algorithm (non-clobbering + idempotent):**
1. Distil the content above from `.sdd/_product/{vision,STACK}.md` and the product slug.
   **Exclude** any `## Forward direction (PROVISIONAL — unreviewed)` section and any
   `PROVISIONAL`-tagged lines from the binding-stack bullets — the block reflects only
   what currently binds. **Brownfield "all-provisional" fallback:** if STACK.md has *no*
   binding entries because everything is a provisional forward direction, use the
   `## Baseline (current)` content as the binding stack (the brownfield baseline *is* the
   stack-of-record) and add a one-line note that a forward direction exists but does not
   yet bind. Never emit an empty binding-stack section.
2. **Detect the existing block by PREFIX, not full line.** The block is present iff a line
   starts with `<!-- BEGIN build-fleet:product` (match the prefix only — the trailing prose
   after the slug may change between versions); its region runs to the next line equal to
   `<!-- END build-fleet:product -->`. A brittle full-line match on the BEGIN marker would
   miss a prose-tweaked block and append a duplicate (breaking idempotency).
3. Splice into `./CLAUDE.md`:
   - **No file** → `Write` it containing just the block.
   - **Block present** (prefix match per step 2) → `Edit` it in place: `old_string` = the
     entire existing region from the `<!-- BEGIN build-fleet:product…` line through the
     `<!-- END build-fleet:product -->` line; `new_string` = the freshly-generated block.
     **Everything outside the region is preserved byte-for-byte** by Edit's exact-match.
   - **Block absent** (an existing hand-written `CLAUDE.md`) → **append via `Edit`**:
     `old_string` = the file's current final line, `new_string` = that same line + a blank
     line + the block. Prefer this over a Read→reconstruct→`Write`: anchoring the append on
     `Edit` makes NON-CLOBBERING structural (exact-match) rather than dependent on faithfully
     re-emitting the whole file. **Never modify pre-existing content.**

**Block-source caveat (why generation can be deferred).** `./CLAUDE.md` is **outside**
`.sdd/`, so `block-source-before-finalized` blocks the write whenever `.sdd/ACTIVE` names a
feature whose `spec.md` STATUS ≠ `FINALIZED`. The generating command **pre-checks** this and,
if the write would be blocked, **skips generation with a deferred note** rather than fighting
the gate — the ratification flip itself (all in `.sdd/_product/`) always succeeds. The escape
hatch is `/build-fleet:product-memory`, run once no feature is mid-non-finalized. (We do
**not** whitelist `CLAUDE.md` in the gate — keeping the FINALIZED gate uniform is worth the
occasional deferral.)

**Hook interactions (M3.1):**
- `validate-backlog-status.sh` (new, PostToolUse) keys on `basename==backlog.md` under
  `.sdd/_product/` — feature dirs have no `backlog.md`, so no collision. It requires a
  `PRODUCT:` header, a valid `STATUS` line, and ≥1 `## Phase N:` heading (structural presence,
  not per-row grammar).
- Both `/build-fleet:plan-review` and `/build-fleet:plan-finalize` **refuse while a feature is
  in `REVIEW`/`CHANGE_REVIEW`** — `restrict-reviewer-writes` confines all writes to
  `.sdd/<active>/` during feature review (so the product scribe / the STATUS flips could not
  write `.sdd/_product/`), and the interrogator roles overlap the feature-reviewer set so a
  mid-review feature would mis-fire `check-review-written`. This single guard (the same one
  `/build-fleet:new-product` uses) covers both hooks; no hook needed teaching about `_product`.
- The product scribe removes `.sdd/_product/.workflow-in-flight` (resolved under the envelope's
  `workspace_dir`); `reap-stale-workflow-markers` reaps it if orphaned (it scans depth-2, which
  includes `_product/`).

## Backlog completion (v0.4 M2)

`.sdd/_product/backlog.md` rows track per-feature completion. Row format:
`- [ ] <slug>   PENDING   depends-on: <none|slug>`, optionally **followed by an
indented 1–3 line intent** (v0.4 M3.3 — see below). On a successful
`/build-fleet:handoff` (devops done), the orchestrator flips the matching row to
`- [x] <slug>   DONE   depends-on: <unchanged>   handoff:<iso-date>` and recomputes
the containing `## Phase N: … — STATUS:` line (`complete` when all its rows are `[x]`,
else `in-progress` if any are, else `pending`). This is an **orchestrator-direct
write** — not the scribe (the scribe is append-only; product-scope writes are M3's
concern, and M3 re-points them through the scribe's `workspace_dir`). A feature with
no matching backlog row (an ad-hoc fix) is left untouched. "Active in flight" is
**derived from `.sdd/ACTIVE`**, not a backlog marker — there is no `[>]` state to
keep in sync.

### Per-feature intent (v0.4 M3.3)

A backlog row carries only a slug + dependency; that loses the plan author's *intent*
for the feature across the tier boundary, so `/build-fleet:new-feature` would re-guess
the scope from a bare slug. M3.3 adds an **indented 1–3 line intent** under each row:

```
## Phase 1: Foundations — STATUS: pending
- [ ] cli-skeleton   PENDING   depends-on: none
      Cobra root command + global --format flag wiring; the app shell other commands hang
      off. No data commands, no rendering, no persistence (those are later features).
- [ ] api-client     PENDING   depends-on: cli-skeleton
      The internal/yahoo typed HTTP wrapper — the sole package that talks to Yahoo.
      Network only: rendering is output-formatter; config is local-config-store.
```

- **It is a sketch, not a spec.** What the feature is + its scope boundary + explicit
  non-goals/deferrals to sibling features. The boundary/deferral facts are the high-value
  part — they keep siblings from overlapping or leaving a gap, and they justify the
  `depends-on` edges. **No** acceptance criteria / interfaces / detailed behavior — those
  stay in the feature's `spec.md`, drafted by the PO and adversarially reviewed at
  `/build-fleet:new-feature` time. The intent is *inherited advisory context* (like the
  stack); the spec is the contract. Two sources of truth for behavior would rot apart and
  make the per-feature review redundant — so the line holds at boundary-level.
- **Authored** by the PO at `/build-fleet:new-product` (it already conceived each feature
  when phasing it). **Inherited** at `/build-fleet:new-feature`: step 5 seeds the feature
  description from the intent, and step 8 hands it to the PO to *realize and elaborate*
  (the PO flags any deviation in `## Self-review notes`).
- **Reviewed, not blindly trusted.** Result quality tracks intent quality, so PLAN_REVIEW
  (M3.1) explicitly interrogates the intents — clarity (can it drive a spec?), clean
  sibling boundaries (no overlap/gap), and whether the stated boundaries justify the deps.
  A vague or wrongly-bounded intent is a finding to fix before ratifying, not silent input
  to a downstream spec.
- **Parser-invisible.** The intent lines have no `- [`/`##` prefix, so the M3.2 resolver,
  `validate-backlog-status`, and the M2 completion-flip (which edits only the `- [ ]` row
  line) all ignore them — the flip preserves the intent untouched.
- **Backward-compatible.** A legacy slug-only row (no intent) works exactly as before; the
  PO drafts from the user's description.

## DEVELOPING loop (v0.4 M3.2)

M3.2 closes the multi-feature loop. **The motivating gap:** `/build-fleet:handoff`
shipped a feature but never cleared `.sdd/ACTIVE`, and `/build-fleet:new-feature`
hard-refuses while `.sdd/ACTIVE` is non-empty — so after shipping feature N there was
no in-plugin way to start N+1 (a manual `rm .sdd/ACTIVE` was required). The
**complete-N → arm-N+1** transition fixes that.

On a **full** `/build-fleet:handoff` completion (devops succeeded + the M2 backlog flip
ran — *not* a CHANGE_REVIEW bounce-back to BUILD), when a product tier exists, handoff:
1. **Clears `.sdd/ACTIVE`** (empties the file — the shipped feature is no longer in
   flight). This is what unblocks the next `/build-fleet:new-feature`. Safe: with no
   active feature, `block-source-before-finalized` and the per-reviewer hooks are simply
   inactive — correct between features.
2. **Re-resolves the next unblocked feature from the LIVE backlog** — *first `PENDING`
   row in the lowest phase whose `depends-on` are all `DONE`* — via the shared
   deterministic resolver `scripts/next-feature.sh`. Re-resolving live (never a cached
   index) means a mid-flight backlog re-prioritization is always honored. The resolver
   is the **single source of truth**: `/build-fleet:handoff`, `/build-fleet:status`, and
   (M4) `/build-fleet:next-feature` all call it instead of re-deriving dependency math in
   prose.
3. **Surfaces — does not auto-start.** Advancement policy stays with the human/orchestrator
   (orchestrator-agnosticism): handoff *reports* the next slug; running
   `/build-fleet:new-feature <slug>` is an explicit act.

**The advancement convenience (v0.4 M4) — `/build-fleet:next-feature`.** Optional. It calls
the **same resolver**, pre-checks readiness (no feature in flight; the next feature's intent
passes the M3.3 quality floor), and emits a dispatch signal `BUILD_FLEET_NEXT_FEATURE:
{slug, phase}` — collapsing "read `/status` → type `/new-feature <slug>`" into one gated step.
It is **convenience, not policy**: resolver only (no reorder/skip/judgement), and it **does
not run `/build-fleet:new-feature` itself** — the dispatcher (the upstream caller in headless,
the human in interactive) starts the feature, which keeps dispatch + caller-side policy with
the orchestrator and avoids duplicating new-feature's logic. If the next feature's intent is
too thin to start unattended it refuses (`NEEDS_DESC`) rather than letting new-feature
STOP-and-ask mid-dispatch. *(Distinct from the v0.2 "M4" classifier that sets TIER/BUILD_MODE —
same label, different milestone series.)*

**Resolver outcomes** (`scripts/next-feature.sh` emits one JSON line):
`next` (slug + phase) · `complete` (all rows `[x]`, `total>0`) · `deadlocked` (`PENDING`
rows remain but none unblocked — a dependency cycle / unsatisfiable edge) · `empty` (a
backlog with no parseable feature rows, `total=0` — distinct from `complete` so an
unparseable backlog never reads as "fully shipped") · `no-backlog` (file absent). The
resolver strips `\r` (CRLF-safe) and tolerates `[x]`/`[X]`/`-`/`*`/`none`/`None`; it has a
committed test harness (`scripts/next-feature.test.sh`).

**Terminal & deadlock are derived, not stored** (matching M2's derive-don't-store):
- **Complete** is computed from the backlog (every row `[x]`) — there is **no terminal
  `PHASE` value**. Appending features/phases to `backlog.md` re-opens the loop automatically.
- **Deadlock** is a runtime **warning** (check `depends-on` / cycles), **not** an escalation
  — the human reorders deps; nothing auto-halts.

**`PHASE=DEVELOPING`** is the product state during this loop. The arming above engages
whenever a product backlog is present; the phase is reported for context, not used as a
hard gate (a feature can be shipped before ratification too — the loop just tracks it).

## Skill routing (v0.4 M1) — domain skills to BUILD roles

build-fleet stays **process machinery**; it ships no domain-craft skills. What it
ships is a routing convention (the **`skill-routing` skill**): the classifier maps a
feature's stack + type to the *names* of domain skills, and the BUILD roles load
them **if available**. Flow:

- **Classifier** (at `/build-fleet:new-feature`) emits a `skill_manifest` in its JSON
  verdict, derived from the inherited binding stack (`.sdd/_product/STACK.md`, when a
  product tier exists — see M1's dependence on M0), the feature description, and the
  project. It writes no state.
- **`/build-fleet:new-feature`** persists a non-empty manifest to
  `.sdd/<feature>/SKILL_MANIFEST.md`. An empty/null manifest writes no file — absence
  means "no routing," and BUILD runs exactly as plain v0.2 (additive/backward-compatible).
- **coder / qa** read `SKILL_MANIFEST.md` at BUILD and load+apply the skills listed
  for their role; the orchestrator's BUILD delegation (`/build-fleet:finalize`, and the
  `deep-build` workflow's coder prompt) also points them at it. Skills load by
  name-mention in the agent's reasoning, not frontmatter — so it works in every
  execution mode (incl. agent-team mode, which ignores per-agent frontmatter skills).

Semantics: routing is **advisory and never gates**. A named skill that isn't
installed is a no-op (the role records `skill-unavailable: <name>` and proceeds). The
manifest never changes `tier`/`build_mode` or any deterministic gate; it only enriches
*how* a role works, never *whether* a gate passes. `tools_recommended` in the manifest
is **recorded only / informational in M1** — no path binds tools yet (skills-first
scope); wiring it into the `deep-build` workflow's `AgentDefinition.tools` is a later
increment. See the `skill-routing` skill for the manifest schema and the stack→skill
mapping table.

## PROGRESS.md schema

Exact field names; hooks and commands parse these lines:

```
FEATURE: <slug>
PHASE: SPEC | REVIEW | FINALIZE | BUILD | CHANGE_REVIEW | HANDOFF | ESCALATED
CYCLE: <int>          # spec-review cycles consumed (one increment per /build-fleet:review workflow run; cross-examination rounds inside a run do not bump CYCLE)
CHANGE_CYCLE: <int>   # change-review cycles consumed (one increment per /build-fleet:handoff invocation; still command-driven in v0.2 until M3 converts CHANGE_REVIEW to a workflow)
TIER: trivial | standard | large    # v0.2 M4 — set by the classifier subagent at /build-fleet:new-feature time. `trivial` opts into the REVIEW-skipping fast-path through finalize. `pending` until classifier runs.
BUILD_MODE: standard | deep-build   # v0.2 M3 — selects /build-fleet:finalize's BUILD orchestration. `standard` = sequential qa→coder via Task tool. `deep-build` = dispatch workflows/deep-build.js. M4's classifier sets this to `deep-build` for tier=large. `pending` until classifier runs.
UPDATED: <iso8601>
```

## spec.md STATUS line

The first line of `spec.md` is always:

```
STATUS: DRAFT | IN_REVIEW | FINALIZED | BLOCKED
```

`validate-spec-status` (PostToolUse on spec.md) rejects a write whose STATUS is missing or
not one of the four values, or whose required sections are absent.

## REVIEW.md entry format

Append-only. Reviewers add one block per cycle; never edit prior blocks. Resolution of a
concern is a *new* approving entry in a later cycle, not an edit.

```
## Cycle <N> — <role> — <iso8601>
- [blocker] <concern>
- [major]   <concern>
- [minor]   <concern>
status: concerns-raised | approved
```

`check-review-written` (SubagentStop) rejects a reviewer that stops without appending a
block attributed to it for the current cycle. In v0.2 workflow REVIEW: the workflow's
reviewer subagents return structured concerns payloads; the workflow script merges them
into the canonical REVIEW.md entries; the `scribe` subagent appends them in the final
phase. The hook skips its gate while `.sdd/<feature>/.workflow-in-flight` exists (the
workflow's envelope post-condition replaces it for workflow paths). Non-workflow paths
(CHANGE_REVIEW until M3) retain the hook's per-reviewer enforcement.

## Severity rubric

| Severity | Definition | Gate effect |
|---|---|---|
| `blocker` | Correctness, security, data loss, or a contradiction of the spec/acceptance. | Blocks FINALIZE and HANDOFF. |
| `major` | Scalability, maintainability, or missing acceptance coverage. | Must be resolved or explicitly accepted (as an ADR) before the gate opens. |
| `minor` | Style, wording, nits. | Advisory; never blocks a gate. |

The severity vocabulary is mirrored verbatim in each reviewer agent's prompt body for
non-workflow direct invocations and as belt-and-suspenders if `AgentDefinition.skills`
preload regresses. In v0.2 workflow REVIEW the orchestrator preloads `review-rubric` via
`AgentDefinition.skills`, so the in-body copy is the redundancy, not the primary source.

## State machine

```
SPEC ──► REVIEW ──► FINALIZE ──► BUILD ──► CHANGE_REVIEW ──► HANDOFF
          ▲  │                              ▲       │
          └──┘ (≤3 cycles, then ESCALATE)   └───────┘ (≤3 cycles, then ESCALATE)
```

**SPEC.** `/build-fleet:new-feature <slug>` scaffolds `.sdd/<slug>/`, runs the
classifier subagent (M4) to set `TIER` + `BUILD_MODE` in PROGRESS.md, and
delegates to product-owner to draft `spec.md` (STATUS=DRAFT) + `acceptance.md`.
For `TIER=trivial`, PO drafts a minimal skeleton spec from the classifier's
`skeleton_spec_hint`; for standard/large, PO drafts the full spec.

Exit: a non-empty spec with all required sections exists.

**M4 trivial fast-path.** Features classified `trivial` skip the REVIEW phase
entirely. The user invokes `/build-fleet:finalize` directly after PO drafts the
skeleton spec; finalize recognizes `TIER=trivial` and proceeds to BUILD without
requiring a completed review cycle. This saves the review tokens for changes
genuinely small enough that the gate cost exceeds the gate value (typo fixes,
dependency bumps, single-line bug fixes). See `agents/classifier.md` for the
criteria and disqualifiers; the classifier errs toward `standard` because
false-trivial is the dangerous miss (skips a review the change needed).

**REVIEW.** `/build-fleet:review` invokes the `workflows/review.js` dynamic workflow with
the current feature and cycle number (`args.feature`, `args.cycle`). The command writes
`.sdd/<feature>/.workflow-in-flight` before dispatch (a marker that makes the two
reviewer-gating hooks skip while a workflow is running); the scribe deletes it as the
workflow's final phase. The `scribe` is a workflow-internal Write-capable subagent (see
`agents/scribe.md`) — not a fleet role like architect/qa/coder, but the single canonical
writer of workflow-driven state mutations.

The workflow runs five phases internally:

1. **Read state** — a Read-only subagent collects spec.md, acceptance.md, prior REVIEW.md.
2. **Fan-out** — architect, qa, coder subagents review in parallel. Each returns a
   structured concerns payload `{role, status, concerns:[{id,severity,text}]}`. Their
   `AgentDefinition.tools` omits `Write`/`Edit`; their `AgentDefinition.skills` preloads
   `review-rubric` (replacing the v0.1 rubric duplication in agent prompt bodies).
3. **Cross-examination** — each reviewer is presented with peers' concerns and must
   refute or affirm each. A refutation must (a) be ≥40 characters, (b) cite a section
   of spec.md or acceptance.md as counter-evidence (regex: `(spec|acceptance)\.md\s*§|line\s+\d+`),
   (c) come from a different-role reviewer (self-refutation is filtered).
4. **Survival vote** — pure script logic. A concern survives unless refuted by a
   different-role reviewer with substantive reasoning. Survivors are the cycle's verdict.
5. **Apply via scribe** — the `scribe` subagent applies the structured envelope to
   PROGRESS.md (`state_delta`) and REVIEW.md (`review_entries`), writes ESCALATION.md
   when `escalation_payload` is non-null, and removes `.workflow-in-flight`.

Convergence rule (replaces v0.1 "all approved with zero blockers"):

> A concern survives unless explicitly refuted by another reviewer during
> cross-examination. The cycle is *clean* iff zero surviving `[blocker]` items.

Verdict semantics:
- `clean` — zero surviving blockers. Next command: `/build-fleet:finalize`.
- `revise` — surviving blockers; CYCLE < 3. Next command: `/build-fleet:review` after PO
  revises spec.md.
- `escalate` — surviving blockers; CYCLE >= 3. Workflow's scribe writes ESCALATION.md,
  sets PHASE=ESCALATED, halts.

The v0.1 cycle-3 agent-team fallback is retired entirely — workflow cross-examination
replaces it.

**FINALIZE.** `/finalize` runs the finalize gate. Permitted only when the most recent
review cycle is fully approved with no open blockers. On success: set STATUS=FINALIZED,
PHASE=BUILD. The source-write block lifts at this point and not before.

**BUILD.** Sequential, tests-first (v0.2 M2 ordering — replaces v0.1 parallel BUILD).
`/build-fleet:finalize`, on a successful gate, dispatches qa first then coder:

1. **qa drafts TEST_PLAN.md + writes failing tests.** Per the `test-plan` skill, qa
   builds the coverage matrix from acceptance.md and implements the test suite under
   `tests/`. Each test must initially FAIL — no source exists yet. qa signals the
   orchestrator with `BUILD_FLEET_QA_TESTS_READY: <count> failing tests in tests/` when done.
2. **coder implements to spec.** Coder refuses to begin until QA's failing tests exist
   in `tests/` and all fail (a passing test against an empty implementation isn't testing
   behavior). Coder iterates until every QA test passes. `gap:` / `deviation:` / `todo:`
   markers go in `IMPL_NOTES.md` per its prompt body.

coder refuses to start while STATUS ≠ FINALIZED (enforced by `block-source-before-finalized`).
coder also refuses if no failing tests exist in `tests/` (self-enforced per `agents/coder.md`;
the v0.1 hook layer does not gate this — Phase 5 hardening or M3 may add a hook).

Exit: implementation exists, every qa test passes, IMPL_NOTES.md lists any gaps/deviations.

### BUILD variants (v0.2 M3)

Two BUILD execution modes — selected by `PROGRESS.md`'s `BUILD_MODE` field. v0.2 M4
sets this automatically via the classifier at `/build-fleet:new-feature` time
(`tier=large` → `deep-build`; everything else → `standard`). Manual override is
possible via direct PROGRESS.md edit or by invoking `/build-fleet:deep-build`
explicitly:

- **`BUILD_MODE: standard`** — the M2 sequential qa-then-coder pattern described
  above. `/build-fleet:finalize` orchestrates it via the Task tool. v0.2 M4's
  classifier sets this for `tier=trivial` and `tier=standard`; manual override
  via direct PROGRESS.md edit is supported.
- **`BUILD_MODE: deep-build`** — for multi-file / multi-package features.
  `/build-fleet:finalize` runs qa first (same as standard), then routes the
  implementation phase to the `workflows/deep-build.js` workflow. The workflow's
  architect subagent designs a file partition; N coders (default 3, max 8) fan out
  in parallel against M2's pre-existing failing tests; an adversarial review
  sub-phase (architect for design, qa for coverage + counterfactual) catches gaps
  before BUILD is declared complete. The scribe aggregates results into
  `IMPL_NOTES.md` via the envelope's new `impl_notes_appendix` field.

  Until M4's classifier ships, `BUILD_MODE` is set manually (either by editing
  PROGRESS.md or by invoking `/build-fleet:deep-build [N]` directly, bypassing
  finalize's routing logic).

  Verdicts:
  - `clean` → next is `/build-fleet:handoff`.
  - `needs-iteration` → re-run `/build-fleet:deep-build` after addressing the
    surviving concerns recorded in IMPL_NOTES.md.
  - `escalate` → **M3 only emits this on workflow malfunction** (spec not
    finalized at workflow entry, no tests present, partition planning failed,
    or a reviewer/coder returned an unparseable payload). M3 does NOT track
    a cycle counter for deep-build; `needs-iteration` loops unbounded until
    the operator either runs `handoff` or manually writes ESCALATION.md to
    halt. Bounded-cycle escalation for deep-build is M3.1 / Phase 5 hardening.

Deep-build is fault-bounded by the workflow runtime's 16-concurrent and
1000-total-agent caps. Plan-approval for the partition happens at workflow launch
in interactive mode (the launch prompt shows the phase list including "Plan file
partition" and "Fan out N coders"); to halt mid-run after a bad partition is
planned, use `/workflows` to stop the workflow.

**CHANGE_REVIEW.** `/handoff` sets PHASE=CHANGE_REVIEW, increments `CHANGE_CYCLE`, and runs
architect + product-owner + qa against the diff:
- architect: design adherence and ADR compliance.
- product-owner: meets `acceptance.md`.
- qa: coverage gaps before handoff; verifies each test would FAIL if coder's source
  change were reverted (the v0.2 M2 counterfactual — a test that passes regardless of
  the source isn't testing behavior, it's decorative).
Exit (to HANDOFF): all three approve with no open blockers. Fail → back to BUILD (bounded
by `CHANGE_CYCLE` ≤ 3, then ESCALATE).

**HANDOFF.** devops takes the finalized, reviewed change → CI/CD, IaC, release notes.

## Hard gates (enforced by hooks)

1. No source write while the active spec STATUS ≠ FINALIZED.
   *(block-source-before-finalized, PreToolUse Write|Edit)*
2. architect/qa may not write outside `.sdd/<active>/`.
   *(restrict-reviewer-writes, PreToolUse Write|Edit — fires on non-workflow review
   paths; workflow REVIEW enforces via `AgentDefinition.tools` allowlists that omit
   `Write`/`Edit` on reviewer subagents. Hook skips while `.workflow-in-flight` marker exists.)*
3. spec.md always carries a valid STATUS line and required sections.
   *(validate-spec-status, PostToolUse Write|Edit on spec.md)*
4. A reviewer cannot stop without recording its review for the current cycle.
   *(check-review-written, SubagentStop — fires on non-workflow review paths; workflow
   REVIEW enforces via the workflow's envelope post-condition that halts the workflow if
   any reviewer returns an empty/malformed concerns payload. Hook skips while
   `.workflow-in-flight` marker exists.)*
5. A session cannot stop on a failing test/lint stack; if no recognized stack exists yet,
   the Stop hook is a silent no-op so bootstrap and empty repos don't deadlock.
   *(stop-tests, Stop)*

`TaskCompleted` and `TeammateIdle` (agent-teams-only) are intentionally **not** shipped.
v0.2 retires the agent-teams fallback entirely — workflow cross-examination replaces the
cycle-3 team debate path.

## Escalation

When a review gate exhausts its cycle budget with blockers still open, the responsible
command writes `.sdd/<feature>/ESCALATION.md` containing: the phase, the cycle count, the
unresolved blockers (verbatim from REVIEW.md), and the conflicting positions. It sets
PHASE=ESCALATED and stops. Escalation is a first-class outcome, not a failure — the human
decides how to break the deadlock.
