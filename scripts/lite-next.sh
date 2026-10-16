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
# Project root: CLAUDE_PROJECT_DIR, else the nearest ancestor holding .sdd/, else the
# git toplevel, else $PWD — a caller whose shell sits in a subdirectory must not see
# "nothing in flight".
root="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$root" ]; then
  d="$PWD"
  while [ "$d" != "/" ] && [ ! -d "$d/.sdd" ]; do d=$(dirname "$d"); done
  if [ -d "$d/.sdd" ]; then root="$d"
  else root=$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD"); fi
fi
cd "$root" 2>/dev/null || {
  printf 'BUILD_FLEET_LITE_NEXT: {"stop":"unknown-state","why":"project dir unreadable"}\n'; exit 0; }

# A routing decision: kind=step|stop, name, sargs (a step's args), nxt (a stop's next), why.
kind=""; name=""; sargs=""; nxt=""; why=""; rpass=""; rchanged=""; rrevisable=""
T(){ kind=step; name="$1"; sargs="$2"; why="$3"; nxt=""; }
S(){ kind=stop; name="$1"; nxt="$2"; why="$3"; sargs=""; }

# field <file> <KEY> — the first "KEY: value" line, CR-stripped and trimmed; empty if absent.
field(){
  [ -f "$1" ] || return 0
  awk -v k="$2" '{ sub(/\r$/, "") } index($0, k ":") == 1 {
    v = substr($0, length(k) + 2); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }' "$1"
}
num(){ case "$1" in ''|*[!0-9]*) printf 0 ;; *) printf '%s' "$1" ;; esac; }

# slug_base <text> — first six words as lowercase kebab, at most 40 chars. Common Latin
# accents are folded by a fixed byte table (Café → cafe; iconv's TRANSLIT is locale-
# dependent on glibc); empty when no ASCII letter or digit remains.
LATIN_FOLD='s/à/a/g;s/À/A/g;s/á/a/g;s/Á/A/g;s/â/a/g;s/Â/A/g;s/ã/a/g;s/Ã/A/g;s/ä/a/g;s/Ä/A/g;s/å/a/g;s/Å/A/g;s/ā/a/g;s/Ā/A/g;s/ă/a/g;s/Ă/A/g;s/ç/c/g;s/Ç/C/g;s/ć/c/g;s/Ć/C/g;s/č/c/g;s/Č/C/g;s/ď/d/g;s/Ď/D/g;s/đ/d/g;s/Đ/D/g;s/ð/d/g;s/Ð/D/g;s/è/e/g;s/È/E/g;s/é/e/g;s/É/E/g;s/ê/e/g;s/Ê/E/g;s/ë/e/g;s/Ë/E/g;s/ē/e/g;s/Ē/E/g;s/ę/e/g;s/Ę/E/g;s/ě/e/g;s/Ě/E/g;s/ğ/g/g;s/Ğ/G/g;s/ì/i/g;s/Ì/I/g;s/í/i/g;s/Í/I/g;s/î/i/g;s/Î/I/g;s/ï/i/g;s/Ï/I/g;s/ī/i/g;s/Ī/I/g;s/ı/i/g;s/İ/I/g;s/ł/l/g;s/Ł/L/g;s/ľ/l/g;s/Ľ/L/g;s/ñ/n/g;s/Ñ/N/g;s/ń/n/g;s/Ń/N/g;s/ň/n/g;s/Ň/N/g;s/ò/o/g;s/Ò/O/g;s/ó/o/g;s/Ó/O/g;s/ô/o/g;s/Ô/O/g;s/õ/o/g;s/Õ/O/g;s/ö/o/g;s/Ö/O/g;s/ø/o/g;s/Ø/O/g;s/ō/o/g;s/Ō/O/g;s/ř/r/g;s/Ř/R/g;s/ś/s/g;s/Ś/S/g;s/š/s/g;s/Š/S/g;s/ş/s/g;s/Ş/S/g;s/ť/t/g;s/Ť/T/g;s/ţ/t/g;s/Ţ/T/g;s/ù/u/g;s/Ù/U/g;s/ú/u/g;s/Ú/U/g;s/û/u/g;s/Û/U/g;s/ü/u/g;s/Ü/U/g;s/ū/u/g;s/Ū/U/g;s/ů/u/g;s/Ů/U/g;s/ý/y/g;s/Ý/Y/g;s/ÿ/y/g;s/Ÿ/Y/g;s/ź/z/g;s/Ź/Z/g;s/ż/z/g;s/Ż/Z/g;s/ž/z/g;s/Ž/Z/g;s/ß/ss/g;s/æ/ae/g;s/Æ/AE/g;s/œ/oe/g;s/Œ/OE/g;s/þ/th/g;s/Þ/TH/g'
slug_base(){
  printf '%s' "$1" | LC_ALL=C sed "$LATIN_FOLD" | awk '{ for (i = 1; i <= NF && i <= 6; i++) printf "%s ", $i }' \
    | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//' | LC_ALL=C cut -c1-40 | sed 's/-*$//'
}
# slugify <text> <fallback> — slug_base, unique under .sdd/. Words in a script with no
# ASCII form (日本語) take <fallback>; symbols only give an empty slug.
slugify(){
  local base s i
  base=$(slug_base "$1")
  if [ -z "$base" ] && printf '%s' "$1" | LC_ALL=C grep -q '[^ -~]'; then base="$2"; fi
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
  # revise can close open blockers/majors only; any other reason (a missing or
  # unparsed reviewer block, an ADR the architect cited but never wrote) needs review.
  rrevisable=$(printf '%s' "$line" | jq -r '
    if ((.reasons // []) | length) == 0 then "yes"
    elif ((.reasons // []) | any(. == "open-blockers" or . == "majors-open")) then "yes"
    else "no" end' 2>/dev/null)
  case "$rpass" in true|false) return 0 ;; esac
  S unknown-state "" "the finalize report is unavailable"; return 1
}

route_product(){
  local pp=.sdd/_product/PROGRESS.md ph nf st
  [ -f "$pp" ] || { S nothing-to-do "" "no item in flight and no product backlog"; return; }
  ph=$(field "$pp" PHASE)
  case "$ph" in
    PLAN)
      if [ "$(field "$pp" SIZE)" = small ] && [ "$(num "$(field "$pp" CYCLE)")" = 0 ]; then
        S plan-ready "status ratify" "small product: ratification skips the plan review"
      else
        T plan-review "" "the product plan has not been reviewed"
      fi ;;
    PLAN_REVIEW)
      local f
      for f in vision.md backlog.md STACK.md DECISIONS.md; do
        if [ -f .sdd/_product/REVIEW.md ] && newer ".sdd/_product/$f" .sdd/_product/REVIEW.md; then
          T plan-review "" "the product plan changed since its review"; return
        fi
      done
      S plan-ready "status ratify" "the product plan is reviewed and awaits ratification" ;;
    ESCALATED) S escalated "status resolve _product <decision>" "the product plan is escalated" ;;
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
            slug=$(slugify "$vision" product)
            [ -n "$slug" ] || { S nothing-to-do "" "--product needs a vision in words"; return; }
            T new-product "$slug $vision" "no product tier yet"; return
          fi
          S product-exists "status" "a product tier already exists; edit .sdd/_product/vision.md instead"; return ;;
        "") ;;
        *)
          slug=$(slug_base "$a")
          if [ -n "$slug" ] && [ "$(field ".sdd/$slug/PROGRESS.md" PHASE)" = PARKED ]; then
            S parked "" "'$slug' is parked under this name; resuming it is a deliberate edit, or word the idea differently"; return
          fi
          slug=$(slugify "$a" feature)
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
  local c="$1" slug="$2" phase="$3" d=".sdd/$2" st tier cyc bs qf
  st=$(field "$d/spec.md" STATUS); tier=$(field "$d/PROGRESS.md" TIER)
  cyc=$(num "$(field "$d/PROGRESS.md" CYCLE)"); bs=$(field "$d/PROGRESS.md" BUILD_STATE)
  qf=$(field "$d/PROGRESS.md" QA_FAIL)
  case "$c" in
    start)
      [ "$st" = FINALIZED ] && { S spec-ready "build" "the spec is finalized"; return; }
      [ "$st" = DRAFT ] || { S unknown-state "" "spec STATUS '$st' not recognised"; return; }
      case "$phase" in SPEC|REVIEW) ;; *) S unknown-state "" "DRAFT spec at PHASE '$phase'"; return ;; esac
      if is_trivial "$tier" "$phase" "$cyc"; then S spec-ready "build" "trivial tier: finalize skips review"; return; fi
      [ "$cyc" -gt 0 ] || { T review "" "the draft has not been reviewed"; return; }
      gate_report "$slug" || return
      if [ "$rpass" = true ]; then S spec-ready "build" "review is clean"; return; fi
      if [ "$rchanged" = true ] || newer "$d/spec.md" "$d/REVIEW.md"; then
        T review "" "the spec changed since the last review"
      elif [ "$rrevisable" = no ]; then
        T review "" "the review is incomplete; revise cannot close it"
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
      # markers that failed the drift gate: implement runs only its qa repair pass
      if [ "$qf" = drift ]; then T implement "" "repair the criterion markers"; return; fi
      case "$bs" in
        "") case "$phase" in
              CHANGE_REVIEW|HANDOFF) S built "ship" "already past BUILD" ;;
              SPEC|REVIEW) T finalize "" "the spec is finalized but PHASE is $phase; finalize sets BUILD" ;;
              FINALIZE|BUILD) T implement "" "finalized; the build has not started" ;;
              *) S unknown-state "" "PHASE '$phase' not recognised" ;;
            esac ;;
        started|needs-iteration) T deep-build "" "build $bs; resume" ;;
        done) S built "ship" "the build is done" ;;
        *) S unknown-state "" "BUILD_STATE '$bs' not recognised" ;;
      esac ;;
    ship)
      if [ "$qf" = drift ]; then S drift "build" "the criterion markers have drifted; build repairs it"; return; fi
      if [ "$bs" = done ] || { [ -z "$bs" ] && { [ "$phase" = CHANGE_REVIEW ] || [ "$phase" = HANDOFF ]; }; }; then
        [ "$st" = FINALIZED ] || { S unknown-state "" "spec STATUS '$st' after a build; ship needs a FINALIZED spec"; return; }
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
      # sev0 hotfix: diagnose skips confirmation and apply-fix takes it from DIAGNOSED.
      if [ "$phase" = DIAGNOSE ] && [ "$(field "$d/PROGRESS.md" SEV)" = sev0 ] \
         && [ "$(field "$d/diagnosis.md" STATUS)" = DIAGNOSED ]; then
        T apply-fix "" "sev0 fast path"; return
      fi
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
  # a new idea or symptom needs the slot: park the item in flight first
  if [ -n "$a" ] && { [ "$c" = start ] || [ "$c" = fix ]; }; then
    S item-in-flight "status park <reason>" "'$slug' ($lane) is in flight"; return
  fi
  if [ "$lane" != "$want" ]; then
    if [ "$lane" = bug ]; then S item-in-flight "fix" "'$slug' (bug) is in flight; fix drives it"
    else S item-in-flight "status" "'$slug' (feature) is in flight; status names its next command"; fi
    return
  fi
  [ -z "$a" ] || { S bad-args "$c" "$c takes no arguments"; return; }
  if [ "$lane" = bug ]; then route_bug "$slug" "$phase"; return; fi
  if [ "$(field "$p" SDD_SCHEMA)" != 2 ]; then
    S unsupported-schema "status park <reason>" "'$slug' was started by an older build-fleet; park it and start it again"; return
  fi
  route_feature "$c" "$slug" "$phase"
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
