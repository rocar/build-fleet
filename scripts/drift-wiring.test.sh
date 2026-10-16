#!/usr/bin/env bash
# Wiring for the drift gate (docs/history/2026-10-15-drift-gate.md §3.3–3.4): asserts
# each firing point, field and signal is written where the spec puts it, so a later
# edit cannot drop one silently. Run: bash scripts/drift-wiring.test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
# want <name> <file> <fixed string> [min count]
want() {
  local c; c=$(grep -cF -- "$3" "$ROOT/$2" 2>/dev/null || true)
  if [ "${c:-0}" -ge "${4:-1}" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$1"
  else fail=$((fail+1)); printf 'FAIL %s — %s lacks [%s] (x%s, found %s)\n' "$1" "$2" "$3" "${4:-1}" "${c:-0}"; fi
}

# wantnot <name> <file> <fixed string> — the string must NOT appear
wantnot() {
  if grep -qF -- "$3" "$ROOT/$2" 2>/dev/null; then fail=$((fail+1)); printf 'FAIL %s — %s still has [%s]\n' "$1" "$2" "$3"
  else pass=$((pass+1)); printf 'ok   %s\n' "$1"; fi
}

# ---- four-file layout (final review) ----
wantnot handoff-no-spec-append   commands/handoff.md   '## Implementation'
want    handoff-ship-fields      commands/handoff.md   'SHIPPED_CHANGE_CYCLE:'
want    deep-build-started-always commands/deep-build.md 'set `BUILD_STATE: started` on every dispatch'
want    qa-test-roots            agents/qa.md          'TEST_ROOTS'
want    implement-test-roots     commands/implement.md 'TEST_ROOTS'
want    implement-markers-mode   commands/implement.md 'drift-gate.sh" --markers <slug>'
wantnot implement-rows-wording   commands/implement.md 'the rows the gate names'

# ---- 0.12.1: repair re-entry, signal wording, notes ----
want    implement-stops-set-qa-fail commands/implement.md 'every stop in steps b2 and e2 sets `QA_FAIL: drift`'
want    implement-repair-gate-first commands/implement.md 'First run the drift gate'
wantnot implement-tests-in-tests    commands/implement.md 'tests in tests/'
want    implement-e2-count          commands/implement.md 'passing tests under the test roots'
want    implement-notes-null        commands/implement.md '"impl_notes_path":null'
want    implement-repair-recorded   commands/implement.md 'DRIFT_REPAIR:'
want    handoff-review-header       commands/handoff.md   'create it with the standard append-only header'
wantnot qa-tests-in-tests           agents/qa.md          'tests in tests/'
wantnot protocol-tests-in-tests     skills/sdd-protocol/SKILL.md 'tests in tests/'
want    coder-no-empty-notes        agents/coder.md       'If there is nothing to list, write nothing'

# ---- 0.12.1: review blocks are findings only — no prose about a status: line ----
wantnot status-no-status-value   commands/status.md          '`status:` line value'
wantnot status-no-status-eval    commands/status.md          '`status:` lines are not evaluated'
wantnot handoff-no-status-info   commands/handoff.md         '`status:` is informational'
wantnot handoff-no-status-eval   commands/handoff.md         '`status:` lines are never evaluated'
wantnot finalize-no-status-info  commands/finalize.md        '`status:` lines are informational'
wantnot protocol-no-status-info  skills/sdd-protocol/SKILL.md '`status:` is informational'

want    finalize-lists-unparsed   commands/finalize.md  '`unparsed-findings` — a reviewer block holds a finding bullet the gate cannot read'
want    implement-repair-no-count commands/implement.md 'with no count to compare'

# ---- flow (§3.3) ----
want new-feature-schema    commands/new-feature.md '   SDD_SCHEMA: 2'
want implement-calls-gate  commands/implement.md   'scripts/drift-gate.sh'
want implement-b2          commands/implement.md   'b2. **Drift gate (before coder).**'
want implement-e2          commands/implement.md   'e2. **Drift gate (after coder).**'
want implement-repair-mode commands/implement.md   '**Repair mode.**'
want implement-fail-line   commands/implement.md   'BUILD_FLEET_QA_VERIFY_FAIL: {"feature":"<slug>","reason":"drift","gate":'
want implement-qa-fail     commands/implement.md   'QA_FAIL: drift' 3
want implement-incomplete  commands/implement.md   '"reason":"drift-repair"'
want implement-repair-phase commands/implement.md   "In repair mode (\`QA_FAIL: drift\`), \`PHASE\` may also be \`CHANGE_REVIEW\` or \`HANDOFF\`"
want implement-repair-path  commands/implement.md   '`BUILD_STATE` absent and `PHASE` `BUILD` → the repair pass of step b2'
want implement-repair-phase-reset commands/implement.md 'in repair mode at `PHASE` `CHANGE_REVIEW` or `HANDOFF`, also set `PHASE: BUILD`'
want handoff-calls-gate    commands/handoff.md     'scripts/drift-gate.sh'
want handoff-refuse        commands/handoff.md     'BUILD_FLEET_HANDOFF_REFUSE: {"feature":"<slug>","code":2,"reason":"drift","gate":'
want handoff-resume        commands/handoff.md     'run the drift gate (step 4) and, if it passes, skip straight to step 9'
want handoff-refusal-case  commands/handoff.md     '- The drift gate fails'

# ---- docs and qa's prompt (§3.4) ----
want qa-description   agents/qa.md                  'repairing it after a drift-gate failure'
want qa-body          agents/qa.md                  'The drift gate (`scripts/drift-gate.sh`)'
want protocol-marker  skills/sdd-protocol/SKILL.md  'is named by a `<slug>/AC-<n>` marker in a test file'
want implement-marker commands/implement.md         'each test with a `<slug>/AC-<n>` comment (on or above it)'
want template-section skills/sdd-spec-template/SKILL.md 'qa marks each test with `<slug>/AC-<n>`'
want protocol-gate    skills/sdd-protocol/SKILL.md  'DRIFT_GATE: on | off'
want protocol-roots   skills/sdd-protocol/SKILL.md  'TEST_ROOTS: <csv>'
want protocol-qafail  skills/sdd-protocol/SKILL.md  'QA_FAIL: drift'
want protocol-build   skills/sdd-protocol/SKILL.md  '**Drift gate.**'
want contract-line    docs/v0.2/CONTRACT.md         'BUILD_FLEET_DRIFT_GATE: {'
want contract-summary docs/v0.2/CONTRACT.md         'BUILD_FLEET_DRIFT_GATE_SUMMARY: {'
want contract-refuse  docs/v0.2/CONTRACT.md         'BUILD_FLEET_HANDOFF_REFUSE: {'
want contract-stop    docs/v0.2/CONTRACT.md         '`drift` (the tests'"'"' criterion markers failed the drift gate'
want readme-ci        README.md                     'scripts/drift-gate.sh --all'
want readme-shipped        README.md                     'For a shipped feature, fix the marker or test the line names'
want claude-md        CLAUDE.md                     'drift-gate'
want changelog        CHANGELOG.md                  '`scripts/drift-gate.sh`'
want smoke            docs/v0.5/smoke/smoke.sh      'echo "[DRIFT]"'

printf '\npassed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
