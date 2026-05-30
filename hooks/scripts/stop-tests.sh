#!/usr/bin/env bash
# Stop: while a build-fleet feature is active, refuse to stop on a failing
# test suite. Silent no-op when no feature is active or no recognized test
# stack is present, so unrelated sessions and bootstrap don't deadlock.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
. "$DIR/_lib.sh"

slug=$(resolve_active)
[ -n "$slug" ] || exit 0

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

if ! out=$($run_test_cmd 2>&1); then
  echo "build-fleet: '${run_test_cmd}' failed for active feature '${slug}'. Tail:" >&2
  echo "----" >&2
  printf '%s\n' "$out" | tail -n 40 >&2
  echo "----" >&2
  exit 2
fi

exit 0
