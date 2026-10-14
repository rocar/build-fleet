#!/usr/bin/env bash
# PostToolUse(Write): run scripts/quote-check.sh when the scribe releases a workflow's
# .workflow-in-flight marker — its FINAL write, after every REVIEW.md block and every
# DECISIONS.md append has landed — and the newest REVIEW.md block is the current
# cycle in the verified shape. Does nothing otherwise (another file, a non-empty
# write, a debate block, an incomplete run that appended no block).
#
# Never changes the write's outcome: always exits 0. Fires inside workflow runs on
# purpose (it does not skip on .workflow-in-flight — the marker write IS the trigger).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "${HERE}/_lib.sh"
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
[ "$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" = "Write" ] || exit 0
path=$(extract_file_path "$input" 2>/dev/null) || exit 0
[ "$(printf '%s' "$input" | jq -r '.tool_input.content // "x"' 2>/dev/null)" = "" ] || exit 0
path_in_sdd "$path" || exit 0
case "$path" in */.workflow-in-flight) ;; *) exit 0 ;; esac
slug=$(basename "$(dirname "$path")")
case "$slug" in ''|.|..|.sdd|_product|-*) exit 0 ;; esac

review=".sdd/${slug}/REVIEW.md"
[ -f "$review" ] || exit 0
cycle=$(read_progress_field "$slug" CYCLE)
case "$cycle" in ''|*[!0-9]*) exit 0 ;; esac
# newest cycle heading must be the current cycle
last=$({ grep -E '^##[[:space:]]+Cycle[[:space:]]+[0-9]+[[:space:]]' "$review" || true; } | tail -1 | sed -E 's/^##[[:space:]]+Cycle[[:space:]]+([0-9]+).*/\1/')
[ "$last" = "$cycle" ] || exit 0
start=$({ grep -nE '^##[[:space:]]+Cycle[[:space:]]+[0-9]+[[:space:]]' "$review" || true; } | tail -1 | cut -d: -f1)
[ "$(sed -n "$((start+1))p" "$review" | tr -d '\r')" = "shape: verified" ] || exit 0

bash "${HERE}/../../scripts/quote-check.sh" "$slug" --cycle "$cycle" >/dev/null 2>&1 || true
exit 0
