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

# Defect fix tests: leading-zero octal, multiline replace_all, NotebookEdit
p=$(new_proj l1 010)
check "leading-zero-cap-decimal-over" "$p" "$(payload Write .sdd/feat/spec.md "$(head -c 10500 /dev/zero | tr '\0' 'x')")" 2
check "leading-zero-cap-decimal-under" "$p" "$(payload Write .sdd/feat/spec.md "$(head -c 9000 /dev/zero | tr '\0' 'x')")" 0
p=$(new_proj l2 008)
check "leading-zero-cap-008-no-crash" "$p" "$(payload Write .sdd/feat/spec.md "$(head -c 9000 /dev/zero | tr '\0' 'x')")" 2

# Multiline replace_all with discriminating arithmetic:
# File: 1020 bytes = 2×"foo\nbar\n" (16 bytes) + padding (1004 bytes)
# old_string="foo\nbar" (7 bytes), new_string="foo\nbarXX" (9 bytes), delta=+2
# Correct count (2 occurrences): 1020 + 2×2 = 1024 ≤ budget 1024 → rc 0
# Old grep miscounts "foo"/"bar" as 4 lines: 1020 + 2×4 = 1028 > budget → rc 2
# Test FAILS on pre-fix (rc 2), PASSES on fixed (rc 0).
p=$(new_proj m1 1)
{ printf 'foo\nbar\nfoo\nbar\n'; head -c 1004 /dev/zero | tr '\0' p; } > "$p/.sdd/feat/acceptance.md"
# Verify fixture is exactly 1020 bytes
fixture_size=$(wc -c < "$p/.sdd/feat/acceptance.md" | tr -d ' ')
if [ "$fixture_size" -eq 1020 ]; then pass=$((pass+1)); printf 'ok   %-40s bytes=%s\n' "multiline-fixture-is-1020-bytes" "$fixture_size"; else fail=$((fail+1)); printf 'FAIL %-40s want=1020 got=%s\n' "multiline-fixture-is-1020-bytes" "$fixture_size"; fi
payload_multiline=$(jq -cn --arg p ".sdd/feat/acceptance.md" --arg o $'foo\nbar' --arg n $'foo\nbarXX' --argjson ra true '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n,replace_all:$ra}}')
check "edit-replace-all-multiline-counts-once-per-occurrence" "$p" "$payload_multiline" 0

# NotebookEdit on spec with cap present → rc 2
p=$(new_proj nb1 1)
payload_nb=$(jq -cn --arg p ".sdd/feat/spec.md" '{tool_name:"NotebookEdit",tool_input:{notebook_path:$p}}')
check "notebookedit-on-spec-refuses" "$p" "$payload_nb" 2

# NotebookEdit on non-spec file → rc 0
p=$(new_proj nb2 1)
mkdir -p "$p/notes"
payload_nb_other=$(jq -cn --arg p "notes/x.ipynb" '{tool_name:"NotebookEdit",tool_input:{notebook_path:$p}}')
check "notebookedit-elsewhere-ignored" "$p" "$payload_nb_other" 0

echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
