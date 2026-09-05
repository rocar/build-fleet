#!/usr/bin/env bash
# scripts/adr-index.sh — deterministic ADR index for a DECISIONS.md.
#
# Prints one line per ADR: "ADR-<N>: <title> [<status>]" — the id + title index the
# product-owner receives INSTEAD of the whole product ADR log (it Reads only the ADRs
# it cites), and the source of the disposition leg's next free feature ADR id.
#
# Usage: adr-index.sh <DECISIONS.md>          # the index, in file order
#        adr-index.sh <DECISIONS.md> --next   # next free integer id (1 if none/absent)
# Ids tolerate zero-padding (ADR-007 → 7). Status is the first "- **Status:** X" line
# inside the block, "unknown" when absent. Exit 0 always (an absent file is an empty
# log). bash 3.2 + BSD/GNU compatible; read-only.
set -uo pipefail

file="${1:-}"
mode="${2:-}"
[ -n "$file" ] || { echo "usage: adr-index.sh <DECISIONS.md> [--next]" >&2; exit 1; }
case "$file" in */../*|../*|*/..|..) echo "adr-index.sh: path '$file' contains '..' — refused" >&2; exit 1 ;; esac

if [ ! -f "$file" ]; then
  if [ "$mode" = "--next" ]; then echo 1; fi
  exit 0
fi

awk -v mode="$mode" '
  { gsub(/\r/, "") }
  /^##[[:space:]]+ADR-[0-9]+:/ {
    if (have) flush()
    line = $0
    sub(/^##[[:space:]]+ADR-/, "", line)
    id = line; sub(/:.*/, "", id); id = id + 0
    title = line; sub(/^[0-9]+:[[:space:]]*/, "", title)
    status = "unknown"; have = 1
    if (id > max) max = id
    next
  }
  have && /^-[[:space:]]+\*\*Status:\*\*/ && status == "unknown" {
    s = $0; sub(/^-[[:space:]]+\*\*Status:\*\*[[:space:]]*/, "", s); sub(/[[:space:]]+$/, "", s)
    status = s
  }
  function flush() { if (mode != "--next") printf "ADR-%d: %s [%s]\n", id, title, status }
  END {
    if (have) flush()
    if (mode == "--next") print max + 1
  }
' "$file"
