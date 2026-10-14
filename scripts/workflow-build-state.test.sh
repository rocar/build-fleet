#!/usr/bin/env bash
# Tests deep-build.js's BUILD_STATE mapping: buildStateFor is EXTRACTED VERBATIM from the
# LAYER1-PURE-HELPERS region and run under node; state_delta must write it.
# Skips if node is absent. Run: bash scripts/workflow-build-state.test.sh
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WF="$DIR/../workflows/deep-build.js"
fail=0
if /usr/bin/grep -qE 'BUILD_STATE: buildStateFor\(verdict\)' "$WF"; then echo "ok   state_delta writes BUILD_STATE"
else echo "FAIL state_delta writes BUILD_STATE"; fail=1; fi
if ! command -v node >/dev/null 2>&1; then
  echo "ok   buildStateFor (SKIPPED: node not found; enforced in CI)"; exit "$fail"
fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wf-bs.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
awk '/LAYER1-PURE-HELPERS START/{f=1;next} /LAYER1-PURE-HELPERS END/{f=0;next} f' "$WF" > "$TMP/h.js"
cat "$TMP/h.js" - > "$TMP/run.js" <<'EOF'
let bad = 0;
function check(n, c) { console.log((c ? "ok   " : "FAIL ") + n); if (!c) bad++; }
check("clean → done", typeof buildStateFor === "function" && buildStateFor("clean") === "done");
check("needs-iteration → needs-iteration", typeof buildStateFor === "function" && buildStateFor("needs-iteration") === "needs-iteration");
check("escalate → needs-iteration", typeof buildStateFor === "function" && buildStateFor("escalate") === "needs-iteration");
process.exit(bad ? 1 : 0);
EOF
node "$TMP/run.js" || fail=1
exit "$fail"
