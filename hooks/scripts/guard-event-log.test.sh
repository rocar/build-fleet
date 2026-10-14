#!/usr/bin/env bash
# Tests for hooks/scripts/guard-event-log.sh — agent writes to the event log are refused.
# Run: bash hooks/scripts/guard-event-log.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/guard-event-log.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/.sdd/feat"
pass=0; fail=0
check() { # check <name> <tool> <file_path> <want_rc>
  local rc=0
  ( cd "$work" && jq -cn --arg t "$2" --arg p "$3" '{tool_name:$t, tool_input:{file_path:$p, content:"x"}}' \
      | CLAUDE_PROJECT_DIR="$work" bash "$HOOK" >/dev/null 2>&1 ); rc=$?
  if [ "$rc" -eq "$4" ]; then pass=$((pass+1)); printf 'ok   %-40s rc=%s\n' "$1" "$rc"
  else fail=$((fail+1)); printf 'FAIL %-40s want=%s got=%s\n' "$1" "$4" "$rc"; fi
}
check "write-feature-events-refused"   Write ".sdd/feat/EVENTS.jsonl" 2
check "edit-feature-events-refused"    Edit  "$work/.sdd/feat/EVENTS.jsonl" 2
check "write-project-events-refused"   Write ".sdd/_events.jsonl" 2
check "write-review-allowed"           Write ".sdd/feat/REVIEW.md" 0
check "write-source-allowed"           Write "src/EVENTS.jsonl.md" 0
check "events-outside-sdd-allowed"     Write "docs/EVENTS.jsonl" 0
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
