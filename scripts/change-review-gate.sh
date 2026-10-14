#!/usr/bin/env bash
# scripts/change-review-gate.sh — the deterministic CHANGE_REVIEW gate (rubric-only).
#
# /build-fleet:handoff calls this instead of evaluating REVIEW.md in prose, so the
# exit rule is testable and the budget guard and the post-review evaluation can
# never disagree.
#
# Rule, over the CURRENT change cycle's blocks (the LAST block per roster role whose
# heading is "## Change-Cycle <CHANGE_CYCLE> — <role> —"; a same-numbered spec-review
# "## Cycle <N>" block never matches):
#   - every roster role has a block                        else missing-<role>
#   - zero UNREFUTED "- [blocker]" lines                    else open-blockers
#   - every "- [major]" line is closed:
#       "  refuted-by: …"            in its continuation run  → closed
#       "  disposition: adr ADR-N"   in its run, ADR-N present in DECISIONS.md → closed
#       "  disposition: adr ADR-N"   in its run, ADR-N absent → majors-without-adr
#       id "<role>-cc<K>-<n>" with K == CHANGE_CYCLE and CHANGE_CYCLE >= 2 → DEMOTED
#                                    (a new major on a delta cycle is advisory; reported,
#                                     never blocks)
#       otherwise ("disposition: fix" or no disposition line)  → OPEN → majors-open
#   Two passes. Pass one records every major's state per id across all roster blocks.
#   Pass two resolves per id: an id closed by an ADR in ANY block is closed in every
#   block (the architect may accept a peer's major by re-listing its id with an ADR).
#   The continuation run is the indented lines after a finding; it ends at the first
#   line that is not indented ("- [", "status:", "## ", a blank line, or EOF).
#   `status:` lines are NOT evaluated.
#   A finding bullet the grammar cannot read (indented "  - [blocker]" / "  - [major]",
#   i.e. nested under another line) is never silently dropped: it is listed under
#   "unparsed" and the gate refuses with unparsed-findings.
#
# Usage: change-review-gate.sh <slug> [--roster a,b,c]
#   ROSTER defaults to architect,product-owner,qa (the CHANGE_REVIEW roster; there is
#   no PROGRESS field for it).
# Output (stdout, exactly one line):
#   BUILD_FLEET_CHANGE_REVIEW_GATE: {"feature","change_cycle","pass":bool,"reasons":[…],"open_blockers":[…],"open_majors":[…],"majors_without_adr":[…],"demoted":[…],"unparsed":[…]}
# Exit: 0 = pass; 2 = refuse; 1 = bad usage / unreadable workspace.
# bash 3.2 + BSD/GNU compatible; read-only. Requires jq for JSON string escaping.
set -uo pipefail

slug="${1:-}"
[ -n "$slug" ] || { echo "usage: change-review-gate.sh <slug> [--roster a,b,c]" >&2; exit 1; }
case "$slug" in */*|..|.|-*) echo "change-review-gate.sh: bad slug '$slug'" >&2; exit 1 ;; esac
shift
roster_arg=""
if [ "${1:-}" = "--roster" ]; then roster_arg="${2:-}"; fi
command -v jq >/dev/null 2>&1 || { echo "change-review-gate.sh: jq is required" >&2; exit 1; }

cd "${CLAUDE_PROJECT_DIR:-.}"
dir=".sdd/${slug}"
progress="${dir}/PROGRESS.md"; review="${dir}/REVIEW.md"; decisions="${dir}/DECISIONS.md"
[ -f "$progress" ] || { echo "change-review-gate.sh: ${progress} not found" >&2; exit 1; }

field() { { grep -m1 "^$1:" "$progress" 2>/dev/null || true; } | sed -E "s/^$1:[[:space:]]*//" | tr -d '\r '; }
cycle=$(field CHANGE_CYCLE)
case "$cycle" in ''|*[!0-9]*) echo "change-review-gate.sh: CHANGE_CYCLE is not an integer ('${cycle}')" >&2; exit 1 ;; esac

roster="$roster_arg"
[ -n "$roster" ] || roster="architect,product-owner,qa"
roles=$(printf '%s' "$roster" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep . || true)

reasons=""; open_blockers=""; records=""; unparsed=""
add() { eval "$1=\"\${$1}\${$1:+\$'\\n'}\$2\""; }

# ---- pass one: scan every roster block, record blockers and per-id major states ----
for role in $roles; do
  [ -f "$review" ] || { add reasons "missing-${role}"; continue; }
  start=$({ grep -nE "^##[[:space:]]+Change-Cycle[[:space:]]+${cycle}[[:space:]]+(—|–|-)[[:space:]]+${role}[[:space:]]+(—|–|-)" "$review" || true; } | tail -1 | cut -d: -f1)
  if [ -z "$start" ]; then add reasons "missing-${role}"; continue; fi
  next=$({ tail -n +"$((start+1))" "$review" | grep -n '^## ' || true; } | head -1 | cut -d: -f1)
  if [ -n "$next" ]; then end=$((start+next-1)); else end=$(grep -c '' "$review" || true); fi   # grep -c '' counts an unterminated last line; wc -l does not
  block=$(sed -n "${start},${end}p" "$review" | tr -d '\r')   # CRLF: a bare \r would read as an indented continuation

  n=$(printf '%s\n' "$block" | wc -l | tr -d ' ')
  k=1
  while [ $k -le $n ]; do
    line=$(printf '%s\n' "$block" | sed -n "${k}p")
    if printf '%s' "$line" | grep -qE '^-[[:space:]]+\[blocker\]'; then
      refuted=false
      j=$((k+1))
      while [ $j -le $n ]; do
        contl=$(printf '%s\n' "$block" | sed -n "${j}p")
        printf '%s' "$contl" | grep -qE '^[[:space:]]+' || break
        if printf '%s' "$contl" | grep -qE '^[[:space:]]+refuted-by:'; then refuted=true; break; fi
        j=$((j+1))
      done
      [ "$refuted" = true ] || add open_blockers "$line"
    elif printf '%s' "$line" | grep -qE '^-[[:space:]]+\[major\]'; then
      id=$(printf '%s' "$line" | sed -nE 's/^-[[:space:]]+\[major\][[:space:]]+\(([^)]+)\).*/\1/p')
      [ -n "$id" ] || id="$line"
      state="open"
      j=$((k+1))
      while [ $j -le $n ]; do
        contl=$(printf '%s\n' "$block" | sed -n "${j}p")
        printf '%s' "$contl" | grep -qE '^[[:space:]]+' || break
        if printf '%s' "$contl" | grep -qE '^[[:space:]]+refuted-by:'; then
          state="refuted"; break
        elif printf '%s' "$contl" | grep -qE '^[[:space:]]+disposition:[[:space:]]+adr[[:space:]]+ADR-0*[0-9]+'; then
          adr=$(printf '%s' "$contl" | sed -nE 's/.*ADR-0*([0-9]+).*/\1/p')
          if [ -f "$decisions" ] && grep -qE "^##[[:space:]]+ADR-0*${adr}:" "$decisions"; then state="adr-ok"; else state="adr-missing"; fi
          break
        fi
        j=$((j+1))
      done
      # delta rule: a major whose id ORIGINATES at this cycle (K == CHANGE_CYCLE >= 2)
      # is advisory. Blockers are never demoted; re-raised ids (K < cycle) stay open.
      if [ "$state" = "open" ] && [ "$cycle" -ge 2 ]; then
        korig=$(printf '%s' "$id" | sed -nE 's/^[a-z-]+-cc0*([0-9]+)-[0-9]+$/\1/p')
        if [ -n "$korig" ] && [ "$korig" -eq "$cycle" ]; then state="demoted"; fi
      fi
      add records "${state}"$'\t'"${id}"
    elif printf '%s' "$line" | grep -qE '^[[:space:]]+-[[:space:]]+\[(blocker|major)\]'; then
      # an indented finding bullet is a finding the grammar cannot classify — never invisible
      add unparsed "${role}: $(printf '%s' "$line" | sed -E 's/^[[:space:]]+//')"
    fi
    k=$((k+1))
  done
done

# ---- pass two: resolve per id (adr-ok anywhere wins; then adr-missing; then demoted; then open) ----
open_majors=""; without_adr=""; demoted=""
ids=$(printf '%s\n' "$records" | grep . | cut -f2- | awk '!seen[$0]++' || true)
if [ -n "$ids" ]; then
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    # ENVIRON, not awk -v: -v processes backslash escapes, which would mangle a legacy id
    # (the whole finding line) so that it matched no record and fell out of every list.
    states=$(printf '%s\n' "$records" | WANT="$id" awk -F'\t' 'substr($0, length($1)+2) == ENVIRON["WANT"] { print $1 }')
    if printf '%s\n' "$states" | grep -qx 'adr-ok'; then :
    elif printf '%s\n' "$states" | grep -qx 'adr-missing'; then add without_adr "$id"
    elif printf '%s\n' "$states" | grep -qx 'demoted'; then add demoted "$id"
    elif printf '%s\n' "$states" | grep -qx 'open'; then add open_majors "$id"
    elif printf '%s\n' "$states" | grep -qx 'refuted'; then :
    else add open_majors "$id"   # a state the resolver cannot place: fail closed
    fi
  done <<EOF_IDS
$ids
EOF_IDS
fi

[ -z "$open_blockers" ] || add reasons "open-blockers"
[ -z "$open_majors" ] || add reasons "majors-open"
[ -z "$without_adr" ] || add reasons "majors-without-adr"
[ -z "$unparsed" ] || add reasons "unparsed-findings"

tojson() { if [ -z "$1" ]; then printf '[]'; else printf '%s\n' "$1" | jq -R . | jq -sc .; fi; }
pass=true; [ -z "$reasons" ] || pass=false
slug_json=$(jq -n --arg s "$slug" '$s')
printf 'BUILD_FLEET_CHANGE_REVIEW_GATE: {"feature":%s,"change_cycle":%s,"pass":%s,"reasons":%s,"open_blockers":%s,"open_majors":%s,"majors_without_adr":%s,"demoted":%s,"unparsed":%s}\n' \
  "$slug_json" "$cycle" "$pass" "$(tojson "$reasons")" "$(tojson "$open_blockers")" "$(tojson "$open_majors")" "$(tojson "$without_adr")" "$(tojson "$demoted")" "$(tojson "$unparsed")"
[ "$pass" = true ] && exit 0 || exit 2
