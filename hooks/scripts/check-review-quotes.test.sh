#!/usr/bin/env bash
# Tests for hooks/scripts/check-review-quotes.sh — the quote check runs once, on the
# scribe's empty Write of .workflow-in-flight, only for a current-cycle verified block.
# Run: bash hooks/scripts/check-review-quotes.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/check-review-quotes.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
. "$DIR/../../scripts/fixtures/verified-review.sh"
pass=0; fail=0
# fire <name> <proj> <tool> <path> <content> <want-new-events>
fire() {
  local before after rc
  before=$(cat "$2/.sdd/feat/EVENTS.jsonl" 2>/dev/null | wc -l | tr -d ' ')
  ( cd "$2" && jq -cn --arg t "$3" --arg p "$4" --arg c "$5" '{tool_name:$t, tool_input:{file_path:$p, content:$c}}' \
      | CLAUDE_PROJECT_DIR="$2" bash "$HOOK" >/dev/null 2>&1 ); rc=$?
  after=$(cat "$2/.sdd/feat/EVENTS.jsonl" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$rc" -eq 0 ] && [ $((after-before)) -eq "$6" ]; then pass=$((pass+1)); printf 'ok   %-40s\n' "$1"
  else fail=$((fail+1)); printf 'FAIL %-40s rc=%s new=%s want=%s\n' "$1" "$rc" "$((after-before))" "$6"; fi
}
p=$(vr_proj v 1); vr_block "$p" 1 qa; vr_block "$p" 1 architect
M="$p/.sdd/feat/.workflow-in-flight"; printf 'run-1' > "$M"
fire "non-empty-marker-write-ignored" "$p" Write "$M" "run-1" 0
fire "review-md-write-ignored"        "$p" Write "$p/.sdd/feat/REVIEW.md" "" 0
fire "edit-of-marker-ignored"         "$p" Edit  "$M" "" 0
fire "marker-release-runs-check"      "$p" Write "$M" "" 1
fire "second-release-no-new-event"    "$p" Write "$M" "" 0
fire "relative-path-release"          "$(vr_proj r 1)" Write ".sdd/feat/.workflow-in-flight" "" 0
p=$(vr_proj d 1); printf '## Cycle 1 — qa — t\n- [minor] (qa-c1-1) x\nstatus: approved\n' >> "$p/.sdd/feat/REVIEW.md"
fire "debate-block-ignored"           "$p" Write "$p/.sdd/feat/.workflow-in-flight" "" 0
p=$(vr_proj s 2 2); vr_block "$p" 1 qa; vr_block "$p" 1 architect
fire "stale-cycle-ignored"            "$p" Write "$p/.sdd/feat/.workflow-in-flight" "" 0
p=$(vr_proj rel 1); vr_block "$p" 1 qa; vr_block "$p" 1 architect
fire "relative-path-verified-runs"    "$p" Write ".sdd/feat/.workflow-in-flight" "" 1
# A quote-check that fails (exit 1) is relayed on stderr and recorded, never swallowed.
plug="$work/plug"; mkdir -p "$plug/hooks/scripts" "$plug/scripts"
cp "$HOOK" "$DIR/_lib.sh" "$plug/hooks/scripts/"
printf '#!/usr/bin/env bash\necho "quote-check.sh: could not evaluate REVIEW.md" >&2\nexit 1\n' > "$plug/scripts/quote-check.sh"
p=$(vr_proj qf 1); vr_block "$p" 1 qa; vr_block "$p" 1 architect
err=$( cd "$p" && jq -cn --arg p "$p/.sdd/feat/.workflow-in-flight" '{tool_name:"Write", tool_input:{file_path:$p, content:""}}' \
  | CLAUDE_PROJECT_DIR="$p" bash "$plug/hooks/scripts/check-review-quotes.sh" 2>&1 >/dev/null ); rc=$?
ev=$(grep -c '"source":"hook:check-review-quotes"' "$p/.sdd/feat/EVENTS.jsonl" 2>/dev/null || true)
if [ "$rc" -eq 0 ] && printf '%s' "$err" | grep -q 'could not evaluate' && [ "$ev" = 1 ] \
   && grep '"source":"hook:check-review-quotes"' "$p/.sdd/feat/EVENTS.jsonl" | grep -q '"decision":"error"'; then
  pass=$((pass+1)); printf 'ok   %-40s\n' "quote-check-failure-relayed"
else fail=$((fail+1)); printf 'FAIL %-40s rc=%s ev=%s err=%s\n' "quote-check-failure-relayed" "$rc" "$ev" "$err"; fi
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
