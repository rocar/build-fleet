#!/usr/bin/env bash
# scripts/quote-check.sh — check every quote in a verified review cycle against the
# files it cites, and record the result as ONE event (REVIEW_SHAPE: verified).
#
# Run by hooks/scripts/check-review-quotes.sh when the scribe releases the
# .workflow-in-flight marker (its final write), so the spec is exactly as reviewed.
# Rules live in scripts/lib/verified-review.jq (shared with finalize-gate.sh).
#
# Usage: quote-check.sh <slug> --cycle N
# Output (stdout, one line):
#   BUILD_FLEET_QUOTE_CHECK: {"slug","cycle","cycle_total","checked","failed","revived":[…],"exempt":bool,"skipped":null|"<reason>"}
#   (skipped: already-checked | not-verified | stale-cycle — --cycle is not PROGRESS's CYCLE)
# Event (first per cycle_total wins): kind gate, source script:quote-check,
#   decision pass|fail, cycle, cycle_total, files (fingerprint), checked, failures,
#   revived, exempt.
# Exit: 0 = checked or skipped; 1 = bad usage / unreadable workspace.
# bash 3.2 + BSD/GNU compatible. Requires jq.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
slug="${1:-}"
[ -n "$slug" ] || { echo "usage: quote-check.sh <slug> --cycle N" >&2; exit 1; }
case "$slug" in */*|..|.|-*) echo "quote-check.sh: bad slug '$slug'" >&2; exit 1 ;; esac
[ "${2:-}" = "--cycle" ] || { echo "usage: quote-check.sh <slug> --cycle N" >&2; exit 1; }
cycle="${3:-}"
case "$cycle" in ''|*[!0-9]*) echo "quote-check.sh: --cycle needs an integer" >&2; exit 1 ;; esac
command -v jq >/dev/null 2>&1 || { echo "quote-check.sh: jq is required" >&2; exit 1; }

# shellcheck source=../hooks/scripts/_lib.sh
. "${HERE}/../hooks/scripts/_lib.sh"
# shellcheck source=lib/review-blocks.sh
. "${HERE}/lib/review-blocks.sh"
RULES="$(cat "${HERE}/lib/verified-review.jq")"

dir=".sdd/${slug}"; progress="${dir}/PROGRESS.md"; review="${dir}/REVIEW.md"
[ -f "$progress" ] || { echo "quote-check.sh: ${progress} not found" >&2; exit 1; }
cycle_total=$(read_progress_field "$slug" CYCLE_TOTAL)
case "$cycle_total" in ''|*[!0-9]*) cycle_total="$cycle" ;; esac

signal() { # signal <checked> <failed> <revived-json> <exempt> <skipped-json>
  printf 'BUILD_FLEET_QUOTE_CHECK: %s\n' "$(jq -cn --arg s "$slug" --argjson c "$cycle" --argjson t "$cycle_total" \
    --argjson k "$1" --argjson f "$2" --argjson r "$3" --argjson e "$4" --argjson sk "$5" \
    '{slug: $s, cycle: $c, cycle_total: $t, checked: $k, failed: $f, revived: $r, exempt: $e, skipped: $sk}')"
}

# A --cycle that is not PROGRESS's CYCLE would record an event under the current
# cycle_total for another cycle's blocks; skip it, recording nothing.
cur=$(read_progress_field "$slug" CYCLE)
if [ -n "$cur" ] && [ "$cur" != "$cycle" ]; then signal 0 0 '[]' false '"stale-cycle"'; exit 0; fi

# First event per cycle_total wins: an incomplete run's marker release must never
# re-check this cycle against a spec revised since.
if read_events "$slug" "script:quote-check" | jq -e --argjson t "$cycle_total" 'select(.cycle_total == $t)' >/dev/null 2>&1; then
  signal 0 0 '[]' false '"already-checked"'; exit 0
fi

blocks=$(verified_cycle_blocks "$review" "$cycle")
if [ -z "$blocks" ]; then signal 0 0 '[]' false '"not-verified"'; exit 0; fi

docs=$(quote_docs_json "$slug")
result=$(printf '%s' "$blocks" | jq -Rs --argjson docs "$docs" --arg slug "$slug" "${RULES}"'
  split("\n## ") | map(vr_parse_block) | add // [] | . as $fs
  | ($fs | vr_quotes | map(. + {pass: vr_check($docs; $slug)})) as $q
  | ([$q[] | select(.pass | not) | {id, where} + (if .v != null then {v} else {} end)]) as $fails
  | ($fs | vr_revived($fails)) as $rev
  | {checked: ($q | length), failures: $fails, revived: $rev, exempt: (($rev | length) > 0)}') \
  || { echo "quote-check.sh: could not evaluate ${review}" >&2; exit 1; }

fp=$(quote_docs_fingerprint "$slug")
blocks_sha=$(printf '%s' "$blocks" | sha256_stdin)
failed=$(printf '%s' "$result" | jq '.failures | length')
decision=pass; [ "$failed" -eq 0 ] || decision=fail
log_event "$slug" "$(printf '%s' "$result" | jq -c --arg d "$decision" --argjson c "$cycle" --argjson t "$cycle_total" --argjson fp "$fp" --arg bs "$blocks_sha" \
  '{kind: "gate", source: "script:quote-check", decision: $d, cycle: $c, cycle_total: $t, files: $fp, blocks_sha256: $bs} + .')"
signal "$(printf '%s' "$result" | jq '.checked')" "$failed" "$(printf '%s' "$result" | jq -c '.revived')" \
  "$(printf '%s' "$result" | jq '.exempt')" null
exit 0
