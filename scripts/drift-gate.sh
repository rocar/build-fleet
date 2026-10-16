#!/usr/bin/env bash
# scripts/drift-gate.sh — the drift gate: every acceptance criterion of a feature is named
# by at least one test marker. Static and model-free.
#
# Gated = PROGRESS.md's DRIFT_GATE is absent, empty or `on`; `off` = unchecked; any other
# value = bad-field. Criteria = distinct AC-<n>[a-z] ids in spec.md's `## Acceptance…`
# section (scripts/lib/criteria.sh). A marker is `<slug>/AC-<n>[a-z]` in a regular, non-.md
# file under the test roots, not preceded by [A-Za-z0-9_.-] and not followed by
# [A-Za-z0-9_-] — so `#calc/AC-3` and `//calc/AC-3` match, `calc/AC-30`, `old-calc/AC-3`
# and `calc/AC-3a` do not count for `calc/AC-3`. Other features' markers are ignored.
# Test roots = TEST_ROOTS (comma-separated, project-relative) if set, else whichever of
# tests, test, spec exist. .git/, node_modules/ and .sdd/ are skipped.
#
# Reasons, in this order: bad-field unsupported-schema no-criteria no-test-roots untested
# unknown-criterion.
#
# Usage: drift-gate.sh <slug> | drift-gate.sh --all | drift-gate.sh --markers <slug>
#   --markers prints the ids marked `<slug>/AC-…` under the test roots, one per line (exit 0;
#   1 on bad usage) — the same matcher, for callers that only ask "are there markers?".
# Output (stdout): one `BUILD_FLEET_DRIFT_GATE: {…}` line per feature; --all adds one
#   `BUILD_FLEET_DRIFT_GATE_SUMMARY: {"checked","unchecked","in_progress","failed"}` line.
#   --all reports a forward feature whose SDD_SCHEMA is not 2 as unchecked (never failed).
# Exit: 0 = pass; 2 = fail; 1 = bad usage / unreadable workspace (CI keys off this).
# bash 3.2 + BSD/GNU compatible; read-only. Requires jq.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/criteria.sh
. "$HERE/lib/criteria.sh"

usage() { echo "usage: drift-gate.sh <slug> | drift-gate.sh --all | drift-gate.sh --markers <slug>" >&2; exit 1; }
[ $# -eq 1 -a "${1:-}" != "--markers" ] || [ $# -eq 2 -a "${1:-}" = "--markers" ] || usage
command -v jq >/dev/null 2>&1 || { echo "drift-gate.sh: jq is required" >&2; exit 1; }
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 1

# field <file> <NAME> — the value of the first "NAME:" line, whitespace stripped
field() { { grep -m1 "^$2:" "$1" 2>/dev/null || true; } | sed -E "s/^$2:[[:space:]]*//" | tr -d '\r '; }
add() { eval "$1=\"\${$1}\${$1:+\$'\\n'}\$2\""; }
tojson() { if [ -z "$1" ]; then printf '[]'; else printf '%s\n' "$1" | jq -R . | jq -sc .; fi; }
js() { jq -n --arg s "$1" '$s'; }

# markers <slug> <root>… — distinct AC ids marked `<slug>/AC-…` under the roots, sorted
markers() {
  local slug="$1"; shift
  find "$@" \( -name .git -o -name node_modules -o -name .sdd \) -prune -o -type f ! -name '*.md' \
      -exec env SLUG="$slug" awk '
    BEGIN { pre = ENVIRON["SLUG"] "/AC-"; L = length(pre) }
    { line = $0; sub(/\r$/, "", line); off = 0
      while ((i = index(substr(line, off + 1), pre)) > 0) {
        p = off + i
        b = (p > 1) ? substr(line, p - 1, 1) : ""
        rest = substr(line, p + L)
        if (b !~ /[A-Za-z0-9_.-]/ && match(rest, /^[0-9]+[a-z]?/)) {
          id = substr(rest, 1, RLENGTH); a = substr(rest, RLENGTH + 1, 1)
          if (a !~ /[A-Za-z0-9_-]/) print "AC-" id
        }
        off = p
      } }' {} + 2>/dev/null | LC_ALL=C sort -u
}

# test_roots <workspace-dir> — the test roots, one per line; returns 1 on a bad TEST_ROOTS
test_roots() {
  local tr e oldifs out=""
  tr=$(field "$1/PROGRESS.md" TEST_ROOTS)
  if [ -n "$tr" ]; then
    case ",$tr," in *,,*) return 1 ;; esac
    oldifs="$IFS"; IFS=','; set -f
    for e in $tr; do
      while case "$e" in ./*) true ;; *) false ;; esac; do e="${e#./}"; done
      case "$e" in ""|/*|*..*|-*|.sdd|.sdd/*) IFS="$oldifs"; set +f; return 1 ;; esac
      out="${out}${out:+$'\n'}./$e"
    done
    IFS="$oldifs"; set +f
  else
    for e in tests test spec; do [ -d "$e" ] && out="${out}${out:+$'\n'}./$e"; done
  fi
  printf '%s' "$out"
}

emit() {  # emit <slug_json> <reasons> <untested> <unknown>
  local pass=true; [ -z "$2" ] || pass=false
  printf 'BUILD_FLEET_DRIFT_GATE: {"feature":%s,"pass":%s,"reasons":%s,"untested":%s,"unknown":%s}\n' \
    "$1" "$pass" "$(tojson "$2")" "$(tojson "$3")" "$(tojson "$4")"
  [ "$pass" = true ] && return 0 || return 2
}

# check_one <slug> — prints one gate line; returns 0 pass, 2 fail, 1 unreadable
check_one() {
  local slug="$1" d=".sdd/$1" sj gate crit tr e roots="" reasons="" untested="" unknown="" found="" id
  local missing_root="" oldifs
  [ -f "$d/PROGRESS.md" ] || { echo "drift-gate.sh: $d/PROGRESS.md not found" >&2; return 1; }
  sj=$(js "$slug")
  gate=$(field "$d/PROGRESS.md" DRIFT_GATE)
  case "$gate" in
    off) printf 'BUILD_FLEET_DRIFT_GATE: {"feature":%s,"pass":true,"unchecked":true}\n' "$sj"; return 0 ;;
    ""|on) ;;
    *) emit "$sj" bad-field "" ""; return ;;
  esac
  [ "$(field "$d/PROGRESS.md" SDD_SCHEMA)" = 2 ] || { emit "$sj" unsupported-schema "" ""; return; }

  roots=$(test_roots "$d") || { emit "$sj" bad-field "" ""; return; }

  crit=$(spec_criteria "$d/spec.md")
  [ -n "$crit" ] || add reasons no-criteria

  if [ -z "$roots" ]; then missing_root=1
  else
    while IFS= read -r e; do [ -d "$e" ] || missing_root=1; done <<EOF_R
$roots
EOF_R
  fi
  if [ -n "$missing_root" ]; then
    add reasons no-test-roots
    echo "drift-gate.sh: '$slug' has no test roots — set TEST_ROOTS: <dir>[,<dir>…] in $d/PROGRESS.md (project-relative; e.g. src for colocated tests), or create tests/, test/ or spec/." >&2
  else
    oldifs="$IFS"; IFS=$'\n'; set -f
    # shellcheck disable=SC2086
    found=$(markers "$slug" $roots)
    IFS="$oldifs"; set +f
  fi

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    printf '%s\n' "$found" | grep -qxF -- "$id" || add untested "$id"
  done <<EOF_C
$crit
EOF_C
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    printf '%s\n' "$crit" | grep -qxF -- "$id" || add unknown "$id"
  done <<EOF_F
$found
EOF_F
  [ -z "$untested" ] || add reasons untested
  [ -z "$unknown" ] || add reasons unknown-criterion
  emit "$sj" "$reasons" "$untested" "$unknown"
}

if [ "$1" = "--markers" ]; then
  case "$2" in */*|..|.|-*|"") echo "drift-gate.sh: bad slug '$2'" >&2; exit 1 ;; esac
  [ -f ".sdd/$2/PROGRESS.md" ] || { echo "drift-gate.sh: .sdd/$2/PROGRESS.md not found" >&2; exit 1; }
  roots=$(test_roots ".sdd/$2") || { echo "drift-gate.sh: bad TEST_ROOTS for '$2'" >&2; exit 1; }
  [ -n "$roots" ] || exit 0
  oldifs="$IFS"; IFS=$'\n'; set -f
  # shellcheck disable=SC2086
  markers "$2" $roots
  IFS="$oldifs"; set +f
  exit 0
fi

if [ "$1" != "--all" ]; then
  case "$1" in */*|..|.|-*|"") echo "drift-gate.sh: bad slug '$1'" >&2; exit 1 ;; esac
  check_one "$1"; exit $?
fi

checked=0; unchecked=0; in_progress=0; failed=""
for d in .sdd/*/; do
  [ -d "$d" ] || continue
  slug=$(basename "$d")
  [ "$slug" = _product ] && continue
  [ -f "$d/PROGRESS.md" ] || continue
  [ "$(field "$d/PROGRESS.md" LANE)" = bug ] && continue
  sch=$(field "$d/PROGRESS.md" SDD_SCHEMA)
  if [ "$sch" != 2 ]; then
    printf 'BUILD_FLEET_DRIFT_GATE: {"feature":%s,"pass":true,"unchecked":true,"schema":%s}\n' "$(js "$slug")" "$(js "$sch")"
    unchecked=$((unchecked+1)); continue
  fi
  bs=$(field "$d/PROGRESS.md" BUILD_STATE); ph=$(field "$d/PROGRESS.md" PHASE)
  built=false
  if [ "$bs" = done ]; then built=true
  elif [ -z "$bs" ]; then case "$ph" in CHANGE_REVIEW|HANDOFF) built=true ;; esac; fi
  if [ "$built" = false ]; then
    printf 'BUILD_FLEET_DRIFT_GATE: {"feature":%s,"pass":true,"in_progress":true}\n' "$(js "$slug")"
    in_progress=$((in_progress+1)); continue
  fi
  line=$(check_one "$slug"); rc=$?
  [ -n "$line" ] && printf '%s\n' "$line"
  case "$line" in *'"unchecked":true'*) unchecked=$((unchecked+1)) ;; *) checked=$((checked+1)) ;; esac
  [ $rc -eq 0 ] || add failed "$slug"
done
printf 'BUILD_FLEET_DRIFT_GATE_SUMMARY: {"checked":%s,"unchecked":%s,"in_progress":%s,"failed":%s}\n' "$checked" "$unchecked" "$in_progress" "$(tojson "$failed")"
[ -z "$failed" ] && exit 0 || exit 2
