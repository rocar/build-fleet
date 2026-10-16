#!/usr/bin/env bash
# scripts/finalize-gate.sh — the deterministic finalize gate (v0.9, rubric-only).
#
# /build-fleet:finalize calls this instead of evaluating REVIEW.md in prose, so the
# gate is testable and can never drift from the workflow's finalize_ready rule.
#
# Rule, over the CURRENT cycle's blocks (the LAST block per roster role whose heading
# is "## Cycle <CYCLE> — <role> —"):
#   - every roster role has a block                        else missing-<role>
#   - zero UNREFUTED "- [blocker]" lines                    else open-blockers
#   - every "- [major]" line is closed by one of the following, found anywhere in
#     the indented run of continuation lines following it (a legacy hand-written
#     finding may wrap its OWN text across several "  "-indented lines before the
#     real continuation appears — scan through those, don't stop at line+1):
#       "  refuted-by: …"            (closed by the survival vote)
#       "  disposition: adr ADR-N"   (closed — ADR-N must exist in DECISIONS.md, else majors-without-adr)
#       neither found in the run     (OPEN                              → majors-open)
#   The indented run ends at the first line matching "^- [", "^status:", "^## " or EOF.
#   A "  refuted-by: …" anywhere in that run closes a blocker or a major.
#   `status:` lines are NOT evaluated (informational since v0.9).
#   An indented finding bullet ("  - [blocker]" / "  - [major]", nested under another line)
#   is listed under "unparsed" and refuses with unparsed-findings — never invisible.
#
# Verified blocks (second line "shape: verified", REVIEW_SHAPE: verified) are judged
# by the rules in scripts/lib/verified-review.jq instead: the vote is recomputed from
# the "verdict:" lines and the cycle's quote-check event (first per cycle_total);
# no event ⇒ quote-check-missing; quote sources changed since the review ⇒
# spec-changed-since-review (gate mode only); a finding open in the previous verified
# cycle and absent from this one stays open (carried-open).
#
# Usage: finalize-gate.sh <slug> [--roster a,b,c] [--report]
#   ROSTER defaults to REVIEW_ROLES in PROGRESS.md, else architect,qa,coder.
# Output (stdout, exactly one line):
#   gate mode:   BUILD_FLEET_FINALIZE_GATE: {"feature","cycle","pass":bool,"reasons":[…],"open_blockers":[…],"open_majors":[…],"majors_without_adr":[…],"unparsed":[…]}
#   --report:    BUILD_FLEET_FINALIZE_REPORT: {…the same fields…, "cycle_total", "shape", "spec_changed", "open":[{id,severity,text,raised_by,why,…}]}
# Gate mode logs one gate event (script:finalize-gate) to .sdd/<slug>/EVENTS.jsonl;
# --report logs nothing, writes nothing, never refuses on spec-changed-since-review,
# and always exits 0.
# Exit (gate mode): 0 = pass; 2 = refuse; 1 = bad usage / unreadable workspace.
# bash 3.2 + BSD/GNU compatible. Requires jq.
set -uo pipefail

slug="${1:-}"
[ -n "$slug" ] || { echo "usage: finalize-gate.sh <slug> [--roster a,b,c]" >&2; exit 1; }
case "$slug" in */*|..|.|-*) echo "finalize-gate.sh: bad slug '$slug'" >&2; exit 1 ;; esac
shift
roster_arg=""; report=false
while [ $# -gt 0 ]; do
  case "$1" in
    --roster) roster_arg="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --report) report=true; shift ;;
    *) echo "finalize-gate.sh: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
command -v jq >/dev/null 2>&1 || { echo "finalize-gate.sh: jq is required" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../hooks/scripts/_lib.sh
. "${HERE}/../hooks/scripts/_lib.sh"
# shellcheck source=lib/review-blocks.sh
. "${HERE}/lib/review-blocks.sh"
RULES="$(cat "${HERE}/lib/verified-review.jq")"
dir=".sdd/${slug}"
progress="${dir}/PROGRESS.md"; review="${dir}/REVIEW.md"; decisions="${dir}/DECISIONS.md"
[ -f "$progress" ] || { echo "finalize-gate.sh: ${progress} not found" >&2; exit 1; }

field() { { grep -m1 "^$1:" "$progress" 2>/dev/null || true; } | sed -E "s/^$1:[[:space:]]*//" | tr -d '\r '; }
cycle=$(field CYCLE)
case "$cycle" in ''|*[!0-9]*) echo "finalize-gate.sh: CYCLE is not an integer ('${cycle}')" >&2; exit 1 ;; esac
cycle_total=$(field CYCLE_TOTAL)
case "$cycle_total" in ''|*[!0-9]*) cycle_total="$cycle" ;; esac

roster="$roster_arg"
[ -n "$roster" ] || roster=$(field REVIEW_ROLES)
[ -n "$roster" ] || roster="architect,qa,coder"
roles=$(printf '%s' "$roster" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep . || true)

reasons=""; open_blockers=""; open_majors=""; without_adr=""; unparsed=""
vblocks=""; legacy_blocks=0
add() { eval "$1=\"\${$1}\${$1:+\$'\\n'}\$2\""; }

for role in $roles; do
  [ -f "$review" ] || { add reasons "missing-${role}"; continue; }
  block=$(last_cycle_block "$review" "$cycle" "$role")
  if [ -z "$block" ]; then add reasons "missing-${role}"; continue; fi
  # verified blocks are read below by heading (cycle_roles), not by roster
  printf '%s\n' "$block" | block_is_verified && continue
  legacy_blocks=$((legacy_blocks+1))

  # blockers + majors: a finding is closed by a "refuted-by:"/"disposition: adr ADR-N"
  # continuation found ANYWHERE in the indented run of lines following it (C1: a
  # legacy hand-written finding may wrap its OWN text across several "  "-indented
  # lines before the real continuation — scan forward, don't stop at line k+1). The
  # run ends at the first line that is NOT indented (a new "- [" finding, "status:",
  # "## " heading, a blank line, or EOF).
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
      closed="" adr=""
      j=$((k+1))
      while [ $j -le $n ]; do
        contl=$(printf '%s\n' "$block" | sed -n "${j}p")
        printf '%s' "$contl" | grep -qE '^[[:space:]]+' || break
        if printf '%s' "$contl" | grep -qE '^[[:space:]]+refuted-by:'; then
          closed="refuted"; break
        elif printf '%s' "$contl" | grep -qE '^[[:space:]]+disposition:[[:space:]]+adr[[:space:]]+ADR-0*[0-9]+'; then
          closed="adr"; adr=$(printf '%s' "$contl" | sed -nE 's/.*ADR-0*([0-9]+).*/\1/p'); break
        fi
        j=$((j+1))
      done
      case "$closed" in
        refuted) : ;;
        adr)
          if [ -f "$decisions" ] && grep -qE "^##[[:space:]]+ADR-0*${adr}:" "$decisions"; then :; else add without_adr "$id"; fi
          ;;
        *) add open_majors "$id" ;;
      esac
    elif printf '%s' "$line" | grep -qE '^[[:space:]]+-[[:space:]]+\[(blocker|major)\]'; then
      # an indented finding bullet is a finding the grammar cannot classify — never invisible
      add unparsed "${role}: $(printf '%s' "$line" | sed -E 's/^[[:space:]]+//')"
    fi
    k=$((k+1))
  done
done

# ---- verified blocks: recompute the vote from verdict lines + the quote-check event ----
spec_changed=false; vopen='[]'
adr_nums() { { grep -E '^##[[:space:]]+ADR-0*[0-9]+:' "$decisions" 2>/dev/null || true; } \
  | sed -E 's/^##[[:space:]]+ADR-0*([0-9]+):.*/\1/' | jq -Rsc 'split("\n") | map(select(length > 0) | tonumber)'; }
qc_event() { read_events "$slug" "script:quote-check" | jq -c --argjson t "$1" 'select(.cycle_total == $t)' | head -1; }
# Every verified block of the current cycle, whatever the roster: a role added with --roles
# (not persisted) still counts. quote-check.sh hashed exactly this text.
vblocks=$(verified_cycle_blocks "$review" "$cycle")
# A jq evaluation that fails on the verified path refuses; it never reads as "no open findings".
vjson() { local out; out=$(jq "$@") && printf '%s' "$out" | jq -e 'type == "array"' >/dev/null 2>&1 && printf '%s' "$out"; }
if [ -n "$vblocks" ]; then
  adrs=$(adr_nums)
  ev=$(qc_event "$cycle_total")
  if [ -z "$ev" ]; then
    add reasons "quote-check-missing"; fails='[]'
  else
    fails=$(printf '%s' "$ev" | jq -c '.failures // []')
    fingerprint_matches "$slug" "$(printf '%s' "$ev" | jq -c '.files // {}')" || spec_changed=true
    [ "$(printf '%s' "$ev" | jq -r '.blocks_sha256 // empty')" = "$(printf '%s' "$vblocks" | sha256_stdin)" ] \
      || add reasons "review-changed-since-check"
  fi
  # carried-open safety net: open at the end of the previous verified cycle, absent now
  prev_open='[]'
  if [ "$cycle" -ge 2 ]; then
    pblocks=$(verified_cycle_blocks "$review" $((cycle-1)))
    if [ -n "$pblocks" ]; then
      pev=$(qc_event $((cycle_total-1)))
      [ -n "$pev" ] || pev='{}'
      pfails=$(printf '%s' "$pev" | jq -c '.failures // []') || pfails='[]'
      prev_open=$(printf '%s' "$pblocks" | vjson -c -Rs --argjson fails "$pfails" --argjson adrs "$adrs" "${RULES}"'
        vr_parse_blocks | map(vr_outcome($fails) | . + {why: vr_open($adrs)}) | map(select(.why != null))') \
        || { add reasons "verified-eval-failed"; prev_open='[]'; }
    fi
  fi
  vopen=$(printf '%s' "$vblocks" | vjson -c -Rs --argjson fails "$fails" --argjson adrs "$adrs" --argjson prev "$prev_open" "${RULES}"'
    vr_parse_blocks | . as $fs
    | ($fs | map(.id)) as $listed
    | ($fs | map(vr_outcome($fails) | . + {why: (if .carried != null and vr_open($adrs) != null then "carried" elif .reopened_closure and vr_open($adrs) != null then "reopened-closure" else vr_open($adrs) end)})
           | map(select(.why != null)))
      + [$prev[] | select(.id as $i | $listed | index($i) | not) | . + {why: "carried-open"}]
    | map({id, severity: .final, text, raised_by: vr_raiser, why,
           quote, absent, ref, test, disposition, carried} | with_entries(select(.value != null)))') \
    || { add reasons "verified-eval-failed"; vopen='[]'; }
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    id=$(printf '%s' "$row" | jq -r '.id'); why=$(printf '%s' "$row" | jq -r '.why'); sev=$(printf '%s' "$row" | jq -r '.severity')
    case "$why" in
      major-without-adr) add without_adr "$id" ;;
      *) if [ "$sev" = blocker ]; then add open_blockers "- [blocker] (${id}) $(printf '%s' "$row" | jq -r '.text')"; else add open_majors "$id"; fi ;;
    esac
  done <<EOF_ROWS
$(printf '%s' "$vopen" | jq -c '.[]')
EOF_ROWS
  [ "$report" = true ] || [ "$spec_changed" = false ] || add reasons "spec-changed-since-review"
fi

[ -z "$open_blockers" ] || add reasons "open-blockers"
[ -z "$open_majors" ] || add reasons "majors-open"
[ -z "$without_adr" ] || add reasons "majors-without-adr"
[ -z "$unparsed" ] || add reasons "unparsed-findings"

tojson() { if [ -z "$1" ]; then printf '[]'; else printf '%s\n' "$1" | jq -R . | jq -sc .; fi; }
pass=true; [ -z "$reasons" ] || pass=false
slug_json=$(jq -n --arg s "$slug" '$s')
if [ "$report" = true ]; then
  shape=debate
  if [ -n "$vblocks" ]; then if [ "$legacy_blocks" -gt 0 ]; then shape=mixed; else shape=verified; fi; fi
  printf 'BUILD_FLEET_FINALIZE_REPORT: %s\n' "$(jq -cn --argjson f "$slug_json" --argjson c "$cycle" --argjson t "$cycle_total" \
    --arg shape "$shape" --argjson pass "$pass" --argjson reasons "$(tojson "$reasons")" \
    --argjson ob "$(tojson "$open_blockers")" --argjson om "$(tojson "$open_majors")" --argjson wa "$(tojson "$without_adr")" --argjson up "$(tojson "$unparsed")" \
    --argjson sc "$spec_changed" --argjson open "$vopen" \
    '{feature: $f, cycle: $c, cycle_total: $t, shape: $shape, pass: $pass, reasons: $reasons, open_blockers: $ob,
      open_majors: $om, majors_without_adr: $wa, unparsed: $up, spec_changed: $sc, open: $open}')"
  exit 0
fi
printf 'BUILD_FLEET_FINALIZE_GATE: {"feature":%s,"cycle":%s,"pass":%s,"reasons":%s,"open_blockers":%s,"open_majors":%s,"majors_without_adr":%s,"unparsed":%s}\n' \
  "$slug_json" "$cycle" "$pass" "$(tojson "$reasons")" "$(tojson "$open_blockers")" "$(tojson "$open_majors")" "$(tojson "$without_adr")" "$(tojson "$unparsed")"
decision=pass; [ "$pass" = true ] || decision=refuse
log_event "$slug" "$(jq -cn --arg d "$decision" --argjson c "$cycle" --argjson t "$cycle_total" --argjson r "$(tojson "$reasons")" \
  '{kind: "gate", source: "script:finalize-gate", decision: $d, cycle: $c, cycle_total: $t, reasons: $r}')"
[ "$pass" = true ] && exit 0 || exit 2
