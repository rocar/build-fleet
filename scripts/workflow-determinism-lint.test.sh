#!/usr/bin/env bash
# Tests for scripts/workflow-determinism-lint.sh — the determinism + sandbox-safety
# gate a *generated* workflow must pass before it can be pinned into workflows/
# (the "generate-then-pin" enrichment lane). Self-contained: writes JS fixtures to
# a mktemp dir, asserts stdout signal lines + exit codes against the real script.
# Run: bash scripts/workflow-determinism-lint.test.sh   (exit 0 = all pass)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$DIR/workflow-determinism-lint.sh"
ROOT="$(cd "$DIR/.." && pwd)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/wf-lint-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0

# mk <name> <content> -> writes a fixture file, echoes its path
mk() {
  local name="$1" body="$2" f="$TMP/$1.js"
  printf '%s\n' "$body" > "$f"
  printf '%s' "$f"
}

# assert_stdout <name> <file> <want-substring>
assert_stdout() {
  local name="$1" file="$2" want="$3" out
  out="$(bash "$SCRIPT" "$file" 2>/dev/null)"
  if printf '%s' "$out" | grep -qF "$want"; then
    pass=$((pass+1)); printf 'ok   %-36s\n' "$name"
  else
    fail=$((fail+1)); printf 'FAIL %-36s want[%s] got[%s]\n' "$name" "$want" "$out"
  fi
}

# assert_rc <name> <file> <want-rc>
assert_rc() {
  local name="$1" file="$2" want="$3" rc=0
  bash "$SCRIPT" "$file" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq "$want" ]; then
    pass=$((pass+1)); printf 'ok   %-36s rc=%s\n' "$name" "$rc"
  else
    fail=$((fail+1)); printf 'FAIL %-36s want rc=%s got rc=%s\n' "$name" "$want" "$rc"
  fi
}

# ---- clean workflows pass ----
CLEAN='// a clean workflow — references nothing forbidden
export const meta = { name: "x", description: "y", phases: [] };
const A = typeof args === "string" ? JSON.parse(args) : (args || {});
const now = A.now;
phase("Go");
const r = await agent("do it", { schema: { type: "object" } });
return { ok: true, now };'
clean=$(mk clean "$CLEAN")
assert_stdout clean-passes        "$clean" 'BUILD_FLEET_LINT_PASS'
assert_rc     clean-passes-rc     "$clean" 0

# A workflow whose HEADER COMMENT documents the banned patterns must still pass —
# this is the load-bearing case: workflows/review.js carries exactly such a note.
COMMENTBANNED='// NO Date.now()/Math.random()/new Date() — they throw. Timestamps come via args.now.
export const meta = { name: "x", description: "y" };
const now = args.now;'
commentbanned=$(mk commentbanned "$COMMENTBANNED")
assert_stdout comment-mentions-banned-ok "$commentbanned" 'BUILD_FLEET_LINT_PASS'
assert_rc     comment-mentions-banned-rc "$commentbanned" 0

# A STRING literal that names a banned API must not false-trip the scanner.
STRINGBANNED='export const meta = { name: "x", description: "y" };
const hint = "do not call Date.now() or Math.random() here";
const now = args.now;'
stringbanned=$(mk stringbanned "$STRINGBANNED")
assert_stdout string-mentions-banned-ok "$stringbanned" 'BUILD_FLEET_LINT_PASS'

# A template literal with ${interpolation} (the normal prompt-building idiom) passes.
TEMPLATE='export const meta = { name: "x", description: "y" };
const feature = args.feature;
const prompt = `Review the ${feature} spec for ${args.cycle}`;
const now = args.now;'
template=$(mk template "$TEMPLATE")
assert_stdout template-literal-ok "$template" 'BUILD_FLEET_LINT_PASS'

# new Date(<arg>) is deterministic (parses a fixed string) and is allowed; only
# argless new Date() reads the wall clock.
NEWDATEARG='export const meta = { name: "x", description: "y" };
const now = args.now;
const d = new Date(now);'
newdatearg=$(mk newdatearg "$NEWDATEARG")
assert_stdout new-date-with-arg-ok "$newdatearg" 'BUILD_FLEET_LINT_PASS'
assert_rc     new-date-with-arg-rc "$newdatearg" 0

# ---- the four real, committed workflows must all pass (regression guard) ----
assert_stdout real-review-passes     "$ROOT/workflows/review.js"      'BUILD_FLEET_LINT_PASS'
assert_rc     real-review-rc         "$ROOT/workflows/review.js"      0
assert_rc     real-deep-build-rc     "$ROOT/workflows/deep-build.js"  0
assert_rc     real-diagnose-rc       "$ROOT/workflows/diagnose.js"    0
assert_rc     real-plan-review-rc    "$ROOT/workflows/plan-review.js" 0

# ---- non-determinism is rejected ----
DATENOW='export const meta = { name: "x", description: "y" };
const t = Date.now();'
datenow=$(mk datenow "$DATENOW")
assert_stdout date-now-flagged    "$datenow" '"rule":"date-now"'
assert_stdout date-now-line       "$datenow" '{"rule":"date-now","line":2}'
assert_stdout date-now-fail       "$datenow" 'BUILD_FLEET_LINT_FAIL'
assert_rc     date-now-rc         "$datenow" 2

RANDOM_FIX='export const meta = { name: "x", description: "y" };
const r = Math.random();'
randfix=$(mk randfix "$RANDOM_FIX")
assert_stdout math-random-flagged "$randfix" '"rule":"math-random"'
assert_rc     math-random-rc      "$randfix" 2

NEWDATE='export const meta = { name: "x", description: "y" };
const d = new Date();'
newdate=$(mk newdate "$NEWDATE")
assert_stdout argless-new-date-flagged "$newdate" '"rule":"argless-new-date"'
assert_rc     argless-new-date-rc      "$newdate" 2

# Math.min and friends must NOT be confused with Math.random (deep-build uses it).
MATHMIN='export const meta = { name: "x", description: "y" };
const n = Math.min(args.max || 3, 8);
const now = args.now;'
mathmin=$(mk mathmin "$MATHMIN")
assert_stdout math-min-ok "$mathmin" 'BUILD_FLEET_LINT_PASS'

# ---- sandbox-escape / Node API is rejected ----
REQUIRE='export const meta = { name: "x", description: "y" };
const fs = require("fs");'
req=$(mk requirejs "$REQUIRE")
assert_stdout require-flagged "$req" '"rule":"forbidden-api"'
assert_rc     require-rc      "$req" 2

IMPORTJS='import fs from "fs";
export const meta = { name: "x", description: "y" };'
imp=$(mk importjs "$IMPORTJS")
assert_stdout import-flagged "$imp" '"rule":"forbidden-api"'

PROCESSJS='export const meta = { name: "x", description: "y" };
process.exit(0);'
proc=$(mk processjs "$PROCESSJS")
assert_stdout process-flagged "$proc" '"rule":"forbidden-api"'

EVALJS='export const meta = { name: "x", description: "y" };
const r = eval("1 + 1");'
evaljs=$(mk evaljs "$EVALJS")
assert_stdout eval-flagged "$evaljs" '"rule":"forbidden-api"'

FETCHJS='export const meta = { name: "x", description: "y" };
const r = await fetch("http://example.com");'
fetchjs=$(mk fetchjs "$FETCHJS")
assert_stdout fetch-flagged "$fetchjs" '"rule":"forbidden-api"'

# An identifier that merely CONTAINS a banned token must not false-trip.
LOOKALIKE='export const meta = { name: "x", description: "y" };
const updateDate = args.now;
const retrieval = updateDate;'
lookalike=$(mk lookalike "$LOOKALIKE")
assert_stdout lookalike-identifiers-ok "$lookalike" 'BUILD_FLEET_LINT_PASS'

# ---- contract: must declare export const meta ----
NOMETA='const x = 1;
function build() { return x + 1; }'
nometa=$(mk nometa "$NOMETA")
assert_stdout missing-meta-flagged "$nometa" '"rule":"missing-meta"'
assert_rc     missing-meta-rc      "$nometa" 2

# ---- multiple violations are all reported ----
MULTI='export const meta = { name: "x", description: "y" };
const t = Date.now();
const r = Math.random();'
multi=$(mk multi "$MULTI")
assert_stdout multi-date   "$multi" '"rule":"date-now"'
assert_stdout multi-random "$multi" '"rule":"math-random"'

# ---- fail-closed on bad input ----
assert_rc no-arg-fails        ""                    2
assert_rc traversal-fails     "../etc/passwd"       2
assert_rc nonexistent-fails   "$TMP/does-not-exist.js" 2

echo "-----"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
