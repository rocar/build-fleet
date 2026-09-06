#!/usr/bin/env bash
# PostToolUse (Write|Edit): when a write touches .sdd/<slug>/acceptance.md, refuse to
# continue if the file now names more distinct acceptance criteria than AC_MAX (in
# that feature's PROGRESS.md). Counts distinct ids of the form AC-<n> or AC-<n><letter>.
#
# WHY: criterion count is the review surface — every criterion is something three
# reviewers can find under-specified. The tap pilot's features carried 56–99 criteria
# and never converged. Over the cap the answer is SPLIT the feature, never renumber.
#
# AC_MAX semantics, precisely: absent OR EMPTY value = no cap (grandfathering);
# `0` = disabled; a non-empty value that is not all digits (e.g. "15x") = refused
# (exit 2) rather than silently running uncapped. The product tier has no
# acceptance.md. PostToolUse cannot undo the write — exit 2 blocks the model's
# continuation until the file is brought under budget, same as validate-spec-status.
set -euo pipefail
trap 'echo "build-fleet: gate script errored unexpectedly — failing closed" >&2; exit 2' ERR

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
. "$DIR/_lib.sh"

require_jq

input=$(cat)
file_path=$(extract_file_path "$input")
[ -n "$file_path" ] || exit 0
[ "$(basename "$file_path")" = "acceptance.md" ] || exit 0
case "$file_path" in */../*|../*|*/..|..) exit 0 ;; esac
case "$file_path" in *.sdd/*) ;; *) exit 0 ;; esac
[ -f "$file_path" ] || exit 0

# slug = the path segment after ".sdd/"
slug="${file_path##*.sdd/}"; slug="${slug%%/*}"
[ "$slug" = "_product" ] && exit 0
progress=".sdd/${slug}/PROGRESS.md"
[ -f "$progress" ] || exit 0

cap=$(read_progress_field "$slug" AC_MAX)
[ -n "$cap" ] || exit 0
case "$cap" in
  *[!0-9]*)
    echo "build-fleet: validate-acceptance-count refused — AC_MAX is not an integer ('${cap}') — fix PROGRESS.md" >&2
    exit 2
    ;;
esac
[ "$cap" -gt 0 ] || exit 0

count=$({ grep -oE 'AC-[0-9]+[a-z]?' "$file_path" || true; } | sort -u | grep -c . || true)
[ "$count" -le "$cap" ] && exit 0

cat >&2 <<MSG
build-fleet: validate-acceptance-count refused — ${file_path} names ${count} distinct acceptance criteria, over its AC_MAX of ${cap} (in ${progress}).

Criterion count is the review surface: each one is a thing three reviewers can find
under-specified, and features with 56–99 criteria did not converge. Do NOT renumber or
merge criteria to fit. SPLIT the feature: name in spec.md '## Self-review notes' which
behaviours (and their criteria) move to a sibling backlog row, then cut them here.
Raising AC_MAX in ${progress} is a deliberate, auditable decision — never edit it just
to land this write.
MSG
exit 2
