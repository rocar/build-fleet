#!/usr/bin/env bash
# SubagentStop: during REVIEW or CHANGE_REVIEW, a reviewer subagent must
# have appended its Cycle <N> block to REVIEW.md attributed to its role
# before it stops. The hook payload's subagent-identity field name varies
# across Claude Code versions — we probe a few.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
. "$DIR/_lib.sh"

require_jq

input=$(cat)
slug=$(resolve_active)
[ -n "$slug" ] || exit 0

# v0.2: workflows handle reviewer accounting via their own envelope post-condition.
# The /build-fleet:review command creates this marker before invoking the Workflow
# tool; scribe removes it on workflow completion. While present, this hook skips —
# workflow reviewer subagents do not write REVIEW.md (the scribe does, after).
if [ -f ".sdd/${slug}/.workflow-in-flight" ]; then
  exit 0
fi

phase=$(read_progress_field "$slug" PHASE)

case "$phase" in
  REVIEW)
    cycle=$(read_progress_field "$slug" CYCLE)
    valid_reviewers="architect qa coder"
    ;;
  CHANGE_REVIEW)
    cycle=$(read_progress_field "$slug" CHANGE_CYCLE)
    valid_reviewers="architect product-owner qa"
    ;;
  *) exit 0 ;;
esac

# Try several keys for the subagent identity. Empty if none present.
agent=$(printf '%s' "$input" | jq -r '
  .subagent_type
  // .agent_type
  // .agent_name
  // .subagent_name
  // .agent
  // empty
')

# Cannot identify the stopping agent → cannot enforce. Allow.
[ -n "$agent" ] || exit 0

# Strip a namespace prefix if present (build-fleet:architect → architect).
agent_short="${agent##*:}"

case " $valid_reviewers " in
  *" $agent_short "*) ;;
  *) exit 0 ;;
esac

review_file=".sdd/${slug}/REVIEW.md"
if [ ! -f "$review_file" ]; then
  echo "build-fleet: ${agent_short} stopped without writing REVIEW.md for cycle ${cycle}. REVIEW.md does not exist." >&2
  exit 2
fi

# Accept en-dash, em-dash, or hyphen between fields in the heading.
if ! grep -Eq "^##[[:space:]]+Cycle[[:space:]]+${cycle}[[:space:]]+[—–-][[:space:]]+${agent_short}[[:space:]]+[—–-]" "$review_file"; then
  echo "build-fleet: ${agent_short} stopped without appending its Cycle ${cycle} block to REVIEW.md." >&2
  echo "Expected a heading matching: ## Cycle ${cycle} — ${agent_short} — <iso8601>" >&2
  exit 2
fi

exit 0
