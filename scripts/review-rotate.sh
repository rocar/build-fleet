#!/usr/bin/env bash
# scripts/review-rotate.sh — bound REVIEW.md to the previous review cycle.
#
# Called by /build-fleet:review BEFORE dispatch (spec review only). Every consumer of
# REVIEW.md keys on the CURRENT cycle's blocks, and cycle >= 2 is a DELTA review that
# needs only the previous cycle — so everything older is moved, verbatim and in
# order, to REVIEW-archive.md (append-only). This bounds every reviewer's input and
# the scribe's append cost without a schema change.
#
# POSITIONAL rule (cycle numbers collide after a resolve-escalation reset, so they
# are never used): a BLOCK is a "## " heading plus every line up to the next "## "
# heading (or EOF). Find the last run of consecutive "## Cycle …" blocks; if it holds
# at least ROSTER blocks, keep its last ROSTER blocks and EVERY block after them
# (escalation archives, run-failure notes, human decisions land after the cycle they
# concern); archive every block before. Fewer than ROSTER cycle blocks ⇒ no-op.
#
# Usage: review-rotate.sh <slug> [--roster N]
#   ROSTER defaults to the count of REVIEW_ROLES in .sdd/<slug>/PROGRESS.md, else 3.
# Output (stdout, one line):
#   BUILD_FLEET_REVIEW_ROTATED: {"feature":"<slug>","archived_blocks":N,"kept_blocks":N}
# Exit: 0 = done (including no-op); 1 = bad usage. Idempotent. bash 3.2 + BSD/GNU.
set -euo pipefail
trap 'echo "build-fleet: review-rotate errored unexpectedly — nothing was changed" >&2; exit 1' ERR

slug="${1:-}"
[ -n "$slug" ] || { echo "usage: review-rotate.sh <slug> [--roster N]" >&2; exit 1; }
case "$slug" in */*|..|.) echo "review-rotate.sh: bad slug '$slug'" >&2; exit 1 ;; esac
shift
roster=""
if [ "${1:-}" = "--roster" ]; then roster="${2:-}"; fi

cd "${CLAUDE_PROJECT_DIR:-.}"
dir=".sdd/${slug}"
review="${dir}/REVIEW.md"
archive="${dir}/REVIEW-archive.md"
progress="${dir}/PROGRESS.md"

emit() { printf 'BUILD_FLEET_REVIEW_ROTATED: {"feature":"%s","archived_blocks":%s,"kept_blocks":%s}\n' "$slug" "$1" "$2"; }

[ -f "$review" ] || { emit 0 0; exit 0; }

if [ -z "$roster" ] && [ -f "$progress" ]; then
  roles=$({ grep -m1 '^REVIEW_ROLES:' "$progress" 2>/dev/null || true; } | sed -E 's/^REVIEW_ROLES:[[:space:]]*//' | tr -d '\r')
  if [ -n "$roles" ]; then
    roster=$(printf '%s' "$roles" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -c . || true)
  fi
fi
case "$roster" in ''|*[!0-9]*|0) roster=3 ;; esac

total_lines=$(wc -l < "$review" | tr -d ' ')
# Heading line numbers (1-based). A file with no "## " heading has nothing to rotate.
starts=$({ grep -n '^## ' "$review" || true; } | cut -d: -f1)
[ -n "$starts" ] || { emit 0 0; exit 0; }

# Arrays of block start/end lines and a per-block "is a Cycle block" flag.
i=0
for s in $starts; do
  bstart[$i]=$s
  if [ $i -gt 0 ]; then bend[$((i-1))]=$((s-1)); fi
  if sed -n "${s}p" "$review" | grep -qE '^##[[:space:]]+Cycle[[:space:]]+[0-9]+[[:space:]]'; then iscycle[$i]=1; else iscycle[$i]=0; fi
  i=$((i+1))
done
nblocks=$i
bend[$((nblocks-1))]=$total_lines
header_end=$((bstart[0]-1))

# Last run of consecutive Cycle blocks: [run_start, run_end].
run_end=-1
j=$((nblocks-1))
while [ $j -ge 0 ]; do
  if [ "${iscycle[$j]}" = 1 ]; then run_end=$j; break; fi
  j=$((j-1))
done
[ $run_end -ge 0 ] || { emit 0 "$nblocks"; exit 0; }
run_start=$run_end
while [ $run_start -gt 0 ] && [ "${iscycle[$((run_start-1))]}" = 1 ]; do run_start=$((run_start-1)); done
run_len=$((run_end-run_start+1))
[ $run_len -ge $roster ] || { emit 0 "$nblocks"; exit 0; }

keep_from=$((run_end-roster+1))
[ $keep_from -gt 0 ] || { emit 0 "$nblocks"; exit 0; }

# Archive blocks [0, keep_from-1] verbatim; keep header + blocks [keep_from, end].
arch_first=${bstart[0]}
arch_last=${bend[$((keep_from-1))]}
keep_first=${bstart[$keep_from]}

tmp_arch=$(mktemp "${TMPDIR:-/tmp}/review-rotate.XXXXXX")
tmp_rev=$(mktemp "${TMPDIR:-/tmp}/review-rotate.XXXXXX")
if [ -f "$archive" ]; then
  cat "$archive" > "$tmp_arch"
else
  printf '# Review Archive — %s\n\nAppend-only. Older review cycles rotated out of REVIEW.md by scripts/review-rotate.sh; REVIEW.md + this file are the audit trail.\n\n' "$slug" > "$tmp_arch"
fi
sed -n "${arch_first},${arch_last}p" "$review" >> "$tmp_arch"
# Guarantee a trailing newline + one blank separator so the next rotation appends cleanly.
[ -n "$(tail -c1 "$tmp_arch")" ] && printf '\n' >> "$tmp_arch"
printf '\n' >> "$tmp_arch"

if [ $header_end -ge 1 ]; then sed -n "1,${header_end}p" "$review" > "$tmp_rev"; else : > "$tmp_rev"; fi
sed -n "${keep_first},\$p" "$review" >> "$tmp_rev"

mv "$tmp_arch" "$archive"
mv "$tmp_rev" "$review"
emit "$keep_from" $((nblocks-keep_from))
exit 0
