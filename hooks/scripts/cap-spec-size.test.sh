#!/usr/bin/env bash
# Tests for hooks/scripts/cap-spec-size.sh (v0.9 PreToolUse byte cap on spec.md /
# acceptance.md driven by SPEC_MAX_KB; absent field = no cap).
# Run: bash hooks/scripts/cap-spec-size.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/cap-spec-size.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
new_proj() { local p="$work/$1"; mkdir -p "$p/.sdd/feat"; printf 'feat\n' > "$p/.sdd/ACTIVE"; printf 'PHASE: SPEC\nSPEC_MAX_KB: %s\n' "$2" > "$p/.sdd/feat/PROGRESS.md"; printf '%s' "$p"; }
# payload <tool> <path> <content|old> [<new>] [replace_all]
payload() { if [ "$1" = Write ]; then jq -cn --arg p "$2" --arg c "$3" '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}'; else jq -cn --arg p "$2" --arg o "$3" --arg n "${4:-}" --argjson ra "${5:-false}" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n,replace_all:$ra}}'; fi; }
check() { local name="$1" proj="$2" json="$3" want="$4" rc=0; ( cd "$proj" && printf '%s' "$json" | CLAUDE_PROJECT_DIR="$proj" bash "$HOOK" >/dev/null 2>&1 ); rc=$?; if [ "$rc" -eq "$want" ]; then pass=$((pass+1)); printf 'ok   %-40s rc=%s\n' "$name" "$rc"; else fail=$((fail+1)); printf 'FAIL %-40s want=%s got=%s\n' "$name" "$want" "$rc"; fi; }
big=$(head -c 1100 /dev/zero | tr '\0' 'x'); small="hello"

p=$(new_proj w1 1)
check "write-over-budget-blocks" "$p" "$(payload Write .sdd/feat/spec.md "$big")" 2
check "write-under-budget-allows" "$p" "$(payload Write .sdd/feat/spec.md "$small")" 0
check "acceptance-also-capped" "$p" "$(payload Write .sdd/feat/acceptance.md "$big")" 2
check "absolute-path-form" "$p" "$(payload Write "$p/.sdd/feat/spec.md" "$big")" 2
printf '%s' "$big" > "$p/.sdd/feat/acceptance.md"
check "edit-growing-over-blocks" "$p" "$(payload Edit .sdd/feat/acceptance.md x xxxx)" 2
check "edit-shrinking-allows" "$p" "$(payload Edit .sdd/feat/acceptance.md "$(head -c 200 /dev/zero | tr '\0' x)" "")" 0
check "edit-replace-all-counts-occurrences" "$p" "$(payload Edit .sdd/feat/acceptance.md x xx true)" 2
p=$(new_proj g1 1); printf 'PHASE: SPEC\n' > "$p/.sdd/feat/PROGRESS.md"
check "no-field-grandfathered" "$p" "$(payload Write .sdd/feat/spec.md "$big")" 0
p=$(new_proj z1 0)
check "zero-disables" "$p" "$(payload Write .sdd/feat/spec.md "$big")" 0
p=$(new_proj o1 1)
check "other-file-ignored" "$p" "$(payload Write .sdd/feat/DECISIONS.md "$big")" 0
check "product-tier-exempt" "$p" "$(payload Write .sdd/_product/spec.md "$big")" 0
check "traversal-ignored" "$p" "$(payload Write .sdd/feat/../feat/spec.md "$big")" 0
rc=0; ( cd "$p" && printf 'not json' | CLAUDE_PROJECT_DIR="$p" bash "$HOOK" >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 2 ]; then pass=$((pass+1)); echo "ok   malformed-json-fails-closed"; else fail=$((fail+1)); echo "FAIL malformed-json-fails-closed got=$rc"; fi
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
