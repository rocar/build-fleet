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

# ---- flow (§3.3) ----
want new-feature-field     commands/new-feature.md '   DRIFT_GATE: on'
want implement-calls-gate  commands/implement.md   'scripts/drift-gate.sh'
want implement-b2          commands/implement.md   'b2. **Drift gate (before coder).**'
want implement-e2          commands/implement.md   'e2. **Drift gate (after coder).**'
want implement-repair-mode commands/implement.md   '**Repair mode.**'
want implement-fail-line   commands/implement.md   'BUILD_FLEET_QA_VERIFY_FAIL: {"feature":"<slug>","reason":"drift","gate":'
want implement-qa-fail     commands/implement.md   'QA_FAIL: drift' 3
want implement-incomplete  commands/implement.md   '"reason":"drift-repair"'
want implement-repair-phase commands/implement.md   "In repair mode (\`QA_FAIL: drift\`), \`PHASE\` may also be \`CHANGE_REVIEW\` or \`HANDOFF\`"
want handoff-calls-gate    commands/handoff.md     'scripts/drift-gate.sh'
want handoff-refuse        commands/handoff.md     'BUILD_FLEET_HANDOFF_REFUSE: {"feature":"<slug>","code":2,"reason":"drift","gate":'
want handoff-resume        commands/handoff.md     'run the drift gate (step 4) and, if it passes, skip straight to step 9'
want handoff-refusal-case  commands/handoff.md     '- The drift gate fails'

# ---- docs and qa's prompt (§3.4) ----
want qa-description   agents/qa.md                  'and its repair pass when the drift gate fails'
want qa-body          agents/qa.md                  'The drift gate (`scripts/drift-gate.sh`)'
want skill-section    skills/test-plan/SKILL.md     '## The drift gate'
want skill-name-rule  skills/test-plan/SKILL.md     'as declared in source'
want protocol-gate    skills/sdd-protocol/SKILL.md  'DRIFT_GATE: on | off'
want protocol-qafail  skills/sdd-protocol/SKILL.md  'QA_FAIL: drift'
want protocol-build   skills/sdd-protocol/SKILL.md  '**Drift gate.**'
want contract-line    docs/v0.2/CONTRACT.md         'BUILD_FLEET_DRIFT_GATE: {'
want contract-summary docs/v0.2/CONTRACT.md         'BUILD_FLEET_DRIFT_GATE_SUMMARY: {'
want contract-refuse  docs/v0.2/CONTRACT.md         'BUILD_FLEET_HANDOFF_REFUSE: {'
want contract-stop    docs/v0.2/CONTRACT.md         '`drift` (the test plan failed the drift gate'
want readme-ci        README.md                     'scripts/drift-gate.sh --all'
want claude-md        CLAUDE.md                     'drift-gate'
want changelog        CHANGELOG.md                  '`scripts/drift-gate.sh`'
want smoke            docs/v0.5/smoke/smoke.sh      'echo "[DRIFT]"'

printf '\npassed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
