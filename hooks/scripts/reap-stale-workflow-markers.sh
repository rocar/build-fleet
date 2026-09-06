#!/usr/bin/env bash
# Stop: reap orphaned .workflow-in-flight markers.
#
# The marker file at .sdd/<slug>/.workflow-in-flight is created by the
# workflow-dispatching commands (review, deep-build, build's deep-build route,
# diagnose, plan-review) before the Workflow tool is invoked, containing the
# run's id. The marker makes check-review-written and restrict-reviewer-writes
# skip their gates while LIVE (non-empty); the scribe RELEASES it as the
# workflow's final phase by emptying it (the scribe holds no Bash to rm).
#
# This reaper runs on session stop and (a) deletes released (empty) markers as
# housekeeping, and (b) removes any live marker older than the staleness
# threshold — a workflow that failed to launch (or crashed) leaves an orphan
# that would silently weaken the per-reviewer hooks for the affected feature.
#
# Threshold: 2 hours (raised from 15 minutes on 2026-09-06, live-run
# recalibration — a real v0.9 review cycle measured 26.6 minutes end-to-end,
# and the Stop hook fires whenever the orchestrator ends a turn while waiting
# on the workflow, so the 900s threshold reaped the LIVE marker mid-run: a
# false reap re-enables check-review-written / restrict-reviewer-writes before
# the scribe applies, and can block the recording write after the whole run's
# cost was spent. This reaper exists to catch CRASHED runs — a live run's
# marker is released by the scribe itself the moment it finishes — so a
# 2-hour grace costs nothing but a delayed hook re-engagement after a crash,
# while comfortably covering runs several times longer than the one measured.
set -euo pipefail

STALE_AFTER_SECONDS=7200

# Operate from cwd (the target project where .sdd/ lives).
[ -d .sdd ] || exit 0

# Find all marker files under .sdd/<slug>/.
# Use -mindepth 2 / -maxdepth 2 to stay scoped to the per-feature layer.
markers=$(find .sdd -mindepth 2 -maxdepth 2 -name '.workflow-in-flight' -type f 2>/dev/null || true)
[ -z "$markers" ] && exit 0

now=$(date +%s)

# Iterate (handle paths with spaces via while-read)
while IFS= read -r marker; do
  [ -z "$marker" ] && continue
  # A RELEASED marker (zero bytes — the scribe empties it at envelope-apply
  # time; it holds no Bash to rm) is reaped immediately regardless of age:
  # the gate hooks already treat it as absent, this is just housekeeping.
  if [ ! -s "$marker" ]; then
    feature=$(dirname "$marker" | sed 's|^\.sdd/||')
    echo "build-fleet: reaping released (empty) workflow marker for feature '${feature}'" >&2
    rm -f "$marker"
    continue
  fi
  # Portable mtime: Linux (GNU) uses `stat -c %Y`, macOS (BSD) uses
  # `stat -f %m`. GNU must be probed FIRST: on GNU, `stat -f %m <file>`
  # does not fail — it's filesystem mode and prints the MOUNT POINT,
  # which would poison the arithmetic below (caught by CI on ubuntu).
  mtime=$(stat -c %Y "$marker" 2>/dev/null || stat -f %m "$marker" 2>/dev/null || echo "$now")
  # Belt-and-suspenders: any non-numeric mtime means "treat as fresh".
  case "$mtime" in *[!0-9]*|"") mtime=$now ;; esac
  age=$((now - mtime))
  if [ "$age" -gt "$STALE_AFTER_SECONDS" ]; then
    feature=$(dirname "$marker" | sed 's|^\.sdd/||')
    echo "build-fleet: reaping stale workflow marker for feature '${feature}' (age=${age}s > ${STALE_AFTER_SECONDS}s threshold)" >&2
    rm -f "$marker"
  fi
done <<< "$markers"

exit 0
