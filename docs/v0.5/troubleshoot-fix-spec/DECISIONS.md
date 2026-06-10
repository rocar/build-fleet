# Architecture Decisions — troubleshoot-fix

Append-only log. Each ADR is immutable; supersede with a new ADR.

## ADR-001: Model bug-fixing as a second, parallel state machine

- **Date:** 2026-06-05
- **Status:** accepted
- **Cycle:** 0 (SPEC-time foundational)

### Context
build-fleet's existing state machine (SPEC → REVIEW → FINALIZE → BUILD →
CHANGE_REVIEW → HANDOFF) is built on one load-bearing axiom: *the spec is the
contract*. Every gate, hook, and role prompt assumes a `spec.md` written
**before** work begins, describing the intended behavior, against which the
review converges and the build is verified.

Bug-fixing inverts that axiom on three axes at once:
- **The trigger is a symptom, not an intent.** A bug starts from "X is wrong,"
  not "build X."
- **The root cause is unknown — diagnosis IS the work.** You cannot write a
  contract for "fix the thing" before you know what the thing is. A spec that
  says "make the bug stop" is not a spec; it is a restatement of the symptom.
- **Verification is a regression test, red-before/green-after**, not "satisfies
  acceptance.md." The proof of a fix is that a test reproduces the defect (red)
  and the change makes it pass (green) — a counterfactual, not a forward
  acceptance check.

Forcing a bug through the SPEC machine therefore means writing a spec for an
outcome whose mechanism is unknown — incoherent, and it would either stall at
the SPEC gate or produce a hollow spec that defeats REVIEW's whole purpose.

### Decision
Introduce a **second, parallel state machine** for the troubleshoot-fix path:
**REPORT → REPRODUCE → DIAGNOSE → FIX → VERIFY → HANDOFF**. Its contract
artifact is a new `diagnosis.md` (not `spec.md`), carrying
`STATUS: REPORTED | REPRODUCING | DIAGNOSED | CONFIRMED | FIXED`. The two
machines coexist; an feature/bug is routed to one or the other at entry, and
the forward (SPEC) machine is left semantically untouched.

### Alternatives considered
- **(a) Extend the SPEC machine with a "bug mode" flag.** Rejected: it pollutes
  every gate, hook, and role prompt with dual semantics, and the
  spec-as-contract axiom cannot be cleanly conditionalized — half the machine
  would have to branch on the flag, doubling the reasoning surface inside code
  that is currently simple and auditable.
- **(b) Treat every bug as a `trivial`-tier feature.** Rejected: the trivial
  fast-path only works for KNOWN-cause one-liners (it skips REVIEW precisely
  because there is nothing to diagnose). It collapses the moment the cause is
  unknown — which is the defining case of a real bug.
- **(c) Handle bugs entirely outside build-fleet (ad-hoc).** Rejected: this
  throws away the reproducing-test + counterfactual discipline that is
  build-fleet's entire value proposition. An ad-hoc fix has no audit trail, no
  red-before proof, and no adversarial check on the root cause.

### Consequences
- **Honest cost: a second machine roughly doubles some surface area** — a new
  command (`/build-fleet:troubleshoot` or similar), a new artifact
  (`diagnosis.md`), a new workflow (`diagnose.js`, ADR-002), a new inviolable
  hook (ADR-003), and a new PROGRESS phase vocabulary. This is real
  maintenance and review weight, and it is the price of admission.
- **Payoff: the forward machine's gates stay uncontaminated and the new path is
  additive.** No existing hook or role prompt changes its meaning; a repo that
  never files a bug behaves byte-identically to today. The two machines are
  legible *because* they are separate.
- **The bug path REUSES proven machinery rather than reinventing it:** the
  counterfactual test gate (today CHANGE_REVIEW's "would this test fail if the
  source were reverted?") becomes the native verification primitive of VERIFY,
  and the survival-vote workflow engine (`review.js`) is reused — inverted — to
  confirm the diagnosis (ADR-002). The second machine is new structure over
  reused mechanism, which bounds the true cost below "double everything."
- **New load-bearing fact:** `diagnosis.md` STATUS becomes a gate input
  (ADR-003). Anything that must reason about "is this a bug or a feature?" now
  resolves the active machine from which contract artifact exists.

## ADR-002: Confirm the root-cause diagnosis with an adversarial workflow (inverted review.js), not a hook

- **Date:** 2026-06-05
- **Status:** accepted
- **Cycle:** 0 (SPEC-time foundational)

### Context
The DIAGNOSE phase produces a root-cause *hypothesis*: "the bug is caused by X."
The machine must decide whether that hypothesis is sound before permitting a
fix — a fix built on a wrong diagnosis treats the symptom and leaves the defect
live. "Is this root-cause analysis correct?" is a **judgment**, not a binary
fact. sdd-protocol is explicit: *"Gates are deterministic; judgments are
adversarial… the category error to avoid is hook-enforcing a judgment."* A hook
can check that `diagnosis.md` is *filled in*; it cannot check that the diagnosis
is *true*.

### Decision
Run diagnosis-confirmation as a **workflow** — `diagnose.js`, an **inverted
`review.js`**. Where `review.js` runs a *survival vote* (a concern dies unless a
different-role reviewer refutes it with a section cite), `diagnose.js` runs the
**dual**: a root-cause hypothesis **survives only if it is NOT refuted** by a
different-role reviewer citing the **reproduction** as counter-evidence. The
burden is inverted because the default posture toward an unproven root cause is
*suspicion*: the hypothesis must withstand attack grounded in the actual
reproduced behavior, not merely be asserted. A surviving (unrefuted) hypothesis
flips `diagnosis.md` to `STATUS: CONFIRMED`.

### Alternatives considered
- **A hook that checks "is `diagnosis.md` filled in"** (e.g., STATUS present,
  a root-cause section non-empty). Rejected: this enforces **form, not
  soundness**. It would pass a confidently-wrong diagnosis and block an empty
  but correct one — exactly the category error sdd-protocol names. Presence is
  cheaply gameable; correctness is the whole point.
- **A single architect subagent unilaterally "approves" the diagnosis.**
  Rejected: a lone approver has no adversary and regresses to rubber-stamping;
  the value is in a *different-role* reviewer attacking the hypothesis with the
  reproduction in hand, which the workflow's cross-examination structure
  provides for free.

### Consequences
- **Reuses the survival-vote engine** rather than authoring new convergence
  logic — `diagnose.js` is a fork/inversion of `review.js`, inheriting its
  cross-examination, citation-substantiveness checks, and scribe-applied
  envelope. The refutation evidence shifts from `spec.md`/`acceptance.md`
  sections to the **reproduction** (the REPRODUCE artifact / failing-test
  output), so the citation regex and the "what counts as counter-evidence"
  rule differ — that is the load-bearing inversion.
- **The CONFIRMED status is earned, not asserted**, giving FIX an audit trail
  ("this root cause survived adversarial challenge at cycle N") symmetric to a
  FINALIZED spec.
- **Cost: a confirmation cycle is bounded like REVIEW** (default 3, then
  escalate) — a genuinely contested diagnosis can consume cycles and must
  escalate to a human rather than loop, inheriting REVIEW's escalation
  machinery and its failure mode (a deadlock surfaces, it does not auto-resolve).
- **It does NOT make diagnosis a deterministic gate.** The deterministic teeth
  live in ADR-003 (the reproducing-test hook); ADR-002 governs *soundness of
  cause*, ADR-003 governs *proof of fix*. Keeping these separate is the
  gates-vs-judgments split applied to the bug path.

## ADR-003: The reproducing-test gate is a new inviolable deterministic hook; the FINALIZED source-write gate gains a second CONFIRMED unlock

- **Date:** 2026-06-05
- **Status:** accepted
- **Cycle:** 0 (SPEC-time foundational)

### Context
A fix is only proven by a regression test that was **red before** the change and
**green after**. Today, "tests first" on the bug path would be a *prompt
convention* (the coder's self-enforcement, per `agents/coder.md`) — and
sdd-protocol already flags that the coder's tests-first rule "is self-enforced…
the v0.1 hook layer does not gate this." A prompt convention is too weak when
the thing being edited is **live, already-shipped code**: the failure mode is a
coder that writes the fix, then writes a test that passes against the fixed code
without ever having been red — a decorative test that proves nothing. This is a
**binary, mechanically checkable fact** ("did a test for this defect exist and
fail before the source change?"), so it is exactly what a deterministic hook is
*for*.

Separately, source writes are gated today by `block-source-before-finalized`,
which unlocks only when the active `spec.md` STATUS=FINALIZED. The bug path has
no `spec.md`; its contract is `diagnosis.md`. Source must be writable during FIX
— but only once the cause is CONFIRMED, never before.

### Decision
Two deterministic changes, both on the bug path, neither weakening the forward
path:
1. **A NEW inviolable reproducing-test hook.** No fix source-write lands unless a
   test exists that **reproduces the defect and was red first**. This is a hard
   gate (exit code 2 = block), not a convention.
2. **`block-source-before-finalized` gains a SECOND unlock**, mirroring the
   FINALIZED unlock: source writes are also permitted when the active
   `diagnosis.md` STATUS=CONFIRMED. The existing FINALIZED unlock is unchanged;
   the hook becomes "unlock iff `spec.md`=FINALIZED **OR** `diagnosis.md`=CONFIRMED,"
   resolving whichever contract the active machine uses.

### Alternatives considered
- **Rely on the coder's self-enforcement (prompt-only tests-first).** Rejected:
  today's tests-first is only a prompt convention, not a gate — sdd-protocol
  itself notes the hook layer does not enforce it. That is acceptable for
  greenfield BUILD (the spec/acceptance constrain the test) but **too weak for
  fixing live code**, where the temptation to write the test green-after is
  strongest and the cost of a decorative regression test is a bug that silently
  reopens.
- **Reuse the existing CHANGE_REVIEW counterfactual check as the only gate.**
  Rejected: that check fires at CHANGE_REVIEW — *after* the fix is written — so
  it catches a decorative test late, after wasted FIX work, rather than blocking
  the bad source-write at the point of edit. Red-before must be enforced *at the
  write*, not audited afterward. (CHANGE_REVIEW's counterfactual remains as
  belt-and-suspenders.)
- **A third, separate source-write hook for the bug path.** Rejected:
  duplicating `block-source-before-finalized`'s logic into a parallel hook
  invites the two drifting apart. A second unlock branch in the one existing
  hook keeps a single source-write authority and a single place to reason about
  "may source be written right now?"

### Consequences
- **The FINALIZED path is provably unweakened:** the new unlock is an additional
  OR-branch keyed on a different artifact (`diagnosis.md`), so a feature with no
  `diagnosis.md` sees byte-identical FINALIZED-only behavior. The change is
  purely additive to the gate's truth table.
- **Red-before becomes a deterministic invariant of the whole path**, not a hope.
  The reproducing-test hook makes "every fix has a test that was once red" a
  property the machine guarantees, which is what lets VERIFY's green-after be
  meaningful.
- **New load-bearing coupling:** the reproducing-test hook must mechanically
  determine "was this test red before the change?" — it needs a reliable signal
  (e.g., a recorded failing-test run captured at REPRODUCE, keyed to
  `diagnosis.md`). That capture step becomes load-bearing; if it is unreliable,
  the gate is unreliable. This is the implementation risk REVIEW should probe.
- **Two artifacts now drive one hook**, so the hook's active-feature resolution
  must read whichever of `spec.md`/`diagnosis.md` exists for the active slug —
  a small but real increase in the hook's branching, justified by keeping
  source-write authority centralized.

## ADR-004: Severity (sev0|sev1|sev2) replaces SIZE as the bug-path routing axis and drives tempo

- **Date:** 2026-06-05
- **Status:** accepted
- **Cycle:** 0 (SPEC-time foundational)

### Context
The forward machine routes by `TIER` (trivial|standard|large), a proxy for the
*size/scope* of the work. Size is the wrong axis for a bug: a one-line fix to a
silent data-corruption bug is tiny in scope but maximally consequential, while a
large refactor-style fix to a cosmetic glitch is the reverse. The bug path needs
a routing axis that captures **blast radius and urgency**, and it must resolve a
genuine tension — the **hotfix-tempo paradox**: a sev0 production outage cannot
wait for a full adversarial diagnosis-confirmation cycle (rigor that costs
wall-clock time the incident does not have), yet a subtle data-corruption bug
*demands* exactly that rigor and would be ruined by a hotfix tempo.

### Decision
Route the bug path by **severity (`sev0 | sev1 | sev2`)** instead of SIZE, and
let severity drive tempo:
- **`sev0`** (active outage / data loss in flight) may **skip the adversarial
  diagnosis-confirmation** (ADR-002) and run it **post-hoc** instead — fix
  first under the deterministic gate, confirm the root cause after the bleeding
  stops.
- **`sev0` may NEVER skip the reproducing-test gate** (ADR-003). Even a hotfix
  ships with a red-before/green-after regression test — that gate is inviolable
  regardless of tempo.
- **`sev1`/`sev2`** run the full machine, confirmation-before-fix.

Severity is the bug-path analogue of TIER, set at REPORT time (by the classifier
or the reporter), and carried in PROGRESS.md.

### Alternatives considered
- **One fixed tempo for all bugs.** Rejected on both horns: a single rigorous
  tempo is too slow for sev0 (the outage outlives the confirmation cycle), and a
  single fast tempo is too loose for sev2 subtle bugs (a data-corruption root
  cause shipped without adversarial confirmation is how you fix the symptom and
  keep the defect). No single tempo serves both.
- **Reuse the existing `TIER` (size) axis for bugs.** Rejected: size does not
  predict blast radius or urgency, so it would route a tiny-but-critical fix
  identically to a tiny-but-cosmetic one — the exact miss severity exists to
  prevent.
- **Let sev0 also skip the reproducing-test gate for maximum speed.**
  Rejected: this is the one corner that must not be cut. A hotfix with no
  red-before test is the highest-risk change in the system (live code, max
  urgency, zero proof) — precisely where a silently-reopening regression is most
  likely. Tempo may relax *judgment* (post-hoc confirmation); it may never relax
  the *deterministic proof of fix*.

### Consequences
- **Resolves the hotfix-tempo paradox by separating what may flex from what may
  not.** The adversarial *judgment* (diagnosis-confirmation) is allowed to move
  after the fix for sev0; the deterministic *proof* (reproducing test) never
  moves. This is the gates-vs-judgments split (ADR-002/ADR-003) applied to
  tempo: relax the judgment under pressure, never the gate.
- **`sev0` post-hoc confirmation is a deferred obligation, not a waiver.** The
  machine must track that a sev0 fix owes a confirmation pass and surface it
  until satisfied — otherwise "post-hoc" silently becomes "never." This deferred
  state is new load-bearing bookkeeping REVIEW should scrutinize.
- **Severity is author-assigned and therefore gameable** — mislabeling a subtle
  bug `sev0` to skip confirmation is the abuse path. The mitigation (the post-hoc
  obligation above, plus that the reproducing-test gate still fires) bounds the
  damage but does not eliminate the misclassification risk; this is an accepted
  residual, flagged here for the audit trail.
- **A new routing vocabulary** (`sev0|sev1|sev2`) parallels `TIER` without
  replacing it — the forward machine keeps SIZE, the bug machine uses SEVERITY,
  and the active machine determines which axis applies. Two vocabularies is the
  honest cost of two machines (ADR-001).
