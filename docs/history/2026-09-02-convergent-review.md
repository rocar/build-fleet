# Convergent review — design

**Date:** 2026-09-02
**Status:** approved (design); implementation plan follows
**Ships as:** build-fleet v0.9.0, one atomic release
**Supersedes:** nothing. Changes the REVIEW convergence rule, the finalize gate, the
review workflow's inputs, and adds guards; the state machine's phases are unchanged.
**Evidence:** the tap pilot (`~/Projects/tap`, 2026-08-09 → 2026-09-02); figures below
come from git history and file sizes there, never from `.sdd/` timestamps (which the
pilot proved are fabricated — see §3.9).

## 1. Problem

The review loop does not converge, independent of feature size.

| Feature (tap) | spec.md | Acceptance criteria | Review cycles | Outcome |
|---|---|---|---|---|
| app-skeleton | 109 KB | 56 | 5 spec + 5 change | shipped |
| domain-schema | 555 KB — **554 KB at first commit** | 67 | 16 spec + 3 change | shipped |
| auth-and-audit | 266 KB | 99 | 6 | parked |
| fixture-and-harness | 49 KB, capped | 67 at draft → 83 | ~7 cumulative, 1 escalation | still in REVIEW |

Five causes, in leverage order:

1. **The exit condition cannot be met.** `review.js` sets a reviewer's `status` to
   `concerns-raised` whenever it holds any major; `commands/finalize.md` requires every
   block to read `status: approved`. So finalize opens only when all three reviewers
   raise zero majors, simultaneously, against a spec they re-read in full every cycle.
   The workflow's `clean` verdict (zero surviving blockers) recommends finalize; the
   gate then refuses on `not-approved`. tap hit clean at cycle 4 and spent three more
   cycles chasing all-approved; cycle 6 found a blocker in the prior fix.
2. **The rubric's ADR exit for majors is never dispatched.** Nothing between cycles
   asks the architect to disposition surviving majors; the pilot had to park the
   feature to get ADRs written.
3. **Review inputs are unbounded.** Reviewers are told to read the whole REVIEW.md
   (199–555 KB) plus DECISIONS.md, and read the 203 KB product ADR log to verify
   cites; ×3 roles ×2 phases, plus a scribe that reads and rewrites the whole log.
   One cycle was recorded at ~866k subagent tokens against a 120k header ceiling
   nothing enforces.
4. **Spec mass originates at the product-owner's first draft.** `new-feature` prepends
   the entire product DECISIONS.md (51 ADRs) and STACK.md to the PO, whose template
   demands acceptance 1:1 with behaviour; the first draft is proportional to that
   context. The cycle budget then resets on every escalation and park (domain-schema
   reached cycle 16 against a budget of 3).
5. **Workflow reviewers are not read-only.** `review.js` passes only `agentType`; the
   runtime's `agent()` has no `tools` option; `architect.md` grants `Edit`, `qa.md` and
   `coder.md` grant `Edit`, `Write`, `Bash`. The protocol and agent bodies claim writes
   are "physically impossible". Reviewers append their own long blocks (guessed
   timestamps) and the scribe appends the canonical ones: 26 cycle headings for 9
   distinct cycle/role pairs in one file. Both reviewer hooks stand down while the
   marker is live, so these writes are ungated. The dispatching commands have no Bash
   and therefore no clock — every `now`, run id and `UPDATED` stamp is invented.

Planning contributed but was not decisive: plan-review asked to split domain-schema in
cycle 3, cycle 4 recorded it "neither acted on nor answered", and the plan was ratified
with five open blockers. Nothing turns a split finding into backlog rows.

## 2. Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Rubric-only finalize gate.** Zero open blockers AND every surviving major fixed-in-spec or ADR-recorded. The "every block approved" requirement is dropped; `status:` becomes informational. | Matches the severity rubric as written. The all-approved rule is what made the loop non-convergent. |
| D2 | **Delta review from cycle 2.** Reviewers verify closure of their own prior `fix` findings and may raise new findings only at blocker severity. | Makes majors monotone non-increasing by construction. One prompt rule; no new state. |
| D3 | **In-workflow disposition leg.** After the survival vote an architect leg classifies each surviving major as `adr` (drafts the ADR) or `fix`; the scribe writes the ADRs. | Keeps single-writer discipline; no park-and-dispatch by hand; the loop can actually reach the rubric's ADR exit. |
| D4 | **One read-only `reviewer` agent** with the role lens injected by the workflow (the pattern `plan-review.js` already uses). | The only isolation mechanism the runtime offers is the agent definition. One file, one description, one rubric-drift surface, versus three per-role variants. |
| D5 | **REVIEW.md rotation by a deterministic script at dispatch**, older cycles archived to `REVIEW-archive.md`. | Every consumer keys on the current cycle, so this bounds every reader and the scribe without a schema bump. Per-cycle files would touch six commands; prompt-only bounding leaves the scribe rewriting 500 KB. |
| D6 | **One release, v0.9.0**, atomic per CLAUDE.md. | Ray's call; fewer release ceremonies. |
| D7 | **Implementation in a separate git worktree** (`release/0.9.0` at `~/build-fleet-0.9`), merged to `main` only at the release commit. | tap sessions run with `--plugin-dir=~/build-fleet`, i.e. the main working tree. A half-landed edit there breaks an in-flight review. The main working tree's content does not change until the merge. |

## 3. Design

### 3.1 Finding identity and the REVIEW.md line grammar

Finding ids become **stable across cycles**: `<role>-c<cycle>-<n>` (e.g. `architect-c1-3`),
enforced by a `pattern` in `CONCERNS_SCHEMA`. The id appears in the REVIEW.md line so a
later cycle can cite it:

```
## Cycle 2 — architect — 2026-09-03T10:12:41Z
- [blocker] (architect-c2-1) <text>
- [major] (architect-c1-3) <text>
  disposition: fix
- [major] (architect-c2-2) <text>
  disposition: adr ADR-7
- [minor] (architect-c2-3) <text>
status: concerns-raised
```

- The `(id)` token sits immediately after the severity tag. `finalize`'s literal
  `[major]` substring search is unaffected.
- `disposition:` is an indented continuation line, the same shape as the existing
  `refuted-by:` line. Values: `fix` (open — the PO must close it in the spec) or
  `adr ADR-<N>` where `ADR-<N>` is an entry in the **feature's** `DECISIONS.md`.
  Disposition ADRs are always feature-scoped; product ADRs are cited in prose as
  `product ADR-<N>` per the `adr` skill, never on a disposition line.
- A major with no disposition line is a defect of the run (the disposition leg did
  not cover it) and is treated by the gate as open.
- Blockers never carry a disposition; they are closed only by a later cycle not
  re-raising them.

### 3.2 `workflows/review.js`

Phases become: Fan-out → Cross-examination → Survival vote → **Disposition** → Apply.

**Fan-out prompt, cycle 1:** as today, with the id pattern and the instruction not to
write any file (the agent cannot anyway — §3.5).

**Fan-out prompt, cycle ≥ 2 (delta review):**
- REVIEW.md now contains only the previous cycle (§3.6). For each of *your own* prior
  findings with `disposition: fix`, and each of your prior blockers, verify closure
  against the current spec/acceptance. Return it again **with its original id** only if
  it is still open; omit it if closed.
- New findings: blocker severity only. Minors remain allowed and advisory. A new major
  is not permitted; if you believe an ADR-accepted trade-off is wrong, raise a blocker
  arguing against the ADR by id.
- Consequence: the set of open majors never grows after cycle 1.

**Cross-examination:** unchanged, plus `DECISIONS.md` as citable evidence (the currently
uncommitted change). Runs at default effort.

**Survival vote:** unchanged (pure JS).

**Disposition leg** (skipped when no major survives): one `reviewer` agent with the
architect lens, `model: "opus"`, structured output
`{ dispositions: [{ id, action: "adr"|"fix", adr_title?, adr_body? }] }` covering
**every** surviving major (validated in JS; a missing id ⇒ `verdict: "incomplete"`, no
state written). The prompt inlines the `adr` skill's entry format and the next free
feature ADR number (passed by the command as `next_adr_id`, computed by
`scripts/adr-index.sh --next` over the feature DECISIONS.md — §3.7),
because no agent file has `skills:` frontmatter and `agent()` has no skills option.
Rule given to the leg: `adr` only for a genuine design trade-off the spec should not
absorb; a missing behaviour, an unsatisfiable criterion, or a contradiction is `fix`.
On the **exhausting cycle** (`cycle >= cycleBudget`) the leg is still run, but any
remaining `fix` disposition is reported into the escalation payload (§3.4).

**Envelope additions** (CONTRACT.md §6):
- `decisions_appendix: string|null` — the ADR blocks to append to the feature
  `DECISIONS.md`, verbatim; mirrors `impl_notes_appendix`.
- `finalize_ready: boolean` — zero surviving blockers AND zero `fix` majors.
- `estimated_cost_actual.output_tokens` — filled from the runtime `budget.spent()`
  delta across the run; `input_tokens: null` (the runtime does not expose it).
- `state_delta` gains `CYCLE_TOTAL` (§3.8) and `LAST_REVIEW_OUTPUT_TOKENS`.
- `next_legal_commands`: `["/build-fleet:finalize"]` only when `finalize_ready`;
  otherwise `["/build-fleet:revise"]`; `[]` on escalate.

**Verdicts:** `clean` / `revise` / `escalate` keep their blocker meaning. `escalate`
now fires at the exhausting cycle when blockers **or** `fix` majors remain; the
escalation payload lists both under `surviving_blockers` and a new `open_majors`.
`incomplete` / `invalid-args` unchanged.

**Return object** adds `finalize_ready`, `open_majors`, `adrs_written`,
`output_tokens`.

**Args** add `cycle_total` (int, current cumulative) and `next_adr_id` (int). Both
optional; absent ⇒ `cycle_total = cycle - 1`, `next_adr_id = 1`.

The scribe leg runs with `effort: "low"`.

### 3.3 The scribe (`agents/scribe.md`)

- **Absent-key rule:** a `state_delta` key with no matching `FIELD:` line in
  PROGRESS.md is appended as a new line (grandfathered PROGRESS files lack
  `CYCLE_TOTAL` and `LAST_REVIEW_OUTPUT_TOKENS`). Existing keys are replaced in place
  as today.
- **`decisions_appendix`:** append verbatim to the workspace `DECISIONS.md`; create
  with the `adr` skill's file header if absent; never touch prior entries; skip when
  absent/empty — same rules as `impl_notes_appendix`.
- **Append mechanics:** append to REVIEW.md, DECISIONS.md and IMPL_NOTES.md with an
  `Edit` anchored on the file's final non-empty line — never a whole-file `Write`.

### 3.4 `commands/finalize.md` — the gate

Step 4 becomes:
- Exactly one block per roster role for the current `CYCLE` (roster from
  `REVIEW_ROLES`, default architect, qa, coder). Missing ⇒ `missing-<role>`.
- Zero `[blocker]` lines ⇒ else `open-blockers`.
- Zero `[major]` lines whose disposition is `fix` or absent ⇒ else `majors-open`.
- Every `disposition: adr ADR-N` cites an `## ADR-N:` heading present in the feature
  `DECISIONS.md` (numeric match, tolerant of zero-padding) ⇒ else `majors-without-adr`.
- `status:` lines are no longer evaluated. `not-approved` stays in the signal grammar,
  documented as **no longer emitted** (additive change; removal would be the breaking
  bump).

The pass output is unchanged. `commands/status.md` prints each major's disposition and
the run's `finalize_ready`.

### 3.5 The `reviewer` agent and the role agents

New `agents/reviewer.md`: `tools: Read, Grep, Glob`, `model: sonnet`, body = review
discipline (read the named files, cite by section, never write) + the severity table
**verbatim** (added to `scripts/rubric-drift.test.sh`'s file list) + the REVIEW.md
line grammar of §3.1. It carries no lens; `review.js` holds a `LENS` map for
`architect`, `qa`, `coder`, `product-owner`. The architect/qa/coder lenses are copies
of each role agent's "Review lens" section — the role agents keep theirs because
CHANGE_REVIEW and direct invocation still run the full agents — and a new
`scripts/lens-drift.test.sh` (the `rubric-drift` pattern) extracts both and fails the
suite if they differ. The `product-owner` lens (does the spec realize the inherited
intent; is every criterion testable) exists only in `review.js`. `review.js` passes
`model: "opus"` for the architect lens and the disposition leg, matching today's cost
profile.

`review.js` dispatches every review, cross-exam and disposition leg as
`agentType: "build-fleet:reviewer"`. The scribe stays `build-fleet:scribe`.

Role agents (`architect.md`, `qa.md`, `coder.md`, `product-owner.md`): the "append a
block to REVIEW.md" instruction is scoped explicitly to non-workflow paths
(CHANGE_REVIEW, direct invocation); the false claims about a workflow-set tools
allowlist are removed; descriptions refreshed (CLAUDE.md rule). `review-rubric`'s
prose about `AgentDefinition.skills` preloading is corrected (the in-body table is the
load-bearing copy on every path).

`diagnose.js` and `deep-build.js` keep their current agents — out of scope (§7).

### 3.6 REVIEW.md rotation — `scripts/review-rotate.sh`

Called by `/build-fleet:review` before dispatch (allowlisted
`Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-rotate.sh":*)`), only when
`PHASE = REVIEW` and `CYCLE ≥ 1`. **Positional rule, not cycle-numbered** (cycle
numbers collide after a `resolve-escalation` reset):

> A *block* is a `## ` heading and every line up to the next `## ` heading (or end of
> file). Find the last run of consecutive `## Cycle …` blocks whose length equals the roster size
> (`REVIEW_ROLES` count, default 3, or `--roster N`). Keep that run and **every block
> after its first heading** (escalation archives, run-failure notes, human decisions
> land after the cycle they concern). Move every block before it, verbatim and in
> order, to `REVIEW-archive.md` (created with an `# Review Archive — <slug>` header;
> append-only). Rewrite REVIEW.md as its original header + the kept blocks.

Emits `BUILD_FLEET_REVIEW_ROTATED: {"feature","archived_blocks","kept_blocks"}` or
`…_ROTATED: {"archived_blocks":0}` when nothing precedes the kept run. Idempotent.
Fewer than roster-size blocks ⇒ no-op. `Change-Cycle` blocks are never rotated (the
script runs only in spec review). Test harness covers: nothing to rotate, one prior
cycle, post-reset duplicate `Cycle 1`, escalation block retained, idempotence, CRLF.

`sdd-protocol` documents `REVIEW-archive.md` (reviewers, `scribe`-append-only; the
audit trail is REVIEW.md + REVIEW-archive.md). `resolve-escalation` and `status` read
REVIEW.md only, as today.

### 3.7 Product-owner context diet

- New `scripts/adr-index.sh <DECISIONS.md>` prints one line per ADR:
  `ADR-<N>: <title> [<status>]`; `--next` prints the next free integer id (1 for an
  empty or absent log). Deterministic, tested.
- `/build-fleet:new-feature` step 5b/8: pass the **binding stack** verbatim and the
  **ADR index** (not the ADR bodies). Instruct the PO to `Read` only the ADRs it
  cites. Pass the feature's size budget (`SPEC_MAX_KB`, `AC_MAX`) and say the caps are
  hooks that refuse the write.
- `/build-fleet:revise` (§3.10) passes the same budget and the `fix` list only.
- `product-owner.md`: draft to the budget; a spec that cannot fit is a split signal
  (`## Self-review notes` names the proposed split), never a compression exercise.

### 3.8 Caps as plugin hooks (ported from tap's guards, with harnesses)

| Hook | Event | Reads | Rule |
|---|---|---|---|
| `cap-spec-size.sh` | PreToolUse Write/Edit on `.sdd/<slug>/{spec,acceptance}.md` | `SPEC_MAX_KB` in the feature PROGRESS | Projects the resulting byte size (exact for Write; old/new delta × occurrences for Edit); refuses over budget. **Absent field ⇒ no cap** (grandfathering). Product tier exempt. |
| `validate-acceptance-count.sh` | PostToolUse Write/Edit on `.sdd/<slug>/acceptance.md` | `AC_MAX` | Counts distinct `AC-<n>[a-z]?` ids; over budget ⇒ exit 2 with the split message. Absent ⇒ no cap. |

Refusal text says **split the feature** (name the rows) rather than compress; raising
the field is the auditable override. Tier defaults scaffolded by `new-feature` into
PROGRESS: `standard` → `SPEC_MAX_KB: 24`, `AC_MAX: 15`; `large` → `48` / `30`;
`trivial` → neither. Both hooks: `_lib.sh` anchoring, `..` rejection, jq-required,
fail-closed trap, bash 3.2 + GNU coreutils.

**Cumulative cycles.** `CYCLE_TOTAL` (scribe-written, never reset) and
`CYCLE_TOTAL_MAX` (default 6) in PROGRESS; `new-feature` scaffolds `0` / `6`.
`/build-fleet:review` reads `CYCLE_TOTAL` (absent ⇒ `CYCLE`) and refuses **before
dispatch** with `{"reason":"cycle-total-exhausted","cycle_total":N,"max":M}` and the
three options (cut scope / ship what exists / raise the ceiling deliberately).
`resolve-escalation` and `park` never touch it. The workflow writes `cycle_total + 1`.

### 3.9 Clock and cost

- `allowed-tools` of `review`, `plan-review`, `deep-build`, `diagnose`, `finalize`,
  `handoff` gain `Bash(date:*)`; each computes `now` as
  `date -u +%Y-%m-%dT%H:%M:%SZ`. Run ids and `UPDATED` stamps become real.
- `/build-fleet:review` refuses with `{"reason":"cost-runaway","last_output_tokens":N}`
  when `LAST_REVIEW_OUTPUT_TOKENS` exceeds 3× the header's `output_tokens` ceiling,
  unless `--override-cost` is passed. The cost preview line is unchanged.

### 3.10 `/build-fleet:revise`

New command, `allowed-tools: Read, Task`. Preconditions: active feature,
`PHASE = REVIEW`, no ESCALATION.md, current cycle has open blockers or `fix` majors.
Extracts exactly those lines (with ids) from the current cycle's blocks, reads the
budget fields, and dispatches `build-fleet:product-owner` with: the list, the budget,
the rule that ADR-dispositioned items are closed and must not be revisited, and the
instruction to record in `## Self-review notes` which ids were closed and how.
Emits `BUILD_FLEET_REVISE_DISPATCHED: {"feature","cycle","items":N}`. Refuses with
`nothing-to-revise` when the cycle is `finalize_ready`. It never edits `.sdd/` itself.

### 3.11 Planning

- `commands/new-product.md` and `product-owner.md` (product tier): **Phase 1 is a
  walking skeleton** — the smallest vertical slice that produces the product's primary
  artifact end to end; first demonstrable output within four features; every phase a
  shippable increment.
- `workflows/plan-review.js`: PO lens adds "first demonstrable output later than the
  4th feature ⇒ `[blocker]` `gap`"; qa lens adds "an intent implying more than ~15
  acceptance criteria ⇒ `[major]` `gap` naming the split". `INTERROGATION_SCHEMA`
  gains optional `split_into: string[]`; the report renders it as its own indented
  line `  split-into: a, b, c` so the gate can grep it.
- `commands/plan-finalize.md`: plain `ratify` refuses (`split-unresolved`) while any
  `split-into:` line of the latest cycle names a slug absent from `backlog.md` and no
  product ADR cites that finding id as refused. `ratify force` overrides, recording it.
- `scripts/intent-block.sh` emits `INTENT_BYTES: n`. `validate-backlog-status.sh`
  rejects a backlog write containing an intent block over `INTENT_MAX_BYTES` **only
  when** `.sdd/_product/PROGRESS.md` carries that field; `new-product` scaffolds `600`.
  Existing products are untouched.

### 3.12 Documentation updated in the same release

`skills/sdd-protocol/SKILL.md` (REVIEW phases, verdicts, `finalize_ready`, gate,
`REVIEW-archive.md`, PROGRESS fields, revise command), `references/product-tier.md`
(walking skeleton, split gate, intent cap), `docs/v0.2/CONTRACT.md` §6 (envelope
fields, return object), `skills/review-rubric/SKILL.md` (new section "Delta review and
disposition" **below** the table — the drift test extracts the table only),
`skills/adr/SKILL.md` (disposition ADRs are feature-scoped), `README.md` (component
counts: 8 agents, 23 commands, 12 hook scripts; the review flow), `CHANGELOG.md`.

## 4. Compatibility and release

v0.9.0. Compatibility note: additive PROGRESS fields (`CYCLE_TOTAL`,
`CYCLE_TOTAL_MAX`, `SPEC_MAX_KB`, `AC_MAX`, `LAST_REVIEW_OUTPUT_TOKENS`;
`INTENT_MAX_BYTES` on the product tier), a new optional workspace file
`REVIEW-archive.md`, new envelope fields (`decisions_appendix`, `finalize_ready`),
REVIEW.md line grammar gains `(id)` and `disposition:` (old blocks still parse), the
`not-approved` refusal code no longer emitted. `SDD_SCHEMA` stays `1` — every reader
ignores unknown lines and every new field is read-with-default. In-flight features on
0.8.0 continue: their next `/build-fleet:review` rotates, dispositions and stamps
`CYCLE_TOTAL` from `CYCLE`.

`main` already sits six commits past `v0.8.0` (three fixes: change-cycle heading,
bug-lane FIXED unlock, plan-review TDZ, stop-tests venv pytest; plus docs). Those are
unreleased and ride in 0.9.0; the CHANGELOG entry lists them.

The atomic release commit carries: tag `v0.9.0`, `plugin.json`, `marketplace.json`,
CHANGELOG, README counts, refreshed descriptions for every agent whose body changed
(architect, qa, coder, product-owner, scribe, reviewer). The currently uncommitted
`workflows/review.js` (DECISIONS.md dispositive) and `hooks/scripts/stop-tests.sh`
(tests-first window) changes ride along; the latter gets its failing harness case
first.

## 5. Implementation order

Work happens in a separate worktree (D7). Order puts the tap-unblocking core first:

1. Ride-along: harness case for the stop-tests window; `node --check`; suite green.
2. `reviewer` agent + drift-test entry; role-agent scoping + descriptions.
3. `review.js`: stable ids, delta prompt, LENS map, disposition leg, envelope fields,
   `finalize_ready`, escalation rule, cost fields, scribe effort. Pure-helper tests +
   determinism lint.
4. `scribe.md`: absent-key rule, `decisions_appendix`, anchored append.
5. `finalize.md` gate + `status.md`; smoke-test walk.
6. `revise` command; clock in commands.
7. `review-rotate.sh` + harness; wired into `review.md`.
8. `adr-index.sh` + harness; `new-feature` context diet + budget scaffolding.
9. Caps: `cap-spec-size.sh`, `validate-acceptance-count.sh`, `CYCLE_TOTAL` dispatch
   refusal, cost-runaway refusal; hooks.json; harnesses.
10. Planning: new-product/PO text, plan-review lenses + `split_into`, plan-finalize
    gate, intent cap.
11. Docs, CHANGELOG, README, versions; full suite; tag; merge to main.

## 6. Testing

- Every hook/script change: a failing case in the existing mktemp harness style first
  (`hooks/scripts/*.test.sh`, `scripts/*.test.sh`), bash 3.2 and GNU-compatible.
- `review.js` and `plan-review.js`: pure helpers between the `LAYER1-PURE-HELPERS`
  markers get extracted-and-run tests (id pattern, finalize_ready, disposition
  coverage check, split rendering); `workflow-determinism-lint.sh` must pass.
- `rubric-drift.test.sh` covers the new agent.
- Smoke (`docs/v0.5/smoke/smoke.sh`): a finalize walk with one `disposition: fix`
  major (refuse `majors-open`), one `adr` major with its ADR present (pass), and one
  citing a missing ADR (refuse `majors-without-adr`).
- Manual: one full review cycle on the tap fixture-and-harness workspace from the
  worktree (`--plugin-dir` pointed at it), before tagging.

## 7. Out of scope

- Reviewer isolation for `diagnose.js` and `deep-build.js` legs (qa needs Bash there).
- Per-cycle review files / an `SDD_SCHEMA` bump.
- Automatic PO revision inside the workflow (revise stays a human-triggered command).
- Any change to tap's own `.sdd/` state; tap continues per the 2026-09-02 assessment.
