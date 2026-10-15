# Changelog

All notable changes to the build-fleet plugin. Follows [Keep a Changelog](https://keepachangelog.com/) conventions; semver bumps track the plugin's `version` in `.claude-plugin/plugin.json`.

## Compatibility

build-fleet's machine surface is versioned: scaffolded `.sdd/` state files carry an
`SDD_SCHEMA: 1` stamp, the status snapshot declares `build-fleet/status-snapshot@1`, and the
`BUILD_FLEET_*` signal-line grammar is at version 1. Any release that changes the `.sdd/` schema
or the signal grammar adds a **Compatibility** line to its entry below, describing the change and
any migration; additive changes keep the version, breaking changes bump it. **Finish or park
(`/build-fleet:status park <reason>`) in-flight items before a major upgrade** — mid-flight `.sdd/` state is not
migrated automatically. build-fleet assumes a single driver per working tree: one orchestrator
session per worktree, with the `.sdd/ACTIVE` lock serializing acquisition within that worktree
only (never across clones).

## [Unreleased] — 0.12.0 (lite)

### Added
- **Five user commands** — `/build-fleet:start [idea | --product "<vision>"]`, `build`, `ship`,
  `fix <symptom>`, `status`. Each drives the existing steps in order and ends with one
  `BUILD_FLEET_LITE_DONE: {"stop":…,"next":…}` line; running it again resumes.
- `scripts/lite-next.sh` — the router: reads `.sdd/` and prints one `BUILD_FLEET_LITE_NEXT:` line
  (the next hidden step, or a stop). Fails closed on any state it does not recognise.
- State markers the router reads: `BUILD_STATE` (`started | needs-iteration | done`, written by
  `implement` and by the deep-build workflow's scribe), `FIX_DONE_CYCLE` (written by `apply-fix`),
  and `HYPOTHESIS_CYCLE` (the first line of a bug's hypothesis).
- `scripts/workflow-parse.test.sh` — every workflow must compile as an async body (replaces the
  `node --check` advice, which rejects top-level `return`).
- **Drift gate** — `scripts/drift-gate.sh` proves every acceptance criterion in a feature's spec
  is named by a `<slug>/AC-<n>` marker comment in a test file under the test roots (`TEST_ROOTS`,
  else whichever of `tests`, `test`, `spec` exist), and that no marker names a criterion the spec
  lacks. On by default (`DRIFT_GATE: off` opts a feature with no tests out). It runs before and
  after coder and at `handoff`; a failure gets one qa repair pass, then `QA_FAIL: drift` and
  `build` repairs it. `drift-gate.sh --all` runs it in CI over every built feature.

### Changed
- **Four files per feature.** A feature is `spec.md` (ending with its `## Acceptance Criteria`),
  `PROGRESS.md`, `DECISIONS.md` and `REVIEW.md`; `IMPL_NOTES.md` exists only once something is
  written to it. The test plan is the tests' own `<slug>/AC-<n>` markers. Skill routing is two
  PROGRESS fields, `CODER_SKILLS` and `QA_SKILLS`. Review blocks are findings only: a role heading
  plus its finding lines. Across the plugin's shipped files the change is 431 lines added and 575
  deleted (net −144).
- **The spec's budget is in lines:** `SPEC_MAX_LINES` (150 standard, 400 large) replaces
  `SPEC_MAX_KB`; `AC_MAX` counts the spec's acceptance section.
- `stop-tests` skips its green-suite check before coder is dispatched (`BUILD_STATE` absent) and
  while a deep-build workflow is running, instead of reading TEST_PLAN/IMPL_NOTES content.
- **Lean agents** — every agent and skill description is one line of at most 40 words that says
  when to use it and when not to; agent bodies describe the role, not the workflow, at about 800
  words (a few have a named cap). No rule was cut: `docs/history/2026-10-16-lean-agents-RULES.md`
  quotes each one before and after. `scripts/agent-surface.test.sh` guards description length,
  body caps, the inventory, and pins every agent's `tools:` list.
- **Every other command is a hidden step** (`user-invocable: false`): it cannot be typed, and the
  lite commands run it. Ask Claude in plain words to run one directly.
- **`build`, `ship` and `status` are human-only** (`disable-model-invocation`): running `build` is
  the approval of the spec, and Claude cannot run these three. The hidden steps behind them are
  still model-invocable, and `fix` (model-invocable) runs a bug through to devops.
- `status` takes the human decisions: `status park <reason>`, `status resolve [<slug>] <decision>`,
  `status ratify [force]`; bare `status` names the next command and shows a plan awaiting
  ratification. It no longer pins the haiku model.
- `new-product` takes `<slug> [vision…]`.
- README's first screen is install plus a 60-second walkthrough; the architecture, hidden-step
  reference and history moved to `docs/reference.md`. `docs/v0.2/CONTRACT.md` opens with the lite
  surface.
- Agent bodies edited for the renames: qa, classifier, coder (description), architect,
  product-owner.

### Renamed
- Step `build` → `implement`; step `fix` → `apply-fix` (the names now belong to the lite commands).

### Removed
- `park`, `resolve-escalation`, `plan-finalize` — their behavior moved into `status`, unchanged.
- `acceptance.md`, `TEST_PLAN.md` and `SKILL_MANIFEST.md` from a feature's layout; the `test-plan`
  skill (skills 7 → 6); `SPEC_MAX_KB`; the review block's `status:` line and the `status` field of
  the reviewer payloads.

### Fixed
- The review gates (`finalize-gate`, `change-review-gate`, the `check-review-written` hook) missed every
  `## Cycle N — <role> —` heading when run in a C locale: the `[—–-]` bracket matched one byte of the
  three-byte em dash. Headings now match in every locale.
- `workflows/plan-review.js` did not parse (backticks inside a template literal, since 0.9.0), so
  the product-plan review could not load.

### Breaking
- Headless callers that typed a hidden step (`claude -p "/build-fleet:review"`) must drive the
  lite commands instead. Signal lines from the hidden steps are unchanged.
- **Compatibility:** forward features are `SDD_SCHEMA: 2`. **Breaking:** a forward feature started
  before 0.12.0 is refused (`unsupported-schema`) by the lite router and the source-write gate —
  park it (`/build-fleet:status park <reason>`) and start it again; nothing is migrated.
  `drift-gate.sh --all` reports such features unchecked. The bug lane and the product tier are
  unchanged (schema 1). Signal grammar adds `BUILD_FLEET_LITE_NEXT` and `BUILD_FLEET_LITE_DONE`; the
  `BUILD_FLEET_DRIFT_GATE` line drops `missing`, `unparsed` and `gaps_open`.

## [0.11.0] — 2026-10-14

### Added
- **Verified review** (`REVIEW_SHAPE: verified`, opt-in; `debate` stays the default): findings carry a
  verbatim spec quote (or a named absence) and a failing test; a panel of three fresh verifiers judges
  each one; two quote-backed refutations kill a finding, one never does; severity is the median vote,
  lowered only with quoted evidence; open findings carry forward between cycles.
- `scripts/quote-check.sh`, run by a hook when the review's scribe finishes, checks every quote word for
  word and records the result in `.sdd/<slug>/EVENTS.jsonl`; a quote that is not found voids its vote.
- The finalize gate recomputes verified votes, refuses `quote-check-missing` and
  `spec-changed-since-review`, `review-changed-since-check` (REVIEW.md edited after its quotes were
  checked) and `verified-eval-failed`, and gains `--report`. Only the three numbered panel verifiers
  vote, each once per finding, whatever it returns.
- Event log essentials: `log_event`, and guards that keep agents from writing the log, through the file
  tools or through Bash.

### Compatibility
- Nothing changes unless `REVIEW_SHAPE: verified` is set. Existing REVIEW.md files parse unchanged.
  `SDD_SCHEMA` stays 1. `.sdd/<slug>/EVENTS.jsonl` is new and committed with the rest of `.sdd/`.

## [0.10.1] — 2026-10-11

Documentation and prompt fixes from a review of the 0.10.0 surface. One of them changes behavior.

### Fixed
- **devops no longer refuses a cycle the change-review gate passed.** Its refusal condition still required every CHANGE_REVIEW block to say `approved`, while the 0.10.0 gate ignores `status:` lines and passes a cycle whose majors are all ADR'd or demoted. A passing cycle with a `concerns-raised` block was refused, `/build-fleet:handoff` left `PHASE: HANDOFF`, and every re-run resumed at devops and refused again. Handoff now passes the gate line to devops, and devops refuses only when the prompt lacks a passing line for the current `CHANGE_CYCLE`. The refusal reason `review-not-approved` keeps its name and now means that.
- `/build-fleet:handoff` refuses with the gate's stderr when the gate prints no line (exit 1: no PROGRESS.md, a non-integer `CHANGE_CYCLE`, jq missing). Before, the resume path handled only pass and fail.
- `/build-fleet:dispatch` shows a verdict with no `risk` field as `elevated`, matching new-feature's fallback. Its description now names the risk and roster preview.
- Prompt wording: qa's CHANGE_REVIEW section names the two-stage order. The architect is told an ADR is the only way its block closes a peer's major. `/build-fleet:review` says new-feature seeds the durable roster. The sdd-protocol skill drops a release reference.

### Docs
- The 0.10.0 design spec gains an outcome note on D2 and the §3.2 table pointing at the REVERT, and §4 says absent `RISK` prints `unset`.
- README: the review workflow node, the dispatch and status rows, and the scripts list. CLAUDE.md's scripts list, `docs/loops.md` and `docs/CLAUDE.sample.md` match the gate.

**Compatibility.** No schema or signal-grammar change. `review-not-approved` keeps its slug with the narrower meaning above.

## [0.10.0] — 2026-10-11

The **proportionate review** release. Review effort now scales with stakes: the
classifier rates risk on a second axis, `new-feature` seeds the review roster and
cycle budget from tier and risk, the three review lenses are calibrated to the
reviewer discipline, and CHANGE_REVIEW exits on a deterministic rubric gate with the
v0.9 convergence rules (ids, dispositions, closed-by-id, delta demotion). Design:
`docs/history/2026-10-10-proportionate-review.md`; evidence:
`docs/history/2026-10-10-orchestration-balance-research.md`. Measured on the tap
pilot before tagging (`docs/history/2026-10-10-proportionate-review-MEASUREMENT.md`):

| Arm | Roster | Agents | Wall-clock | output_tokens | Surviving blockers | Surviving `fix` majors | Refutations that discarded a concern |
|---|---|---|---|---|---|---|---|
| three-role (2026-09-06) | architect, qa, coder | 8 | 26.6 min | 274,075 | 0 | 9 | 3 |
| two-role (2026-10-11) | architect, qa | 6 | 3.8 min | 23,448 | 0 | 5 | 0 |

**Decision: REVERT.** The two-role arm lacked six of the three-role arm's nine `fix`
majors, and at least one is real by evidence (openpyxl's `COLOR_INDEX` has 64 entries
and the fixture's styles.xml carries `indexed="64"`), so under the spec's rule the
`standard` + `low` row keeps `architect, qa, coder` with budget 3. The risk axis and the
seeding mechanism ship; the cut does not. Two caveats travel with the number: five of
the six lacked findings came from roles present in both arms and the arms differ 7× in
wall-clock and 12× in output tokens, so one month of model drift, not the roster, is
the likelier cause — the pre-registered rule was applied as written and a same-model
re-measurement is open to a later release. And the tap used for both arms is an
archived copy; production tap does not run build-fleet, and the measured feature is
not being continued.

Classifier previews on tap (`/build-fleet:dispatch`, run headlessly against the worktree):

```
"tighten the login check so a disabled account cannot obtain a session token"
→ BUILD_FLEET_CLASSIFICATION: {"tier":"standard","build_mode":"standard","skip_review":false,"confidence":"medium","risk":"elevated","risk_reasons":["auth"]}
"fix the typo 'recieve' in docs/README.md"
→ BUILD_FLEET_CLASSIFICATION: {"tier":"trivial","build_mode":"standard","skip_review":true,"confidence":"low","risk":"low","risk_reasons":[]}
"add a position_history table and backfill it from the positions table across the ingest and export packages"
→ BUILD_FLEET_CLASSIFICATION: {"tier":"standard","build_mode":"standard","skip_review":false,"confidence":"medium","risk":"elevated","risk_reasons":["data-migration"]}
```

The third reads `standard` where the design expected `large`: the classifier read tap,
found no `ingest`/`export` packages and one tight package (`src/tap/db` plus migrations),
and applied the existing single-partition rule; main at v0.9.0 sizes the same description
`standard` too. The risk half is what this release adds, and it reads as designed.

No live CHANGE_REVIEW run exists yet: the gate harness is this release's proof, and
the first `/build-fleet:handoff` on a build-fleet-driven repository is the live check.

### Added
- **Classifier risk axis** — `risk: low | elevated` + `risk_reasons` (slugs: `auth`, `secrets`, `billing`, `data-migration`, `ci-release`, `new-dependency`, `review-requested`, `irreversible`, `public-contract`, `shared-module`). Elevated is never `trivial`. PROGRESS gains `RISK:`.
- **Tier-by-risk review seeding** in `new-feature` step 7 (`standard` + `low` → architect, qa, coder, budget 3 — reverted from the designed architect, qa / 2 by the measurement above; everything else → architect, qa, coder, budget 3; the hand-edit-only trivial row → architect, qa, budget 2), recorded by the new `BUILD_FLEET_REVIEW_DEFAULTS` line. A `trivial` + `elevated` verdict is coerced to `standard` (`BUILD_FLEET_CLASSIFIER_FALLBACK` reason `risk-tier-conflict`). `dispatch` previews risk and the would-seed roster; `status` prints TIER, RISK and the roster.
- **`scripts/change-review-gate.sh`** (+ harness, 35 cases) — the CHANGE_REVIEW exit `/build-fleet:handoff` now computes: every roster role has a `## Change-Cycle N` block, zero unrefuted blockers, every major closed by an ADR present in DECISIONS.md or demoted; two passes so an architect ADR closes a peer's id in every block. Fails closed on an unterminated last line, a CRLF file, a legacy major with backslashes, and an indented finding bullet (reason `unparsed-findings`). One signal line, `BUILD_FLEET_CHANGE_REVIEW_GATE`.

### Changed
- **CHANGE_REVIEW is two-stage**: product-owner and qa in parallel, then the architect, who reads their blocks and may accept a peer's major by ADR (closed-by-id). Findings carry ids `<role>-cc<K>-<n>` and `disposition:` lines; from change cycle 2 the delta rule applies and a new major is advisory. The budget guard and the exit both call the gate, so they cannot disagree; the exhausting cycle escalates directly with blockers and `fix` majors both listed. A missing block, an unparsed finding or an ADR the architect cited but never wrote re-dispatches that reviewer, not the coder.
- **`handoff` resumes at devops when `PHASE: HANDOFF`** (a previous run's devops refusal) instead of refusing the phase it told the user to re-run from.
- **Lenses calibrated**: qa's "invent assumptions ⇒ major" and "vague words ⇒ blocker-tier" and coder's gap list move to "a major only where a coder would guess at behaviour a test could fail on; vagueness is a major inside an acceptance criterion and a minor elsewhere"; the coder lens drops its coverage bullet (qa's duplicate); the architect's failure-modes bullet is severity-rated. Both copies (agent + `review.js` LENS); descriptions refreshed (classifier, architect, qa, coder, product-owner).

### Fixed
- `agents/product-owner.md` named a `## Cycle <N>` heading for its CHANGE_REVIEW block, which `check-review-written.sh` rejects in that phase; now `## Change-Cycle <N>`.

**Compatibility.** `SDD_SCHEMA` stays `1`. Additive PROGRESS field `RISK` (read-with-default; absent prints `unset`). Signal grammar: new lines `BUILD_FLEET_CHANGE_REVIEW_GATE`, `BUILD_FLEET_REVIEW_DEFAULTS`; new fields `risk`, `risk_reasons` on `BUILD_FLEET_CLASSIFICATION`, `risk_assigned` on `BUILD_FLEET_CLASSIFIER_FALLBACK`; new fallback reason `risk-tier-conflict`; gate reason slugs `missing-<role>`, `open-blockers`, `majors-open`, `majors-without-adr`, `unparsed-findings`. REVIEW.md Change-Cycle lines gain `(id)` and `disposition:`; old blocks still parse — an undispositioned legacy major reads as open and bounces to the coder once, after which reviewers re-raise with ids. A feature seeded before 0.10.0 keeps its three-role roster; edit `REVIEW_ROLES` / `REVIEW_CYCLE_BUDGET` by hand to adopt the table. No migration required.

## [0.9.0] — 2026-09-06

The **convergent review** release. The REVIEW loop is now bounded and monotone: a
rubric-only finalize gate, delta review from cycle 2, in-workflow ADR disposition of
majors, read-only reviewers, bounded review inputs, spec/criteria/cumulative-cycle caps,
a real clock in the dispatching commands, and walking-skeleton planning. Design:
`docs/history/2026-09-02-convergent-review.md`. Validated live on the pilot on
2026-09-06: a full cycle 1 on a 49 KB spec ran 8 agents in 26.6 min (734k
subagent tokens, 274k output), rotated a 199 KB REVIEW.md to 17 KB, wrote its
first disposition ADR, and the finalize gate agreed with the workflow's
`finalize_ready` (9 open `fix` majors, 0 blockers).

### Added
- **`agents/reviewer.md`** — the read-only reviewer every `review.js` leg runs as (Read/Grep/Glob; lens injected by the workflow). Ends double-written REVIEW.md blocks, fabricated timestamps and ungated writes.
- **Disposition leg** in `workflows/review.js` — surviving majors become `disposition: adr ADR-N` (ADR drafted, scribe-written via the new envelope field `decisions_appendix`) or `disposition: fix`. Finding ids are stable (`<role>-c<cycle>-<n>`). Enforced in code, not only asked for in the prompt: on a delta cycle (≥ 2) any major whose id originates at cycle ≥ 2 is demoted to minor with a prefixed explanatory text; a disposition with an empty ADR body, a duplicate id, or a missing id fails the run as `incomplete` (`disposition-incomplete`) with nothing written.
- **`finalize_ready`** in the review envelope/return, and **`scripts/finalize-gate.sh`** — the deterministic gate `/build-fleet:finalize` now calls (harness: `finalize-gate.test.sh`).
- **`/build-fleet:revise`** — dispatches the PO with exactly the current cycle's blockers + `fix` majors and the size budget.
- **`scripts/review-rotate.sh`** — positional rotation of REVIEW.md into `REVIEW-archive.md` at dispatch; **`scripts/adr-index.sh`** — ADR id/title index and `--next`.
- **Hooks `cap-spec-size` (PreToolUse) and `validate-acceptance-count` (PostToolUse)** — `SPEC_MAX_KB` / `AC_MAX`, scaffolded by tier (standard 24 KB / 15, large 48 KB / 30); absent = no cap; refusal says split.
- **`CYCLE_TOTAL` / `CYCLE_TOTAL_MAX`** — cumulative, never reset; `/build-fleet:review` refuses `cycle-total-exhausted` before dispatch when `CYCLE_TOTAL_MAX` is not `0` and `CYCLE_TOTAL >= CYCLE_TOTAL_MAX`. **`LAST_REVIEW_OUTPUT_TOKENS`** recorded from the runtime budget; `cost-runaway` refusal (override with `--override-cost`).
- **Planning:** walking-skeleton rule for Phase 1; plan-review lenses flag a late first output (`[blocker]`) and over-scoped intents with a named `split_into`; `plan-finalize ratify` refuses `split-unresolved`; `INTENT_MAX_BYTES` (600) intent cap via `validate-backlog-status`; `intent-block.sh` emits `INTENT_BYTES`.
- Tests: `workflow-review-convergence.test.sh`, `lens-drift.test.sh`, `review-rotate.test.sh`, `adr-index.test.sh`, `finalize-gate.test.sh`, `cap-spec-size.test.sh`, `validate-acceptance-count.test.sh`; new cases in the stop-tests, intent-block, backlog-status and plan-review-config harnesses.

### Changed
- **Finalize gate is rubric-only:** zero open blockers AND every major fixed-or-ADR'd. The "every block `status: approved`" requirement is gone; `status:` is informational. `not-approved` is no longer emitted (kept in the grammar). A `refuted-by:` continuation (the survival vote) closes a blocker or a major — refuted findings never gate; absent that, a blocker is closed only when a later cycle does not re-raise it.
- **Delta review:** from cycle 2 reviewers verify closure by id and may raise new findings at blocker severity only. Escalation fires on the exhausting cycle when blockers **or** `fix` majors remain (ESCALATION.md lists both).
- **Product-owner context diet:** `new-feature` passes the binding stack + the ADR index, not the whole product DECISIONS.md, and states the size budget.
- Dispatching commands compute `now` with `date -u` (`Bash(date:*)`); the scribe appends with anchored Edits and appends absent `state_delta` keys.
- Role agents' `## Review lens` sections are mirrored in `review.js` (`lens-drift.test.sh`); their REVIEW.md append instructions are scoped to non-workflow paths; descriptions refreshed.

### Fixed
- Workflow reviewers were never tool-restricted (the runtime's `agent()` has no `tools` option), contrary to the protocol text — resolved by the reviewer agent.
- Guessed timestamps in `.sdd/` (commands had no clock).
- The `clean → finalize` recommendation that the gate then refused.
- `scripts/workflow-determinism-lint.sh` — the meta check piped a large stripped source into `grep -q`; under `pipefail` printf died of SIGPIPE and a valid workflow read as `missing-meta` ~7% of runs; now reads to EOF (harness case: a ~400 KB valid workflow linted 25×).
- `cap-spec-size` hardening: leading-zero caps parsed as decimal, newline-safe `replace_all` occurrence counting, and `NotebookEdit` on a spec/acceptance file refuses (fails closed).
- The finalize gate and `/build-fleet:revise` treat a refuted blocker as closed.
- The scribe anchors appends on the final BLOCK (headings are unique), not the final line.
- Ride-along fixes since 0.8.0 (unreleased on `main`): distinct `## Change-Cycle N` heading; bug-lane source unlock at `STATUS=FIXED`; plan-review `LENS` TDZ; stop-tests prefers the project `.venv`; stop-tests stands down in the BUILD tests-first window (now with a harness case).
- `hooks/scripts/reap-stale-workflow-markers.sh` — `STALE_AFTER_SECONDS` raised from 900 (15 min) to 7200 (2 hours): the Stop hook fires whenever the orchestrator ends a turn while waiting on the workflow, so the old threshold reaped the LIVE marker mid-run on the 2026-09-06 pilot run (26.6 min), forcing a manual restore; a false reap re-enables `check-review-written` / `restrict-reviewer-writes` before the scribe applies and can block the recording write after the whole run's cost was spent. The reaper exists for CRASHED runs only — a live run's marker is released by the scribe itself — so the 2-hour grace costs nothing but a delayed re-engagement after a crash.
- `workflows/review.js` `@cost-ceiling` recalibrated from the v0.2 guess (`120000`/`30000`) to `600000`/`120000`, measured from the 2026-09-06 live run's 274,075 output tokens; the old ceiling put `commands/review.md`'s 3× `cost-runaway` trip at 90,000 — below the cost of a normal run — and would have refused the next review.

**Compatibility.** `SDD_SCHEMA` stays `1`. Additive PROGRESS fields (`CYCLE_TOTAL`, `CYCLE_TOTAL_MAX`, `SPEC_MAX_KB`, `AC_MAX`, `LAST_REVIEW_OUTPUT_TOKENS`; product `INTENT_MAX_BYTES`) — all read-with-default; a new optional workspace file `REVIEW-archive.md`; envelope fields `finalize_ready` and `decisions_appendix`; REVIEW.md lines gain `(id)` and `disposition:` (old blocks still parse — an undispositioned legacy major reads as open). Signal grammar: new `BUILD_FLEET_REVIEW_ROTATED`, `BUILD_FLEET_FINALIZE_GATE`, `BUILD_FLEET_REVISE_DISPATCHED`; new refusal reasons `cycle-total-exhausted`, `cost-runaway`, `majors-open`, `nothing-to-revise`, `split-unresolved`; `not-approved` no longer emitted. **Migration for an in-flight 0.8.0 feature** (one whose REVIEW.md blocks carry no `(id)` / `disposition:` lines): before its first 0.9 review, edit PROGRESS.md to `CYCLE: 0` and add `CYCLE_TOTAL: <the old CYCLE value>` so the next run is a full cycle 1 with fresh ids — legacy findings cannot be re-raised by id and would otherwise be dropped or demoted by the delta rules. The run then rotates the old log to REVIEW-archive.md, dispositions every surviving major and stamps `CYCLE_TOTAL`. Headless callers of `/build-fleet:review`: pass `--add-dir <plugin dir>` so the Workflow tool accepts the plugin's script path, and set `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0` so `claude -p` waits for the run (it otherwise terminates background work after 10 minutes).

## [0.8.0] — 2026-06-20

`/build-fleet:new-feature` gains a richer feature-detail intake: an optional inline detail
argument, an explicit source-precedence, and a bounded interactive clarify loop in place of the
old one-shot ask. Additive and backward-compatible — the slug-only invocation still works. No
`.sdd/` schema, signal-grammar, or config changes.

### Added

- **Inline feature-detail argument** — `/build-fleet:new-feature <slug> [feature details…]`. The
  first whitespace-delimited token is the slug; everything after it is an optional free-text
  description. When present it is the authoritative description for the run, and is the channel
  headless / `claude -p` callers use to supply detail (`commands/new-feature.md` Arguments + step 5;
  `argument-hint` updated).
- **Structured clarify loop** — when no usable description is found, `new-feature` now asks via
  `AskUserQuestion` (added to the command's `allowed-tools`) in a bounded loop that targets the
  missing components and repeats until the ≥2-of-3 quality floor is met, the user picks
  "proceed anyway", or a 3-round soft cap is reached. Replaces the previous single stop-and-ask.
- **Thin-description hand-off** — if the clarify loop ends below the floor, the product-owner
  delegation labels the description "best-effort / below the usual detail floor" and asks PO to
  surface the gaps in `## Self-review notes` rather than inventing requirements.

### Changed

- **Description sourcing is now an explicit precedence** — inline arg → conversation context →
  product-backlog intent, with **the inline arg winning** when present. The ≥2-of-3 quality floor
  (what the feature is / its scope boundary / its non-goals) now governs *all* sources: the
  deterministic `INTENT_VERDICT` from `intent-block.sh` for backlog intents, and an orchestrator
  judgment for free-text arg / conversation descriptions. The clarify loop fires on a description
  that is empty **or** below the floor (previously only when entirely absent).
- **`/build-fleet:new-feature` is interactive-only when no detail is provided.** With no inline
  arg and nothing usable in context, the clarify loop needs a human responder; in a headless /
  `claude -p` run, supply the description via the inline argument instead. The `BUILD_FLEET_*`
  signal grammar is unchanged.

## [0.7.1] — 2026-06-17

A correctness patch: a temporal-dead-zone (TDZ) crash made the **deep-build**, **diagnose**, and
**plan-review** workflows fail *every* scribe apply, so verdicts were computed but never written to
`.sdd/` and the in-flight marker was stranded. The deterministic determinism-lint now catches the
class so it can never recur silently. No schema, signal-grammar, or config changes.

### Fixed

- **Scribe-apply TDZ in `deep-build.js`, `diagnose.js`, and `plan-review.js`.** `SCRIBE_RESULT_SCHEMA`
  was declared below every `applyScribe()` call site. `applyScribe` is a hoisted function declaration,
  so the call resolved — but it reads the const via `agent(…, {schema})`, and because the script
  `return`s before reaching the declaration the const stayed in its temporal dead zone: every scribe
  apply threw `ReferenceError: Cannot access 'SCRIBE_RESULT_SCHEMA' before initialization`. The const
  is now hoisted above the first call site in all three, matching the fix `review.js` already received
  (commit `9e50f8a`, shipped in 0.7.0); the sibling workflows were missed by that sweep. `node --check`
  cannot see this — it is a runtime error, not a syntax error.

### Added

- **Determinism-lint rule `scribe-schema-tdz`** (`scripts/workflow-determinism-lint.sh`) — asserts
  `SCRIBE_RESULT_SCHEMA` is declared above the first `applyScribe()` call, so this TDZ class fails the
  lint (and CI) at authoring/pin time instead of reaching a run. With test-harness coverage, including
  a regression assertion that the three previously-broken workflows now pass.

**Compatibility.** None affected. No `.sdd/` schema or signal-grammar change — a correctness fix plus a
new static guard.

## [0.7.0] — 2026-06-15

The **dynamic-workflow enrichment**: build-fleet keeps its deterministic static core but gains
(1) per-item configurable review rosters and cycle budgets, and (2) a governed *generate-then-pin*
lane for novel work. Determinism/auditability is preserved throughout — new configuration is
validated and clamped, and generated workflows are linted, reviewed, and frozen before they can
run. Research + design: `docs/history/2026-06-15-layer2-scaffold-workflow.md`.

### Added

- **Configurable review rosters + cycle budgets (Layer 1).** All four workflows accept optional,
  validated config that defaults to the historical behavior exactly:
  - `review.js` — `roles` (≥2 of architect/qa/coder/product-owner; the structured-output role enum
    tracks the roster) and `cycle_budget` (1–3, clamped to the ceiling — configurable downward only).
  - `plan-review.js` — `roles` (≥2 of product-owner/architect/qa).
  - `deep-build.js`, `diagnose.js` — `cycle_budget` (1–3, clamped).
  The pure validators are unit-tested by verbatim extraction from each workflow.
- **Command wiring.** `/build-fleet:review`, `:plan-review`, `:deep-build`, and `:diagnose` resolve
  config as **flag > durable PROGRESS field > default** (`--roles` / `--cycle-budget`; `REVIEW_ROLES`,
  `REVIEW_CYCLE_BUDGET`, `BUILD_CYCLE_BUDGET`, `DIAGNOSE_CYCLE_BUDGET`, `PLAN_REVIEW_ROLES`), pass the
  resolved value through to the authoritative workflow validator, and emit a `BUILD_FLEET_*_CONFIG`
  audit line. `/build-fleet:new-feature` scaffolds the feature-lane fields at their defaults.
- **`/build-fleet:scaffold-workflow` — governed generate-then-pin lane (Layer 2)** for novel, large,
  unknown-shape tasks. *Draft*: Claude authors a candidate workflow into quarantine
  (`.sdd/_generated/<name>.js`), the determinism lint runs, and architect + qa interrogate it
  (advisory). *Ratify*: a hard, fail-closed lint gate (`scripts/pin-workflow.sh`) then freezes the
  candidate into the project's `.claude/workflows/<name>.js`, invokable as `/<name>`. The candidate is
  **never executed before pinning**; the pinned artifact is static and replayable.
- **`scripts/workflow-determinism-lint.sh`** — determinism + sandbox-safety gate (rejects
  `Date.now()` / `Math.random()` / argless `new Date()`, `require`/`import`/`process`/`fs`/`fetch`/
  `eval`, and a missing `export const meta`; strips comments/strings first). With test harness.
- **`scripts/pin-workflow.sh`** — fail-closed pin (lint gate + validated, traversal-rejecting copy
  into `.claude/workflows/`). With test harness.
- Optional PROGRESS fields `REVIEW_ROLES`, `REVIEW_CYCLE_BUDGET`, `BUILD_CYCLE_BUDGET` (feature lane;
  the bug/product analogs `DIAGNOSE_CYCLE_BUDGET` / `PLAN_REVIEW_ROLES` are read-with-default).
- `.sdd/_generated/` quarantine namespace (gitignored).
- Signals: `BUILD_FLEET_REVIEW_CONFIG`, `_PLAN_REVIEW_CONFIG`, `_DEEP_BUILD_CONFIG`, `_DIAGNOSE_CONFIG`,
  `_SCAFFOLD_DRAFT`, `_WORKFLOW_PINNED`, `_WORKFLOW_PIN_REFUSED`, and the lint's
  `_LINT_PASS` / `_LINT_FAIL` / `_LINT_VIOLATION`.

### Changed

- Slash commands 21 → 22 (`scaffold-workflow` added).
- README gains a generate-then-pin section + diagram and a configurable-rosters/budgets note;
  command reference, PROGRESS schema, and the `.sdd/` tree updated. The `sdd-protocol` skill's
  PROGRESS schema documents the new optional fields.

**Compatibility.** Additive only. New PROGRESS fields are optional (readers ignore unknown lines),
and the new `BUILD_FLEET_*` signal names are additive. `SDD_SCHEMA` stays `1`, the signal-line
grammar stays at version 1, and the status snapshot stays `build-fleet/status-snapshot@1`. No
migration required; in-flight `.sdd/` items are unaffected.

## [0.6.2] — 2026-06-11

### Fixed

- **README accuracy pass.** Version banner 0.5 → 0.6; intro rewritten in present tense (was
  framed as v0.4 release notes); the last surviving exit-code claim replaced with the
  `{"code","reason"}` refusal contract; hooks table now lists all ten gates (guard-bash-writes
  was missing) with the fail-closed and bounded-stop-tests semantics; PROGRESS schema gains
  `BUILD_CYCLE`, `PARKED`, and `SDD_SCHEMA`; release-channel CI description matches the
  tag-push design; headless signal list gains PARKED/RESOLVED/ACTIVE_CONFLICT. Docs only.

## [0.6.1] — 2026-06-11

### Fixed

- **Marker reaper broken on Linux.** GNU `stat -f %m <file>` does not fail — it runs in
  filesystem mode and prints the mount point, so the BSD-first probe order poisoned the age
  arithmetic and `reap-stale-workflow-markers.sh` died (exit 1) on every Linux session stop,
  leaving stale `.workflow-in-flight` markers unreaped. Probe order is now GNU-first with a
  numeric guard. Caught by the 0.6.0 CI matrix on its first run.
- **release-channel CI race.** The version≡tag check ran on main pushes and failed spuriously
  when the merge landed before the tag was pushed. It now runs on `v*` tag pushes and pins the
  tag to plugin.json's version — race-free.

## [0.6.0] — 2026-06-11

The professional-standard release: ships the pollable status snapshot (ROADMAP **v0.3a**)
and remediates all 66 findings of the 2026-06-09 end-to-end audit
(`docs/audits/2026-06-09-ultracode-audit.md`).

### Added

- **Pollable status snapshot (ROADMAP v0.3a).** `scripts/status-snapshot.sh` emits one
  machine-readable JSON object (`build-fleet/status-snapshot@1`) describing the full `.sdd/`
  state — for external orchestrators to poll. README gains an "Orchestrator integration"
  section (invocation outside Claude Code, signal stability policy).
- **`/build-fleet:build`** — BUILD orchestration split out of `/build-fleet:finalize`;
  finalize is now a pure, idempotent gate.
- **`/build-fleet:park`** and **`/build-fleet:resolve-escalation`** — the sanctioned sev0
  preemption path and the human escalation-resolution path (both `disable-model-invocation`).
- **Bash/NotebookEdit write gate** (`guard-bash-writes.sh`): shell-level source writes are
  blocked during locked phases; write-gate matchers extended to NotebookEdit.
- **Atomic `.sdd/ACTIVE` acquisition** (`scripts/acquire-active.sh`): noclobber lock with
  owner metadata; new-feature/triage acquire, handoff/ship-fix/park release.
- **Deterministic helpers replace prose:** `scripts/intent-block.sh` (backlog intent
  extraction + quality verdict), `scripts/product-memory-splice.sh` (marker-safe CLAUDE.md
  splicing — never clobbers content outside the markers).
- **Test infrastructure:** `scripts/run-tests.sh` single entrypoint (17 suites, 250+ cases),
  GitHub Actions CI (macOS bash-3.2 + Linux matrix, release-channel version≡tag check),
  suites for every previously untested gate, severity-rubric drift test.

### Changed

- **Gates fail closed.** Path-traversal (`..`) rejection in all path helpers; hooks anchor at
  `CLAUDE_PROJECT_DIR`; missing jq blocks (with install instructions) while an item is active;
  unexpected gate errors trap to exit 2. `stop-tests` honors `stop_hook_active`, retries are
  bounded (3) and escalate to ESCALATION.md instead of wedging the session.
- **Workflow contracts are honest.** `now` is a required arg (no more `UNKNOWN_TIME` in audit
  trails); cost previews parse the real `@cost-ceiling` header; deep-build enforces a
  3-cycle budget via the new `BUILD_CYCLE` field; scribe application is verified (a failed
  state write can no longer hide behind a success verdict); transient agent failures return
  `incomplete` for re-run instead of bricking the feature in ESCALATED; `.workflow-in-flight`
  markers carry a run token, are released by the owning run only, and orphans reap at 15 min.
- **Exit-code tables removed everywhere** — slash commands cannot set exit codes. Refusals
  carry `{"code": <int>, "reason": "<slug>"}` in the `BUILD_FLEET_REFUSE` JSON; the signal
  lines are the sole machine contract (CONTRACT.md updated).
- **Documentation describes the shipped system.** sdd-protocol restructured (321-line core +
  `references/{product-tier,bug-lane}.md`), present tense, classifier contradiction removed;
  adr skill supports product ADRs + `PROVISIONAL`; agent descriptions enumerate bug-lane
  roles; CLAUDE.md is now contributor instructions (v0.1 design spec archived in
  `docs/history/`); milestone jargon stripped from the user-facing surface.
- **verify counterfactual is snapshot-safe:** a `git stash create` SHA is recorded before any
  tree mutation and restore is verified before any verdict.

### Removed

- `workflows/hello.js` (dev probe; findings preserved in `docs/v0.2/hello-probe.md`).

### Compatibility

- Scaffolded `.sdd/` files now carry `SDD_SCHEMA: 1`; existing state without the stamp is
  read fine. New per-worktree coordination files (`ACTIVE.lock`, `.stop-test-retries`) are
  covered by the scaffolded `.sdd/.gitignore` policy.
- **Breaking for headless callers:** `/build-fleet:finalize` no longer runs BUILD — dispatch
  `/build-fleet:build` after it. Exit-code dispatch was never real; parse the
  `BUILD_FLEET_*` lines (now with `{code, reason}`). Review/deep-build/finalize dispatches
  must supply `now`. Signal grammar and snapshot schema remain at version 1 (additive).

## [0.5.1] — 2026-06-10

### Added

- **MIT license.** `LICENSE` file at the repo root, `license` fields in `plugin.json` and the
  marketplace entry, a License section in the README, and SPDX headers on the workflow scripts.
  Every prior tag shipped without a license (all-rights-reserved by default); v0.5.1 is the first
  legally adoptable release. No functional changes.

## [0.5.0] — 2026-06-05

### Added

- **Troubleshoot-fix bug lane** — a second, parallel state machine for diagnosing and fixing
  *unknown-cause* bugs, additive to the forward feature machine (a repo that never files a bug is
  byte-for-byte unchanged). Phases: `REPORT → REPRODUCE → DIAGNOSE → FIX → VERIFY → HANDOFF`. Its
  contract is a new **`diagnosis.md`** artifact (STATUS `REPORTED|REPRODUCING|DIAGNOSED|CONFIRMED|FIXED`),
  not a spec. Spec of record: `docs/v0.5/troubleshoot-fix-spec/`.
- **Artifact + validator (M0).** `skills/sdd-diagnosis-template` (the diagnosis.md contract);
  `hooks/scripts/validate-diagnosis-status.sh` (PostToolUse, keyed on `basename==diagnosis.md`; no
  cross-fire with the spec validator). `_lib.sh` gains `read_diagnosis_status`, `resolve_lane`,
  `tests_exist`, `path_in_tests`.
- **Source-write gates (M2).** `hooks/scripts/require-reproducing-test.sh` (NEW) — a bug source
  write is blocked unless `diagnosis.md` STATUS==CONFIRMED **and** ≥1 test exists under `tests/`
  (severity-independent — holds for sev0). `block-source-before-finalized.sh` gains a second unlock
  (CONFIRMED), the FINALIZED path byte-identical.
- **Entry (M1).** `/build-fleet:triage <symptom>` scaffolds the bug + runs the classifier in a new
  **bug mode** (`{severity, cause_known}`); a known-cause bug is bounced to the forward trivial path.
- **Diagnosis confirmation (M3).** `workflows/diagnose.js` — an inverted `review.js`: architect +
  coder try to refute the root-cause hypothesis citing the reproduction; CONFIRMED iff no refutation
  survives. Driven by `/build-fleet:reproduce` + `/build-fleet:diagnose`.
- **Fix tail (M4).** `/build-fleet:fix` (FIX gate — flips diagnosis.md→CONFIRMED, drives the coder),
  `/build-fleet:verify` (reuses the CHANGE_REVIEW counterfactual verbatim), `/build-fleet:ship-fix`
  (devops + clears `.sdd/ACTIVE`). sev0 hotfix fast-path. `/build-fleet:status` is bug-lane-aware.
- **New PROGRESS bug-lane fields:** `LANE: bug`, `SEV: sev0|sev1|sev2`, `FIX_CYCLE`. New signals
  include `BUILD_FLEET_TRIAGE`(`_KNOWN_CAUSE`), `BUILD_FLEET_REPRO_READY`,
  `BUILD_FLEET_DIAGNOSE_SEV0_SKIP`, `BUILD_FLEET_FIX_GATE`/`_DONE`, `BUILD_FLEET_VERIFY`,
  `BUILD_FLEET_SHIP_FIX`, `BUILD_FLEET_POSTHOC_DIAGNOSIS_DUE`.
- **Planted-bug smoke test** (`docs/v0.5/smoke/`) — a fixture (a paginator with a floor-division
  bug) + a driver that walks the bug through the lane's deterministic backbone (the hook gates +
  the STATUS lifecycle + RED→GREEN + the VERIFY counterfactual) against the **actual** hooks, plus
  a live-run `WALKTHROUGH.md` for the LLM-driven classifier + `diagnose.js` parts.

### Fixed

- **Hook fail-open under bash 3.2.** The `_lib.sh` STATUS/field readers ended in an unguarded `grep`
  pipeline that, under `set -euo pipefail`, aborted the hook with exit 1 (non-blocking) on a
  status-less file instead of reaching exit 2 — letting a source write slip the gate. Guarded all
  five readers (`read_diagnosis_status`, `read_spec_status`, `read_progress_field`,
  `read_product_field`, `resolve_product`); closes a latent `spec.md` bypass dating to v0.2.
- **Bug-lane `tests/` deadlock (AC-7).** `block-source-before-finalized` blocked a bug's `tests/`
  writes until CONFIRMED — but the reproducing test, written at REPRODUCE *before* CONFIRMED, is the
  precondition for ever reaching CONFIRMED, so the lane deadlocked at REPRODUCE. Taught the bug
  branch to permit `tests/` (mirroring `require-reproducing-test`). Caught by the new planted-bug
  smoke test; now a regression case in `block-source-before-finalized.test.sh`.

## [0.4.0] — 2026-06-05

> **Note:** 0.3.0 was never released. The ROADMAP's v0.3x items (status export,
> orchestrator-mediated human intervention) ship in later versions; the plugin version
> jumps 0.2.1 → 0.4.0.

### Added

- **Product tier (M0)** — a reserved `.sdd/_product/` namespace (vision, phased backlog,
  `STACK.md`, product ADRs) inherited read-only by every feature. The **binding
  stack-of-record** prevents two features from picking conflicting stacks; greenfield
  ratifies a fresh stack, brownfield's observed baseline binds while the forward stack
  stays `PROVISIONAL`. Entry point: `/build-fleet:new-product`. The tier is optional and
  additive — a repo with no `.sdd/_product/` behaves exactly as before.
- **PLAN state machine (M3.1).** `PLAN → PLAN_REVIEW → PLAN_FINALIZE → DEVELOPING`,
  mirroring the feature machine one level up with an inverted temperament. New
  `workflows/plan-review.js` runs PLAN_REVIEW as **interrogation, not a survival vote**
  — product-owner / architect / qa surface questions, risks, and gaps (including intent
  quality); nothing is auto-killed and it never auto-escalates.
- **Human ratification gate.** `/build-fleet:plan-finalize` **never auto-passes** — even
  with zero findings. Bare invocation is a dry-run; `ratify` flips state only with zero
  open blockers; `ratify force` overrides them on the record. It never promotes a
  `PROVISIONAL` stack entry.
- **DEVELOPING loop (M2 + M3.2).** A successful `/build-fleet:handoff` flips the
  feature's backlog row to DONE and **clears `.sdd/ACTIVE`**; the next unblocked feature
  is re-resolved live by the new deterministic resolver `scripts/next-feature.sh`
  (with its own test harness) — never a cached index.
- **Per-feature backlog intent (M3.3)** — a 1–3 line scope sketch (what + scope boundary
  + non-goals) inherited by `/build-fleet:new-feature` and reviewed at PLAN_REVIEW;
  seeds the spec so the PO realizes the plan's intent instead of re-guessing from the slug.
- **`/build-fleet:next-feature` (M4)** — optional advancement convenience: resolves +
  gates the next backlog feature and emits a dispatch signal. It surfaces, it doesn't
  auto-advance.
- **Product memory (M3.1.1).** Ratification (and `/build-fleet:product-memory`) writes a
  delimited `<!-- BEGIN/END build-fleet:product -->` block into the repo-root `CLAUDE.md`
  — non-clobbering (everything outside the markers is preserved) and idempotent.
- **Dynamic skill routing to BUILD roles (M1)** — new `skills/skill-routing` skill +
  classifier manifest rules route domain skills to coder/qa; routed skills are inherited
  by product-tier features.
- **New commands:** `/build-fleet:new-product`, `/build-fleet:plan-review`,
  `/build-fleet:plan-finalize`, `/build-fleet:next-feature`, `/build-fleet:product-memory`.
- **New hook:** `hooks/scripts/validate-backlog-status.sh` (validates backlog.md edits).
- **Scribe `workspace_dir` (M3.0)** — workflow state mutations can now target either
  `.sdd/<feature>/` or `.sdd/_product/`.

### Fixed

- **Hooks resolve `.sdd` paths under a symlinked cwd.**
- **Product-stack inheritance keystone hardened (M0)** — brownfield forward stack is
  `PROVISIONAL`, the observed baseline binds.
- **Skill-routing precision + dispatch parity (M1).**

## [0.2.1] — 2026-05-30

### Fixed

- **Stop-hook deadlock at SPEC phase.** `hooks/scripts/stop-tests.sh` ran the
  test suite in every phase and treated `pytest` exit code 5 ("no tests
  collected") as a failure. Pre-BUILD there are no tests yet — and the
  `block-source-before-finalized` gate makes it impossible to write any — so the
  session could neither stop nor pass. The hook now (a) only enforces the suite
  in `BUILD | CHANGE_REVIEW | HANDOFF`, and (b) tolerates `pytest` exit 5 as a
  non-failure. Surfaced by the first real install dogfood (bf-smoke).
- **`new-feature` classified from the bare slug.** With no description in
  conversation context, the command let the classifier infer requirements from
  the slug name alone, producing a hallucinated spec. New step 5 ("Establish the
  feature description") stops and asks the user what the feature should do when
  no description exists in context; subsequent steps renumbered.

## [0.2.0] — 2026-05-30

### Added

- **Dynamic workflow for REVIEW phase** (M1). `workflows/review.js` runs 5 phases: read state → fan-out reviewers (architect/qa/coder) → adversarial cross-examination → survival vote → scribe applies state delta. Replaces the v0.1 parallel-Task fan-out + cycle-3 agent-teams fallback.
- **`workflows/deep-build.js` for fan-out BUILD** (M3). Architect plans a file partition; up to 8 coders fan out in parallel; in-workflow adversarial review (architect + qa) catches integration gaps before BUILD declares complete. Partition overlap detection prevents concurrent coders from racing on shared files.
- **Three-tier M4 routing.** New `agents/classifier.md` (read-only subagent emitting JSON verdicts) + new `commands/dispatch.md` (query-only classifier wrapper). `/build-fleet:new-feature` now invokes the classifier and writes `TIER` + `BUILD_MODE` to PROGRESS.md. Trivial features skip REVIEW; large features get `BUILD_MODE=deep-build` for automatic routing through finalize.
- **`agents/scribe.md` subagent** — write-only state applier; the canonical writer of workflow-driven `.sdd/` state mutations (workflows can't touch the filesystem directly).
- **Headless mode first-class.** Every command emits `BUILD_FLEET_*:` JSON-line signals before any human-readable prose. New signals: `BUILD_FLEET_REFUSE`, `BUILD_FLEET_CLASSIFICATION`, `BUILD_FLEET_CLASSIFIER_FALLBACK`, `BUILD_FLEET_COST_PREVIEW`, `BUILD_FLEET_WORKFLOW_LAUNCHED`, `BUILD_FLEET_FINALIZE_PASS/REFUSE`, `BUILD_FLEET_FINALIZE_TRIVIAL_FAST_PATH`, `BUILD_FLEET_BUILD_ROUTE`, `BUILD_FLEET_QA_TESTS_READY`, `BUILD_FLEET_QA_VERIFY_FAIL`, `BUILD_FLEET_CODER_REFUSE`, `BUILD_FLEET_BUILD_COMPLETE/INCOMPLETE/DISPATCH_FAIL`.
- **Tests-first BUILD ordering** (M2). `/build-fleet:finalize` now sequences qa-first then coder for `BUILD_MODE=standard`. coder refuses to begin until QA's failing tests exist (emits `BUILD_FLEET_CODER_REFUSE:` machine-readable). CHANGE_REVIEW adds the M2 counterfactual gate ("would each test fail without coder's source change?").
- **`hooks/scripts/reap-stale-workflow-markers.sh`** — Stop hook that removes `.workflow-in-flight` markers older than 1 hour (handles orphan markers from failed workflow launches; preserves safety property of per-reviewer hooks).
- **PROGRESS.md schema fields:** `TIER` (M4: `trivial | standard | large | pending`), `BUILD_MODE` (M3+M4: `standard | deep-build | pending`).
- **`docs/v0.2/CONTROLS.md`** — M0 gate-vs-judgment control inventory.
- **`docs/v0.2/CONTRACT.md`** — workflow ↔ command-layer contract, grounded against `@anthropic-ai/claude-agent-sdk@0.3.158`. Reproduces `WorkflowInput`/`WorkflowOutput` schemas verbatim from SDK type definitions.
- **`ROADMAP.md`** — v0.2 milestones + v0.3 forecast (orchestrator-mediated human intervention via Hermes).

### Changed

- **`hooks/scripts/check-review-written.sh` and `restrict-reviewer-writes.sh`** add a `.sdd/<slug>/.workflow-in-flight` marker bypass. The hooks skip while a workflow is running (workflow's envelope post-condition replaces them for workflow paths); they still fire on non-workflow review paths (CHANGE_REVIEW via `/build-fleet:handoff`).
- **CYCLE semantics:** v0.2 cycles count workflow runs (not command invocations). Cross-examination rounds inside one workflow run do NOT bump CYCLE.
- **Severity rubric (review-rubric skill) preloaded into workflow reviewer subagents** via `AgentDefinition.skills: ["review-rubric"]` instead of v0.1's duplication into agent prompt bodies.
- **`commands/finalize.md` is now a gate AND orchestrator** for the BUILD sequence (M2 sequential or M3 deep-build, routed on BUILD_MODE; M4 trivial fast-path skips review-cycle gate but still honors ESCALATION.md).
- **`agents/scribe.md`** also writes IMPL_NOTES.md when envelope has `impl_notes_appendix` (used by deep-build workflow). Tight constraint: scribe only writes files whose corresponding envelope field is present and non-empty.
- **Signal rename: `QA_TESTS_READY:` → `BUILD_FLEET_QA_TESTS_READY:`** for namespace consistency with the rest of the `BUILD_FLEET_*` family.
- **`.claude-plugin/plugin.json`** version bumped to `0.2.0`.

### Deprecated

- **`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` env var** — no longer needed. The cycle-3 agent-teams fallback in `/build-fleet:review` is gone; workflow cross-examination replaces it. The README section that asked for this env var has been removed.

### Decisions deferred to a future version

- **`hooks/scripts/restrict-reviewer-writes.sh` is retained** despite the v0.2 plan's (`docs/history/V0.2-PLAN.md`) "retire entirely" guidance. CHANGE_REVIEW (`/build-fleet:handoff`) is still v0.1-style and depends on the hook for its reviewer-write-boundary enforcement. The hook will be retired when CHANGE_REVIEW becomes a workflow.
- **`check-review-written.sh` is similarly retained** for the same non-workflow CHANGE_REVIEW path.
- Several **VERIFY-AT-M1 markers** remain in `workflows/review.js` and `workflows/deep-build.js` — runtime-global signature assumptions (`agent()`, `parallel()`, `phase()`) that will be confirmed against a real `/deep-research` raw script at first dispatch.

### Notes for v0.2 users

- **Requires Claude Code v2.1.154 or later** with dynamic workflows enabled (`/config` → "Dynamic workflows" on Pro plans). Hard requirement; no v0.1 fallback if workflows are unavailable.
- **Headless callers** (`claude -p`, Agent SDK / Hermes) must include `Workflow` in `--allowedTools`. The orchestrator is responsible for human approval between workflow runs (no mid-workflow gates in v0.2; that's v0.3's scope).
- The `BUILD_FLEET_*:` signal grammar is documented in `README.md`; the full contract is in `docs/v0.2/CONTRACT.md` § 8.

## [0.1.0] — 2026-05-30

Initial release. Five role subagents (product-owner, architect, coder, qa, devops) executing the deterministic SPEC → REVIEW → FINALIZE → BUILD → CHANGE_REVIEW → HANDOFF state machine. Five hooks enforce gate boundaries: `block-source-before-finalized`, `restrict-reviewer-writes`, `validate-spec-status`, `check-review-written`, `stop-tests`. Five skills (sdd-protocol, sdd-spec-template, adr, review-rubric, test-plan), five commands (new-feature, review, finalize, handoff, status). Bounded review cycles (≤3 then ESCALATE); first-class human escalation.

Validated end-to-end via the a–g dry-run matrix on 2026-05-30.
