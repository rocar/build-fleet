#!/usr/bin/env bash
# Tests for scripts/review-rotate.sh (v0.9 positional REVIEW.md rotation).
# Run: bash scripts/review-rotate.test.sh   (exit 0 = all pass)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROT="$DIR/review-rotate.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass=0; fail=0

new_proj() { local p="$work/$1"; mkdir -p "$p/.sdd/feat"; printf 'REVIEW_ROLES: architect, qa, coder\nCYCLE: 1\n' > "$p/.sdd/feat/PROGRESS.md"; printf '# Review Log — feat\n\nAppend-only.\n\n' > "$p/.sdd/feat/REVIEW.md"; printf '%s' "$p"; }
cyc() { local p="$1" c="$2"; for r in architect qa coder; do printf '## Cycle %s — %s — t\n- [minor] (%s-c%s-1) n\nstatus: approved\n\n' "$c" "$r" "$r" "$c" >> "$p/.sdd/feat/REVIEW.md"; done; }
misc() { printf '## %s — t\nbody\n\n' "$2" >> "$1/.sdd/feat/REVIEW.md"; }
run() { out=$( cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$ROT" feat "${@:2}" 2>/dev/null ); rc=$?; }
assert() { local name="$1" cond="$2"; if eval "$cond"; then pass=$((pass+1)); printf 'ok   %-44s\n' "$name"; else fail=$((fail+1)); printf 'FAIL %-44s (%s) out=%s\n' "$name" "$cond" "${out:-}"; fi; }
headings() { grep -c '^## ' "$1/.sdd/feat/REVIEW.md"; }

# --- no REVIEW.md → no-op signal, exit 0 ---
p="$work/nofile"; mkdir -p "$p/.sdd/feat"; run "$p"
assert "no-file-noop" "[ $rc -eq 0 ] && printf '%s' \"\$out\" | grep -q '\"archived_blocks\":0'"

# --- one cycle only → nothing to archive ---
p=$(new_proj one); cyc "$p" 1; run "$p"
assert "one-cycle-noop" "[ $rc -eq 0 ] && printf '%s' \"\$out\" | grep -q '\"archived_blocks\":0' && [ ! -f '$p/.sdd/feat/REVIEW-archive.md' ]"

# --- two cycles → cycle 1 archived, cycle 2 kept, header preserved ---
p=$(new_proj two); cyc "$p" 1; cyc "$p" 2; run "$p"
assert "two-cycles-archives-3" "printf '%s' \"\$out\" | grep -q '\"archived_blocks\":3,\"kept_blocks\":3'"
assert "two-cycles-keeps-cycle-2" "[ \$(headings '$p') -eq 3 ] && grep -q 'Cycle 2 — architect' '$p/.sdd/feat/REVIEW.md' && ! grep -q 'Cycle 1 — ' '$p/.sdd/feat/REVIEW.md'"
assert "two-cycles-header-kept" "head -1 '$p/.sdd/feat/REVIEW.md' | grep -q '^# Review Log — feat'"
assert "two-cycles-archive-has-cycle-1" "grep -c '^## Cycle 1 — ' '$p/.sdd/feat/REVIEW-archive.md' | grep -q '^3$'"
assert "two-cycles-archive-header" "head -1 '$p/.sdd/feat/REVIEW-archive.md' | grep -q '^# Review Archive — feat'"

# --- idempotent ---
run "$p"
assert "idempotent" "printf '%s' \"\$out\" | grep -q '\"archived_blocks\":0' && [ \$(headings '$p') -eq 3 ]"

# --- post-reset duplicate Cycle 1: the LATER run is kept, the escalation block archived ---
p=$(new_proj reset); cyc "$p" 1; cyc "$p" 2; misc "$p" 'Escalation resolved'; cyc "$p" 1; misc "$p" 'Run failure recorded'; run "$p"
assert "reset-archives-7" "printf '%s' \"\$out\" | grep -q '\"archived_blocks\":7,\"kept_blocks\":4'"
assert "reset-keeps-trailing-note" "grep -q 'Run failure recorded' '$p/.sdd/feat/REVIEW.md'"
assert "reset-archives-escalation" "grep -q 'Escalation resolved' '$p/.sdd/feat/REVIEW-archive.md' && ! grep -q 'Escalation resolved' '$p/.sdd/feat/REVIEW.md'"

# --- second rotation appends to the existing archive ---
cyc "$p" 2; run "$p"
assert "second-rotation-appends" "[ \$(grep -c '^## ' '$p/.sdd/feat/REVIEW-archive.md') -eq 11 ]"

# --- roster from flag: 2 roles keeps last 2 cycle blocks ---
p=$(new_proj flag); cyc "$p" 1; cyc "$p" 2; run "$p" --roster 2
assert "roster-flag" "printf '%s' \"\$out\" | grep -q '\"archived_blocks\":4,\"kept_blocks\":2'"

# --- CRLF headings are still recognised ---
p=$(new_proj crlf); cyc "$p" 1; cyc "$p" 2; sed -i.bak $'s/$/\r/' "$p/.sdd/feat/REVIEW.md"; run "$p"
assert "crlf-tolerated" "printf '%s' \"\$out\" | grep -q '\"archived_blocks\":3'"

# --- bad slug → exit 1 ---
out=$( cd "$work" && bash "$ROT" '../x' 2>/dev/null ); rc=$?
assert "bad-slug-exit-1" "[ $rc -eq 1 ]"

echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
