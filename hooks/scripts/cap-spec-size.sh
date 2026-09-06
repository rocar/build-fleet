#!/usr/bin/env bash
# PreToolUse (Write|Edit|NotebookEdit): refuse a write that would push .sdd/<slug>/spec.md or
# acceptance.md past its byte budget (SPEC_MAX_KB in that feature's PROGRESS.md).
#
# WHY: the review loop can only ADD findings; nothing in it rewards cutting. The tap
# pilot reached a 555 KB spec and a 266 KB spec for a login feature, each costing many
# review cycles. The cap makes cycle N+1 no larger than cycle N — and the refusal
# text says SPLIT, not compress: a spec that cannot fit its budget is a feature that
# should be two backlog rows.
#
# SPEC_MAX_KB semantics, precisely: absent OR EMPTY value = no cap; `0` = disabled;
# a non-empty value that is not all digits (e.g. "24KB") = refused (exit 2) rather
# than silently running uncapped. Every workspace scaffolded before v0.9 is
# grandfathered (absent field, no cap); /build-fleet:new-feature scaffolds the field
# from tier defaults. The product tier (.sdd/_product/) is exempt. Ported from the
# tap pilot's local guard.
#
# Handles: leading-zero values (010 → decimal 10, not octal 8); newline-safe
# replace_all occurrence counting; NotebookEdit refuses closed (cannot project bytes).
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
case "$rel" in */../*|../*|*/..|..) exit 0 ;; esac   # traversal is not inside .sdd/
case "$rel" in
  .sdd/_product/*) exit 0 ;;
  .sdd/*/spec.md|.sdd/*/acceptance.md) ;;
  *) exit 0 ;;
esac

slug="${rel#.sdd/}"; slug="${slug%%/*}"
base="${rel##*/}"
progress=".sdd/${slug}/PROGRESS.md"
[ -f "$progress" ] || exit 0

cap_kb=$(read_progress_field "$slug" SPEC_MAX_KB)
[ -n "$cap_kb" ] || exit 0                          # grandfathering: no field, no cap
case "$cap_kb" in
  *[!0-9]*)
    echo "build-fleet: cap-spec-size refused — SPEC_MAX_KB is not an integer ('${cap_kb}') — fix PROGRESS.md" >&2
    exit 2
    ;;
esac
cap_kb=$((10#$cap_kb))                              # normalize (leading zeros: 010 → 10, not octal)
[ "$cap_kb" -gt 0 ] || exit 0                       # 0 disables the cap

cap_bytes=$(( cap_kb * 1024 ))
current=0
[ -f "$rel" ] && current=$(wc -c < "$rel" | tr -d ' ')

# Project the resulting size. Bytes, not jq's `length` (codepoints undercount
# em-dash-heavy files). Exact for Write; old/new delta × occurrences for Edit.
case "$tool" in
  Write)
    projected=$(printf '%s' "$input" | jq -j '.tool_input.content // empty' | wc -c | tr -d ' ')
    ;;
  Edit)
    old=$(printf '%s' "$input" | jq -j '.tool_input.old_string // empty' | wc -c | tr -d ' ')
    new=$(printf '%s' "$input" | jq -j '.tool_input.new_string // empty' | wc -c | tr -d ' ')
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
    echo "build-fleet: cap-spec-size refused — ${rel} is a spec/acceptance file; NotebookEdit cannot be size-projected. Use Write or Edit." >&2
    exit 2
    ;;
  *) exit 0 ;;
esac

[ "$projected" -le "$cap_bytes" ] && exit 0

cat >&2 <<MSG
build-fleet: cap-spec-size refused — ${rel} would become ${projected} bytes, over its ${cap_bytes}-byte budget.

  current   : ${current} bytes
  projected : ${projected} bytes
  budget    : ${cap_bytes} bytes (SPEC_MAX_KB: ${cap_kb} in ${progress})
  over by   : $(( projected - cap_bytes )) bytes

A spec that cannot fit its budget is a feature that should be SPLIT, not compressed:
name the split in '## Self-review notes' (which behaviours move to a sibling backlog
row) and draft ${base} for the smaller feature. Move rationale to DECISIONS.md rather
than the spec. Raising SPEC_MAX_KB in ${progress} is a deliberate, auditable decision —
never edit it just to land this write.
MSG
exit 2
