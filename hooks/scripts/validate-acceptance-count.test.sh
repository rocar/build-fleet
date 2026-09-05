#!/usr/bin/env bash
# Tests for hooks/scripts/validate-acceptance-count.sh (v0.9 PostToolUse criterion
# cap driven by AC_MAX; absent field = no cap).
# Run: bash hooks/scripts/validate-acceptance-count.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/validate-acceptance-count.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
new_proj() { local p="$work/$1"; mkdir -p "$p/.sdd/feat"; printf 'feat\n' > "$p/.sdd/ACTIVE"; printf 'PHASE: SPEC\nAC_MAX: %s\n' "$2" > "$p/.sdd/feat/PROGRESS.md"; printf '%s' "$p"; }
check() { local name="$1" proj="$2" fp="$3" want="$4" rc=0; ( cd "$proj" && printf '{"tool_input":{"file_path":"%s"}}' "$fp" | CLAUDE_PROJECT_DIR="$proj" bash "$HOOK" >/dev/null 2>&1 ); rc=$?; if [ "$rc" -eq "$want" ]; then pass=$((pass+1)); printf 'ok   %-40s rc=%s\n' "$name" "$rc"; else fail=$((fail+1)); printf 'FAIL %-40s want=%s got=%s\n' "$name" "$want" "$rc"; fi; }
check_err() { local name="$1" proj="$2" fp="$3" needle="$4" rc=0 err; err=$( cd "$proj" && printf '{"tool_input":{"file_path":"%s"}}' "$fp" | CLAUDE_PROJECT_DIR="$proj" bash "$HOOK" 2>&1 >/dev/null ); rc=$?; if [ "$rc" -eq 2 ] && printf '%s' "$err" | grep -qi "$needle"; then pass=$((pass+1)); printf 'ok   %-40s rc=2\n' "$name"; else fail=$((fail+1)); printf 'FAIL %-40s got=%s (%s)\n' "$name" "$rc" "$err"; fi; }

p=$(new_proj a 3); printf 'AC-1 a\nAC-2 b\nAC-3 c\nAC-3a d\n' > "$p/.sdd/feat/acceptance.md"
check "four-distinct-over-three-blocks" "$p" ".sdd/feat/acceptance.md" 2
check_err "message-says-split" "$p" ".sdd/feat/acceptance.md" "SPLIT"
printf 'AC-1 a\nAC-2 b\nAC-2 repeated\nsee AC-1 again\n' > "$p/.sdd/feat/acceptance.md"
check "repeats-count-once" "$p" ".sdd/feat/acceptance.md" 0
printf 'AC-1 a\nAC-2 b\nAC-3 c\n' > "$p/.sdd/feat/acceptance.md"
check "exactly-at-cap-allows" "$p" ".sdd/feat/acceptance.md" 0
check "spec-file-ignored" "$p" ".sdd/feat/spec.md" 0
check "absent-file-allows" "$p" ".sdd/other/acceptance.md" 0
p=$(new_proj g 3); printf 'PHASE: SPEC\n' > "$p/.sdd/feat/PROGRESS.md"; printf 'AC-1\nAC-2\nAC-3\nAC-4\nAC-5\n' > "$p/.sdd/feat/acceptance.md"
check "no-field-grandfathered" "$p" ".sdd/feat/acceptance.md" 0
p=$(new_proj z 0); printf 'AC-1\nAC-2\nAC-3\nAC-4\n' > "$p/.sdd/feat/acceptance.md"
check "zero-disables" "$p" ".sdd/feat/acceptance.md" 0
p=$(new_proj t 1); mkdir -p "$p/docs"; printf 'AC-1\nAC-2\n' > "$p/docs/acceptance.md"
check "outside-sdd-ignored" "$p" "docs/acceptance.md" 0
rc=0; ( cd "$p" && printf 'not json' | CLAUDE_PROJECT_DIR="$p" bash "$HOOK" >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 2 ]; then pass=$((pass+1)); echo "ok   malformed-json-fails-closed"; else fail=$((fail+1)); echo "FAIL malformed-json-fails-closed got=$rc"; fi
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
