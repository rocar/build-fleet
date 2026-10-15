#!/usr/bin/env bash
# scripts/drift-gate.sh — the drift gate: every acceptance criterion of a gated feature
# maps to a named test that exists in the repo. Static and model-free.
#
# Gated = PROGRESS.md carries `DRIFT_GATE: on` (absent, empty or `off` = unchecked; any
# other value = bad-field). Criteria = distinct AC-<n>[a-z] ids in acceptance.md, else in
# spec.md's `## Acceptance…` section (same id pattern as validate-acceptance-count.sh).
# Matrix = the table rows under TEST_PLAN.md's `## Coverage matrix`:
#   | AC-1, AC-2 | `test_name` | unit | `tests/file.py::test_name` |
# Each cell is trimmed of whitespace and one pair of backticks. Separator rows and
# header rows (first cell `Criterion`) are skipped. Column 2 is the name as declared in
# source; a trailing ` (failure)` and then a trailing `[…]` parametrize id are stripped.
# Column 4 before the first `::` is the file, relative to the project root.
#
# Reasons, in this order: bad-field no-test-plan no-criteria untested unknown-criterion
# missing-file missing-test gaps-open unparsed.
#
# Usage: drift-gate.sh <slug> | drift-gate.sh --all
# Output (stdout): one `BUILD_FLEET_DRIFT_GATE: {…}` line per feature; --all adds one
#   `BUILD_FLEET_DRIFT_GATE_SUMMARY: {"checked","unchecked","in_progress","failed"}` line.
# Exit: 0 = pass; 2 = fail; 1 = bad usage / unreadable workspace (CI keys off this).
# bash 3.2 + BSD/GNU compatible; read-only. Requires jq.
set -uo pipefail

usage() { echo "usage: drift-gate.sh <slug> | drift-gate.sh --all" >&2; exit 1; }
[ $# -eq 1 ] || usage
command -v jq >/dev/null 2>&1 || { echo "drift-gate.sh: jq is required" >&2; exit 1; }
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 1

# field <file> <NAME> — the value of the first "NAME:" line, whitespace stripped
field() { { grep -m1 "^$2:" "$1" 2>/dev/null || true; } | sed -E "s/^$2:[[:space:]]*//" | tr -d '\r '; }
add() { eval "$1=\"\${$1}\${$1:+\$'\\n'}\$2\""; }
tojson() { if [ -z "$1" ]; then printf '[]'; else printf '%s\n' "$1" | jq -R . | jq -sc .; fi; }

# has_word <file> <name> — name occurs with no [A-Za-z0-9_] on either side
has_word() {
  WANT="$2" awk 'BEGIN { w = ENVIRON["WANT"]; L = length(w) }
    { line = $0; off = 0
      while ((i = index(substr(line, off + 1), w)) > 0) {
        p = off + i
        b = (p > 1) ? substr(line, p - 1, 1) : ""
        a = substr(line, p + L, 1)
        if (b !~ /[A-Za-z0-9_]/ && a !~ /[A-Za-z0-9_]/) { found = 1; exit }
        off = p
      } }
    END { exit found ? 0 : 1 }' < "$1"   # stdin, not an operand: awk reads "k=v" as an assignment
}
# has_name <file> <name> — the whole-word / per-segment / substring rule of the spec
has_name() {
  local f="$1" n="$2" seg rest seen=""
  case "$n" in
    */*)
      rest="$n"
      while [ -n "$rest" ]; do
        seg="${rest%%/*}"
        if [ "$seg" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
        [ -n "$seg" ] || continue
        has_name "$f" "$seg" || return 1
        seen=1
      done
      [ -n "$seen" ]; return ;;   # a name of only slashes names nothing
  esac
  if printf '%s' "$n" | grep -qE '^[A-Za-z0-9_]+$'; then has_word "$f" "$n"
  else grep -qF -- "$n" "$f"; fi
}

# matrix_rows <TEST_PLAN.md> — one tab-separated record per (id,row):
#   R <id> <name> <location> <file>     or     U <row text>
matrix_rows() {
  awk -F'|' '
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function tick(s) { if (length(s) >= 2 && substr(s, 1, 1) == "`" && substr(s, length(s), 1) == "`") s = substr(s, 2, length(s) - 2); return trim(s) }
    function cell(s) { return tick(trim(s)) }
    /^## / { insec = ($0 ~ /^## Coverage matrix[ \t\r]*$/); next }
    !insec { next }
    { row = $0; sub(/\r$/, "", row) }
    row !~ /^[ \t]*\|/ { next }
    row ~ /^[ \t|:-]+$/ { next }
    {
      line = row; sub(/^[ \t]*\|/, "", line); sub(/\|[ \t]*$/, "", line)
      nc = split(line, c, "|")
      if (cell(c[1]) == "Criterion") next
      if (nc < 4) { print "U\t" row; next }
      name = trim(c[2]); sub(/[ \t]*\(failure\)$/, "", name); name = tick(name)
      sub(/[ \t]*\(failure\)$/, "", name); sub(/\[[^]]*\]$/, "", name); name = trim(name)
      loc = cell(c[4]); file = loc; k = index(file, "::"); if (k) file = substr(file, 1, k - 1)
      file = trim(file)
      n = split(cell(c[1]), ids, ","); good = (n > 0)
      for (j = 1; j <= n; j++) { ids[j] = trim(ids[j]); if (ids[j] !~ /^AC-[0-9]+[a-z]?$/) good = 0 }
      if (!good || name == "" || file == "") { print "U\t" row; next }
      for (j = 1; j <= n; j++) print "R\t" ids[j] "\t" name "\t" loc "\t" file
    }' "$1"
}

# check_one <slug> — prints one gate line; returns 0 pass, 2 fail, 1 unreadable
check_one() {
  local slug="$1" d=".sdd/$1" gate crit rows reasons="" untested="" unknown="" missing="" unparsed=""
  local f_untested="" f_unknown="" f_file="" f_test="" covered="" gaps=false tp
  local kind id name loc file rest
  [ -f "$d/PROGRESS.md" ] || { echo "drift-gate.sh: $d/PROGRESS.md not found" >&2; return 1; }
  local slug_json; slug_json=$(jq -n --arg s "$slug" '$s')
  gate=$(field "$d/PROGRESS.md" DRIFT_GATE)
  case "$gate" in
    ""|off) printf 'BUILD_FLEET_DRIFT_GATE: {"feature":%s,"pass":true,"unchecked":true}\n' "$slug_json"; return 0 ;;
    on) ;;
    *) printf 'BUILD_FLEET_DRIFT_GATE: {"feature":%s,"pass":false,"reasons":["bad-field"],"untested":[],"unknown":[],"missing":[],"unparsed":[],"gaps_open":false}\n' "$slug_json"; return 2 ;;
  esac

  if [ -f "$d/acceptance.md" ]; then
    crit=$({ grep -oE 'AC-[0-9]+[a-z]?' "$d/acceptance.md" || true; } | LC_ALL=C sort -u)
  elif [ -f "$d/spec.md" ]; then
    crit=$(awk '/^## /{ insec = ($0 ~ /^## Acceptance/); next } insec' "$d/spec.md" | { grep -oE 'AC-[0-9]+[a-z]?' || true; } | LC_ALL=C sort -u)
  else crit=""; fi

  tp="$d/TEST_PLAN.md"
  if [ -f "$tp" ]; then
    rows=$(matrix_rows "$tp")
    if awk '/^## /{ insec = ($0 ~ /^## Gaps[ \t\r]*$/); next } insec && /^[ \t]*- / { found = 1 } END { exit found ? 0 : 1 }' "$tp"; then gaps=true; fi
  else rows=""; add reasons no-test-plan; fi
  [ -n "$crit" ] || add reasons no-criteria

  while IFS="$(printf '\t')" read -r kind id name loc file; do
    case "$kind" in
      U) rest="$id${name:+	$name}${loc:+	$loc}${file:+	$file}"; add unparsed "$rest"; continue ;;
      R) ;;
      *) continue ;;
    esac
    add covered "$id"
    if ! printf '%s\n' "$crit" | grep -qxF -- "$id"; then
      printf '%s\n' "$unknown" | grep -qxF -- "$id" || add unknown "$id"
      f_unknown=1
    fi
    case "$file" in
      /*|*..*|.sdd/*|*/.sdd/*|*.md) add missing "$id	$name	$loc	missing-file"; f_file=1; continue ;;
    esac
    if [ ! -f "$file" ]; then add missing "$id	$name	$loc	missing-file"; f_file=1; continue; fi
    has_name "$file" "$name" || { add missing "$id	$name	$loc	missing-test"; f_test=1; }
  done <<EOF_ROWS
$rows
EOF_ROWS

  if [ -n "$crit" ]; then
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      printf '%s\n' "$covered" | grep -qxF -- "$id" || { add untested "$id"; f_untested=1; }
    done <<EOF_CRIT
$crit
EOF_CRIT
  fi

  [ -z "$f_untested" ] || add reasons untested
  [ -z "$f_unknown" ] || add reasons unknown-criterion
  [ -z "$f_file" ] || add reasons missing-file
  [ -z "$f_test" ] || add reasons missing-test
  [ "$gaps" = false ] || add reasons gaps-open
  [ -z "$unparsed" ] || add reasons unparsed

  local pass=true missing_json
  [ -z "$reasons" ] || pass=false
  if [ -z "$missing" ]; then missing_json='[]'
  else missing_json=$(printf '%s\n' "$missing" | jq -R 'split("\t") | {criterion: .[0], test: .[1], location: .[2], why: .[3]}' | jq -sc .); fi
  printf 'BUILD_FLEET_DRIFT_GATE: {"feature":%s,"pass":%s,"reasons":%s,"untested":%s,"unknown":%s,"missing":%s,"unparsed":%s,"gaps_open":%s}\n' \
    "$slug_json" "$pass" "$(tojson "$reasons")" "$(tojson "$untested")" "$(tojson "$unknown")" "$missing_json" "$(tojson "$unparsed")" "$gaps"
  [ "$pass" = true ] && return 0 || return 2
}

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
  bs=$(field "$d/PROGRESS.md" BUILD_STATE); ph=$(field "$d/PROGRESS.md" PHASE)
  built=false
  if [ "$bs" = done ]; then built=true
  elif [ -z "$bs" ]; then case "$ph" in CHANGE_REVIEW|HANDOFF) built=true ;; esac; fi
  if [ "$built" = false ]; then
    printf 'BUILD_FLEET_DRIFT_GATE: {"feature":%s,"pass":true,"in_progress":true}\n' "$(jq -n --arg s "$slug" '$s')"
    in_progress=$((in_progress+1)); continue
  fi
  line=$(check_one "$slug"); rc=$?
  [ -n "$line" ] && printf '%s\n' "$line"
  case "$line" in *'"unchecked":true'*) unchecked=$((unchecked+1)) ;; *) checked=$((checked+1)) ;; esac
  [ $rc -eq 0 ] || add failed "$slug"
done
printf 'BUILD_FLEET_DRIFT_GATE_SUMMARY: {"checked":%s,"unchecked":%s,"in_progress":%s,"failed":%s}\n' "$checked" "$unchecked" "$in_progress" "$(tojson "$failed")"
[ -z "$failed" ] && exit 0 || exit 2
