#!/usr/bin/env bash
# Tests for hooks/scripts/cap-spec-size.sh (PreToolUse line cap on spec.md driven by
# SPEC_MAX_LINES; absent field = no cap).
# Run: bash hooks/scripts/cap-spec-size.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/cap-spec-size.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
# new_proj <name> <SPEC_MAX_LINES value> — spec.md starts at 8 lines (l1..l8)
new_proj() { local p="$work/$1"; mkdir -p "$p/.sdd/feat"; printf 'feat\n' > "$p/.sdd/ACTIVE"; printf 'SDD_SCHEMA: 2\nPHASE: SPEC\nSPEC_MAX_LINES: %s\n' "$2" > "$p/.sdd/feat/PROGRESS.md"; printf 'l%s\n' 1 2 3 4 5 6 7 8 > "$p/.sdd/feat/spec.md"; printf '%s' "$p"; }
# payload <tool> <path> <content|old> [<new>] [replace_all]
payload() { if [ "$1" = Write ]; then jq -cn --arg p "$2" --arg c "$3" '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}'; else jq -cn --arg p "$2" --arg o "$3" --arg n "${4:-}" --argjson ra "${5:-false}" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n,replace_all:$ra}}'; fi; }
check() { local name="$1" proj="$2" json="$3" want="$4" rc=0; ( cd "$proj" && printf '%s' "$json" | CLAUDE_PROJECT_DIR="$proj" bash "$HOOK" >/dev/null 2>&1 ); rc=$?; if [ "$rc" -eq "$want" ]; then pass=$((pass+1)); printf 'ok   %-44s rc=%s\n' "$name" "$rc"; else fail=$((fail+1)); printf 'FAIL %-44s want=%s got=%s\n' "$name" "$want" "$rc"; fi; }
stderr_of() { ( cd "$1" && printf '%s' "$2" | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>&1 >/dev/null ); }
has_err() { local name="$1" err="$2" needle="$3"; if printf '%s' "$err" | grep -qF -- "$needle"; then pass=$((pass+1)); printf 'ok   %s\n' "$name"; else fail=$((fail+1)); printf 'FAIL %-44s missing %s in: %s\n' "$name" "$needle" "$err"; fi; }
lines() { local i=1 out=""; while [ "$i" -le "$1" ]; do out="${out}l$i"$'\n'; i=$((i+1)); done; printf '%s' "$out"; }
S=.sdd/feat/spec.md

p=$(new_proj w 10)
check "write-under-allows" "$p" "$(payload Write $S "$(lines 10)")" 0
check "write-over-refuses" "$p" "$(payload Write $S "$(lines 11)")" 2
err=$(stderr_of "$p" "$(payload Write $S "$(lines 11)")")
has_err "refusal-names-lines" "$err" "11 lines"
has_err "refusal-names-budget" "$err" "10-line budget"
has_err "refusal-names-backlog-row" "$err" "backlog row"
has_err "refusal-names-decisions" "$err" "DECISIONS.md"
if printf '%s' "$err" | grep -q "Self-review notes"; then fail=$((fail+1)); echo "FAIL refusal-no-self-review-notes"; else pass=$((pass+1)); echo "ok   refusal-no-self-review-notes"; fi
check "write-unterminated-last-line-counts" "$p" "$(payload Write $S "$(lines 10)"$'\nx')" 2
check "absolute-path-form" "$p" "$(payload Write "$p/$S" "$(lines 11)")" 2
check "edit-add-lines-over" "$p" "$(payload Edit $S $'l8\n' $'l8\na\nb\nc\n')" 2
check "edit-add-lines-under" "$p" "$(payload Edit $S $'l8\n' $'l8\na\nb\n')" 0
p=$(new_proj j 10); lines 10 > "$p/$S"
check "edit-join-lines-allowed" "$p" "$(payload Edit $S $'l1\nl2\n' $'l1 l2\n')" 0
check "edit-at-budget-same-lines-allowed" "$p" "$(payload Edit $S l1 L1)" 0
p=$(new_proj ra 10); printf 'X\nX\nl3\nl4\nl5\nl6\nl7\nl8\n' > "$p/$S"
check "edit-replace-all-two-occurrences" "$p" "$(payload Edit $S $'X\n' $'X\nY\n' true)" 0
p=$(new_proj ra3 10); printf 'X\nX\nX\nl4\nl5\nl6\nl7\nl8\n' > "$p/$S"
check "edit-replace-all-three-occurrences" "$p" "$(payload Edit $S $'X\n' $'X\nY\n' true)" 2
p=$(new_proj g 10); printf 'SDD_SCHEMA: 2\nPHASE: SPEC\n' > "$p/.sdd/feat/PROGRESS.md"
check "no-field-no-cap" "$p" "$(payload Write $S "$(lines 500)")" 0
p=$(new_proj kb 10); printf 'SDD_SCHEMA: 2\nSPEC_MAX_KB: 1\n' > "$p/.sdd/feat/PROGRESS.md"
check "kb-field-ignored" "$p" "$(payload Write $S "$(lines 500)")" 0
p=$(new_proj z 0)
check "zero-disables" "$p" "$(payload Write $S "$(lines 500)")" 0
p=$(new_proj lz 010)
check "leading-zero-decimal-at" "$p" "$(payload Write $S "$(lines 10)")" 0
check "leading-zero-decimal-over" "$p" "$(payload Write $S "$(lines 11)")" 2
p=$(new_proj l8 008)
check "leading-zero-008-no-crash" "$p" "$(payload Write $S "$(lines 9)")" 2
p=$(new_proj bad 150L)
check "garbage-refuses" "$p" "$(payload Write $S "x")" 2
has_err "garbage-refuses-message" "$(stderr_of "$p" "$(payload Write $S x)")" "SPEC_MAX_LINES is not an integer ('150L')"
p=$(new_proj o 1)
check "acceptance-md-not-capped" "$p" "$(payload Write .sdd/feat/acceptance.md "$(lines 500)")" 0
check "other-file-ignored" "$p" "$(payload Write .sdd/feat/DECISIONS.md "$(lines 500)")" 0
check "product-tier-exempt" "$p" "$(payload Write .sdd/_product/spec.md "$(lines 500)")" 0
check "traversal-into-sdd-refuses" "$p" "$(payload Write .sdd/feat/../feat/spec.md "$(lines 500)")" 2
check "traversal-other-sdd-file-ignored" "$p" "$(payload Write .sdd/feat/../feat/DECISIONS.md "$(lines 500)")" 0
check "traversal-outside-sdd-ignored" "$p" "$(payload Write docs/../other/spec.md "$(lines 500)")" 0
check "notebookedit-on-spec-refuses" "$p" "$(jq -cn --arg p $S '{tool_name:"NotebookEdit",tool_input:{notebook_path:$p}}')" 2
check "notebookedit-elsewhere-ignored" "$p" "$(jq -cn '{tool_name:"NotebookEdit",tool_input:{notebook_path:"notes/x.ipynb"}}')" 0
rc=0; ( cd "$p" && printf 'not json' | CLAUDE_PROJECT_DIR="$p" bash "$HOOK" >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 2 ]; then pass=$((pass+1)); echo "ok   malformed-json-fails-closed"; else fail=$((fail+1)); echo "FAIL malformed-json-fails-closed got=$rc"; fi
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
