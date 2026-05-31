---
description: Initialize the product tier — scaffold .sdd/_product/ (vision, backlog, STACK, product DECISIONS) and delegate product-owner to draft vision + phased backlog and architect to ratify the stack-of-record. Inherited read-only by every feature. No gate, no workflow (v0.4 M0).
argument-hint: "<product-slug>"
allowed-tools: Read, Write, Edit, Task
---

# /build-fleet:new-product

You are the **orchestrator**. You scaffold `.sdd/` state and route work; you do
not author the vision, choose the stack, or write source yourself.

The runtime rulebook is the `sdd-protocol` skill. Consult its **Product tier
(v0.4 M0)** section for the `.sdd/_product/` layout, file ownership, and the
inheritance contract. This command introduces the product tier as **inherited
context only** — there is no outer state machine, no review gate, and no scribe
in M0. Those arrive in later v0.4 milestones.

## Arguments

`$ARGUMENTS` — the product slug. Kebab-case, no whitespace. If empty, refuse and
tell the user a slug is required.

## Refusal cases (check first, in order)

1. **`.sdd/_product/` already exists.** Refuse: a repo has one product tier.
   Tell the user to edit the existing `_product/` files directly, or to inspect
   them with `/build-fleet:status`. Stop.
2. **A feature is mid-review.** Read `.sdd/ACTIVE`; if non-empty, read
   `.sdd/<active>/PROGRESS.md` `PHASE`. If `PHASE` is `REVIEW` or `CHANGE_REVIEW`,
   refuse: the `restrict-reviewer-writes` hook confines **all** writes to
   `.sdd/<active>/` during those phases, so product-tier scaffolding would be
   blocked — and you should not reshape the product foundation while a feature
   review is converging. Tell the user to finish or escalate the active review
   first, then re-run. Stop.
   *(Any other active-feature phase — SPEC, FINALIZE, BUILD, HANDOFF — is fine:
   `/new-product` touches only `.sdd/_product/`, never `.sdd/ACTIVE`, and those
   phases do not engage the reviewer-write restriction.)*
3. **`$ARGUMENTS` is empty.** Refuse; require a slug. Stop.

## Establish the product description

Before scaffolding, determine *what the product is*. Look back through the
conversation for a description the user already gave. **If none exists, STOP and
ask** — do not infer a product from its slug. Ask for: the problem it solves,
who it's for, the rough feature set, and any stack the user already has in mind.
Wait for the answer. Carry it verbatim into the delegations below.

## Size the ceremony (classifier-gated)

Judge product size to keep small products lightweight (mirrors the feature-tier
`trivial | standard | large` axis):

- **small** — a single-purpose tool, a handful of features, one obvious stack.
  Collapse ceremony: `vision.md` may merge Overview/Goals and **omit** the
  `## FAQ` section and `OUTCOME:` field; `backlog.md` may use a single phase.
- **standard / large** — multiple phases or a non-obvious stack. Full ceremony:
  `vision.md` includes `## Non-goals`, `## FAQ`, and an `OUTCOME:` line.

You may reuse the `build-fleet:classifier` subagent for this sizing if the call
is non-obvious; otherwise size it inline from the description. Record the chosen
size in `_product/PROGRESS.md` (`SIZE:` field) so later milestones can read it.
Eight ceremony files before any code on a 3-feature tool is how a product gets
abandoned — bias small.

## What you do

1. **Scaffold `.sdd/_product/`** with these files. Write the scaffolds yourself
   (you have `Write`); the agents fill the bodies (mirrors `/new-feature`, where
   the orchestrator scaffolds and roles author):

   - `vision.md` — first line `STATUS: DRAFT`, then the section headings the
     chosen size requires (Overview, Goals; plus Non-goals, FAQ, and an
     `OUTCOME:` line for standard/large). Leave bodies empty — PO fills them.
     *(No hook validates `vision.md`'s STATUS in M0 — `validate-spec-status`
     fires only on files named `spec.md`. The STATUS line is forward-compat for
     the M3 product-FINALIZE gate.)*
   - `backlog.md` — header:
     ```
     PRODUCT: <slug>
     STATUS: DRAFT

     ## Phase 1: <name> — STATUS: pending
     - [ ] <feature-slug>   PENDING   depends-on: none
     ```
     Leave the feature rows as a single placeholder — PO fills the real phases.
   - `STACK.md` — first line `STATUS: DRAFT`, then headings: `## Languages & runtimes`,
     `## Frameworks & libraries`, `## Data & storage`, `## Infrastructure & deploy`,
     `## Conventions`. Empty bodies — architect fills them.
   - `DECISIONS.md` — `# Product Architecture Decisions — <slug>` then
     `Append-only ADR log. Product-wide decisions, inherited read-only by every feature.`
   - `PROGRESS.md` — product-tier state:
     ```
     PRODUCT: <slug>
     SIZE: <small | standard | large>
     UPDATED: <iso8601>
     ```
     *(No `PHASE` field in M0 — there is no product state machine yet. M3 adds it.)*

2. **Delegate vision + backlog to product-owner.** Spawn `build-fleet:product-owner`
   via the Task tool. Tell it: it owns `.sdd/_product/vision.md` and
   `.sdd/_product/backlog.md`; draft the vision from the description (size-gated
   sections per above) and a **phased** feature backlog. Each backlog feature row
   is `- [ ] <slug>   PENDING   depends-on: <none | other-slug>`. It must NOT set
   any STATUS beyond `DRAFT` (there is no product review gate in M0). Pass the
   product description verbatim. **Brownfield note:** the backlog is
   *forward-looking* — features that already exist in the codebase are not backlog
   rows; only planned/next work goes in `backlog.md`.

3. **Delegate stack + product ADRs to architect.** Spawn `build-fleet:architect`
   via the Task tool. It owns `.sdd/_product/STACK.md` and `.sdd/_product/DECISIONS.md`,
   and records the *why* of each load-bearing choice as a product ADR (per the
   `adr` skill). This stack is **inherited read-only by every feature** — the
   single source of truth that prevents two features picking conflicting stacks.
   The architect uses `Edit` to fill the scaffolds you created (it has no
   `Write`); make sure the scaffold files already exist from step 1.

   **Tell the architect which mode it is in** — greenfield vs brownfield — based
   on whether real source already exists in the repo:

   - **Greenfield** (no meaningful source — e.g. only `.sdd/`, README, config):
     *ratify* a stack-of-record from the product description and the user's stated
     preferences. This is a forward design decision.
   - **Brownfield** (real source/manifests already exist — `package.json`,
     `go.mod`, `Cargo.toml`, `requirements.txt`, `pyproject.toml`, a populated
     `src/`, etc.): **infer and record the *actual* stack from the code.** Read the
     manifests and representative source; STACK.md must describe what the codebase
     *is*, not what the architect would prefer. **Do not propose a migration** —
     STACK.md is documentation of reality, not a redesign. If the architect
     believes the existing stack is wrong, that is a finding to surface to the
     user, not a unilateral STACK.md rewrite.

   Detect brownfield cheaply before delegating: if the repo contains source
   manifests or a non-trivial source tree outside `.sdd/`, pass `mode=brownfield`
   and name the manifest files you saw; otherwise `mode=greenfield`. (A repo that
   has prior `.sdd/<feature>/` dirs but no source yet is still greenfield for stack
   purposes — those features haven't been built.)

4. **Report back.** Summarize the vision one-liner, the phases and feature count,
   and the chosen stack. Tell the user the product tier is now **inherited
   context**: subsequent `/build-fleet:new-feature` runs will read `_product/STACK.md`
   and `_product/DECISIONS.md` and hold features to the product stack. Note that
   editing `_product/` files is done directly (no gate in M0); the product
   review/finalize gates and the phased build loop arrive in later v0.4 milestones.

## Gates to honor

- All `.sdd/_product/*` writes are inside `.sdd/`, so `block-source-before-finalized`
  permits them (it allows any path under `.sdd/`, and exits early when there is no
  active feature). The only blocker is the mid-review refusal in case 2 above —
  honor it rather than fighting the hook.
- M0 ships **no** new hook and **no** product gate. If you find yourself wanting
  to enforce a product STATUS transition, that's M3 — stop and surface it.

## Hard "no"s

- Do not run any workflow or invoke the scribe — M0 is plain file scaffolding.
- Do not touch `.sdd/ACTIVE` or any `.sdd/<feature>/` directory.
- Do not author the vision or choose the stack yourself — delegate.
