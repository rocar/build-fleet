#!/usr/bin/env bash
# SubagentStop (matcher scopes this to the reviewer roles in hooks.json):
# during REVIEW or CHANGE_REVIEW, a reviewer subagent must have appended its
# Cycle <N> block to REVIEW.md attributed to its role before it stops. The
# documented payload field is agent_type; one legacy fallback is kept for
# older Claude Code versions.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
. "$DIR/_lib.sh"

require_jq

input=$(cat)
slug=$(resolve_active)
[ -n "$slug" ] || exit 0

# Workflows handle reviewer accounting via their own envelope post-condition.
# The dispatching command writes its run id into this marker before invoking the
# Workflow tool; the scribe releases it on completion by emptying it (it has no
# Bash to rm). While the marker is LIVE (present AND non-empty) this hook skips —
# workflow reviewer subagents do not write REVIEW.md (the scribe does, after).
# An empty marker means "released": the hook re-engages and the reaper deletes it.
if [ -s ".sdd/${slug}/.workflow-in-flight" ]; then
  exit 0
fi

phase=$(read_progress_field "$slug" PHASE)

# The heading label is phase-specific so CHANGE_REVIEW blocks never collide with
# spec-review blocks in the same REVIEW.md: the CYCLE and CHANGE_CYCLE counters
# both start at 1, so spec review writes "## Cycle N" and CHANGE_REVIEW writes
# "## Change-Cycle N" — two disjoint heading families.
case "$phase" in
  REVIEW)
    cycle=$(read_progress_field "$slug" CYCLE)
    valid_reviewers="architect qa coder"
    heading="Cycle"
    ;;
  CHANGE_REVIEW)
    cycle=$(read_progress_field "$slug" CHANGE_CYCLE)
    valid_reviewers="architect product-owner qa"
    heading="Change-Cycle"
    ;;
  *) exit 0 ;;
esac

# Cycle counters come from PROGRESS.md free text — they feed a grep pattern
# below, so refuse to enforce on a non-integer value rather than wedging the
# subagent against a pattern that can never match (audit §4 hooks minor).
case "$cycle" in
  ''|*[!0-9]*)
    echo "build-fleet: PROGRESS.md cycle counter for phase ${phase} is not an integer ('${cycle}') — review-written check skipped." >&2
    exit 0
    ;;
esac

# Subagent identity: agent_type is the documented field; subagent_type is a
# legacy fallback. Empty if neither is present.
agent=$(printf '%s' "$input" | jq -r '
  .agent_type
  // .subagent_type
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

# Accept en-dash, em-dash, or hyphen between fields in the heading. ${heading} is
# phase-specific ("Cycle" | "Change-Cycle"), so a stale spec-review "## Cycle N"
# block can never satisfy a CHANGE_REVIEW "## Change-Cycle N" check (and vice versa).
if ! grep -Eq "^##[[:space:]]+${heading}[[:space:]]+${cycle}[[:space:]]+[—–-][[:space:]]+${agent_short}[[:space:]]+[—–-]" "$review_file"; then
  echo "build-fleet: ${agent_short} stopped without appending its ${heading} ${cycle} block to REVIEW.md." >&2
  echo "Expected a heading matching: ## ${heading} ${cycle} — ${agent_short} — <iso8601>" >&2
  exit 2
fi

exit 0
