#!/usr/bin/env bash
# REVIEW.md block headings use an em dash ("## Cycle 1 — architect — <ts>"). A bracket
# like [—–-] matches one BYTE in the C locale, so a gate run from a C-locale shell (a
# daemon, a CI runner, LANG=C) saw no reviewer blocks at all. Headings must match in
# every locale. Run: bash scripts/review-heading-locale.test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
printf '# REVIEW\n\n## Cycle 1 — architect — 2026-10-15T00:00:00Z\nstatus: approved\n' > "$work/REVIEW.md"
for loc in C en_US.UTF-8; do
  out=$(LC_ALL=$loc bash -c '. "$1/scripts/lib/review-blocks.sh"; last_cycle_block "$2" 1 architect' _ "$ROOT" "$work/REVIEW.md" 2>/dev/null | head -1)
  case "$out" in "## Cycle 1"*) pass=$((pass+1)); echo "ok   last_cycle_block under LC_ALL=$loc" ;;
    *) fail=$((fail+1)); echo "FAIL last_cycle_block under LC_ALL=$loc got[$out]" ;; esac
done
hits=$(/usr/bin/grep -rln '\[—–-\]' "$ROOT/scripts" "$ROOT/hooks" 2>/dev/null | /usr/bin/grep -v 'review-heading-locale.test.sh$' || true)
if [ -z "$hits" ]; then pass=$((pass+1)); echo "ok   no byte-bracket dash patterns"; else fail=$((fail+1)); echo "FAIL byte-bracket dash patterns in: $(echo $hits)"; fi
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
