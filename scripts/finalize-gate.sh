#!/usr/bin/env bash
# scripts/finalize-gate.sh — the deterministic finalize gate (v0.9, rubric-only).
#
# /build-fleet:finalize calls this instead of evaluating REVIEW.md in prose, so the
# gate is testable and can never drift from the workflow's finalize_ready rule.
#
# Rule, over the CURRENT cycle's blocks (the LAST block per roster role whose heading
# is "## Cycle <CYCLE> — <role> —"):
#   - every roster role has a block                        else missing-<role>
#   - zero "- [blocker]" lines                             else open-blockers
#   - every "- [major]" line's next line is one of
#       "  refuted-by: …"            (closed by the survival vote)
#       "  disposition: adr ADR-N"   (closed — ADR-N must exist in DECISIONS.md, else majors-without-adr)
#       "  disposition: fix" / none  (OPEN                              → majors-open)
#   `status:` lines are NOT evaluated (informational since v0.9).
#
# Usage: finalize-gate.sh <slug> [--roster a,b,c]
#   ROSTER defaults to REVIEW_ROLES in PROGRESS.md, else architect,qa,coder.
# Output (stdout, exactly one line):
#   BUILD_FLEET_FINALIZE_GATE: {"feature","cycle","pass":bool,"reasons":[…],"open_blockers":[…],"open_majors":[…],"majors_without_adr":[…]}
# Exit: 0 = pass; 2 = refuse; 1 = bad usage / unreadable workspace.
# bash 3.2 + BSD/GNU compatible; read-only. Requires jq for JSON string escaping.
set -uo pipefail

slug="${1:-}"
[ -n "$slug" ] || { echo "usage: finalize-gate.sh <slug> [--roster a,b,c]" >&2; exit 1; }
case "$slug" in */*|..|.) echo "finalize-gate.sh: bad slug '$slug'" >&2; exit 1 ;; esac
shift
roster_arg=""
if [ "${1:-}" = "--roster" ]; then roster_arg="${2:-}"; fi
command -v jq >/dev/null 2>&1 || { echo "finalize-gate.sh: jq is required" >&2; exit 1; }

cd "${CLAUDE_PROJECT_DIR:-.}"
dir=".sdd/${slug}"
progress="${dir}/PROGRESS.md"; review="${dir}/REVIEW.md"; decisions="${dir}/DECISIONS.md"
[ -f "$progress" ] || { echo "finalize-gate.sh: ${progress} not found" >&2; exit 1; }

field() { { grep -m1 "^$1:" "$progress" 2>/dev/null || true; } | sed -E "s/^$1:[[:space:]]*//" | tr -d '\r '; }
cycle=$(field CYCLE)
case "$cycle" in ''|*[!0-9]*) echo "finalize-gate.sh: CYCLE is not an integer ('${cycle}')" >&2; exit 1 ;; esac

roster="$roster_arg"
[ -n "$roster" ] || roster=$(field REVIEW_ROLES)
[ -n "$roster" ] || roster="architect,qa,coder"
roles=$(printf '%s' "$roster" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep . || true)

reasons=""; open_blockers=""; open_majors=""; without_adr=""
add() { eval "$1=\"\${$1}\${$1:+\$'\\n'}\$2\""; }

for role in $roles; do
  [ -f "$review" ] || { add reasons "missing-${role}"; continue; }
  # last block for this role + cycle: heading line number
  start=$({ grep -nE "^##[[:space:]]+Cycle[[:space:]]+${cycle}[[:space:]]+[—–-][[:space:]]+${role}[[:space:]]+[—–-]" "$review" || true; } | tail -1 | cut -d: -f1)
  if [ -z "$start" ]; then add reasons "missing-${role}"; continue; fi
  # block end: next "## " heading after start, or EOF
  next=$({ tail -n +"$((start+1))" "$review" | grep -n '^## ' || true; } | head -1 | cut -d: -f1)
  if [ -n "$next" ]; then end=$((start+next-1)); else end=$(wc -l < "$review" | tr -d ' '); fi
  block=$(sed -n "${start},${end}p" "$review")

  # blockers
  while IFS= read -r l; do
    [ -n "$l" ] && add open_blockers "$l"
  done <<< "$(printf '%s\n' "$block" | grep -E '^-[[:space:]]+\[blocker\]' || true)"

  # majors: examine each major line + its following line
  n=$(printf '%s\n' "$block" | wc -l | tr -d ' ')
  k=1
  while [ $k -le $n ]; do
    line=$(printf '%s\n' "$block" | sed -n "${k}p")
    if printf '%s' "$line" | grep -qE '^-[[:space:]]+\[major\]'; then
      id=$(printf '%s' "$line" | sed -nE 's/^-[[:space:]]+\[major\][[:space:]]+\(([^)]+)\).*/\1/p')
      [ -n "$id" ] || id="$line"
      nextl=$(printf '%s\n' "$block" | sed -n "$((k+1))p")
      if printf '%s' "$nextl" | grep -qE '^[[:space:]]+refuted-by:'; then
        :
      elif printf '%s' "$nextl" | grep -qE '^[[:space:]]+disposition:[[:space:]]+adr[[:space:]]+ADR-0*[0-9]+'; then
        adr=$(printf '%s' "$nextl" | sed -nE 's/.*ADR-0*([0-9]+).*/\1/p')
        if [ -f "$decisions" ] && grep -qE "^##[[:space:]]+ADR-0*${adr}:" "$decisions"; then :; else add without_adr "$id"; fi
      else
        add open_majors "$id"
      fi
    fi
    k=$((k+1))
  done
done

[ -z "$open_blockers" ] || add reasons "open-blockers"
[ -z "$open_majors" ] || add reasons "majors-open"
[ -z "$without_adr" ] || add reasons "majors-without-adr"

tojson() { if [ -z "$1" ]; then printf '[]'; else printf '%s\n' "$1" | jq -R . | jq -sc .; fi; }
pass=true; [ -z "$reasons" ] || pass=false
printf 'BUILD_FLEET_FINALIZE_GATE: {"feature":"%s","cycle":%s,"pass":%s,"reasons":%s,"open_blockers":%s,"open_majors":%s,"majors_without_adr":%s}\n' \
  "$slug" "$cycle" "$pass" "$(tojson "$reasons")" "$(tojson "$open_blockers")" "$(tojson "$open_majors")" "$(tojson "$without_adr")"
[ "$pass" = true ] && exit 0 || exit 2
