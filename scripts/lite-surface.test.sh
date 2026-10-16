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

# --- the three decisions live in status ---
for c in park resolve-escalation plan-finalize; do
  if [ -f "$ROOT/commands/$c.md" ]; then no "$c deleted" "commands/$c.md still exists"; else ok "$c deleted"; fi
done
stale=$(/usr/bin/grep -rlE '/build-fleet:(park|resolve-escalation|plan-finalize)([^-a-z]|$)' "$ROOT" \
  --exclude-dir=.git --exclude-dir=history --exclude-dir=.sdd --exclude-dir=.superpowers --exclude=CHANGELOG.md --exclude=lite-surface.test.sh 2>/dev/null || true)
if [ -z "$stale" ]; then ok "no file names a deleted command"; else no "no file names a deleted command" "$(echo $stale)"; fi
for form in 'park <reason>' 'resolve' 'ratify'; do
  if /usr/bin/grep -qF "$form" "$ROOT/commands/status.md"; then ok "status has $form"; else no "status has $form" "missing"; fi
done
if fm "$ROOT/commands/status.md" | /usr/bin/grep -q '^model:'; then no "status has no model pin" "model: still set"; else ok "status has no model pin"; fi

# --- the five-command surface ---
count=$(ls "$ROOT"/commands/*.md | wc -l | tr -d ' ')
if [ "$count" = 24 ]; then ok "24 command files"; else no "24 command files" "found $count"; fi
for f in "$ROOT"/commands/*.md; do
  c=$(basename "$f" .md)
  hidden=no; fm "$f" | /usr/bin/grep -q '^user-invocable: false$' && hidden=yes
  human=no; fm "$f" | /usr/bin/grep -q '^disable-model-invocation: true$' && human=yes
  if is_lite "$c"; then
    [ "$hidden" = no ] && ok "$c is user-invocable" || no "$c is user-invocable" "has user-invocable: false"
  else
    [ "$hidden" = yes ] && ok "$c is hidden" || no "$c is hidden" "missing user-invocable: false"
  fi
  case "$c" in build|ship|status) want=yes ;; *) want=no ;; esac
  [ "$human" = "$want" ] && ok "$c human-only=$want" || no "$c human-only=$want" "got $human"
done
# the loop block is identical in all four drivers
ref=""
for c in start build ship fix; do
  blk=$(awk '/<!-- LITE-LOOP START -->/{f=1} f{print} /<!-- LITE-LOOP END -->/{f=0}' "$ROOT/commands/$c.md" 2>/dev/null)
  if [ -z "$blk" ]; then no "$c has the loop block" "missing"; continue; fi
  if [ -z "$ref" ]; then ref="$blk"; ok "$c has the loop block"
  elif [ "$blk" = "$ref" ]; then ok "$c loop block matches start"
  else no "$c loop block matches start" "drift"; fi
  words=$(wc -w < "$ROOT/commands/$c.md" | tr -d ' ')
  [ "$words" -le 650 ] && ok "$c body ≤ 650 words ($words)" || no "$c body ≤ 650 words" "$words"
done

# --- final-review fixes ---
for f in commands/start.md commands/status.md; do
  if /usr/bin/grep -qF 'never appear in your own command list' "$ROOT/$f"; then ok "$f: router next is authoritative"; else no "$f: router next is authoritative" "missing"; fi
done
if /usr/bin/grep -qF 'BUILD_FLEET_TRIAGE_KNOWN_CAUSE' "$ROOT/commands/fix.md"; then ok "loop stops on a known-cause divert"; else no "loop stops on a known-cause divert" "missing"; fi
if /usr/bin/grep -qF '`known-cause`' "$ROOT/docs/v0.2/CONTRACT.md"; then ok "CONTRACT lists known-cause"; else no "CONTRACT lists known-cause" "missing"; fi
if /usr/bin/grep -qiE 'cannot approve a spec|cannot approve, ship' "$ROOT/README.md" "$ROOT/CHANGELOG.md"; then no "docs do not overclaim the human-only guarantee" "found"; else ok "docs do not overclaim the human-only guarantee"; fi
qa_line=$(/usr/bin/grep -n 'BUILD_FLEET_QA_VERIFY_FAIL: {"feature":"<slug>","reason":"<zero-tests' "$ROOT/commands/implement.md" | head -1 | cut -d: -f1)
bs_line=$(/usr/bin/grep -n 'Set `BUILD_STATE: started`' "$ROOT/commands/implement.md" | head -1 | cut -d: -f1)
if [ -n "$qa_line" ] && [ -n "$bs_line" ] && [ "$bs_line" -gt "$qa_line" ]; then ok "BUILD_STATE: started is set after qa's suite is verified"
else no "BUILD_STATE: started is set after qa's suite is verified" "qa=$qa_line bs=$bs_line"; fi
echo "lite-surface: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
