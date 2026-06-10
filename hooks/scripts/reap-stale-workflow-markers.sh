#!/usr/bin/env bash
# Stop: reap orphaned .workflow-in-flight markers.
#
# v0.2 M5 hardening. The marker file at .sdd/<slug>/.workflow-in-flight is
# created by /build-fleet:review and /build-fleet:deep-build (and finalize's
# deep-build branch) before the Workflow tool is invoked. The marker makes
# check-review-written and restrict-reviewer-writes skip their gates while
# present; the scribe deletes it as the workflow's final phase.
#
# If a workflow fails to launch (or crashes), the marker is left behind. This
# orphan silently weakens the per-reviewer hooks for the affected feature on
# subsequent non-workflow operations. This reaper runs on session stop and
# removes any marker older than the staleness threshold.
#
# Threshold: 15 minutes (lowered from 1 hour in the 2026-06 audit remediation,
# §3.14 — markers now carry the dispatching run's id, the scribe deletes only
# its own marker, and dispatch commands clean up dead runs themselves, so the
# reaper is a last-resort backstop and can be aggressive). A false positive
# only re-enables hooks — no data loss; a live run that outlasts the threshold
# is protected by the run-id ownership check everywhere except this backstop.
set -euo pipefail

STALE_AFTER_SECONDS=900

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
  # Portable mtime: macOS uses `stat -f %m`, Linux uses `stat -c %Y`.
  mtime=$(stat -f %m "$marker" 2>/dev/null || stat -c %Y "$marker" 2>/dev/null || echo "$now")
  age=$((now - mtime))
  if [ "$age" -gt "$STALE_AFTER_SECONDS" ]; then
    feature=$(dirname "$marker" | sed 's|^\.sdd/||')
    echo "build-fleet: reaping stale workflow marker for feature '${feature}' (age=${age}s > ${STALE_AFTER_SECONDS}s threshold)" >&2
    rm -f "$marker"
  fi
done <<< "$markers"

exit 0
