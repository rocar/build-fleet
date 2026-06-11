# Audit Remediation Implementation Plan (AUDIT-2026-06-09)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all 34 confirmed blocker/major findings and all 32 minor findings from `docs/audits/2026-06-09-ultracode-audit.md`, bringing the build-fleet plugin to professional standard.

**Architecture:** Nine sequential batches matching the audit's §6 order-of-work. Batch 1 lands the license on `main` as v0.5.1 (standalone release); batches 2–8 land on the feature branch (rebased onto main) as one v0.6.0 release; batch 9 is the release cut + full verification. Hooks work is TDD: every gate change gets a test case in the existing hermetic mktemp harness style before the fix.

**Tech Stack:** bash 3.2-compatible shell (hooks/scripts), Claude Code plugin conventions (plugin.json, hooks.json, commands/agents/skills frontmatter), Claude Code dynamic Workflow JS (workflows/*.js), GitHub Actions.

**Spec of record:** `docs/audits/2026-06-09-ultracode-audit.md`. Each task below cites audit item numbers (§3.N = major N, §4 = minors). The executor MUST read the cited audit items and the target files before editing — the audit gives file:line evidence for every item.

**Testing contract (all tasks):** Hook/script tests run directly: `bash hooks/scripts/<name>.test.sh` and `bash scripts/<name>.test.sh` — each prints a PASS/FAIL summary and exits non-zero on failure. The smoke test is `bash docs/v0.5/smoke/smoke.sh`. After T4 exists, `bash scripts/run-tests.sh` runs everything. A task is done only when every suite passes.

---

### Task 1: License to main, cut v0.5.1 (audit §2; §4 author-identity minor)

**Files:**
- Create on `main`: `LICENSE` (MIT, "Copyright (c) 2026 Ray Car")
- Modify on `main`: `.claude-plugin/plugin.json` (add `"license": "MIT"`, bump version 0.5.0→0.5.1), `.claude-plugin/marketplace.json` (bump version if it carries one; add license line), `README.md` (License section at end), `workflows/*.js` (SPDX header line), `CHANGELOG.md` (`[0.5.1]` entry)
- Note: all of these edits already exist as *uncommitted working-tree changes on the feature branch* — they must move to main, not ship buried in the feature branch.

- [ ] **Step 1:** `git stash -u` on `feat/v0.3a-status-snapshot` (captures LICENSE + the license-field/SPDX/README edits; docs/audits/2026-06-09-ultracode-audit.md and the plan file ride along, that's fine).
- [ ] **Step 2:** `git checkout main && git stash pop`. Resolve trivially if README context differs (main lacks e679b49). Keep `docs/audits/2026-06-09-ultracode-audit.md` and `docs/superpowers/plans/` out of this commit (they get committed on the feature branch later).
- [ ] **Step 3:** Bump `.claude-plugin/plugin.json` version to `0.5.1`; mirror in `.claude-plugin/marketplace.json` if it pins a version. Add a `[0.5.1] - 2026-06-10` CHANGELOG entry: "Added: MIT LICENSE file, license field in plugin.json, SPDX headers. No functional changes."
- [ ] **Step 4:** Verify: `jq -e '.license == "MIT" and .version == "0.5.1"' .claude-plugin/plugin.json` and `test -f LICENSE`.
- [ ] **Step 5:** Commit on main: `chore(release): v0.5.1 — add MIT license (audit §2)`. Tag `v0.5.1` (annotated, local — push left to the human).
- [ ] **Step 6:** `git checkout feat/v0.3a-status-snapshot && git rebase main`. Re-add the untracked `docs/audits/2026-06-09-ultracode-audit.md` + plan file if stash juggling moved them; commit them on the feature branch: `docs: check in the 2026-06-09 ultracode audit + remediation plan`.

### Task 2: Manifests, CHANGELOG backfill, README requirements, repo hygiene (audit §3.30, §3.31-docs-half, §3.4-README-half, §3.5-README-half, §3.21-plugin.json-half; §4 manifests/hygiene minors)

**Files:**
- Modify: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.gitignore`, `.claude/settings.json`
- Move: `V0.2-PLAN.md` → `docs/history/V0.2-PLAN.md`
- Create: `.claude/settings.local.json` entry note (gitignored)

- [ ] **Step 1 (§3.30):** Backfill a `[0.4.0]` CHANGELOG entry between [0.2.1] and [0.5.0] from `git log v0.2.1..v0.4.0 --oneline` + README's product-tier docs. Note explicitly: "0.3.0 was never released; ROADMAP v0.3x items ship in later versions."
- [ ] **Step 2 (§3.4, §3.5):** README Requirements section: add `jq` (used by every gate hook + status-snapshot.sh), `bash` (all hooks; Windows requires Git Bash/WSL — the gate layer does not run without it), `git`.
- [ ] **Step 3 (§3.21 partial):** Rewrite `plugin.json` `description` to ≤2 sentences (currently 1,109 chars of changelog prose). E.g.: "Spec-driven multi-agent software house: product-owner/architect/coder/qa/devops subagents executing a hook-gated SPEC→REVIEW→FINALIZE→BUILD→CHANGE_REVIEW→HANDOFF state machine, with a product planning tier and a reproducing-test-gated bug lane. Deterministic gates, bounded review cycles, first-class human escalation, headless orchestrator support."
- [ ] **Step 4 (§4):** `plugin.json`: add `homepage`/`repository` (https://github.com/rocar/build-fleet) and `keywords`. `marketplace.json`: drop duplicated `version`/`description` (inherit from plugin.json), keep/unify author identity across plugin.json/marketplace.json/LICENSE.
- [ ] **Step 5 (§4):** `.gitignore`: add `.pytest_cache/` and `__pycache__/`; `git rm -r --cached .pytest_cache`. Move `enabledPlugins` from `.claude/settings.json` to (gitignored) `.claude/settings.local.json`; add `.claude/settings.local.json` to `.gitignore` if absent.
- [ ] **Step 6 (§4):** `git mv V0.2-PLAN.md docs/history/V0.2-PLAN.md`; fix any references (`grep -rn "V0.2-PLAN" --include="*.md" .`).
- [ ] **Step 7 (§4):** CHANGELOG.md:13 cites gitignored `.sdd/troubleshoot-fix/` as "spec of record" — snapshot that dir into `docs/v0.5/troubleshoot-fix-spec/` and repoint the citation.
- [ ] **Step 8 (§4):** Add README "Release channel" line: main always equals the latest tag. (CI check lands in T4.)
- [ ] **Step 9:** Run `bash docs/v0.5/smoke/smoke.sh` + all existing `*.test.sh`; commit: `chore(audit): manifests, changelog backfill, requirements, repo hygiene (§3.30, §4)`.

### Task 3: Hook hardening (audit §3.1–§3.6; §4 hook minors) — TDD, one commit

**Files:**
- Modify: `hooks/scripts/_lib.sh`, `hooks/hooks.json`, `hooks/scripts/block-source-before-finalized.sh`, `hooks/scripts/require-reproducing-test.sh`, `hooks/scripts/restrict-reviewer-writes.sh`, `hooks/scripts/stop-tests.sh`, `hooks/scripts/check-review-written.sh`
- Create: `hooks/scripts/guard-bash-writes.sh` (+ `.test.sh`)
- Test: extend `block-source-before-finalized.test.sh`, `require-reproducing-test.test.sh`; new test files as listed

For every step: write the failing test case first in the existing harness style (mktemp repo, stdin JSON matching the real hook contract, assert exit code + stderr), run it red, fix, run green.

- [ ] **Step 1 (§3.1):** Path traversal. In `_lib.sh` `path_in_sdd`/`path_in_active_sdd`/`path_in_tests`, reject any `..` segment before the glob match:
  ```bash
  case "$p" in */../*|../*|*/..|..) return 1 ;; esac
  ```
  Tests: `.sdd/../src/app.py`, `tests/../src/app.py`, `..`, `.sdd/..` → blocked, in both gate test suites.
- [ ] **Step 2 (§3.3):** cwd anchoring. Top of `_lib.sh` (after the shebang/source guard): `cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0` so `.sdd/ACTIVE` and all relative paths resolve at the project root. Test: run gate from a subdir of the fixture with `CLAUDE_PROJECT_DIR` set → still blocks.
- [ ] **Step 3 (§3.4):** jq fail-closed. `require_jq` in `_lib.sh`: when jq is missing during an active feature, `echo "build-fleet: jq is required by the gate hooks — install jq (brew install jq / apt install jq)" >&2; exit 2`. Keep exit 0 when no feature is active. Test: `PATH` stripped of jq + active feature → exit 2.
- [ ] **Step 4 (§3.5):** Fail closed on unexpected errors, in every *blocking* PreToolUse gate script (block-source-before-finalized, require-reproducing-test, restrict-reviewer-writes, validate-spec-status, validate-diagnosis-status, validate-backlog-status):
  ```bash
  trap 'echo "build-fleet: gate script errored unexpectedly — failing closed" >&2; exit 2' ERR
  ```
  placed after `set -euo pipefail`. Deliberate allows remain explicit `exit 0`. Fault-injection test: corrupt PROGRESS.md/unreadable spec → exit 2, not 1.
- [ ] **Step 5 (§3.2):** New `hooks/scripts/guard-bash-writes.sh` registered in hooks.json under PreToolUse `"matcher": "Bash"`: while the active lane is in a source-locked phase (same condition block-source-before-finalized uses), block Bash commands matching write-to-source patterns (`>`/`>>` redirection outside `.sdd/` & `tests/`, `tee`, `cp/mv/install` with a non-`.sdd`/non-`tests` destination, `sed -i`, `patch`, heredoc into source). Conservative: block on match, allow otherwise; message tells the agent to use Write/Edit so the gates can adjudicate. Also extend the existing gates' matcher to `"Write|Edit|NotebookEdit"` and parse `.tool_input.notebook_path // .tool_input.file_path` in `_lib.sh`'s extractor. Tests: heredoc-to-src blocked in DRAFT, `ls` allowed, NotebookEdit to src blocked, NotebookEdit to `.sdd/` allowed.
- [ ] **Step 6 (§3.6):** `stop-tests.sh`: read stdin JSON, exit 0 immediately when `stop_hook_active` is true; maintain `.sdd/<slug>/.stop-test-retries` counter — on the 3rd consecutive red-suite block, append ESCALATION.md (existing escalation format), emit the escalation message, exit 0 (stop allowed, escalated); delete the counter on a green run. Honor an operator override: `.sdd/<slug>/.skip-stop-tests` flag file → exit 0 with a one-line warning. Add `"timeout": 300` to the Stop entry in hooks.json. Tests: loop-guard respected; counter escalates at 3; override file works; green run clears counter.
- [ ] **Step 7 (§4 hook minors):** `check-review-written.sh`: scope its hooks.json SubagentStop entry with a reviewer-name matcher, use the documented `agent_type` field, validate `cycle` is an integer. `stop-tests.sh`: make the project-type detection independent fall-throughs (package.json AND pytest AND make all run if present) or honor an explicit `TEST_CMD` in `.sdd/<slug>/PROGRESS.md`. `block-source-before-finalized.sh` header + hooks.json description: say "blocks all non-.sdd, non-tests writes" (not "source").
- [ ] **Step 8:** Run every hook suite; commit: `fix(hooks): close traversal/Bash/cwd/jq/ERR bypasses, bound stop-tests, fail closed (§3.1-6)`.

### Task 4: Test infrastructure (audit §3.8; §4 severity-rubric drift test, release-channel CI check)

**Files:**
- Create: `scripts/run-tests.sh`, `.github/workflows/ci.yml`, `hooks/scripts/{restrict-reviewer-writes,check-review-written,stop-tests,reap-stale-workflow-markers,validate-backlog-status,validate-spec-status}.test.sh`, `scripts/rubric-drift.test.sh`
- Modify: `README.md` (Development section)

- [ ] **Step 1:** `scripts/run-tests.sh`:
  ```bash
  #!/usr/bin/env bash
  set -u
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fail=0; total=0
  for t in "$root"/hooks/scripts/*.test.sh "$root"/scripts/*.test.sh; do
    [ -f "$t" ] || continue
    total=$((total+1))
    echo "── $t"
    bash "$t" || fail=$((fail+1))
  done
  echo "── smoke"
  total=$((total+1)); bash "$root/docs/v0.5/smoke/smoke.sh" || fail=$((fail+1))
  echo "suites: $total, failed: $fail"
  exit $((fail > 0))
  ```
- [ ] **Step 2:** Test suites for the six uncovered hooks, in the existing harness style (see `block-source-before-finalized.test.sh` for the pattern), priority order: `validate-spec-status` (full suite, currently one incidental case), `restrict-reviewer-writes` (incl. the marker-skip path), `check-review-written` (empty review rejected; cycle integer), `stop-tests` (builds on T3 step 6 cases), `reap-stale-workflow-markers` (fresh marker kept, stale reaped), `validate-backlog-status`. Each ≥6 cases covering allow, block, malformed-input, and the T3 hardening behaviors.
- [ ] **Step 3 (§4 agents minor):** `scripts/rubric-drift.test.sh`: diff the severity-rubric table block extracted from `agents/architect.md`, `agents/qa.md`, `skills/review-rubric/SKILL.md` — fail on drift.
- [ ] **Step 4:** `.github/workflows/ci.yml`: on push/PR, matrix `[macos-latest, ubuntu-latest]`, steps: install jq, `bash scripts/run-tests.sh`; plus a release-channel job on main asserting `jq -r .version .claude-plugin/plugin.json` equals the latest `v*` tag.
- [ ] **Step 5:** README "Development" section: how to run the tests, harness conventions, CI badge optional.
- [ ] **Step 6:** `bash scripts/run-tests.sh` → all green; commit: `test(audit): run-tests entrypoint, CI matrix, suites for the six untested gates (§3.8)`.

### Task 5: Workflow correctness (audit §3.9–§3.15; §4 workflow + cycle-budget minors)

**Files:**
- Modify: `workflows/review.js`, `workflows/deep-build.js`, `workflows/diagnose.js`, `workflows/plan-review.js`, `commands/review.md`, `commands/deep-build.md`, `commands/finalize.md`, `hooks/scripts/reap-stale-workflow-markers.sh`, `agents/scribe.md`, `README.md` (workflow count)
- Delete: `workflows/hello.js` (notes → `docs/v0.2/hello-probe.md`)

- [ ] **Step 1 (§3.9):** Add `"now": "<iso8601>"` to the dispatch specs in `commands/review.md:48`, `commands/deep-build.md:53`, `commands/finalize.md:186` (copy the working pattern from `diagnose.md:82`). In all four workflow scripts, fail args-validation when `now` is absent (deep-build.js:45's message already claims it's required — make it true). Remove the `"UNKNOWN_TIME"` fallback.
- [ ] **Step 2 (§3.10):** Replace `estimatedCost` parsing instructions with the `@cost-ceiling` header-comment contract in `review.md:38`, `deep-build.md:45`, `finalize.md:179` (copy wording from `diagnose.md:74`).
- [ ] **Step 3 (§3.11):** deep-build.js: accept a `cycle` arg backed by a `BUILD_CYCLE` field in PROGRESS.md (mirror CHANGE_CYCLE); escalate at the cycle budget exactly like review.js:160; wire or delete the dead `escalate` branches at lines 396/408/415-416; `needs-iteration` envelope carries the remaining budget.
- [ ] **Step 4 (§3.12):** In all four `applyScribe` call sites (review.js:171, deep-build.js:270, diagnose.js:160, plan-review.js:152): give the scribe agent a structured-output schema (or check the `SCRIBE_OK:` prefix per scribe.md's contract), retry once on failure, then surface `scribe_apply: "failed"` in the workflow return object so the dispatching command refuses instead of reporting success.
- [ ] **Step 5 (§3.13):** Port plan-review.js:107-132's `cleanupEnvelope` pattern (verdict `incomplete`, PHASE/CYCLE untouched, marker removed, "re-run" guidance) to review.js:124-131, diagnose.js:107-115, deep-build.js:191-198 for null/missing agent payloads. ESCALATED is reserved for genuine cycle exhaustion. deep-build's incomplete message must tell the human partial writes may exist in the worktree.
- [ ] **Step 6 (§3.14):** Marker lifecycle: dispatch commands write the workflow runId into `.workflow-in-flight`; the scribe deletes only a marker whose runId matches; workflow args-validation failures return a structured `invalid-args` verdict *after* dispatching a minimal scribe cleanup envelope (never a bare throw); dispatch commands poll the launched run and delete the marker themselves on early failure; lower `reap-stale-workflow-markers.sh:21` threshold to 900s.
- [ ] **Step 7 (§3.15):** Delete `workflows/hello.js`; move its probe findings note into `docs/v0.2/hello-probe.md`; fix README's workflow count (already says four — verify it's accurate after deletion).
- [ ] **Step 8 (§4):** Citation gating: add a structured `citation: {file, locator}` field to the reviewer schemas in review.js:260 and diagnose.js:222,265; validate presence in JS rather than regexing for `§`/`tests/`. Cycle-budget off-by-one: align review.js/diagnose.js code and prose (SKILL.md:23-26, review.md:32) on "escalate when a cycle would exceed 3" — pick the code's semantics and fix the prose.
- [ ] **Step 9:** `node --check workflows/*.js`; run suites + smoke; commit: `fix(workflows): now/cost contracts, cycle bounds, scribe verification, cleanup-not-escalate, marker ownership (§3.9-15)`.

### Task 6: Command safety (audit §3.22–§3.29; §4 command minors)

**Files:**
- Modify: `commands/plan-finalize.md`, `commands/handoff.md`, `commands/status.md`, `commands/verify.md`, `commands/finalize.md`, `commands/next-feature.md`, `commands/new-feature.md`, `commands/product-memory.md`, `commands/{review,deep-build,diagnose,dispatch,plan-review,plan-finalize,next-feature,product-memory}.md` (exit-code tables), `docs/v0.2/CONTRACT.md`, `agents/qa.md`, `skills/sdd-protocol/SKILL.md` (verify pattern refs)
- Create: `commands/build.md`, `commands/park.md`, `commands/resolve-escalation.md`, `scripts/intent-block.sh` (+ `.test.sh`), `scripts/product-memory-splice.sh` (+ `.test.sh`)

- [ ] **Step 1 (§3.22):** `disable-model-invocation: true` on plan-finalize.md. Evaluate handoff.md/ship-fix.md: they are orchestrator-dispatched in the DEVELOPING loop, so leave model-invocable but document why in a frontmatter comment.
- [ ] **Step 2 (§3.23):** `allowed-tools: Read, Write, Edit, Bash, Task` on handoff.md; `allowed-tools: Read, Bash(bash:*)` scoped to the two resolver scripts on status.md (copy the scoping idiom from ship-fix.md/next-feature.md).
- [ ] **Step 3 (§3.24):** Delete every exit-code table (eight commands + CONTRACT.md:610-619). Extend the `BUILD_FLEET_REFUSE` signal JSON with `{"code": <int>, "reason": "<slug>"}` and state in each command + CONTRACT.md that the `BUILD_FLEET_*` signal lines are the sole machine contract.
- [ ] **Step 4 (§3.25):** Split finalize.md: keep the gate + STATUS flip (idempotent); move step 6's ~160 lines of build orchestration into new `commands/build.md` (`/build-fleet:build` — qa→coder dispatch + BUILD_MODE routing, preconditions: STATUS=FINALIZED). finalize's success message points to `/build-fleet:build`. Update cross-references (`grep -rn "finalize" commands/ skills/ README.md`).
- [ ] **Step 5 (§3.26):** `scripts/intent-block.sh`: stdin = backlog row / feature args, stdout = the canonical intent block + `INTENT_VERDICT: usable|too-thin` line; next-feature.md and new-feature.md both call it; keep one prose definition of the quality floor in sdd-protocol. Tests: usable row, too-thin row, malformed row.
- [ ] **Step 6 (§3.27):** New `commands/park.md` (`/build-fleet:park`): requires confirmation arg, empties `.sdd/ACTIVE`, appends `PARKED <timestamp> <reason>` to PROGRESS.md, emits `BUILD_FLEET_PARKED` signal — the sanctioned sev0-preemption path. New `commands/resolve-escalation.md`: archives ESCALATION.md content into REVIEW.md (append-only), deletes ESCALATION.md, resets the relevant cycle counter in PROGRESS.md, requires an explicit human-decision arg, emits `BUILD_FLEET_RESOLVED`. Update triage.md:31, diagnose.md:36-37, status.md:59-60 to point at them.
- [ ] **Step 7 (§3.28):** verify.md (and qa.md:125-128, sdd-protocol:554-556): before the counterfactual, record `git stash create` SHA (or temp-branch commit) in IMPL_NOTES.md; qa operates against that ref; orchestrator verifies `git status` matches the pre-counterfactual snapshot before evaluating the verdict; forbid the bare-`git checkout` variant.
- [ ] **Step 8 (§3.29):** `scripts/product-memory-splice.sh`: reads the new block on stdin, splices between `<!-- build-fleet:begin -->`/`<!-- build-fleet:end -->` markers in the target CLAUDE.md. Tests: no-file, block-present, block-absent, missing-END (error, no write), duplicate-final-line. product-memory.md calls the script instead of model-driven Edits.
- [ ] **Step 9 (§4 command minors):** frontmatter pass — drop empty `argument-hint`s, pin `model:` on read-only commands, scope Bash grants (finalize.md:4, status.md:3, fix.md:4); adopt `!`-preamble for cheap read-only state loads (status.md:13). Namespacing rename: **deferred** per the audit's own advice (breaking) — add a ROADMAP note instead.
- [ ] **Step 10:** Run `bash scripts/run-tests.sh`; commit: `feat(commands): safety frontmatter, honest refuse contract, finalize/build split, park + resolve-escalation, scripted splices (§3.22-29)`.

### Task 7: Documentation truth (audit §3.7-agents-half, §3.16–§3.21; §4 skill + agent minors)

**Files:**
- Modify: `skills/sdd-protocol/SKILL.md`, `skills/adr/SKILL.md`, `skills/sdd-spec-template/SKILL.md`, `skills/test-plan/SKILL.md`, `skills/review-rubric/SKILL.md`, `skills/skill-routing/SKILL.md`, `agents/{architect,coder,qa,devops,scribe,classifier}.md`, `CLAUDE.md`, commands/* descriptions
- Create: `skills/sdd-protocol/references/product-tier.md`, `skills/sdd-protocol/references/bug-lane.md`, `docs/history/DESIGN-SPEC-v0.1.md` (archived CLAUDE.md)

- [ ] **Step 1 (§3.16+§3.17):** Restructure sdd-protocol: SKILL.md keeps principles, workspace layout, PROGRESS schema, state machine, hard gates, escalation (~250 lines, present tense, no vN.N/MN milestone references); product tier → `references/product-tier.md`; bug lane → `references/bug-lane.md`; one-line pointers in SKILL.md. Delete the classifier contradiction (lines 718-739 stale paragraph); fix five-vs-four phase count (SKILL.md:662-663) against review.js; fix unnamespaced `/finalize`,`/handoff` (lines 694,758) → `/build-fleet:` forms; align cycle-budget prose with the T5 step 8 decision.
- [ ] **Step 2 (§3.18):** adr skill: add both ADR homes (`.sdd/<feature>/DECISIONS.md`, `.sdd/_product/DECISIONS.md`), `PROVISIONAL` status + promotion rule (ratified at plan-review or explicit human edit), product-scope ID rule, `Cycle:` conditional on feature scope.
- [ ] **Step 3 (§3.19):** Agent descriptions: enumerate bug-lane triggers in architect/coder/qa/devops descriptions, classifier-style; fix devops.md:3's "only after handoff" contradiction with its ship-fix role.
- [ ] **Step 4 (§3.7):** architect.md:143-144 and qa.md: state truthfully that BUILD/HANDOFF write-restraint is prompt-enforced (the hook only fires in REVIEW|CHANGE_REVIEW) — or, if T3 added phase-scoped enforcement, describe exactly what is enforced.
- [ ] **Step 5 (§3.20):** Replace root CLAUDE.md with current contributor instructions: actual layout (7 agents in `agents/`, hooks via `hooks/hooks.json`), how to run tests/smoke, the release checklist (tag + plugin.json + marketplace.json + CHANGELOG + README counts + agent descriptions move together), `.sdd/` policy pointer. Archive the v0.1 design spec to `docs/history/DESIGN-SPEC-v0.1.md`.
- [ ] **Step 6 (§3.21):** Jargon strip: every command `description:` ≤ ~60 chars imperative; remove M-numbers/AC-tags/B-numbers from command bodies and agent prompts (`coder.md:61`, `product-owner.md:38,71`, `qa.md:80`, `scribe.md:18`, `finalize.md:16-27`, `new-feature.md:39`, `diagnose.md:51`, `next-feature.md:2`, `deep-build.md:2`); name behaviors, not milestones.
- [ ] **Step 7 (§4 skills minors):** sdd-spec-template STATUS-line placement stated once (line-start within first 30 lines, matching the hook); test-plan/SKILL.md:29-77 four-backtick outer fence fix; trim version lore from review-rubric + skill-routing descriptions; skill-routing:35-38,142 states the precise loading mechanism (Skill tool; `AgentDefinition.skills` preload for workflow dispatch).
- [ ] **Step 8 (§4 agents minors):** add `color:` per role; "Use this agent when…" descriptions with negative triggers for coder/qa; slim classifier.md under 10KB (manifest-rule detail → skill-routing); fix scribe.md:5,136 false "strictest allowlist" claim and replace its Bash `rm` with a workflow-step or hook-reaped sentinel.
- [ ] **Step 9:** `bash scripts/run-tests.sh` (rubric-drift test guards the T7 edits); commit: `docs(audit): truth pass — sdd-protocol restructure, adr PROVISIONAL, agent descriptions, CLAUDE.md rewrite, jargon strip (§3.16-21)`.

### Task 8: Team/concurrency + operational policies (audit §3.32; §4 remaining minors)

**Files:**
- Create: `scripts/acquire-active.sh` (+ `.test.sh`)
- Modify: `commands/new-feature.md`, `commands/triage.md`, `commands/new-product.md`, `hooks/scripts/_lib.sh` (if ACTIVE format gains owner metadata), `skills/sdd-protocol/SKILL.md` (policy section), `README.md`, `CHANGELOG.md`, `scripts/status-snapshot.sh` docs

- [ ] **Step 1:** `scripts/acquire-active.sh`: atomic acquisition via `set -o noclobber` create of `.sdd/ACTIVE.lock` (owner pid/session + slug inside), then write ACTIVE; release/steal rules documented in the header; `--release` and `--status` modes. Tests: concurrent double-acquire (one wins), release, stale-lock detection.
- [ ] **Step 2:** new-feature.md/triage.md call the script instead of check-then-write prose.
- [ ] **Step 3:** Publish the `.sdd/` git policy (sdd-protocol + README): commit artifacts + `_product/`; ignore `ACTIVE`, `ACTIVE.lock`, `.workflow-in-flight`, `.stop-test-retries`; `/new-product` scaffolds `.sdd/.gitignore` accordingly.
- [ ] **Step 4:** Schema-version stamps: scaffolded PROGRESS.md/spec.md/diagnosis.md get `SDD_SCHEMA: 1`; CHANGELOG gains a per-release Compatibility/Migration section ("finish or park in-flight items before major upgrades"); document the single-driver-per-worktree assumption until locking covers multi-repo.
- [ ] **Step 5 (§4 remaining):** README "Polling / orchestrator integration" section for the status-snapshot schema incl. the vendor/copy path (`${CLAUDE_PLUGIN_ROOT}` unusable by external pollers); stability/deprecation policy paragraph for the `BUILD_FLEET_*` signal grammar (generalize the `@1` versioning).
- [ ] **Step 6:** `bash scripts/run-tests.sh`; commit: `feat(ops): atomic ACTIVE acquisition, .sdd git policy, schema stamps, orchestrator docs (§3.32)`.

### Task 9: Release v0.6.0 + final verification (audit §3.31)

**Files:**
- Modify: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`, `README.md`, `ROADMAP.md`
- Move: `docs/audits/2026-06-09-ultracode-audit.md` → `docs/audits/2026-06-09-ultracode-audit.md`

- [ ] **Step 1:** Re-run the full gauntlet: `bash scripts/run-tests.sh` (every suite + smoke) and `node --check workflows/*.js`. All green or the task stops here.
- [ ] **Step 2:** Sweep for stale counts/references: README component counts (workflows=4, hooks, skills, commands incl. build/park/resolve-escalation), `grep -rn "hello.js\|estimatedCost\|UNKNOWN_TIME" --include="*.md" --include="*.js" .` → zero hits outside docs/history + docs/audits.
- [ ] **Step 3:** Bump plugin.json + marketplace.json to `0.6.0`; write the `[0.6.0]` CHANGELOG entry (map ROADMAP v0.3a → 0.6.0; Compatibility section per T8); update ROADMAP.
- [ ] **Step 4:** `git mv docs/audits/2026-06-09-ultracode-audit.md docs/audits/2026-06-09-ultracode-audit.md`; commit everything: `chore(release): v0.6.0 — audit remediation complete`.
- [ ] **Step 5:** Report to the human: branch state, local tag v0.5.1 on main, v0.6.0 ready to tag on merge; pushing main/tags and opening the PR is theirs to trigger.

---

## Self-review notes

- Audit coverage check: §2→T1; §3.1-6→T3; §3.7→T7(+T3); §3.8→T4; §3.9-15→T5; §3.16-21→T7(+T2 for plugin.json desc); §3.22-29→T6; §3.30→T2; §3.31→T2+T9; §3.32→T8; §4 manifests→T2, skills→T7, hooks→T3, agents→T7(+T4 drift test), commands→T6 (namespacing deferred per audit), workflows→T5. All 34 majors + 32 minors mapped; the single deliberately-deferred item (command namespacing rename) is per the audit's own "stage it" guidance and gets a ROADMAP note in T6.
- Sequencing: T3 before T4 (tests cover hardened behavior); T5 before T6 (commands reference workflow contracts); T7 after T5/T6 (docs describe final behavior); T9 last.
