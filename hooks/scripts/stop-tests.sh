#!/usr/bin/env bash
# Stop: while a build-fleet feature is active AND in a phase where its tests
# should exist, refuse to stop on a failing test suite. Silent no-op when no
# feature is active, the feature is pre-BUILD, or no recognized test stack is
# present, so unrelated sessions and bootstrap don't deadlock.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
. "$DIR/_lib.sh"

slug=$(resolve_active)
[ -n "$slug" ] || exit 0

# Phase gate: tests are authored by qa during BUILD (M2 tests-first). Before
# BUILD there are legitimately no tests, and the block-source-before-finalized
# gate makes it impossible for the session to create any. Running the suite in
# SPEC/REVIEW/FINALIZE therefore can only deadlock the stop. Only enforce the
# test gate once the feature has reached a phase where its tests should exist.
phase=$(read_progress_field "$slug" PHASE)
case "$phase" in
  BUILD|CHANGE_REVIEW|HANDOFF) ;;
  *) exit 0 ;;
esac

run_test_cmd=""
if [ -f package.json ]; then
  if command -v jq >/dev/null 2>&1 && jq -e '.scripts.test' package.json >/dev/null 2>&1; then
    run_test_cmd="npm test --silent"
  fi
elif [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ]; then
  if command -v pytest >/dev/null 2>&1; then
    run_test_cmd="pytest -q"
  fi
elif [ -f Makefile ]; then
  if grep -Eq '^test:' Makefile; then
    run_test_cmd="make test"
  fi
fi

[ -n "$run_test_cmd" ] || exit 0

# Capture output and exit code without tripping `set -e`.
out=$($run_test_cmd 2>&1) && rc=0 || rc=$?

# pytest exit code 5 == "no tests collected". That is not a test failure; it is
# a missing-suite signal. Treat it as a pass so an empty collection never hard-
# blocks a stop — a genuinely missing suite is surfaced by the BUILD
# orchestration and the CHANGE_REVIEW coverage gate, not by deadlocking Stop.
if [ "$rc" -eq 5 ] && printf '%s' "$run_test_cmd" | grep -q '^pytest'; then
  rc=0
fi

if [ "$rc" -ne 0 ]; then
  echo "build-fleet: '${run_test_cmd}' failed for active feature '${slug}'. Tail:" >&2
  echo "----" >&2
  printf '%s\n' "$out" | tail -n 40 >&2
  echo "----" >&2
  exit 2
fi

exit 0
