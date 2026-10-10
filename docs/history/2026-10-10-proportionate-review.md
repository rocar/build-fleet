# Proportionate review — design

**Date:** 2026-10-10
**Status:** approved (design); implementation plan follows
**Ships as:** build-fleet v0.10.0, one atomic, additive release
**Supersedes:** nothing. Changes how a feature's review roster and budget are chosen,
the severity calibration of the three review lenses, and the CHANGE_REVIEW exit rule.
The state machine's phases, the hooks, the review workflow's legs and the finalize gate
are unchanged.
**Evidence:** `2026-10-10-orchestration-balance-research.md` (same directory), the
2026-09-06 pilot measurement recorded in CHANGELOG 0.9.0, and the pilot table in
`2026-09-02-convergent-review.md` §1.

## 1. Problem

v0.9.0 made the REVIEW loop converge. What remains is structural cost that does not
vary with stakes, plus one loop that still carries the pre-0.9 exit rule.

| Symptom | Evidence | Cause |
|---|---|---|
| Every feature pays the same review, whatever its risk. | One healthy cycle 1 on a 49 KB spec: 8 agent invocations, 26.6 min, 734k subagent tokens. A standard feature pays at least two cycles before any code exists. | `commands/new-feature.md` step 3 seeds `REVIEW_ROLES: architect, qa, coder` and `REVIEW_CYCLE_BUDGET: 3` unconditionally. The classifier sizes work but says nothing about reversibility or blast radius, so there is no signal to scale on. |
| Reviewers over-report. | The qa lens: "If you have to invent assumptions, that's at minimum a `[major]`"; "'Fast', 'robust', 'user-friendly' are `[blocker]`-tier vagueness". The coder lens is a list of things to flag as missing. Under a survive-unless-refuted vote every unrefuted finding reaches disposition. | The lenses predate `agents/reviewer.md`, whose discipline already says: under-specification is a `[major]` only when a coder would have to guess at behaviour a test could fail on; prose that could be shorter is a `[minor]`. The lenses contradict the agent they are injected into. |
| CHANGE_REVIEW can fail to converge. | `commands/handoff.md` step 8 bounces to BUILD on "any open `[blocker]` or any reviewer's `status: concerns-raised`" and exits only when "all three are `status: approved`". Step 5's budget guard looks only at open blockers, so the two steps disagree. The pilot ran 5 change cycles on app-skeleton and 3 on domain-schema against a budget of 3. | The all-approved exit v0.9 removed from spec review (cause 1 in the convergent-review design) was never removed here. There are no finding ids, no `disposition:` lines and no delta rule in change review. |

The research separates two things the speed complaint conflates: the non-converging
loop was a bug and is fixed; the per-cycle cost is a design choice. The evidence says
the measured benefit of adversarial review comes from citation-forced refutation by a
different role, which `review.js` already enforces, not from reviewer headcount. So
the fan-out width is what should scale with stakes; the gates and the citation rule
stay.

## 2. Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **A risk axis, separate from size.** The classifier emits `risk: low | elevated` plus `risk_reasons`. | Size and stakes are different axes; today heavy review is keyed on size alone. Anthropic's cost guidance is a stakes criterion, which is the classifier's job. |
| D2 | **Seed the roster and budget from a tier-by-risk table at new-feature.** `standard` + `low` seeds `architect, qa` and budget `2`; everything else keeps `architect, qa, coder` and `3`. | Config-only: review.js's roster floor is already 2 and the finalize gate and rotation script already read `REVIEW_ROLES`. Seeding keeps the value visible and editable in PROGRESS.md. Resolving at dispatch instead would hide it and duplicate the logic in three readers. |
| D3 | **Parse-failure fallback is `standard` + `elevated`.** | Reproduces today's behaviour exactly when the classifier misbehaves. |
| D4 | **Elevated risk is a trivial disqualifier.** | A risky change never skips review, however small. The existing never-trivial list becomes the first group of risk reasons. |
| D5 | **Align the three lenses to the reviewer discipline.** Severity words in the lenses change; the rubric table does not. The coder lens drops its coverage bullet. | The calibration already exists in `agents/reviewer.md`; this removes a contradiction, not adds policy. The coder coverage bullet duplicates qa's and produces paired findings the cross-examination processes twice. |
| D6 | **CHANGE_REVIEW stays static and gets a deterministic gate**, `scripts/change-review-gate.sh`, modelled on `finalize-gate.sh` but its own script. | `docs/loops.md` records why change review is static: the orchestrator needs Bash for the diff and the counterfactual. A workflow conversion is the right eventual shape and the wrong blast radius for a minor release. A separate script leaves the finalize gate and its harness untouched. |
| D7 | **Change-review findings get ids, dispositions, closed-by-id and a delta rule.** Ids `<role>-cc<N>-<n>`; every major carries `disposition:`; an id closed by an ADR in any current-cycle block is closed everywhere; a new major at change cycle ≥ 2 is advisory. **The fan-out is two-stage**: qa and product-owner in parallel, then the architect, who reads their blocks. | These are the v0.9 convergence rules, ported to the static path. Closed-by-id is the static form of the disposition leg, where the architect already overrules the raiser; sequencing the architect after its peers is what lets it accept a peer's trade-off major in the same cycle instead of after a coder bounce. Costs wall-clock, not agents. |
| D8 | **CHANGE_REVIEW roster and budget unchanged**: architect, product-owner, qa; 3 cycles. | The measured pain was the exit rule, not headcount. qa must hold Bash for the counterfactual; the PO sign-off is the acceptance check. A tier-based change-review roster is parked until measured. |
| D9 | **The two-role versus three-role measurement is the release gate.** | The only evidence that headcount drops losslessly is one unreplicated run. v0.9.0 validated live on tap before tagging; this release does the same and lets the result fix the `standard` + `low` row. |
| D10 | **One release, v0.10.0, implemented in a separate worktree** and merged at the release commit. | tap sessions run with `--plugin-dir=~/build-fleet`; a half-landed edit on main breaks an in-flight review. Same as v0.9's D7. |

## 3. Design

### 3.1 Classifier risk axis (`agents/classifier.md`)

The tier verdict gains two fields. Bug mode is unchanged.

```json
{
  "tier": "trivial|standard|large",
  "rationale": "<one paragraph: which criteria fired, which disqualifiers cleared, which risk reasons fired>",
  "skip_review": true,
  "build_mode": "standard|deep-build",
  "skeleton_spec_hint": null,
  "confidence": "high|medium|low",
  "skill_manifest": null,
  "risk": "low|elevated",
  "risk_reasons": []
}
```

`risk` is `elevated` when at least one reason fires; `risk_reasons` lists the slugs,
and is empty when `risk` is `low`. Reason slugs, fixed vocabulary:

| Group | Slug | Fires when |
|---|---|---|
| Never-trivial | `auth` | authentication or authorization logic changes |
| | `secrets` | secrets handling, key material, credential storage |
| | `billing` | payment, invoicing, pricing or entitlement logic |
| | `data-migration` | a schema migration or a backfill of persisted data |
| | `ci-release` | CI/CD, build config or release tooling |
| | `new-dependency` | a new external dependency is introduced |
| | `review-requested` | the user explicitly asked for review |
| Irreversibility | `irreversible` | the change deletes or transforms persisted data, or has external side effects that cannot be undone (sends, charges, third-party writes) |
| Blast radius | `public-contract` | a public API, wire format or storage format other code or systems depend on changes |
| | `shared-module` | a module imported across most of the repo changes behaviour |

Rules added to the verdict section:

- `risk=elevated` ⇒ `risk_reasons` non-empty and `tier ≠ trivial`. The never-trivial
  disqualifier list is retained verbatim and now also names the slugs it maps to.
- `risk=low` ⇒ `risk_reasons` is `[]`. Risk is low when no reason fires; the classifier
  does not elevate on a hunch. The cost asymmetry section gains one sentence: a false
  `low` costs one reviewer lens on a change that still gets cross-examined, refuted by
  citation and gated; a false `elevated` costs roughly three extra agent invocations.
- The `confidence` field covers both axes.

The `description:` frontmatter changes with the body: it names the risk output.

### 3.2 PROGRESS.md and the seeding table (`commands/new-feature.md`, `commands/dispatch.md`, `commands/status.md`)

PROGRESS.md gains one field, written beside `TIER` and `BUILD_MODE`:

```
RISK: low | elevated | pending    # set by the classifier at /build-fleet:new-feature. `pending` until it runs.
```

`new-feature` step 3 keeps seeding the historical defaults (`architect, qa, coder`, budget
`3`) so a classifier fallback or an interrupted run leaves a working feature. Step 7
writes `RISK:` and rewrites `REVIEW_ROLES:` and `REVIEW_CYCLE_BUDGET:` from this table:

| TIER | RISK | REVIEW_ROLES | REVIEW_CYCLE_BUDGET |
|---|---|---|---|
| standard | low | architect, qa | 2 |
| standard | elevated | architect, qa, coder | 3 |
| large | low or elevated | architect, qa, coder | 3 |
| trivial | low | architect, qa | 2 |
| trivial | elevated | coerced to `standard` + `elevated`: architect, qa, coder | 3 |

The trivial-low row exists so a later hand edit of `TIER` to `standard` finds a sane
roster; REVIEW is skipped for trivial features. The trivial-elevated row is a
coercion, not a seeding: the classifier's rule forbids the pair, but a verdict is model
output, so `new-feature` step 7 enforces it deterministically. If `risk=elevated` and
`tier=trivial`, the command writes `TIER: standard`, `BUILD_MODE: standard`, treats
`skip_review` as false, ignores `skeleton_spec_hint`, and emits
`BUILD_FLEET_CLASSIFIER_FALLBACK` with `"reason":"risk-tier-conflict"` before the
classification line. Without this row a mis-emitted verdict would reach the trivial
fast-path and skip review on exactly the change that needed it. `BUILD_CYCLE_BUDGET`, `CYCLE_TOTAL_MAX`,
`SPEC_MAX_KB` and `AC_MAX` are unchanged. The pair is architect plus qa because the
architect lens carries correctness, failure modes, data integrity and security and the
architect already runs the disposition leg, while the qa lens carries testability and
coverage; the coder lens overlaps both. Humans override as before: edit PROGRESS.md, or
pass `--roles` / `--cycle-budget` for one run.

Signal lines. `BUILD_FLEET_CLASSIFICATION` gains `"risk"` and `"risk_reasons"` in both
`new-feature` and `dispatch`. `BUILD_FLEET_CLASSIFIER_FALLBACK` gains
`"risk_assigned":"elevated"`. `new-feature` step 7 emits one new line after writing the
fields:

```
BUILD_FLEET_REVIEW_DEFAULTS: {"feature":"<slug>","tier":"<...>","risk":"<...>","roles":["..."],"cycle_budget":<n>}
```

`new-feature` step 8's user report names the seeded roster and budget and how to
override them. `dispatch` prints risk, its reasons and the roster and budget the table
would seed. `status` step 2 prints `TIER`, `RISK`, `REVIEW_ROLES` and
`REVIEW_CYCLE_BUDGET` after `PHASE`. `scripts/status-snapshot.sh` is unchanged; the
snapshot schema stays `build-fleet/status-snapshot@1`.

### 3.3 Lens alignment (`agents/architect.md`, `agents/qa.md`, `agents/coder.md`, `workflows/review.js` LENS)

Each lens lives in the agent's `## Review lens` section and in the `LENS` map of
`review.js`; `scripts/lens-drift.test.sh` requires the two copies to match, so both move
together. The severity rubric table, mirrored in four files, does not change. The three
agents' `description:` lines change with their bodies.

**architect.** One bullet changes; the other seven are unchanged.

```
- **Failure modes.** What happens on partial failure, network loss, retries,
  concurrent callers, malformed input? Silence is a `[major]` when the failure
  would corrupt data or break an acceptance criterion, a `[minor]` otherwise.
```

**qa.** The whole lens is replaced:

```
- **Testability.** For each acceptance criterion: could you write a test from it
  *alone*? A `[major]` only where a coder would have to guess at behaviour a test
  could fail on; cite the criterion. Prose that could be tighter is a `[minor]`.
- **Measurability.** "Fast", "robust", "user-friendly" with no number or observable
  check: a `[major]` inside an acceptance criterion, a `[minor]` in narrative text.
- **Coverage.** Spec behaviour with no acceptance criterion is a `[major]`. An
  acceptance criterion with no described behaviour is a `[major]` only if a coder
  would implement it blind, otherwise a `[minor]`.
```

**coder.** The whole lens is replaced; the coverage bullet is removed as qa's duplicate.

```
- **Interface contracts.** A signature, error envelope or data shape the spec
  leaves open is a `[major]` only when two reasonable implementations would fail
  different tests; otherwise state the assumption you would make as a `[minor]`.
- **Implementability.** An acceptance criterion that cannot be implemented as
  written, or that contradicts another, is a `[blocker]`.
- **Hidden dependencies.** An implicit dependency on infrastructure or a library
  the spec does not name is a `[major]` when it changes the stack or the deploy
  shape, a `[minor]` otherwise.
```

The product-owner lens, which exists only in `review.js`, is unchanged. The lens
prose around each list in the agent files ("Common findings:" and similar) is adjusted
so the list reads as calibration, not as a checklist of things to find.

### 3.4 Change-review finding grammar

CHANGE_REVIEW blocks keep their heading family, `## Change-Cycle <N> — <role> — <iso8601>`,
and adopt the v0.9 line grammar:

```
## Change-Cycle 2 — architect — 2026-10-12T09:41:07Z
- [blocker] (architect-cc2-1) <text>
- [major] (qa-cc1-3) <text, re-listed from qa's cycle-1 block>
  disposition: adr ADR-5
- [major] (architect-cc1-2) <text, re-raised: still open>
  disposition: fix
- [minor] (architect-cc2-2) <text>
status: concerns-raised
```

- **Ids are stable**: `<role>-cc<K>-<n>`, where `K` is the change cycle the finding was
  first raised in. A re-raised finding keeps its id.
- **Every major carries a `disposition:` continuation**, written by the reviewer that
  raised it. `fix` is the default. `adr ADR-N` is written only by the architect, who
  appends the ADR to `DECISIONS.md` first. The product-owner and qa never write ADRs.
- **Closed-by-id wins across blocks.** The architect may accept a peer's open major by
  listing its id under the architect block with `disposition: adr ADR-N`. The gate
  closes that id in every block of the current cycle. So that this works within one
  cycle, the fan-out is two-stage: qa and product-owner run in parallel and write their
  blocks; the architect runs after them, reads those blocks, and reviews the diff and
  dispositions peer majors in one Task. Running all three in parallel would mean every
  trade-off major costs a coder bounce and a full extra cycle before the architect
  could accept it.
- **Delta rule from change cycle 2.** Each reviewer verifies closure of its own prior
  blockers and `fix` majors against the new diff and re-raises by id what is still
  open. New findings are `[blocker]` only, plus advisory minors. A new `[major]` whose
  id originates at the current cycle is advisory: the gate reports it as demoted and
  it does not block. This is safe by the rubric, not by luck: correctness, security,
  data loss and spec contradiction are blockers and are never demoted, and the qa
  change-review lens already rates a missing acceptance test as a blocker. What
  demotion touches is maintainability-class findings in code written to close the
  previous cycle. The 3-cycle budget bounds the rest, as it does in spec review.
- **`status:` is informational**, as in spec review.

### 3.5 The gate (`scripts/change-review-gate.sh`)

```
Usage: change-review-gate.sh <slug> [--roster a,b,c]
  Roster defaults to architect,product-owner,qa (no PROGRESS field in this release).
Reads CHANGE_CYCLE from PROGRESS.md (non-integer → exit 1).
For each roster role: the LAST block headed "## Change-Cycle <N> — <role> —"
  (en-dash, em-dash or hyphen accepted); missing → reason missing-<role>.
  A same-numbered "## Cycle <N>" spec-review block never matches.
Within a block, a finding's continuation run is the indented lines that follow it,
  ending at the first line matching "^- [", "^status:", "^## " or EOF.
  - [blocker] line: OPEN unless "refuted-by:" appears in its run.
  - [major] line, id from "(<id>)" else the line text:
      "disposition: adr ADR-N" in its run and "## ADR-N:" present in DECISIONS.md → CLOSED
      "disposition: adr ADR-N" with no such ADR                                → majors-without-adr
      "refuted-by:" in its run                                                  → CLOSED
      id matches <role>-cc<K>-<n> with K == N and N >= 2                        → DEMOTED
      otherwise                                                                 → OPEN
Two passes, not one: pass one scans every roster block and records each finding's
  state per id; pass two resolves, so an id CLOSED by adr in any block is CLOSED in
  every block, and only then are open_blockers / open_majors / demoted emitted.
Output (stdout, exactly one line):
  BUILD_FLEET_CHANGE_REVIEW_GATE: {"feature","change_cycle","pass":bool,"reasons":[…],"open_blockers":[…],"open_majors":[…],"majors_without_adr":[…],"demoted":[…]}
  reasons ⊆ {missing-<role>, open-blockers, majors-open, majors-without-adr}
Exit: 0 pass; 2 refuse; 1 bad usage / unreadable workspace.
bash 3.2 + BSD/GNU compatible; read-only; requires jq.
```

`finalize-gate.sh` is not modified. The two scripts share an idiom, not code; the
`finalize-gate.test.sh` harness is the regression guard that proves it.

### 3.6 `commands/handoff.md`

- **Step 2** also accepts `PHASE: HANDOFF`: a previous run reached devops and failed, so
  the command resumes at step 9 provided the gate over the current change cycle passes.
  Today step 9 tells the user to re-run handoff after a devops failure while step 2
  refuses that phase.
- **Step 5** becomes: read `CHANGE_CYCLE`. If it is `>= 3`, run the gate. Pass → the
  current cycle already passed; continue to step 9. Fail → write `ESCALATION.md` from
  the gate line's `open_blockers` and `open_majors`, set `PHASE: ESCALATED`, stop.
- **Step 7** becomes two-stage. First, `build-fleet:product-owner` and `build-fleet:qa`
  in parallel (two Task calls in one message). When both blocks exist, `build-fleet:architect`
  alone, with a pointer to the two fresh blocks. All prompts add the id grammar and the
  `disposition:` requirement on every major, and the delta rule when `CHANGE_CYCLE >= 2`
  with a pointer to the previous Change-Cycle blocks. The architect prompt adds the
  closed-by-id rule and the ADR-first requirement. The role lenses in the prompt are
  unchanged. Wall-clock per change cycle grows by roughly one architect run; the agent
  count does not change.
- **Step 8** becomes: run the gate and relay its line. Pass → step 9. Fail with
  `CHANGE_CYCLE < 3` → delegate `build-fleet:coder` with exactly the gate's
  `open_blockers` and `open_majors`, set `PHASE: BUILD`, stop. Fail with
  `CHANGE_CYCLE >= 3` → the escalation path of step 5. The exhausting cycle escalates
  directly, as the review workflow does; step 5's guard exists for a pre-0.10 workspace
  whose third cycle bounced without escalating. `status:` lines are never evaluated.
- `allowed-tools` already includes `Bash`; the gate is invoked as
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/change-review-gate.sh" "<slug>"`.
- The refusal-cases list gains the gate's reasons.

### 3.7 Role agents in CHANGE_REVIEW (`agents/architect.md`, `agents/product-owner.md`, `agents/qa.md`)

- Every `## During CHANGE_REVIEW` section states the heading family, the id grammar,
  the `disposition:` line and the delta rule. The product-owner section currently
  names `## Cycle <N> — product-owner`, which `check-review-written.sh` rejects during
  CHANGE_REVIEW; it moves to `## Change-Cycle <N>`.
- The architect section adds: you run after qa and product-owner; read their blocks
  for this cycle and, from change cycle 2, the previous cycle's blocks too. For each
  open `fix` major that is a trade-off rather than a defect, append the ADR, then list
  the id under your block with `disposition: adr ADR-N`. A defect stays `fix`.
- qa and product-owner: every major you raise carries `disposition: fix`.
- The REVIEW.md block examples in all three agents gain the `(id)` and `disposition:`
  lines. Descriptions change with bodies.

`hooks/scripts/check-review-written.sh` is unchanged: the CHANGE_REVIEW roster and
heading family are the same.

### 3.8 Documentation updated in the same release

- `skills/sdd-protocol/SKILL.md`: PROGRESS schema gains `RISK`; the `REVIEW_ROLES` and
  `REVIEW_CYCLE_BUDGET` comments say the defaults are seeded by tier and risk; the SPEC
  paragraph names the risk axis; the CHANGE_REVIEW paragraph's exit becomes the gate
  rule and names the delta rule and closed-by-id.
- `skills/review-rubric/SKILL.md`: "How a major becomes an ADR" describes the
  change-review grammar: ids, `disposition:`, closed-by-id, the demotion of new majors.
- `agents/classifier.md`: §3.1.
- `README.md`: the PROGRESS schema block gains `RISK` and the seeding note; the
  classifier sentence names risk; the state-diagram label that names the fixed roster
  says "roster by tier and risk"; the handoff row of the command table names the gate.
  Component counts move only if a count the README states changes.
- `docs/loops.md`: the CHANGE_REVIEW row's exit column and the "plain
  all-approve-or-bounce gate" passage describe the gate rule.
- `docs/v0.2/CONTRACT.md` §8: the new signal line and the new fields.
- `docs/PILOT.md`: the command listing's `/build-fleet:review` line names the fixed
  roster; it says the roster is seeded by tier and risk.
- `CHANGELOG.md`: the 0.10.0 entry with the Compatibility line in §4 and the tap
  measurement from §6.

## 4. Compatibility and release

`SDD_SCHEMA` stays `1`. Additive changes only:

- PROGRESS field `RISK` (read-with-default; absent reads as `pending` in `status`).
- Signal grammar: new fields `risk`, `risk_reasons` on `BUILD_FLEET_CLASSIFICATION`;
  new field `risk_assigned` on `BUILD_FLEET_CLASSIFIER_FALLBACK`; new lines
  `BUILD_FLEET_REVIEW_DEFAULTS` and `BUILD_FLEET_CHANGE_REVIEW_GATE`.
- REVIEW.md Change-Cycle lines gain `(id)` and `disposition:`; old blocks still parse.

Migration for an in-flight feature: none required. A feature seeded before 0.10.0 keeps
its three-role roster; edit `REVIEW_ROLES` and `REVIEW_CYCLE_BUDGET` by hand to adopt
the table. A feature already in CHANGE_REVIEW with legacy blocks: at its next handoff
run the gate reads every undispositioned major as open and bounces to the coder once;
reviewers re-raise with ids on that cycle. A legacy block reading `status:
concerns-raised` with no open findings now passes, which is the intended fix.

Release checklist, atomic per CLAUDE.md: tag `v0.10.0`; `plugin.json` version and
description; `marketplace.json`; the CHANGELOG entry; README counts and schema block;
the `description:` of every agent whose body changed (classifier, architect, qa, coder,
product-owner). Main equals the tag. No milestone names in command or agent text.

## 5. Implementation order

Work happens in a `release/0.10.0` worktree at `~/build-fleet-0.10` (D10); the main
working tree stays at v0.9.0 until the merge, which is what step 1 relies on.

1. The measurement on tap against main at v0.9.0 (§6). Its result fixes the
   `standard` + `low` row before the seeding table is written into `new-feature`.
2. `scripts/change-review-gate.test.sh`, failing, then `scripts/change-review-gate.sh`
   until it passes; `run-tests.sh` picks it up by glob.
3. `commands/handoff.md` §3.6; the three agents' CHANGE_REVIEW sections §3.7; the
   rubric, protocol, loops, contract and status updates for change review.
4. `agents/classifier.md` §3.1; `commands/new-feature.md`, `commands/dispatch.md`,
   `commands/status.md` §3.2; protocol and README schema.
5. Lenses §3.3 in the three agents and `review.js`; `lens-drift.test.sh` and
   `rubric-drift.test.sh` green; `node --check workflows/review.js` and the
   determinism lint green.
6. Classifier previews on tap from the worktree, `claude --plugin-dir ~/build-fleet-0.10`
   (§6); CHANGELOG with the measurement and the previews; version bump; descriptions;
   merge; tag.

## 6. Testing

**Gate harness** (`scripts/change-review-gate.test.sh`, hermetic mktemp workspace,
bash 3.2): zero findings passes; an open blocker fails with `open-blockers`; a `fix`
major fails with `majors-open`; an `adr` major with the ADR present passes; an `adr`
major whose ADR is absent fails with `majors-without-adr`; a missing role fails with
`missing-<role>`; a qa `fix` major closed by the architect's block with an ADR passes
(closed-by-id); a new major at change cycle 2 passes and appears in `demoted`; a
re-raised cycle-1 major at cycle 2 fails; a legacy block with no ids and an
undispositioned major fails; headings with en-dash, em-dash and hyphen all match; a
same-numbered `## Cycle N` block with an open blocker is ignored; `--roster` overrides
the default; a non-integer `CHANGE_CYCLE` exits 1.

**Drift and lint.** `lens-drift.test.sh`, `rubric-drift.test.sh`,
`workflow-determinism-lint.test.sh`, `node --check`. The full suite via
`scripts/run-tests.sh` on macOS and in CI's Linux job.

**Classifier previews on tap.** `/build-fleet:dispatch` with three descriptions: a
change to the login check reads `standard` + `elevated` with `auth`; a docs typo reads
`trivial` + `low`; a new table plus backfill across packages reads `large` with
`data-migration`. Record the three signal lines in the CHANGELOG entry.

**The measurement, release gate (D9).** tap's `.sdd/fixture-and-harness/` working tree
already holds the three-role arm: the 2026-09-06 v0.9.0 cycle 1, uncommitted, with
`CYCLE: 1`, `CYCLE_TOTAL: 6`, `LAST_REVIEW_OUTPUT_TOKENS: 274075`, three `## Cycle 1`
blocks in REVIEW.md and disposition ADR-7 in DECISIONS.md. HEAD holds the pre-migration
0.8 state at `CYCLE: 2`. So the measurement is one new run, not two:

1. Copy `.sdd/fixture-and-harness/` aside as the three-role arm. Its figures are
   recorded in CHANGELOG 0.9.0: 8 agents, 26.6 min, 274,075 output tokens, 0 blockers,
   9 `fix` majors.
2. Reconstruct the state that run started from, in place: delete the three `## Cycle 1`
   blocks from REVIEW.md, delete ADR-7 from DECISIONS.md, set `CYCLE: 0` and
   `CYCLE_TOTAL: 5`, drop `LAST_REVIEW_OUTPUT_TOKENS`. Keep REVIEW-archive.md and the
   rest of PROGRESS.md as is.
3. With the main working tree still at v0.9.0, which D10 guarantees until the merge,
   run `/build-fleet:review --roles architect,qa --cycle-budget 2` in tap. Record the
   agent count from the workflow log, wall-clock from the launch line to completion,
   `output_tokens`, the surviving blockers and `fix` majors by text, and the
   cross-examination yield: refutations issued and concerns actually discarded, from
   the `refuted-by:` lines. The yield tests the objection that two orthogonal lenses
   cannot refute each other; the three-role arm's REVIEW.md gives the baseline.
4. Compare the surviving sets by content. If the two-role arm lacks a blocker or `fix`
   major that the three-role arm kept and Ray judges real, the `standard` + `low` row
   reverts to `architect, qa, coder` and budget `3`: the risk axis and the seeding
   mechanism still ship, without the cut. Either way the numbers go into the CHANGELOG
   entry.
5. Record the confounds with the result: one month of model drift between the arms.
   The lens changes are in neither arm, because the run uses v0.9.0, so the roster is
   the only plugin-side difference.
6. Whichever arm Ray continues the feature from goes back into the working tree. If it
   is the two-role arm, first edit PROGRESS.md to `REVIEW_ROLES: architect, qa` and
   `REVIEW_CYCLE_BUDGET: 2`: the flag is not persisted, and the finalize gate would
   otherwise report `missing-coder`.

Success criteria: the two-role cycle logs 5 or 6 agent invocations against 8; the gate
harness passes every case above; both handoff call sites cite the script; the suite is
green on both CI platforms; the measurement is recorded.

**CHANGE_REVIEW live run.** No tap feature is at BUILD. The harness is this release's
proof; the first tap handoff after 0.10.0 is the live check and is noted in the pilot
doc as such.

## 7. Out of scope

Named so they are not mistaken for omissions:

- A roles-of-one review path (single rubric-driven reviewer, no cross-examination). The
  floor of 2 ripples through `review.js`, the finalize gate's roster, rotation and the
  cross-exam skip; the evidence says measure first.
- Dropping the product-owner's mandated self-review procedure once the `opus` alias
  resolves to Opus 5 or later; the "Self-review notes" output block the delta review
  reads would stay.
- A three-way critic verdict (agree / disagree-with-citation / disagree-concern). Needs
  a `REFUTATION_SCHEMA` change and a critic lens; a candidate for the next measurement.
- A tier-based CHANGE_REVIEW roster or budget (D8).
- CHANGE_REVIEW as a dynamic workflow (D6).
- Command namespacing and progressive disclosure of the 23 commands: a breaking rename
  of the headless contract, deferred to a major version per ROADMAP.md.
