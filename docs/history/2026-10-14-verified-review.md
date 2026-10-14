# Verified review — design

**Date:** 2026-10-14
**Status:** draft for review (design approved section by section in brainstorming); amended after an independent Gemini review (§9); implementation plan follows approval
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
| D7 | **Quotes are checked by a PostToolUse hook when the scribe writes REVIEW.md**, and the result is recorded as an event. | The workflow runtime has no filesystem, and `/review` returns before the workflow finishes, so no command is present at apply time. The hook is deterministic bash and runs before anyone can revise the spec. |
| D8 | **The finalize gate is the authority** for the verified shape: it recomputes the vote from recorded verdicts and the quote-check event. | The deterministic layer decides; the workflow's answer is provisional. |
| D9 | **Reuse the read-only `reviewer` agent** in a verify mode. | No ninth agent, no new tool allowlist. |
| D10 | **Open findings carry forward.** Every open finding of a verified cycle must reappear in the next one, open or with a confirmed closure; silence keeps it open. | Delta reviewers and the gate look only at the latest cycle; without this, a finding revived by the quote check would vanish. |

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
visible `demoted:` line under it. Minors are never verified.

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
- `demoted: {"reason":"no-anchor"|"no-test"|"test-invalid"|"anchor-quote-failed"}` records a
  demotion to minor.
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
receives the blocker and major findings as `{id, severity, text, anchor, ref, test}`.
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

**Delta cycles (cycle ≥ 2).** The reviewer's closure list is every **open** finding of the
previous verified cycle that it raised: blockers, `fix` majors, and findings the quote check
revived (D10; the ids come from the previous cycle's quote-check event, passed by `/review`
as the `carried` arg). For each, it either re-lists it as still open, with its original id and
severity, or claims closure with a `closure` quote of the revised spec text. The panel votes
`confirm`/`reject` on each closure; a closure holds when a majority confirms and its quote
passes §3.4. A rejected or failed closure keeps the finding open. New blockers raised in a
delta cycle are verified like any new finding. The delta rule and the disposition leg are
otherwise unchanged.

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
`hooks/scripts/check-review-quotes.sh`, matched on Write/Edit of `.sdd/<slug>/REVIEW.md`.
The scribe writes REVIEW.md while applying the workflow's envelope, so the check runs at
apply time, against the spec exactly as reviewed. `/review` cannot do this: it launches the
workflow asynchronously and returns at once. The hook **ignores `.workflow-in-flight`** (the
scribe writes inside a workflow run), runs only when the newest cycle block for the active
item carries `shape: verified`, and is **idempotent**: each run appends a fresh event, and the
latest event for a cycle is authoritative. The script is bash 3.2 and GNU compatible,
anchors at the project root, requires jq, and rejects `..`.

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
  `source: script:quote-check`, `decision: pass|fail`, `cycle: N`, the sha256 of each file
  it read, `checked` (count), `failures` — each `{id, where: "anchor"|"verdict"|"closure", v?}` —
  and `revived`, the ids whose kill or closure no longer holds once failed quotes are removed.
- It prints `BUILD_FLEET_QUOTE_CHECK: {"slug":…,"cycle":N,"checked":…,"failed":…}`.

**Effect of a failed quote:**

| Failed quote | Effect |
|---|---|
| finding anchor | the finding is demoted to minor (`anchor-quote-failed`, applied by the gate) |
| refutation, or a lower-severity vote | that vote is invalid; the vote is recomputed; a finding whose kill drops below 2 valid refutations revives as open, and is listed in `revived`. It carries forward (D10): the gate counts it open, `/revise` hands it to the PO, and the next delta cycle must close it. |
| closure | the closure is invalid; the finding stays open |

**On the budget-exhausting cycle.** A revived finding is the verifiers' fault, not the
spec's. So a cycle whose latest quote-check event lists any `revived` id **does not count
against `REVIEW_CYCLE_BUDGET`**: `/review` reads that event at dispatch and allows one more
cycle. `CYCLE_TOTAL_MAX` still applies, so the extension is bounded, and reaching it
escalates as today. No command needs to write state outside the workflow.

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
2. applies the cycle's quote-check event; **no event for a verified cycle ⇒ refuse with
   `quote-check-missing`**;
3. recomputes demotions, kills, severities and closures with the §3.3 rules; a re-listed
   finding whose closure holds is **closed**, and is not counted under step 4;
4. applies **carry-forward** (D10): every finding open at the end of the previous verified
   cycle (blockers, `fix` majors, and the previous event's `revived` ids) that the current
   cycle neither re-lists nor closes is **counted open**, reason `carried-open`;
5. applies today's rule: no open blockers; no majors dispositioned `fix` or undispositioned.

`review.js` still returns `finalize_ready`; for the verified shape it is provisional, and
`/review` prints the gate's `--report` result (dashboard spec §3.4) after the quote check.
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
- `commands/review.md`: resolves the three settings and passes them through; at dispatch
  it reads the previous cycle's latest quote-check event (for the budget exemption, §3.4)
  and passes its open and `revived` ids as the `carried` arg, read from
  `finalize-gate.sh --report` (added to its allowed tools). It never writes state. The
  no-workflow fallback path always runs `debate` and says so.
- `commands/revise.md` hands the PO the gate's open set, which now includes revived and
  carried findings. `commands/finalize.md` is unchanged: it runs the gate.
- `hooks/hooks.json` registers `check-review-quotes.sh` under PostToolUse
  `Write|Edit` (the only registration point).
- `scripts/status-snapshot.sh` and `/build-fleet:status` show `review_shape` and, for a
  verified cycle, a summary: raised, upheld, refuted, quotes failed. Additive to
  `status-snapshot@1`.

**Unchanged:** `change-review-gate.sh`, `check-review-written.sh` (no-workflow path only),
`review-rotate.sh` (moves whole blocks; a test confirms it carries the new lines). The
scribe writes what the envelope gives it, including the `shape:` and `demoted:` lines; its
body is unchanged.

**An assumption the plan must verify first:** plugin PostToolUse hooks fire for tool calls
made by subagents inside a workflow run (the scribe). The dashboard spec's `record-phase.sh`
rests on the same assumption. If it fails, the fallback is the gate refusing
`quote-check-missing`, and the design must move the check before this ships.

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
- Delta: closure confirm/reject; carried ids appear in each raiser's closure list; new
  blockers verified.
- Lens and verification schemas accept good and reject bad payloads.
- Args: `shape`, `verifier_model`, `verify_blockers_solo`, `carried` validated; bad values ⇒
  `invalid-args`.
- Lens schema rejects a blocker or major without `anchor` or `test`; the fallback writes
  `demoted:`.

**`quote-check.sh` harness** (mktemp):
- Normalization: whitespace and newlines, curly quotes, dashes, markdown markers; case kept.
- Bounds 10–500; a spec's own `...` matches; an elided quote fails.
- File allowlist, including `.sdd/_product/DECISIONS.md`; `..` and other files refused;
  `absent:` passes only when the named section heading exists.
- One event per run, with file hashes, failures and `revived`; re-running is idempotent and
  the latest event wins; signal line printed.

**`check-review-quotes.sh` hook harness:** fires on a REVIEW.md write whose newest block is
verified, including with `.workflow-in-flight` present; does nothing for a debate block or
another file; never changes the write's outcome.

**`finalize-gate.sh` harness** (failing case first for each):
- Vote recomputed from `verdict:` lines; malformed line ⇒ invalid verdict.
- Failed refutation quote revives a finding ⇒ refuse.
- Failed anchor quote demotes.
- Verified block with no quote-check event ⇒ `quote-check-missing`.
- A failed lower-severity quote restores the original severity.
- A re-listed finding with a confirmed, quote-checked closure is closed (not `majors-open`).
- Carry-forward: a finding open in cycle N and absent from cycle N+1 is `carried-open`; a
  revived id from N's event is open in N+1 until closed.
- Shape is detected only from `shape: verified`; a debate line containing the word
  "verdict:" stays debate.
- Mixed debate/verified blocks parse.
- Every existing debate-shape case passes unchanged.

**Also:** `review-rotate.sh` carries the new lines; `rubric-drift` and `lens-drift` pass;
the smoke test runs a fixture verified REVIEW.md (no model) through the hook,
`quote-check.sh` and `finalize-gate.sh`; `/review` grants one extra cycle when the previous
event lists revived ids, and not beyond `CYCLE_TOTAL_MAX`.

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

