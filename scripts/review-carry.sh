#!/usr/bin/env bash
# scripts/review-carry.sh — what /build-fleet:review must pass to the next verified
# cycle: the open findings carried forward and the review-budget exemption.
#
# Reads the CURRENT (last completed) cycle of .sdd/<slug>/. When its blocks are in the
# verified shape, `carried` is the open set from `finalize-gate.sh --report` (full
# finding objects) and `exempt_cycles` counts this review phase's cycles whose
# quote-check event is exempt (a finding reopened by a failed quote). The phase's
# cycles are those with cycle_total in (CYCLE_TOTAL - CYCLE, CYCLE_TOTAL] — CYCLE
# resets on resolve-escalation, CYCLE_TOTAL never does. Debate shape or no cycle yet:
# nothing is carried and exempt_cycles is 0.
#
# Usage: review-carry.sh <slug>
# Output (stdout, one line):
#   BUILD_FLEET_REVIEW_CARRY: {"feature","cycle","previous_shape":"verified"|"debate"|"none","carried":[…],"open_count":N,"exempt_cycles":N}
# Exit: 0; 1 = bad usage / unreadable workspace; 2 (no output line) = the last cycle is
# verified but finalize-gate.sh --report gave no report. Writes nothing. bash 3.2; requires jq.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
slug="${1:-}"
[ -n "$slug" ] || { echo "usage: review-carry.sh <slug>" >&2; exit 1; }
case "$slug" in */*|..|.|-*) echo "review-carry.sh: bad slug '$slug'" >&2; exit 1 ;; esac
command -v jq >/dev/null 2>&1 || { echo "review-carry.sh: jq is required" >&2; exit 1; }
# shellcheck source=../hooks/scripts/_lib.sh
. "${HERE}/../hooks/scripts/_lib.sh"
# shellcheck source=lib/review-blocks.sh
. "${HERE}/lib/review-blocks.sh"

progress=".sdd/${slug}/PROGRESS.md"; review=".sdd/${slug}/REVIEW.md"
[ -f "$progress" ] || { echo "review-carry.sh: ${progress} not found" >&2; exit 1; }
cycle=$(read_progress_field "$slug" CYCLE); case "$cycle" in ''|*[!0-9]*) cycle=0 ;; esac
total=$(read_progress_field "$slug" CYCLE_TOTAL); case "$total" in ''|*[!0-9]*) total="$cycle" ;; esac

out() { printf 'BUILD_FLEET_REVIEW_CARRY: %s\n' "$(jq -cn --arg f "$slug" --argjson c "$cycle" --arg s "$1" --argjson k "$2" --argjson e "$3" \
  '{feature: $f, cycle: $c, previous_shape: $s, carried: $k, open_count: ($k | length), exempt_cycles: $e}')"; }

[ "$cycle" -ge 1 ] || { out none '[]' 0; exit 0; }
shape=debate
for role in $(cycle_roles "$review" "$cycle"); do
  last_cycle_block "$review" "$cycle" "$role" | block_is_verified && { shape=verified; break; }
done
[ "$shape" = verified ] || { out debate '[]' 0; exit 0; }

report=$(bash "${HERE}/finalize-gate.sh" "$slug" --report 2>/dev/null | sed -n 's/^BUILD_FLEET_FINALIZE_REPORT: //p')
[ -n "$report" ] || { echo "review-carry.sh: finalize-gate.sh --report gave no report; refusing to carry an empty open set" >&2; exit 2; }
carried=$(printf '%s' "$report" | jq -c '.open // []')
exempt=$(read_events "$slug" "script:quote-check" | jq -s --argjson lo $((total - cycle)) --argjson hi "$total" \
  'group_by(.cycle_total) | map(.[0]) | map(select(.cycle_total > $lo and .cycle_total <= $hi and .exempt == true)) | length')
out verified "$carried" "${exempt:-0}"
