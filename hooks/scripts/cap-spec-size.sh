#!/usr/bin/env bash
# PreToolUse (Write|Edit|NotebookEdit): refuse a write that would push .sdd/<slug>/spec.md
# past its line budget (SPEC_MAX_LINES in that feature's PROGRESS.md).
#
# WHY: the review loop can only ADD findings; nothing in it rewards cutting. The tap
# pilot reached a 555 KB spec and a 266 KB spec for a login feature, each costing many
# review cycles. The cap makes cycle N+1 no larger than cycle N — and the refusal
# text says SPLIT, not compress: a spec that cannot fit its budget is a feature that
# should be two backlog rows.
#
# SPEC_MAX_LINES semantics, precisely: absent OR EMPTY value = no cap; `0` = disabled;
# a non-empty value that is not all digits (e.g. "150L") = refused (exit 2) rather
# than silently running uncapped. /build-fleet:new-feature scaffolds the field from
# tier defaults. The product tier (.sdd/_product/) is exempt.
#
# Lines are what a reader pays. lines(text) = newline count, plus 1 for a non-empty
# unterminated last line (awk's NR). An Edit's delta is counted in newline characters
# (new − old) × occurrences, so joining or splitting lines is counted exactly.
# Handles: leading-zero values (010 → decimal 10, not octal 8); newline-safe
# replace_all occurrence counting; NotebookEdit refuses closed (cannot project lines).
set -euo pipefail
trap 'echo "build-fleet: gate script errored unexpectedly — failing closed" >&2; exit 2' ERR

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
. "$DIR/_lib.sh"

require_jq

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
path=$(extract_file_path "$input")
[ -n "$path" ] || exit 0

# Repo-relative form so the .sdd/<slug>/ match works for relative and absolute paths.
rel="$path"
phys=$(pwd -P 2>/dev/null || pwd)
case "$rel" in
  "$PWD"/*) rel="${rel#"$PWD"/}" ;;
  "$phys"/*) rel="${rel#"$phys"/}" ;;
  ./*) rel="${rel#./}" ;;
esac
case "$rel" in
  */../*|../*|*/..|..)
    # A traversal path that names .sdd/ could resolve to a spec; it is never measured, so refuse it.
    case "$rel" in *.sdd/*spec.md) echo "build-fleet: cap-spec-size refused — '${path}' contains '..'; write the spec by its plain path" >&2; exit 2 ;; esac
    exit 0 ;;
esac
case "$rel" in
  .sdd/_product/*) exit 0 ;;
  .sdd/*/spec.md) ;;
  *) exit 0 ;;
esac

slug="${rel#.sdd/}"; slug="${slug%%/*}"
base="${rel##*/}"
progress=".sdd/${slug}/PROGRESS.md"
[ -f "$progress" ] || exit 0

cap=$(read_progress_field "$slug" SPEC_MAX_LINES)
[ -n "$cap" ] || exit 0                             # absent: no cap
case "$cap" in
  *[!0-9]*)
    echo "build-fleet: cap-spec-size refused — SPEC_MAX_LINES is not an integer ('${cap}') — fix PROGRESS.md" >&2
    exit 2
    ;;
esac
cap=$((10#$cap))                                    # normalize (leading zeros: 010 → 10, not octal)
[ "$cap" -gt 0 ] || exit 0                          # 0 disables the cap

lines_of() { awk 'END { print NR }'; }
nl_of() { tr -cd '\n' | wc -c | tr -d ' '; }
current=0
[ -f "$rel" ] && current=$(lines_of < "$rel")

case "$tool" in
  Write)
    projected=$(printf '%s' "$input" | jq -j '.tool_input.content // empty' | lines_of)
    ;;
  Edit)
    old=$(printf '%s' "$input" | jq -j '.tool_input.old_string // empty' | nl_of)
    new=$(printf '%s' "$input" | jq -j '.tool_input.new_string // empty' | nl_of)
    n=1
    if [ "$(printf '%s' "$input" | jq -r '.tool_input.replace_all // false')" = "true" ] && [ -f "$rel" ]; then
      oldstr=$(printf '%s' "$input" | jq -j '.tool_input.old_string // empty')
      if [ -n "$oldstr" ]; then
        content=$(cat "$rel"; printf x); content="${content%x}"   # keep trailing newlines
        n=0; rest="$content"
        while [ -n "$rest" ] && [ "${rest#*"$oldstr"}" != "$rest" ]; do
          rest="${rest#*"$oldstr"}"; n=$((n+1))
        done
        [ "$n" -gt 0 ] 2>/dev/null || n=1
      fi
    fi
    projected=$(( current + (new - old) * n ))
    ;;
  NotebookEdit)
    echo "build-fleet: cap-spec-size refused — ${rel} is a spec file; NotebookEdit cannot be size-projected. Use Write or Edit." >&2
    exit 2
    ;;
  *) exit 0 ;;
esac

[ "$projected" -le "$cap" ] && exit 0

cat >&2 <<MSG
build-fleet: cap-spec-size refused — ${rel} would become ${projected} lines, over its ${cap}-line budget.

  current   : ${current} lines
  projected : ${projected} lines
  budget    : ${cap} lines (SPEC_MAX_LINES: ${cap} in ${progress})
  over by   : $(( projected - cap )) lines

A spec that cannot fit its budget is a feature that should be SPLIT, not compressed:
name the sibling backlog rows for the behaviours that move out in your report (not in
the spec, which is at its budget), and cut them from ${base}. Move rationale to DECISIONS.md rather than the spec. Raising
SPEC_MAX_LINES in ${progress} is a deliberate, auditable decision — never edit it just
to land this write.
MSG
exit 2
