#!/usr/bin/env bash
# PreToolUse(Write|Edit|NotebookEdit): the event log is append-only and written only by
# build-fleet's own scripts (log_event in _lib.sh). An agent tool call that targets
# .sdd/<slug>/EVENTS.jsonl or .sdd/_events.jsonl is refused (exit 2), whatever the
# phase and whether or not a workflow is in flight. Everything else passes (exit 0).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "${HERE}/_lib.sh"
input=$(cat)
if ! command -v jq >/dev/null 2>&1; then
  # Without jq the path cannot be read; refuse only when the raw payload names an event log.
  case "$input" in *EVENTS.jsonl*|*_events.jsonl*) echo "build-fleet: the event log is written only by build-fleet scripts (jq missing; refusing)." >&2; exit 2 ;; esac
  exit 0
fi
path=$(extract_file_path "$input" 2>/dev/null) || exit 0
[ -n "$path" ] || exit 0
case "$(basename "$path")" in
  EVENTS.jsonl|_events.jsonl)
    if path_in_sdd "$path" || case "$path" in */.sdd/*|.sdd/*) true ;; *) false ;; esac; then
      echo "build-fleet: ${path} is the append-only event log; only build-fleet's scripts write it. Agents never edit it." >&2
      exit 2
    fi ;;
esac
exit 0
