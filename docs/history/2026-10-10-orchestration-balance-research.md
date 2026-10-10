# build-fleet: how much orchestration is the right amount? A research report

**Date:** 2026-10-10
**Question (Ray):** As models get more capable, practitioners say give less guidance and let the model reason. build-fleet's multi-agent debate and vote makes it much slower than lighter spec-driven frameworks such as superpowers, yet Hermes is also building multi-agent voting. What is the right balance for a plugin that is effective, easy to use, and still produces high-quality output?
**Method:** deep-research workflow (106 agents, 24 sources fetched, 119 claims extracted, 25 adversarially verified: 14 confirmed, 11 refuted) plus local verification against the installed build-fleet 0.9.0, superpowers 6.4.1 and Hermes 0.21.5 sources.

## 1. Position

Keep the deterministic skeleton. Make the debate conditional on stakes, not default. Default the standard tier to a roster of two instead of three. Retune the reviewer lenses so they stop hunting for gaps. Shrink the user-facing surface by progressive disclosure, not by removing gates.

One fact answers the speed comparison directly: superpowers has no agent spec review at all. Its only agent review is one reviewer per task on a code diff plus one whole-branch pass at the end; the spec itself is approved by the human in the brainstorming conversation. build-fleet's 26.6 minutes per cycle is spent on a stage superpowers hands back to Ray. The two plugins are not doing the same work faster or slower; they put the human in different places.

Two things the question conflates must be separated first:

- **(b) The loop that did not converge was a bug, and v0.9.0 fixed it.** The tap pilot's 5 to 16 review cycles per feature came from an all-approved exit condition that could not be met, unbounded reviewer inputs (~866k tokens per cycle), reviewers that were not read-only, no ADR disposition for majors, and no clock. None of those five causes is "debate is slow".
- **(a) The remaining cost is structural.** One healthy cycle 1 on a 49 KB spec is 8 agent invocations, 26.6 minutes, 734k subagent tokens, and it left 9 open fix majors, so a standard feature pays at least two cycles (about 50 minutes) before any code exists. That is the real question: does 8 agents per cycle buy quality that 2 would not?

The evidence says the quality comes from one specific component, citation-forced refutation by a different role, which build-fleet already has in code. It does not come from reviewer headcount. So the fan-out width and the cross-examination round are what should become conditional; the gates and the citation rule should stay.

## 2. What the evidence says, ranked by confidence

**High confidence**

1. **Homogeneous multi-agent debate does not reliably beat a single strong model with self-consistency, and extra debate rounds make LLM-judge bias worse.** Smit et al. (ICML 2024, "Should we be going MAD?"), Zhang et al. (2025, "Stop Overvaluing Multi-Agent Debate": across 36 configurations no MAD method beat plain chain-of-thought in more than 15 to 20 percent of settings), Ma et al. (EMNLP 2025: judge bias consistency drops sharply after round 1 and never recovers). Caveat: 2024-era models on QA and function-level code, not spec review on Claude 5.
2. **Anthropic's current direction is less process prescription, not less specification.** Every "remove over-prompting" line in the Opus 5, Fable 5 and skills best-practice pages sits beside "state the boundaries, define explicit constraints". Hooks remain the recommended layer for anything that must happen every time. The 80 percent system-prompt cut was mostly relocation into selectively loaded skills and tool descriptions. The "experts say give less guidance" premise is half right: prune procedure and tone, keep scope, bounds, deterministic checks and risk-tiered constraints. build-fleet's hooks, state machine and spec-first discipline are the second kind.
3. **A reviewer prompted to find gaps will report gaps even when the work is sound.** Anthropic's Claude Code best-practices page says so verbatim and tells you to scope reviewers to "only gaps that affect correctness or the stated requirements". build-fleet's qa lens reads "if you have to invent assumptions, that's at minimum a [major]" and "'fast', 'robust', 'user-friendly' are [blocker]-tier vagueness"; the coder lens is a list of things to flag as missing. Under a survive-unless-refuted vote, every unrefuted gap they generate reaches the disposition leg.
4. **For Opus 5 specifically, Anthropic says remove explicit self-verification instructions** because the model self-verifies unprompted; Sonnet 5.5 and Haiku 5.5 guides say the opposite. This targets a model re-checking its own work, not fresh-context verifier roles. In build-fleet it touches only the two `model: opus` agents (architect, product-owner), and only the product-owner's mandated "Self-review before you signal ready" procedure.

**Medium confidence**

5. **What makes multi-reviewer review pay is structured, evidence-grounded disagreement, not agent count.** Qiu & Gill (ICML 2026 DL4C workshop, "Adversarial Review"): a 3-agent coder+reviewer+critic protocol matched or beat a 5-agent fan-out, but naive adversarial review was the worst method on the code-review benchmark (false consensus) until a prompt-only change forced the critic to choose agree / disagree-with-citation / disagree-concern. Single run, no confidence intervals, workshop tier. build-fleet's cross-examination already discards any refutation without a structured citation (review.js lines 670 to 676), which is exactly the fix that paper found; this is the strongest reason to keep that leg and the clearest evidence the lens count can drop without losing the mechanism.
6. **Anthropic prices multi-agent at roughly 15x chat tokens (research system) and 7x a standard session (Claude Code agent teams) and says it is justified only when task value pays for it.** That is a stakes criterion, which is the classifier's job, not a flat yes or no.

**Primary sources that did not reach the adversarial verification pass (treat as strong but unvoted)**

7. **superpowers 6.0.0 (2026-06-16) cut its per-task review from two reviewers to one** because the two-reviewer flow "turned out to be expensive and easy to game"; its evals report roughly twice as fast and almost 50 percent fewer tokens (verified in the installed RELEASE-NOTES.md). It also found one run had put all 26 reviewers on the top-tier model, so every dispatch now names a model; banned the controller from telling reviewers what to ignore; made reviewers read-only; and added a 5-round circuit breaker where the orchestrator rules rather than escalates. It explicitly forbids a second-opinion reviewer. Spec review there is a human conversation, not an agent review.
8. **GitHub Spec Kit** reviews with one read-only `/analyze` pass. **BMAD** runs parallel lenses then a verifying triage step instead of cross-exam plus vote, and ships two tiers: quick (one reviewer, "several times cheaper") for development, thorough for anything with production consequences. **Kiro** uses human approval gates. None of the four mainstream frameworks reviews by debate or vote.
9. **Hermes has shipped no voting or consensus mechanism.** Issue #412 ("Consensus & Voting Engine", opened by the maintainer 2026-03-05) is still open and states "no voting or consensus mechanism exists". The one deliberation attempt, Model Council (PR #84904), merged and was reverted the same day with no stated rationale. Mixture of Agents is synthesis, not voting. `delegate_task` permits identical-goal best-of-N fan-out but "comparing or synthesizing the outputs is left to the parent agent"; Nous's shipped investment is in bounding fan-out (250-iteration cap and 10 concurrent children by default, both confirmed in the installed source; depth limit, stall monitor, per-delegation cost). Confirmed against the installed source: no council code remains. So "Hermes is developing voting" is an open proposal, not a capability to match.
10. **Risk-tiering practice:** tier heavy review by reversibility and blast radius, not size (Clouatre 2026). ByteDance's BitsAI-CR (FSE 2025) deliberately chose precision over recall with a generate-then-filter pipeline because developers ignore high-volume review. GitHub's ReviewBench ensemble A/B: precision up 8 percent, recall up 13.6 percent, comment volume up 61 percent. An ICSE 2025 controlled study found automated review anchors human reviewers to the flagged locations.

**Refuted or unsupported (do not cite):** that debate's benefit comes from model heterogeneity; that self-consistency beats debate at matched spend; that Anthropic scopes fan-out away from coding; that Opus 5 single-pass review has both high precision and recall; that Anthropic's recommended second-opinion shape is specifically a single reviewer rather than a fan-out.

## 3. What this implies for build-fleet

**Keep, unconditionally**

- The fail-closed hooks (source-write block, spec status, stop-tests, reviewer write restriction). This is the layer Anthropic still recommends for anything that must happen every time.
- Spec before code and tests-first BUILD. These specify scope and done conditions, which every current Anthropic page retains.
- The tier classifier and its never-trivial disqualifiers (auth, authz, secrets, billing, data migrations, CI). Do not widen `trivial`; a false trivial skips the gate that would have caught the bug.
- Fresh-context, read-only reviewers that are not the author.
- Exactly one cross-examination round (bias amplifies after round 1).
- Citation-required refutation by a different role. Already in code; it is the one component with measured benefit.
- The 3-cycle bound and escalation, and the v0.9 delta-review rules.

**Cut or retune**

- Rewrite the qa and coder lenses (review.js LENS block, mirrored in agents/qa.md and agents/coder.md; lens-drift and rubric-drift tests move with them) from gap-hunting to "flag only what breaks correctness or a stated acceptance criterion; everything else is minor". This shrinks the surviving-major set at the source, which shrinks the disposition leg and the revise cycle.
- Once the `opus` alias resolves to Opus 5 or later, drop the product-owner's mandated self-review procedure while keeping the "Self-review notes" output block the delta review reads.
- **CHANGE_REVIEW still has the v0.8 bug.** commands/handoff.md fans out architect, product-owner and qa via three Task calls and exits only when "all three approve with no open blockers"; "any reviewer's status: concerns-raised" sends it back to BUILD. That is the all-approved exit condition v0.9 removed from spec review because it could not converge, and the pilot shows the change-review loop ran long too: the convergent-review design doc's table records 5 change cycles on app-skeleton and 3 on domain-schema against a budget of 3. Make the CHANGE_REVIEW exit rubric-only (zero open blockers, majors fixed or ADR'd), the same rule finalize-gate.sh computes.

**Make conditional on tier and risk**

- `standard` tier (the default), config-only step available today: `REVIEW_ROLES` of two (for example architect,qa) and `REVIEW_CYCLE_BUDGET` 1 or 2. Two full lens reviewers cross-examine each other under the existing refute-or-affirm schema; the roster floor is already 2 in review.js because cross-examination needs a different-role refuter. Agent count per cycle becomes 2 fan-out + 2 cross-exam + 0 or 1 disposition + 1 scribe, so 5 or 6 instead of 8. Wall-clock is for the measurement below to establish.
- `standard` tier, proposed schema change to test: replace one lens reviewer with a critic whose only moves are agree / disagree-with-spec-citation / disagree-concern, the three-way verdict from Qiu & Gill. This is not expressible today: `REFUTATION_SCHEMA` in review.js has the enum `refute | affirm` only and no critic lens exists. Treat it as a candidate for the measurement, not a default.
- `large` tier, and any item whose classifier rationale hits a never-trivial disqualifier: the full roster (architect, qa, coder), cross-examination, disposition, budget 3. This is Anthropic's "value high enough to pay for it" case.
- Have the classifier emit a risk flag (reversibility, blast radius) separately from the size tier. Size and stakes are different axes; today the heavy review is keyed on size alone.
- Optionally add a roles=1 path (single rubric-driven fresh-context reviewer, no cross-exam, finalize gate still applies) for standard items with no risk flag. This needs a small review.js change because the current floor is 2 by design.

**Shrink the surface without removing gates**

- superpowers ships 15 skills, 0 agents, 0 commands and 1 hook; build-fleet ships 54 components across 5 kinds. Anthropic's own 80 percent prompt cut worked by relocation into progressively disclosed skills, not deletion. The analogue here is a small set of lifecycle entrypoints (`dispatch`, `status`, `review`, `build`, `handoff`, `triage`) with the lane-specific commands reachable from them and documented in the sdd-protocol skill rather than listed in the slash menu.

**Measure before committing**

- Run the two-role and three-role configurations on the same spec (tap's fixture-and-harness is already migrated) and compare the surviving-major sets and wall-clock. The only evidence that two reviewers lose nothing against three is one unreplicated Sonnet 4.5 run. Record `LAST_REVIEW_OUTPUT_TOKENS` for both.

## 4. Caveats

- No surviving source tests debate or multi-reviewer protocols on Claude-5-class models, and none tests role-specialised spec-citing cross-examination, which is build-fleet's exact leg. Transfer is inference.
- Anthropic's figures are unaudited self-reports; its own eval-noise post puts sub-3-point effects below resolving power.
- The superpowers speed numbers are the maintainer's own evals and come with the caveat that they "won't hold on every harness and for every workload".
- Angle 3 (framework comparison) and angle 4 (Hermes) are answered from primary sources (release notes, GitHub issues and PRs, official docs, installed code) that the workflow's adversarial pass did not vote on because they fell outside its top-25 claim budget.

## 5. Sources

Peer-reviewed / preprint: arXiv 2311.17371 (Smit et al., ICML 2024); arXiv 2502.08788 (Zhang et al., 2025); arXiv 2505.19477 (Ma et al., EMNLP 2025 Findings); arXiv 2608.18167 (Qiu & Gill, ICML 2026 DL4C); arXiv 2501.15134 (BitsAI-CR, FSE 2025); ICSE 2025 "Deep Learning-based Code Reviews: A Paradigm Shift or a Double-Edged Sword?".
Anthropic: anthropic.com/engineering/multi-agent-research-system; platform.claude.com prompting guides for Opus 5, Fable 5 and the cross-model best practices; platform.claude.com agent-skills best-practices; code.claude.com best-practices, workflows, agent-teams, costs; claude.dev "The new rules of context engineering for Claude 5 generation models" and "A harness for every task".
Frameworks: obra/superpowers RELEASE-NOTES.md v6.0.0 to v6.4.1 (also verified locally); docs.bmad-method.org "Review a Change" and "Run multi-agent discussions"; github/spec-kit PR #491; ranjankumar.in "Spec-driven development: invariants not frameworks"; mcp.directory "Superpowers in 2026: still worth it after Fable 5?".
Hermes: NousResearch/hermes-agent issue #412, PR #84904 and revert #84994, issue #135607, releases v0.18.0 to v0.21.6; hermes-agent.nousresearch.com delegation and mixture-of-agents docs; installed source at ~/.hermes/hermes-agent (commit f21b947, 2026-09-29).
Practice: clouatre.ca "AI Approval Gates"; github.blog ReviewBench (2026-10-05); augmentcode.com recall-vs-precision guide.
Local: ~/build-fleet (workflows/review.js, commands/handoff.md, agents/classifier.md, skills/sdd-protocol/SKILL.md, docs/history/2026-09-02-convergent-review.md); ~/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1.
