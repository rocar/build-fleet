#!/usr/bin/env bash
# Every workflow must parse. Workflows run as an async function body (top-level await
# and return), so plain `node --check` rejects them; this compiles each as one.
# Skips if node is absent. Run: bash scripts/workflow-parse.test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v node >/dev/null 2>&1; then
  echo "ok   workflow-parse (SKIPPED: node not found; enforced in CI)"; exit 0
fi
fail=0
for f in "$ROOT"/workflows/*.js; do
  if err=$(node -e '
    const src = require("fs").readFileSync(process.argv[1], "utf8").replace(/^export /m, "");
    new (Object.getPrototypeOf(async function () {}).constructor)(src);' "$f" 2>&1); then
    echo "ok   $(basename "$f") parses"
  else
    echo "FAIL $(basename "$f") — $(printf '%s' "$err" | /usr/bin/grep -m1 -E 'Error')"; fail=1
  fi
done
exit "$fail"
