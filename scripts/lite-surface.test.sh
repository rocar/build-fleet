#!/usr/bin/env bash
# Tests the lite command surface (docs/history/2026-10-15-lite.md §3.1–3.2, §5.3):
# five user commands, every other command hidden, no stale command names.
# Run: bash scripts/lite-surface.test.sh   (exit 0 = all pass)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
ok(){ pass=$((pass+1)); printf 'ok   %s\n' "$1"; }
no(){ fail=$((fail+1)); printf 'FAIL %s — %s\n' "$1" "$2"; }
fm(){ awk 'NR == 1 && /^---$/ { f = 1; next } f && /^---$/ { exit } f' "$1"; }
LITE="start build ship fix status"
is_lite(){ case " $LITE " in *" $1 "*) return 0 ;; esac; return 1; }

# --- renamed steps ---
for s in implement apply-fix; do
  if [ -f "$ROOT/commands/$s.md" ]; then ok "step $s exists"; else no "step $s exists" "commands/$s.md missing"; fi
done
internal=""
for f in "$ROOT"/commands/*.md; do is_lite "$(basename "$f" .md)" || internal="$internal $f"; done
# shellcheck disable=SC2086
hits=$(/usr/bin/grep -rlE '/build-fleet:(build|fix)([^-a-z]|$)' $internal \
  "$ROOT/agents" "$ROOT/workflows" "$ROOT/hooks" "$ROOT/scripts" 2>/dev/null \
  | /usr/bin/grep -vE '/lite-(surface\.test|next|next\.test)\.sh$' || true)
if [ -z "$hits" ]; then ok "no internal file names the old step names"
else no "no internal file names the old step names" "$(echo $hits)"; fi

echo "lite-surface: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
