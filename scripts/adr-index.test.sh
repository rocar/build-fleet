#!/usr/bin/env bash
# Tests for scripts/adr-index.sh (v0.9 ADR index + --next).
# Run: bash scripts/adr-index.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDX="$DIR/adr-index.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
assert() { local name="$1" cond="$2"; if eval "$cond"; then pass=$((pass+1)); printf 'ok   %-40s\n' "$name"; else fail=$((fail+1)); printf 'FAIL %-40s (%s)\n' "$name" "$cond"; fi; }

f="$work/DECISIONS.md"
printf '# Architecture Decisions — feat\n\nAppend-only log.\n\n## ADR-1: use token bucket\n\n- **Date:** 2026-09-01\n- **Status:** accepted\n\n### Context\nx\n\n## ADR-007: keep Decimal everywhere\n\n- **Status:** superseded by ADR-9\n\n## ADR-9: round once\n' > "$f"
out=$(bash "$IDX" "$f")
assert "index-line-1" "printf '%s\n' \"\$out\" | grep -qx 'ADR-1: use token bucket \\[accepted\\]'"
assert "index-zero-padded-normalised" "printf '%s\n' \"\$out\" | grep -qx 'ADR-7: keep Decimal everywhere \\[superseded by ADR-9\\]'"
assert "index-status-unknown" "printf '%s\n' \"\$out\" | grep -qx 'ADR-9: round once \\[unknown\\]'"
assert "index-count" "[ \$(printf '%s\n' \"\$out\" | wc -l | tr -d ' ') -eq 3 ]"
assert "next-is-max-plus-one" "[ \"\$(bash \"\$IDX\" \"\$f\" --next)\" = 10 ]"
assert "next-absent-file-is-1" "[ \"\$(bash \"\$IDX\" \"\$work/none.md\" --next)\" = 1 ]"
assert "absent-file-index-empty-rc0" "[ -z \"\$(bash \"\$IDX\" \"\$work/none.md\")\" ] && bash \"\$IDX\" \"\$work/none.md\""
printf '# Architecture Decisions — feat\n\nAppend-only log.\n' > "$work/empty.md"
assert "empty-log-next-is-1" "[ \"\$(bash \"\$IDX\" \"\$work/empty.md\" --next)\" = 1 ]"
sed -i.bak $'s/$/\r/' "$f"
assert "crlf-tolerated" "[ \"\$(bash \"\$IDX\" \"\$f\" --next)\" = 10 ]"
rc=0; bash "$IDX" '../x' >/dev/null 2>&1 || rc=$?
assert "traversal-refused" "[ $rc -eq 1 ]"
rc=0; bash "$IDX" >/dev/null 2>&1 || rc=$?
assert "no-arg-usage-exit-1" "[ $rc -eq 1 ]"
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
