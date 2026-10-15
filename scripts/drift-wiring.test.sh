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
want handoff-calls-gate    commands/handoff.md     'scripts/drift-gate.sh'
want handoff-refuse        commands/handoff.md     'BUILD_FLEET_HANDOFF_REFUSE: {"feature":"<slug>","code":2,"reason":"drift","gate":'
want handoff-resume        commands/handoff.md     'run the drift gate (step 4) and, if it passes, skip straight to step 9'
want handoff-refusal-case  commands/handoff.md     '- The drift gate fails'

printf '\npassed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
