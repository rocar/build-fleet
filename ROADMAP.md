# build-fleet — Roadmap

## v0.1 — shipped 2026-05-30

**What landed:** five role subagents (product-owner, architect, coder, qa, devops), five SDD skills (sdd-protocol, sdd-spec-template, adr, review-rubric, test-plan), five slash commands (/build-fleet:new-feature, :review, :finalize, :handoff, :status), five hook scripts (block-source-before-finalized, restrict-reviewer-writes, validate-spec-status, check-review-written, stop-tests) enforcing the gate layer. State machine: SPEC → REVIEW → FINALIZE → BUILD → CHANGE_REVIEW → HANDOFF, with bounded review cycles (≤3) and ESCALATION.md as first-class outcome.

**Validation:** 7/7 a–g dry-run steps passed end-to-end on `smoke-test` and `escalation-test` features. Every gate fired correctly, including the escalation pathway under a manufactured-blocker stress case.

**Known gaps that v0.2 addresses:**
- Cycle-3 agent-team fallback in `/build-fleet:review` depends on an unstable platform feature gated by `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` env var.
- "All-approved" finalize gate is a binary proxy for what's really a judgment call (do the concerns survive scrutiny?), exposed by the escalation-test planted-blocker case.
- Single-track command pipeline can't proportionally scale to trivial fixes (over-ceremony) or to multi-file features (under-fan-out).
- BUILD has coder and qa run in parallel; no enforced tests-first ordering.

---

## v0.2 — workflows architecture (in design)

### Direction

Adopt Claude Code's [dynamic workflow primitive](https://code.claude.com/docs/en/workflows) as the orchestration substrate for multi-agent SDD phases. v0.1's hooks remain the tool-level safety backbone; workflow scripts host phase-transition logic and adversarial cross-examination. Plugin stays orchestrator-agnostic — Hermes-driven headless use is first-class from M1 onward.

### Principle of separation (the M0 lens)

- **Deterministic gates** (binary, mechanically checkable) stay as hooks: source-write block until FINALIZED, STATUS validity, tests-pass, "no open blockers."
- **Judgment convergence** (subjective, needs cross-examination) moves into workflow scripts: spec soundness, concern survival, implementation faithfulness.

Trying to hook-enforce a judgment (or vote on a binary) is the category error v0.2 corrects.

### Milestones

**M0 — Control inventory + workflow contract (design spike, no code shipped).**
Deliverables:
- `docs/v0.2/CONTROLS.md` — every existing control classified as gate-or-judgment; destination per control (hook / workflow script / subagent frontmatter / retired).
- `docs/v0.2/CONTRACT.md` — workflow ↔ command-layer state-mutation contract; headless-mode contract; cost-ceiling declaration format; structured-stdout schema.
- Empirical hook-firing matrix recorded from a minimal probe workflow.

Output gates M1–M4.

**M1 — Review workflow.** Replace `/build-fleet:review`'s parallel + agent-team-cycle-3 hybrid with a workflow that pattern-matches `/deep-research`: fan out reviewers, adversarial cross-check, survival vote, structured report. The convergence rule moves from "all-approved" to "a concern survives unless refuted by cross-examination." `check-review-written` (SubagentStop) re-homes as a workflow post-condition.

**M2 — Tests-first BUILD ordering.** Protocol-only change. QA authors failing tests against acceptance.md before coder implements; the failing tests become coder's convergence target. Small, but it's the prerequisite that makes M3's parallel coders possible.

**M3 — Build workflow.** `/build-fleet:deep-build` for large/multi-file features: fan out coders across partitioned file ownership against M2's failing-test target, with the platform's launch prompt as the plan-approval gate (interactive mode) and the upstream orchestrator providing the equivalent in headless mode. Plan-approval gate is therefore *inherited from the runtime*, not custom code. Adversarial review sub-phase follows the fan-out.

**M4 — Routing front door.** Three-tier classifier: trivial → fast-path skip (skeleton spec straight to finalize); standard → v0.1 command pipeline; large → workflow dispatch to M3. Lands last; depends on M1 and M3 existing as concrete dispatch targets.

### First-class capabilities in v0.2

- **Headless mode (`claude -p` / Agent SDK).** From M1 onward, every workflow command works headlessly. The launch-prompt plan-approval gate is replaced by the caller's between-phase approval (e.g., Hermes posts the workflow's structured output to Discord; Ray approves the next kanban task). Workflows declare cost ceilings the caller can surface upstream.
- **v0.1 hook backbone retained.** Tool-call hooks (`block-source-before-finalized`, `validate-spec-status`) fire on workflow subagents, preserving the source-write block and the spec-format gate.

### Drops from v0.2

- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` README step.
- Cycle-3 agent-team fallback branch in `/build-fleet:review`.
- Deferred `TaskCompleted` / `TeammateIdle` hooks (agent-teams-only, doubly moot).
- `hooks/scripts/restrict-reviewer-writes.sh` — workflow reviewer subagents declare `tools:` allowlists without `Write`/`Edit`; the restriction lives where it belongs (subagent definition) and the hook becomes redundant.

### v0.2 explicitly does NOT include

- Mid-workflow human intervention via external channels (Discord/Slack/email). Workflows can't pause for input mid-run by design. Intervention happens at phase boundaries.
- Discord/Hermes integration adapters inside the plugin. Build-fleet stays orchestrator-agnostic.
- Marketplace registration.

---

## v0.3 — orchestrator-mediated human intervention (forecast)

### Direction

Open the integration surface between build-fleet workflows and external orchestrators (Hermes being the primary case) so mid-cycle human review can happen via Discord threads, kanban tasks, or other channels — without rendering build-fleet a Hermes-specific plugin. The plugin ships the *protocol*; the orchestrator ships the adapter.

### Candidate milestones

**M0 (v0.3) — Integration handshake protocol.** Define the contract by which an external orchestrator can: (a) hand a workflow a kanban task ID + human-channel handle, (b) receive a workflow's intermediate `WAITING_FOR_HUMAN` signal with a typed payload, (c) resume the workflow (likely as a fresh invocation with a `--resume-token` and the prior state) carrying the human verdict.

**M1 (v0.3) — Reference Hermes adapter.** Reference implementation: kanban task as the workflow handle, Discord thread as the gate surface, signal protocol for resume. Lives outside the plugin (Hermes config or a sibling repo). The plugin only ships the protocol contract.

**M2 (v0.3) — Mid-workflow gate primitives.** Once the protocol exists, add a `PAUSE_FOR_HUMAN` step type to build-fleet workflows that want it. May depend on platform-side capabilities (callback hooks, pause-and-resume primitives) maturing — track the workflows doc for changes.

### Deferred from v0.3 to even later

- Multi-orchestrator support (Hermes + Linear + Slack-as-orchestrator simultaneously).
- Plan-approval-via-Discord for headless launches. The v0.2 pattern ("caller surfaces cost ceiling on Discord before dispatch") likely covers 80% of the use case; revisit only if the gap shows in production.

### Gate-vs-judgment hardening candidates (version-flexible)

- **Reviewer-blocker disclaimer detection.** Lint for `[blocker]` items accompanied by self-disclaiming prose ("planted", "no new concerns", "for the escalation test") in the same review block. Surfaces manufactured blockers without softening the gate. Could land in v0.2 if a real failure mode surfaces; otherwise v0.3.
- **Survival-vote audit trail.** Structured `[refuted-by: <reviewer> reason: <prose>]` annotations on concerns that the cross-examination phase rejected, so escalation triage has the evidence.

---

## Durable principles (apply to every version)

- **Spec is the contract.** No implementation begins until a spec is FINALIZED.
- **Gates are deterministic; judgments are adversarial.** The M0 classification is the rule, not a heuristic.
- **Escalation is a first-class outcome, not a failure.** Human review at boundaries is the correctness mechanism, not an exception path.
- **Filesystem is shared memory.** Subagent memories silo; the workspace `.sdd/<feature>/` does not.
- **Plugin is read-only machinery; `.sdd/` is per-project state.** Never let machinery and state interleave. The plugin tree is re-installable; `.sdd/` is the truth.
- **Orchestrator-agnostic.** Build-fleet works from CLI, headless `claude -p`, Hermes, or any future orchestrator. No orchestrator-specific code lives in the plugin.
