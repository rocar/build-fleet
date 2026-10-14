#!/usr/bin/env bash
# scripts/lite-next.sh — the router behind the five lite commands.
#
# Reads .sdd/ state and prints exactly one line naming the next hidden step, or a stop:
#   BUILD_FLEET_LITE_NEXT: {"step":"<hidden command | action:hypothesis>","args":"<s>","why":"<s>"}
#   BUILD_FLEET_LITE_NEXT: {"stop":"<reason>","next":"/build-fleet:<cmd …>","why":"<s>"}
# Read-only: never writes. Fails closed: a state it does not recognise is a stop
# (unknown-state), never a guess. Routing table: docs/history/2026-10-15-lite.md §3.3.
#
# Usage: lite-next.sh <start|build|ship|fix|status> [args…]
# Env:   CLAUDE_PROJECT_DIR (project root; default $PWD)
#        BUILD_FLEET_FINALIZE_GATE (test seam; default scripts/finalize-gate.sh)
# bash 3.2 + BSD/GNU compatible. Requires jq (absent ⇒ unknown-state).
set -uo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${BUILD_FLEET_FINALIZE_GATE:-$HERE/finalize-gate.sh}"

cmd="${1:-}"
case "$cmd" in
  start|build|ship|fix|status) shift ;;
  *) echo "usage: lite-next.sh <start|build|ship|fix|status> [args…]" >&2; exit 1 ;;
esac
args="$*"

if ! command -v jq >/dev/null 2>&1; then
  printf 'BUILD_FLEET_LITE_NEXT: {"stop":"unknown-state","why":"jq is required"}\n'; exit 0
fi
cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null || {
  printf 'BUILD_FLEET_LITE_NEXT: {"stop":"unknown-state","why":"project dir unreadable"}\n'; exit 0; }

# A routing decision: kind=step|stop, name, sargs (a step's args), nxt (a stop's next), why.
kind=""; name=""; sargs=""; nxt=""; why=""; rpass=""; rchanged=""
T(){ kind=step; name="$1"; sargs="$2"; why="$3"; nxt=""; }
S(){ kind=stop; name="$1"; nxt="$2"; why="$3"; sargs=""; }

# field <file> <KEY> — the first "KEY: value" line, CR-stripped and trimmed; empty if absent.
field(){
  [ -f "$1" ] || return 0
  awk -v k="$2" '{ sub(/\r$/, "") } index($0, k ":") == 1 {
    v = substr($0, length(k) + 2); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }' "$1"
}
num(){ case "$1" in ''|*[!0-9]*) printf 0 ;; *) printf '%s' "$1" ;; esac; }

# slugify <text> — first six words as lowercase kebab, at most 40 chars, unique under .sdd/.
slugify(){
  local base s i
  base=$(printf '%s' "$1" | awk '{ for (i = 1; i <= NF && i <= 6; i++) printf "%s ", $i }' \
    | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//' | cut -c1-40 | sed 's/-*$//')
  [ -n "$base" ] || return 0
  s="$base"; i=2
  while [ -e ".sdd/$s" ]; do s="$base-$i"; i=$((i + 1)); done
  printf '%s' "$s"
}

is_trivial(){ [ "$1" = trivial ] && [ "$2" = SPEC ] && [ "$3" = 0 ]; }
newer(){ [ -f "$1" ] && { [ ! -f "$2" ] || [ "$1" -nt "$2" ]; }; }

# gate_report <slug> — sets rpass/rchanged from finalize-gate --report; stops on no report.
gate_report(){
  local line
  line=$(bash "$GATE" "$1" --report 2>/dev/null | sed -n 's/^BUILD_FLEET_FINALIZE_REPORT: //p' | head -1)
  rpass=$(printf '%s' "$line" | jq -r '.pass' 2>/dev/null)
  rchanged=$(printf '%s' "$line" | jq -r '.spec_changed' 2>/dev/null)
  case "$rpass" in true|false) return 0 ;; esac
  S unknown-state "" "the finalize report is unavailable"; return 1
}

route_product(){
  local pp=.sdd/_product/PROGRESS.md ph nf st
  [ -f "$pp" ] || { S nothing-to-do "" "no item in flight and no product backlog"; return; }
  ph=$(field "$pp" PHASE)
  case "$ph" in
    PLAN) T plan-review "" "the product plan has not been reviewed" ;;
    PLAN_REVIEW) S plan-ready "status ratify" "the product plan is reviewed and awaits ratification" ;;
    ESCALATED) S escalated "status resolve <decision>" "the product plan is escalated" ;;
    DEVELOPING)
      if ! grep -q '^<!-- BEGIN build-fleet:product' CLAUDE.md 2>/dev/null; then
        T product-memory "" "the product block in CLAUDE.md is missing"; return
      fi
      nf=$(bash "$HERE/next-feature.sh" .sdd/_product/backlog.md 2>/dev/null) || nf=""
      st=$(printf '%s' "$nf" | jq -r '.status // empty' 2>/dev/null)
      if [ "$st" = next ]; then
        T new-feature "$(printf '%s' "$nf" | jq -r '.slug')" "the next unblocked backlog feature"
      else
        S nothing-to-do "" "backlog: ${st:-unreadable}"
      fi ;;
    *) S unknown-state "" "product PHASE '$ph' not recognised" ;;
  esac
}

route_idle(){  # nothing in .sdd/ACTIVE
  local c="$1" a="$2" slug vision
  case "$c" in
    start)
      case "$a" in
        --product|--product\ *)
          if [ ! -f .sdd/_product/PROGRESS.md ]; then
            vision="${a#--product}"; vision="${vision# }"
            slug=$(slugify "$vision")
            [ -n "$slug" ] || { S nothing-to-do "" "--product needs a vision in words"; return; }
            T new-product "$slug $vision" "no product tier yet"; return
          fi ;;
        "") ;;
        *)
          slug=$(slugify "$a")
          [ -n "$slug" ] || { S nothing-to-do "" "the idea has no usable words"; return; }
          T new-feature "$slug $a" "nothing in flight; scaffold the idea"; return ;;
      esac
      route_product ;;
    build|ship) S nothing-to-do "start" "no item in flight" ;;
    fix)
      if [ -n "$a" ]; then T triage "$a" "nothing in flight; file the bug"
      else S nothing-to-do "" "no item in flight and no symptom given"; fi ;;
  esac
}

route_feature(){
  local c="$1" slug="$2" phase="$3" d=".sdd/$2" st tier cyc bs
  st=$(field "$d/spec.md" STATUS); tier=$(field "$d/PROGRESS.md" TIER)
  cyc=$(num "$(field "$d/PROGRESS.md" CYCLE)"); bs=$(field "$d/PROGRESS.md" BUILD_STATE)
  case "$c" in
    start)
      [ "$st" = FINALIZED ] && { S spec-ready "build" "the spec is finalized"; return; }
      [ "$st" = DRAFT ] || { S unknown-state "" "spec STATUS '$st' not recognised"; return; }
      case "$phase" in SPEC|REVIEW) ;; *) S unknown-state "" "DRAFT spec at PHASE '$phase'"; return ;; esac
      if is_trivial "$tier" "$phase" "$cyc"; then S spec-ready "build" "trivial tier: finalize skips review"; return; fi
      [ "$cyc" -gt 0 ] || { T review "" "the draft has not been reviewed"; return; }
      gate_report "$slug" || return
      if [ "$rpass" = true ]; then S spec-ready "build" "review is clean"; return; fi
      if [ "$rchanged" = true ] || newer "$d/spec.md" "$d/REVIEW.md" || newer "$d/acceptance.md" "$d/REVIEW.md"; then
        T review "" "the spec changed since the last review"
      else
        T revise "" "review has open items"
      fi ;;
    build)
      if [ "$st" != FINALIZED ]; then
        [ "$st" = DRAFT ] || { S unknown-state "" "spec STATUS '$st' not recognised"; return; }
        if is_trivial "$tier" "$phase" "$cyc"; then T finalize "" "trivial tier"; return; fi
        [ "$cyc" -gt 0 ] || { S spec-not-ready "start" "the spec has not been reviewed"; return; }
        gate_report "$slug" || return
        if [ "$rpass" = true ]; then T finalize "" "review is clean"
        else S spec-not-ready "start" "review has open items"; fi
        return
      fi
      case "$bs" in
        "") case "$phase" in
              CHANGE_REVIEW|HANDOFF) S built "ship" "already past BUILD" ;;
              SPEC|REVIEW|FINALIZE|BUILD) T implement "" "finalized; the build has not started" ;;
              *) S unknown-state "" "PHASE '$phase' not recognised" ;;
            esac ;;
        started|needs-iteration) T deep-build "" "build $bs; resume" ;;
        done) S built "ship" "the build is done" ;;
        *) S unknown-state "" "BUILD_STATE '$bs' not recognised" ;;
      esac ;;
    ship)
      if [ "$bs" = done ] || { [ -z "$bs" ] && { [ "$phase" = CHANGE_REVIEW ] || [ "$phase" = HANDOFF ]; }; }; then
        case "$phase" in
          BUILD|CHANGE_REVIEW|HANDOFF) T handoff "" "built; change review, then devops" ;;
          *) S unknown-state "" "PHASE '$phase' not recognised" ;;
        esac
      else
        S not-built "build" "the build is not done"
      fi ;;
  esac
}

route_bug(){
  local d=".sdd/$1" phase="$2" cyc hc fc fd
  cyc=$(num "$(field "$d/PROGRESS.md" CYCLE)")
  case "$phase" in
    REPORT) T reproduce "" "no reproduction yet" ;;
    REPRODUCE|DIAGNOSE)
      hc=$(num "$(field "$d/diagnosis.md" HYPOTHESIS_CYCLE)")
      if [ "$hc" -le "$cyc" ]; then
        T action:hypothesis "HYPOTHESIS_CYCLE: $((cyc + 1))" "no hypothesis awaits judgement"
      else
        T diagnose "" "hypothesis $hc awaits judgement"
      fi ;;
    FIX)
      fc=$(num "$(field "$d/PROGRESS.md" FIX_CYCLE)"); fd=$(field "$d/PROGRESS.md" FIX_DONE_CYCLE)
      if [ -n "$fd" ] && [ "$(num "$fd")" = "$fc" ]; then T verify "" "the fix is applied"
      else T apply-fix "" "the diagnosis is confirmed"; fi ;;
    HANDOFF) T ship-fix "" "the fix is verified" ;;
    *) S unknown-state "" "bug PHASE '$phase' not recognised" ;;
  esac
}

route_active(){
  local c="$1" a="$2" slug="$3" d p phase lane want
  d=".sdd/$slug"; p="$d/PROGRESS.md"
  [ -f "$p" ] || { S unknown-state "" "'$slug' has no PROGRESS.md"; return; }
  phase=$(field "$p" PHASE); lane=$(field "$p" LANE); [ -n "$lane" ] || lane=feature
  if [ -f "$d/ESCALATION.md" ] || [ "$phase" = ESCALATED ]; then
    S escalated "status resolve <decision>" "'$slug' is escalated"; return
  fi
  if [ "$phase" = PARKED ]; then
    S parked "" "'$slug' is parked; resuming it is a deliberate edit"; return
  fi
  want=feature; [ "$c" = fix ] && want=bug
  if [ "$lane" != "$want" ] || [ -n "$a" ]; then
    S item-in-flight "status park <reason>" "'$slug' ($lane) is in flight"; return
  fi
  if [ "$lane" = bug ]; then route_bug "$slug" "$phase"; else route_feature "$c" "$slug" "$phase"; fi
}

decide(){  # decide <cmd> <args>
  local active=""
  [ -f .sdd/ACTIVE ] && active=$(tr -d ' \t\r\n' < .sdd/ACTIVE)
  if [ -z "$active" ]; then route_idle "$1" "$2"; return; fi
  case "$active" in */*|.*|-*) S unknown-state "" ".sdd/ACTIVE holds an invalid slug"; return ;; esac
  route_active "$1" "$2" "$active"
}

if [ "$cmd" = status ]; then
  via=start; decide start ""
  if [ "$kind" = stop ] && [ "$name" = spec-ready ]; then via=build; decide build ""; fi
  if [ "$kind" = stop ] && [ "$name" = built ]; then via=ship; decide ship ""; fi
  if [ "$kind" = stop ] && [ "$name" = item-in-flight ]; then via=fix; decide fix ""; fi
  if [ "$kind" = step ]; then S status "$via" "next step: $name"; fi
else
  decide "$cmd" "$args"
fi
[ -n "$kind" ] || S unknown-state "" "no routing row matched"

if [ "$kind" = step ]; then
  jq -cn --arg s "$name" --arg a "$sargs" --arg w "$why" '{step: $s, args: $a, why: $w}'
else
  jq -cn --arg r "$name" --arg n "$nxt" --arg w "$why" \
    '{stop: $r} + (if $n == "" then {} else {next: ("/build-fleet:" + $n)} end) + {why: $w}'
fi | sed 's/^/BUILD_FLEET_LITE_NEXT: /'
exit 0
