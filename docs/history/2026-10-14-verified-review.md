# Verified review — design

**Date:** 2026-10-14
**Status:** draft for review (design approved section by section in brainstorming); amended after three independent Gemini reviews (§9); implementation plan follows approval
**Ships as:** part of build-fleet v0.12.0, with the gate event log (Part A of
`2026-10-14-dashboard.md`), which the quote check records into.
**Supersedes:** nothing. Adds a second spec-review shape, `verified`, beside today's
`debate`. The default stays `debate` until the 0.12 measurement decides.
**Scope:** spec review (`workflows/review.js`, `/build-fleet:review`, the finalize gate)
only. Change review, `diagnose.js` and `plan-review.js` adopt the protocol only after the
measurement shows it wins.
**Evidence:** roadmap review sections 1 and 5 (https://claude.ai/artifact/RjjQEmAJ6woyP1aGQXdK4j);
`workflows/review.js` as of v0.10.1; the deep-research verification pattern (independent
judges, 2 of 3 refutations to kill a claim).

## 1. Problem

build-fleet's positioning rests on a spec review no other SDD tool has. The review already
runs isolated lenses and a citation-backed vote, but three mechanics undo it:

| Today (`review.js`, v0.10.1) | Why it fails |
|---|---|
| `applySurvivalVote` takes `refs[0]`: one valid refutation kills a finding. | A veto, not a vote. One reviewer can drop a real defect. |
| `validCitation` passes any non-empty `{file, locator}` strings, e.g. `"§ Constraints"`. | Nothing checks the cited text exists or says what the refutation claims. |
| The refuters are the other lens reviewers. | They have a stake in their own findings and their own lens. |
| A finding is free text. | Nothing could prove it wrong. |
| Severity is set once, by the reviewer who raised it. | Over-reporting survives. |

The research separates debate (agents reading each other's arguments; consensus drift)
from verification (independent judges, majority vote, verdicts grounded in outside
evidence). The fixes below move the review fully onto the verification side.

## 2. Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Spec review only** in 0.12. | That is what arm 4 measures; a losing protocol never spreads. |
| D2 | **A selectable shape**, `REVIEW_SHAPE: debate \| verified`, default `debate`. | The measurement runs both shapes on the same frozen spec; nothing changes for anyone who doesn't opt in. |
| D3 | **A panel of 3 fresh verifiers**, each judging every finding independently. Optional: blockers get their own per-finding panel. | Meets the research's main condition, judges who never see each other, at about today's agent count. Per-finding panels for everything would scale cost with finding count. |
| D4 | **Findings must be checkable:** an anchor (verbatim quote, or a named absence) and a test that would fail, required by the lens schema for blockers and majors. A finding that still lacks them is demoted to minor, visibly. | Makes the rubric's existing rule, a major only if a test could fail, mechanical. |
| D5 | **Kill on ≥ 2 valid refutations.** | A vote, not a veto. |
| D6 | **Severity can be lowered by the panel, never raised, and lowering needs the same evidence as a refutation.** | Corrects over-reporting without a new escalation loop, and without a quote-free back door around D5. |
| D7 | **Quotes are checked by a PostToolUse hook on the scribe's final write**, the release of `.workflow-in-flight`, and the result is recorded as an event. | The workflow runtime has no filesystem, and `/review` returns before the workflow finishes, so no command is present at apply time. The marker release is the scribe's last action, after REVIEW.md and DECISIONS.md are complete, and before anyone can revise the spec. |
| D8 | **The finalize gate is the authority** for the verified shape: it recomputes the vote from recorded verdicts and the quote-check event. | The deterministic layer decides; the workflow's answer is provisional. |
| D9 | **Reuse the read-only `reviewer` agent** in a verify mode. | No ninth agent, no new tool allowlist. |
| D10 | **Open findings carry forward, in writing.** Every open finding of a verified cycle is written into the next cycle's block: closed with a confirmed closure, or re-listed by `review.js` with a `carried:` line (its original record, whether or not its reviewer re-listed it). A finding whose raiser left the roster is written in the first roster role's block. | Delta reviewers, the gate and rotation all look only at the latest cycles; a finding that is only implied would vanish once rotation archives the cycle that raised it. |

## 3. Design

### 3.1 The finding grammar (lens reviewers, verified shape)

| Field | Required for | Contents |
|---|---|---|
| `id` | all | `<role>-c<cycle>-<n>`, as today |
| `severity` | all | `blocker` · `major` · `minor` |
| `text` | all | the claim, one sentence (same field name as today) |
| `anchor` | blocker, major | `{"kind":"quote","file":F,"text":T}` with `F` ∈ `spec.md`, `acceptance.md`, `DECISIONS.md`, `_product/DECISIONS.md` and `T` 10–500 characters copied verbatim; **or** `{"kind":"absent","file":F,"section":S,"missing":M}` |
| `ref` | optional | list of `§<Section>`, `AC-<n>`, `ADR-<n>` |
| `test` | blocker, major | one sentence: a test that would fail if the finding is real |

In the verified shape the lens schema **requires** `anchor` and `test` on every blocker and
major, so a reviewer cannot omit them. As a fallback (an empty `test`, or an `anchor` with an
empty `text`), the script **demotes** the finding to minor, logs it, and the scribe writes a
visible `demoted:` line under it. Minors are never verified. (A demotion caused later by a
failed anchor quote cannot be written into the block, which already exists; it is shown by
the quote-check event, `/status`, the gate report and the dashboard, and in the next cycle's
carried entry.)

The lens prompt gains this grammar in the verified shape only. The `LENS` text injected
from each role agent is unchanged, so `scripts/lens-drift.test.sh` keeps passing.

### 3.2 REVIEW.md, verified shape

Today's block grammar stays; new continuation lines are added. Machine-read lines are
single-line JSON, parsed with jq (quotes may contain any character).

```
## Cycle 1 — qa — 2026-10-20T09:12:03Z
shape: verified
- [major] (qa-c1-2) Retry limit for failed uploads is unspecified
  quote: {"file":"spec.md","text":"the client retries failed uploads"}
  ref: §Behavior, AC-3
  test: an upload against a server that always returns 500 stops within a bounded number of attempts
  verdict: {"v":1,"vote":"uphold","severity":"major"}
  verdict: {"v":2,"vote":"refute","severity":"minor","reason":"…","quote":{"file":"spec.md","text":"Retries are capped at 3 attempts"}}
  verdict: {"v":3,"vote":"uphold","severity":"major"}
  verified: upheld 2/3, severity major
  disposition: fix
status: concerns-raised
```

- `absent:` replaces `quote:` for an absence anchor:
  `absent: {"file":"spec.md","section":"Behavior","missing":"a retry cap"}`.
- `shape: verified` is the second line of every verified block; the gate keys on it (§3.5).
- Every quote, anywhere, has the one shape `{"file":…,"text":…}`: in `quote:` and `closure:`
  lines it is the whole value; in a `verdict:` line it is the `quote` member.
- A verdict may carry `"test_invalid":true` (§3.3).
- `demoted: {"reason":"no-anchor"|"no-test"|"test-invalid"}` records a demotion the workflow
  decided. Demotions from a failed quote are recorded in the quote-check event (§3.4).
- `carried: {"from_cycle":N,"reason":"not-addressed"|"re-listed"}` marks a finding `review.js`
  carried into a delta cycle (D10): its reviewer left it out (`not-addressed`) or re-listed it
  (`re-listed`; the reviewer's copy is replaced by the record). `N` is the cycle it was first
  carried from. It keeps its original `quote:`,
  `ref:` and `test:` lines and gets no new verdicts. Its `disposition:` line is never copied:
  like every re-listed finding, it goes through this cycle's disposition leg (§3.3).
- `verified:` is a human summary; every parser ignores it and recomputes.
- Delta-cycle closure claims re-list the finding with its original id and add
  `closure: {"file":"spec.md","text":"…"}`, followed by the panel's `verdict:` lines with
  `"vote":"confirm"` or `"vote":"reject"`.
- `refuted-by:` is not used in the verified shape. The debate shape keeps it unchanged.
- Minors are written as today, with `quote:`/`ref:`/`test:` lines only if the reviewer gave
  them.

### 3.3 The verifier panel

**Agent.** `agents/reviewer.md` (Read, Grep, Glob; sonnet), dispatched with a verification
prompt. The panel runs after the fan-out barrier; its 3 members run in parallel.

**Input per verifier.** It reads `spec.md`, `acceptance.md` and `DECISIONS.md` itself, and
receives the blocker and major findings as `{id, severity, text, anchor, ref, test}`, and in
a delta cycle the closure claims as `{id, text, closure}`.
It does **not** receive `raised_by`, the reviewer's reasoning, or other verifiers' output.
Verifier `k` (0-based) receives the list rotated left by `k` positions, so no finding is
always judged first; rotation is deterministic because the runtime provides no randomness.

**Output schema** (`VERIFICATION_SCHEMA`), one entry per finding:

| Field | Values |
|---|---|
| `id` | finding id |
| `vote` | `uphold` · `refute` (delta closures: `confirm` · `reject`) |
| `severity` | `blocker` · `major` · `minor` |
| `reason` | string |
| `quote` | `{file, text}` — **required** with `refute`, and with any `severity` below the finding's own; optional otherwise |
| `test_invalid` | optional boolean, with a reason: the named test is vacuous or could not exercise the claim |

**Instruction.** Refute only when the spec as written already answers the claim, and quote
the text that answers it. A test that is vacuous or could not exercise the claim is not a
refutation: set `test_invalid` with a reason. To vote a lower severity, quote the text that
makes the finding less serious. When unsure, uphold at the finding's own severity.

**The vote** (`applyVerifiedVote`, pure JS):
- A refutation is **valid** when it carries a quote with a non-empty `file` and `text` and a
  `reason` of at least 40 characters. Whether the quote is real is checked in §3.4.
- A finding is **killed** when it has **≥ 2 valid refutations**.
- A surviving finding's **severity** is the median of the returned severity votes, **capped
  at the reviewer's original severity**. A vote **below** the original counts only if it
  carries a quote and a reason of at least 40 characters (and, at the gate, the quote passed
  §3.4); otherwise it counts as the original severity. With an even number of votes, the
  median is the higher of the two middle values. A finding lowered to minor stops blocking and
  needs no disposition.
- A majority of verifiers setting `test_invalid` demotes the finding to minor
  (`demoted: test-invalid`), the same mechanical rule as a missing test.
- **Panel failures:** with 2 verifiers returned, a kill needs both. With fewer than 2, the run
  ends `incomplete` with `reason: verifier-panel` and writes no review state (the scribe only
  releases the marker), the same handling as `disposition-incomplete`.

**Delta cycles (cycle ≥ 2).** `/review` passes the previous verified cycle's **open set** as
the `carried` arg: full finding objects `{id, raised_by, severity, text, anchor, ref, test,
disposition?}` for every open blocker, `fix` major and revived finding, read from
`finalize-gate.sh --report`. Each reviewer's prompt lists the carried findings it raised.
For each, it either leaves it out (it stays open), or claims closure
with a `closure` quote of the revised spec text. The panel votes `confirm`/`reject` on each
closure; a closure holds when a majority confirms (and, at the gate, its quote passes §3.4).
A rejected closure keeps the finding open. After the fan-out, `review.js` writes every
carried finding not claimed closed as its original record with a `carried:` line, including
one its reviewer re-listed anyway (so re-listing can never demote, re-verify or drop it);
carried findings are not re-verified. A carried finding whose raiser is no longer in the
roster is written in the first roster role's block and can be closed only by its raiser. New blockers raised in a delta cycle are verified like
any new finding.

**What reaches disposition and `finalize_ready`.** Findings whose closure holds are removed
from `surviving` before the disposition leg and before `finalize_ready` is computed. Re-listed
and carried findings stay in `surviving` and go through the disposition leg as re-raised
findings do today. The delta rule is otherwise unchanged.

**Settings.**

| Setting | PROGRESS.md field | `/review` flag | Default |
|---|---|---|---|
| shape | `REVIEW_SHAPE` | `--shape debate\|verified` | `debate` |
| panel model | `VERIFIER_MODEL` | `--verifier-model opus\|sonnet\|haiku` | `sonnet` |
| per-blocker panels | `VERIFY_BLOCKERS_SOLO` | `--verify-blockers-solo` | `false` |

As with `REVIEW_ROLES`, `/review` passes `shape`, `verifier_model` and
`verify_blockers_solo` as workflow args only when set, and `review.js` validates them
through its `invalid-args` path. With `VERIFY_BLOCKERS_SOLO: true`, each blocker gets its
own panel of 3 that sees only that finding; majors stay on the shared panel. Many blockers
mean many agents; measurement runs pass `--override-cost`, and the cost ceiling is
recalibrated after 0.12 (§3.6). A non-Claude
verifier is not possible inside the workflow runtime; the cross-vendor comparison stays in
the measurement's arm 3.

### 3.4 The quote check

**`scripts/quote-check.sh <slug> --cycle N`** is run by a new PostToolUse hook,
`hooks/scripts/check-review-quotes.sh`, matched on a Write of `.sdd/<slug>/.workflow-in-flight`
with empty content: the scribe's release of the marker, which is its **final** action, after
every REVIEW.md block and every DECISIONS.md append has landed. The check therefore runs once
per apply, against the spec exactly as reviewed. `/review` cannot do this: it launches the
workflow asynchronously and returns at once. A hook on REVIEW.md itself would fire after each
role's block (the scribe appends one `Edit` per block) and see a partial cycle.

The hook runs the check only when the newest cycle block in REVIEW.md is for PROGRESS.md's
current `CYCLE` and carries `shape: verified`; otherwise it does nothing (an `incomplete` run,
another workflow's marker release, or `/review`'s own release of a dead run's marker). **The
first event for a cycle wins:** the hook does nothing when `EVENTS.jsonl` already holds a
quote-check event for that cycle. An `incomplete` run leaves `CYCLE` and REVIEW.md unchanged,
so its marker release would otherwise re-check the previous cycle against a spec revised
since, and overwrite a correct result. The script is bash 3.2 and GNU compatible, anchors at the project root,
requires jq, and rejects `..`.

- It collects every quote in cycle N's verified blocks: finding anchors (`quote:`),
  refutation quotes (`verdict:` with `quote`), and closure quotes (`closure:`).
- The file must be `spec.md`, `acceptance.md` or `DECISIONS.md` in `.sdd/<slug>/`, or the
  product `.sdd/_product/DECISIONS.md` (reviewers are told to cite product ADRs). Anything
  else fails the quote.
- **Normalization**, applied to both the quote and the file before an exact substring match:
  collapse every run of whitespace (including newlines) to one space; map curly quotes to
  straight and en/em dashes to `-`; remove `*`, `_` and backticks. Matching is
  case-sensitive.
- A quote must be 10–500 characters after normalization. There is no ellipsis rule: an
  elided quote already fails the exact match, and a spec's own `...` matches normally.
- `absent:` anchors are checked only for their `section`: a heading with that text must exist
  in the named file.
- It appends **one `gate` event** to `.sdd/<slug>/EVENTS.jsonl`:
  `source: script:quote-check`, `decision: pass|fail`, `cycle: N`; `files`: for `spec.md`
  the sha256 **without its `STATUS:` line** (finalize rewrites it), for `acceptance.md` the
  sha256, and for each `DECISIONS.md` its byte length and the sha256 of that many bytes
  (DECISIONS files are append-only, so the gate checks the prefix); `checked` (count);
  `failures`, each `{id, where: "anchor"|"verdict"|"closure", v?}`; `revived`, the ids
  **reopened** once failed quotes are removed (a kill that no longer holds, a lowered severity
  restored, or a closure that failed); and `exempt`, true when `revived` is non-empty.
- It prints `BUILD_FLEET_QUOTE_CHECK: {"slug":…,"cycle":N,"checked":…,"failed":…}`.

**Effect of a failed quote:**

| Failed quote | Effect |
|---|---|
| finding anchor | the finding is demoted to minor (`anchor-quote-failed`, applied by the gate) |
| refutation, or a lower-severity vote | that vote is invalid; the vote is recomputed; a finding whose kill drops below 2 valid refutations revives as open, and a lowered severity is restored; both are listed in `revived`, and the event is `exempt`. The finding carries forward (D10): the gate counts it open, `/revise` hands it to the PO, and the next cycle's block carries it. |
| closure | the closure is invalid; the finding stays open, is listed in `revived` (reported as `reopened-closure`), and the event is `exempt` |

**On the budget-exhausting cycle.** A finding reopened by the quote check was judged on false
evidence, so its cycle did not really settle it. A cycle whose quote-check event is `exempt`
**does not count against `REVIEW_CYCLE_BUDGET`**, whoever wrote the failed quote. Without
this, the exhausting cycle can deadlock: the workflow reports clean and writes no
ESCALATION.md, the gate refuses, `/review`'s budget precondition refuses, and
`/resolve-escalation` has nothing to resolve. A fabricated closure gains its author nothing,
the event records whose quote failed, and the total stays bounded (below).
`/review` counts the exempt cycles of the current review phase and passes `exempt_cycles`;
both `/review`'s own budget precondition and `review.js` use **budget + exempt_cycles** as the
effective budget (`review.js` adds it after the `MAX_CYCLE_BUDGET` clamp, so `decideVerdict`
does not escalate the extra cycle). `CYCLE_TOTAL_MAX` still applies, so the extension is
bounded, and reaching it escalates as today. No command writes state outside the workflow.

**Stated limit.** The check catches invented quotes. It does not catch a real quote used to
argue a wrong point; the majority vote is the defense against that. `docs` and
`sdd-protocol` say so.

### 3.5 Authority: the finalize gate

`scripts/finalize-gate.sh` detects the shape **per cycle block**: a block whose second line
is `shape: verified` is verified; any other block is parsed exactly as today. Mixed files (a
feature that changed shape mid-way, or a REVIEW.md from before 0.12) parse correctly.

For verified blocks the gate:
1. parses `quote:`/`absent:`/`verdict:`/`closure:` lines with jq; a malformed JSON line
   counts as an invalid verdict (it can never kill);
2. applies the cycle's quote-check event (the first, §3.4); **no event for a verified cycle ⇒
   refuse with `quote-check-missing`**; and **at finalize only**, if `spec.md` (without its
   `STATUS:` line) or `acceptance.md` no longer matches the event, or a `DECISIONS.md` prefix
   changed ⇒ refuse with `spec-changed-since-review`. `--report` never refuses on this: it
   reports `spec_changed: true` and still returns the open set, which `/review` and
   `/revise` read after a legitimate revision;
3. recomputes demotions, kills, severities and closures with the §3.3 rules; a re-listed
   finding whose closure holds is **closed**, and is not counted under step 4;
4. counts every entry with a `carried:` line as open, and, as a safety net for D10, counts
   any finding open at the end of the previous verified cycle that the current cycle neither
   lists nor closes as open, reason `carried-open`;
5. applies today's rule: no open blockers; no majors dispositioned `fix` or undispositioned.

Added after the final code review (2026-10-14): the gate reads the current cycle's verified
blocks by heading, not by roster (a role added with `--roles` still counts); it counts one
verdict per verifier per finding (a repeated line keeps its first); it refuses
`review-changed-since-check` when the cycle's verified blocks differ from what the quote check
hashed (`blocks_sha256` in the event); and it refuses `verified-eval-failed` rather than read a
failed evaluation as "no open findings".

`review.js` still returns `finalize_ready`; for the verified shape it is provisional, and
`/build-fleet:status` and `/build-fleet:finalize` show the gate's answer (`--report`,
dashboard spec §3.4) once the quote check has run.
When every quote passes, the two agree by construction: `review.js` applies the same rules, including carry-forward from its `carried` arg (tested in §5).

### 3.6 `review.js` and the commands

```
Fan-out review ──┬─ debate:   Cross-examination → Survival vote ──┐
                 └─ verified: Verification panel → Vote ──────────┴→ Disposition → Apply
```

- `meta.phases` is a pure literal and lists both branches; a run enters only its own.
- The disposition leg receives surviving majors at their final severity.
- Escalation is unchanged: the budget-exhausting cycle with open blockers or `fix` majors
  writes `ESCALATION.md`.
- `@cost-ceiling` stays at its current value until 0.12 measures the verified shape; it is
  then set to the larger of the two shapes.
- `commands/review.md`: resolves the three settings and passes them through. **Only when the
  previous cycle is verified**, it also passes `carried` (the open set from
  `finalize-gate.sh --report`) and `exempt_cycles` (from the phase's quote-check events), and
  applies budget + `exempt_cycles` in its own budget precondition, reading the open set for
  that precondition from `--report` rather than scanning for `disposition: fix`. `finalize-gate.sh` is added
  to its allowed tools. It never writes state. For a debate-shape feature neither arg is
  passed. The no-workflow fallback path always runs `debate` and says so.
- `commands/revise.md` gains `Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/finalize-gate.sh":*)`.
  For a verified cycle it hands the PO the open set from `finalize-gate.sh --report` (which
  includes revived and carried findings) instead of scanning for `refuted-by:`; for a debate
  cycle it is unchanged. `commands/finalize.md` is unchanged: it runs the gate.
- `hooks/hooks.json` registers `check-review-quotes.sh` under PostToolUse `Write` (the only
  registration point); the script itself filters for the marker path and empty content.
- **Depends on Part A of the dashboard spec**, which ships in the same release: the event log
  (`EVENTS.jsonl`, `log_event`) and `finalize-gate.sh --report`.
- `scripts/status-snapshot.sh` and `/build-fleet:status` show `review_shape` and, for a
  verified cycle, a summary: raised, upheld, refuted, quotes failed. Additive to
  `status-snapshot@1`.

**Unchanged:** `change-review-gate.sh`, `check-review-written.sh` (no-workflow path only),
`review-rotate.sh` (moves whole blocks; a test confirms it carries the new lines). The
scribe writes what the envelope gives it, including the `shape:` and `demoted:` lines; its
body is unchanged.

**An assumption the plan must verify first:** plugin PostToolUse hooks fire for tool calls
made by subagents inside a workflow run (the scribe's marker release). The dashboard spec's `record-phase.sh`
rests on the same assumption. If it fails, the fallback is the gate refusing
`quote-check-missing`, and the design must move the check before this ships.

Verified 2026-10-14 (Claude Code 2.1.299): a plugin PostToolUse(Write)
hook received the workflow subagent's empty Write of `.workflow-in-flight`.

### 3.7 Agents and skills

- `skills/review-rubric/SKILL.md` and its mirrors in `agents/architect.md`, `agents/qa.md`,
  `agents/reviewer.md` gain a **Verified review** subsection: in the verified shape a
  blocker or major needs an anchor and a test, otherwise it is a minor.
  `scripts/rubric-drift.test.sh` keeps the four copies identical.
- `agents/reviewer.md` gains its verify mode (input, output, instruction from §3.3).
  Its description changes; so do architect's and qa's (mirrored body text).
- `skills/sdd-protocol/SKILL.md` documents the shape, the grammar, the vote, the quote
  check and the stated limit; the REVIEW.md format block gains the verified example.

## 4. Compatibility and release

- Ships in 0.12.0 with the event log; the quote check depends on it.
- With `REVIEW_SHAPE` unset nothing changes: same workflow path, same REVIEW.md, same gate
  behaviour. `SDD_SCHEMA` stays `1` (new continuation lines only).
- CHANGELOG Compatibility line: opt-in; existing REVIEW.md files parse unchanged.
- Release checklist: version, marketplace, CHANGELOG, README (scripts +1
  `quote-check.sh`; hook scripts +1 `check-review-quotes.sh`), the reviewer, architect and qa
  descriptions, `sdd-protocol`, `commands/review.md` argument hint and allowed tools,
  `commands/revise.md`.
- The parked dashboard spec gets one revision to read `verdict:` lines and quote-check
  events for its finding cards, funnel and spec heat map.

## 5. Testing

**`review.js` pure functions** (existing `workflow-review-*.test.sh` style), plus
`node --check workflows/*.js` and `workflow-determinism-lint.sh`:
- 2 valid refutations kill; 1 does not; a refutation without a quote or with a reason under
  40 characters is ignored.
- 2 verifiers returned ⇒ a kill needs both; fewer than 2 ⇒ `incomplete` / `verifier-panel`,
  nothing written.
- Severity: median, capped at the original; never raised; a lower vote without a quote and
  reason counts as the original; an even count takes the higher middle value.
- `test_invalid` majority demotes; a minority does not.
- Demotion of a blocker/major without anchor or test.
- Rotation by verifier index is deterministic.
- Delta: closure confirm/reject; verifiers receive the closure quote; carried findings appear
  in each raiser's prompt; a carried finding the reviewer omits is re-listed with `carried:`;
  closed findings are excluded from disposition and `finalize_ready`; new blockers verified.
- Budget: with `exempt_cycles: 1` and budget 3, cycle 4 does not escalate unless findings
  stay open after it; `exempt_cycles` is added after the clamp.
- Lens and verification schemas accept good and reject bad payloads.
- Args: `shape`, `verifier_model`, `verify_blockers_solo`, `carried`, `exempt_cycles`
  validated; bad values ⇒ `invalid-args`; absent ⇒ today's behaviour.
- Lens schema rejects a blocker or major without `anchor` or `test`; the fallback writes
  `demoted:`.

**`quote-check.sh` harness** (mktemp):
- Normalization: whitespace and newlines, curly quotes, dashes, markdown markers; case kept.
- Bounds 10–500; a spec's own `...` matches; an elided quote fails.
- File allowlist, including `.sdd/_product/DECISIONS.md`; `..` and other files refused;
  `absent:` passes only when the named section heading exists.
- One event per cycle, with `spec.md` hashed without `STATUS:`, `acceptance.md` hashed,
  DECISIONS prefixes, failures, `revived` and `exempt`; a failed closure is in `revived` and
  makes the event `exempt`; a failed anchor alone does not; a second run for a cycle that
  already has an event writes nothing (first event wins); signal line printed.

**`check-review-quotes.sh` hook harness:** fires on an empty Write of `.workflow-in-flight`
when the newest REVIEW.md block is the current cycle and verified; does nothing on a REVIEW.md
write, a non-empty marker write, a debate block, a stale cycle or another file; never changes
the write's outcome.

**`finalize-gate.sh` harness** (failing case first for each):
- Vote recomputed from `verdict:` lines; malformed line ⇒ invalid verdict.
- Failed refutation quote revives a finding ⇒ refuse.
- Failed anchor quote demotes.
- Verified block with no quote-check event ⇒ `quote-check-missing`.
- A failed lower-severity quote restores the original severity.
- A re-listed finding with a confirmed, quote-checked closure is closed (not `majors-open`).
- Carry-forward: a `carried:` entry is open; a finding open in cycle N and absent from N+1
  is `carried-open`; a revived id from N's event is open in N+1 until closed; after rotation
  archives cycle N, a carried finding is still found in N+1's block.
- `spec-changed-since-review` at finalize: an edit to `spec.md` or `acceptance.md`, or to an
  existing line of `DECISIONS.md`, refuses; the `STATUS:` flip and an ADR append do not;
  `--report` reports `spec_changed` and still returns the open set.
- Hook on an `incomplete` run's marker release does not overwrite the previous cycle's event.
- Exhausting cycle with a failed closure quote: `/review` grants the exempt cycle instead of
  refusing `cycle-budget-exhausted`.
- `/revise` with a verified cycle hands the PO the report's open set, including revived and
  carried findings; a debate cycle is handled as today.
- Shape is detected only from `shape: verified`; a debate line containing the word
  "verdict:" stays debate.
- Mixed debate/verified blocks parse.
- Every existing debate-shape case passes unchanged.

**Also:** `review-rotate.sh` carries the new lines; `rubric-drift` and `lens-drift` pass;
the smoke test runs a fixture verified REVIEW.md (no model) through the hook,
`quote-check.sh` and `finalize-gate.sh`; `/review` grants one extra cycle when the previous
event is `exempt`, and not beyond `CYCLE_TOTAL_MAX`.

**Once, live:** one real verified review on a scratch feature before the measurement
(watch for verifiers paraphrasing instead of quoting).

## 6. What the measurement needs from this protocol

The measurement protocol is its own document, like 0.10's MEASUREMENT file. This design
guarantees:
- **Control:** `--shape`, `--verifier-model`, `--verify-blockers-solo`, so one frozen spec
  copy is reviewed by every arm.
- **Numbers per run:** output tokens (the workflow's return) and wall time (event log).
- **Inspectability:** every finding, verdict and quote result is recorded in REVIEW.md and
  EVENTS.jsonl, so results are judged without re-running anything.

Recommendation for that document: **plant known defects** in a copy of a real spec, so each
arm's recall is measured against an answer key; a human, blind to the arm, judges the
remaining findings. This fixes the 0.10 measurement's lack of ground truth.

## 7. Success criteria

- When every quote passes, the gate's recomputed result equals `review.js`'s provisional
  `finalize_ready`.
- No finding is killed, or lowered below its severity, without quoted evidence that passed
  the check (2 valid refutations to kill).
- No open finding disappears between cycles without a confirmed closure.
- No invented quote is accepted (fixture-tested).
- With `REVIEW_SHAPE` unset, the existing suite passes unchanged.

## 8. Out of scope

- Change review, `diagnose.js`, `plan-review.js` (after the measurement).
- Making `verified` the default (a later release, if arm 4 wins).
- Non-Claude verifiers inside the workflow.
- Detecting a real quote used for a wrong argument.
- The measurement protocol itself.

## 9. Independent review (Gemini 3.8 Flash, 2026-10-14)

Reconciled against the code; amendments applied in this revision.

| Finding | Outcome |
|---|---|
| `/review` is async and cannot run the quote check or dispatch the scribe | Confirmed. The check moved to a PostToolUse hook (D7, §3.4); the exhausting-cycle case became a bounded budget exemption. |
| A revived major vanishes at the next cycle | Confirmed (delta prompt and gate read only the latest cycle). Carry-forward rule (D10, §3.5). |
| Confirmed closures counted as open majors | Confirmed. Closure rule in §3.5 step 3. |
| Severity votes bypass the 2-refutation kill | Confirmed. Lowering needs quoted evidence (D6, §3.3). |
| "Test could not fail" refutation cannot carry a quote | Confirmed. Replaced by `test_invalid` (§3.3). |
| Verdict JSON in two shapes | Confirmed. One quote shape (§3.2). |
| `claim` vs `text` field | Confirmed. Field stays `text` (§3.1). |
| Product ADRs excluded from the allowlist | Confirmed. Added (§3.4). |
| Quote bounds and ellipsis ban too rigid | Partly. Bounds 10–500; ellipsis rule dropped. |
| Median of two votes undefined | Confirmed. Higher middle value. |
| Shape detection by `verdict:` substring | Partly (an anchored match would not misfire); explicit `shape: verified` line. |
| `absent:` anchors unchecked | Partly (the panel can still refute). Section heading now checked. |
| Per-blocker panels may trip the cost guard | Plausible, unshown. Noted (§3.3). |
| Demoting unanchored blockers is dangerous | Kept: fields are now schema-required, so demotion is a visible fallback. |
| A same-model panel shares blind spots | Kept: measured by arms 3 and 4b. |

### Second review (Gemini 3.8 Flash, 2026-10-14)

Nine first-round fixes confirmed sound. New findings, reconciled against the code:

| Finding | Outcome |
|---|---|
| Budget exemption cannot work: `review.js` clamps the budget to 3 and `decideVerdict` escalates at `cycle >= budget` | Confirmed. `exempt_cycles` added after the clamp, also in `/review`'s precondition (§3.4). |
| Findings carried "by silence" vanish once rotation archives the raising cycle | Confirmed. Carried findings are now written into the next block with `carried:` (D10, §3.3). |
| Confirmed closures still reach disposition and `finalize_ready` in `review.js` | Confirmed. Removed from `surviving` first (§3.3). |
| Hook on REVIEW.md fires on a partial cycle | Confirmed (one `Edit` per block). Trigger moved to the scribe's final marker release (D7, §3.4). |
| Hook races DECISIONS.md appends | False: ADRs drafted in a run postdate every quote in it. Moot with the new trigger. |
| Fabricated closure quotes earn a budget exemption | Confirmed. Only verifier-quote revivals are `exempt`. |
| Verifiers are not given the closure quote | Confirmed. Added to their input. |
| `/revise` cannot read verified blocks | Confirmed (`Read, Task`; scans `refuted-by:`). Gains the gate's `--report` (§3.6). |
| `demoted:` cannot be written for failed anchor quotes | Confirmed. Recorded in the event and surfaced elsewhere (§3.1, §3.2). |
| Restored severities not tracked | Confirmed. Included in `revived`. |
| Gate never compares recorded hashes | Confirmed, and a gap today too. `spec-changed-since-review` (§3.5). |
| `finalize-gate.sh --report` does not exist | False as a defect: Part A of the dashboard spec adds it in the same release; dependency now explicit. |
| `carried` breaks the debate shape | Mostly false; wording tightened: passed only after a verified cycle. |

### Third review (Gemini 3.8 Flash, 2026-10-14)

| Finding | Outcome |
|---|---|
| Exhausting cycle deadlocks when a closure quote fails (workflow clean, gate refuses, `/review` refuses, no ESCALATION.md) | Confirmed. Any reopen makes the cycle `exempt` (§3.4); `/review`'s precondition reads the open set from `--report`. Reverses the second round's verifier-only rule. |
| Hook on an `incomplete` run's marker release re-checks the previous cycle against a revised spec and overwrites its event | Confirmed (`cleanupEnvelope` leaves `CYCLE` unchanged). First event per cycle wins. |
| Carried findings keep vs re-run disposition | Confirmed contradiction. Disposition is never copied; re-listed and carried findings are dispositioned each cycle, as today. |
| `spec-changed-since-review` blocks delta dispatch | Partly. Refusal is finalize-only; `--report` flags it and returns the open set. |
| §5 test contradicts the exemption rule | Confirmed; aligned with the new rule. |
| DECISIONS hashes recorded but unchecked | Partly (a full hash would refuse legitimate appends). Prefix check. |
| `acceptance.md` has no `STATUS:` line | Confirmed wording slip. Fixed. |
| A failed closure leaves an undispositioned major | Mostly false (gate, `--report`, carry-forward handle it). Reported as `reopened-closure`. |

Review rounds stop here; remaining edge cases are left to the plan's failing-first tests.

