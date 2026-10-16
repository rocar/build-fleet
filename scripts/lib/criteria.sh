# scripts/lib/criteria.sh — acceptance criteria of a spec. Sourced, never run.
# The one extractor: hooks/scripts/validate-acceptance-count.sh and scripts/drift-gate.sh
# both call it, so the hook's count and the gate's set cannot disagree.
# bash 3.2 + BSD/GNU compatible.

# spec_criteria <spec.md> — distinct AC-<n>[a-z] ids in the `## Acceptance…` section
# (from that heading to the next `## ` heading; `### ` subsections stay inside), one per
# line, sorted. Nothing for a missing file or a spec with no such section.
spec_criteria() {
  [ -f "$1" ] || return 0
  awk '{ sub(/\r$/, "") } /^## /{ insec = ($0 ~ /^## Acceptance/); next } insec' "$1" \
    | { grep -oE 'AC-[0-9]+[a-z]?' || true; } | LC_ALL=C sort -u
}
