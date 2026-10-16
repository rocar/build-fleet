#!/usr/bin/env bash
# Tests for log_event / read_events / sha256_stdin in hooks/scripts/_lib.sh.
# The rule under test: logging never changes a caller's decision — every failure is
# swallowed with a stderr note and return 0.
# Run: bash scripts/log-event.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$DIR/../hooks/scripts/_lib.sh"
work="$(mktemp -d)"; trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT
pass=0; fail=0
assert() { if eval "$2"; then pass=$((pass+1)); printf 'ok   %s\n' "$1"; else fail=$((fail+1)); printf 'FAIL %s (%s)\n' "$1" "$2"; fi; }
mkdir -p "$work/p/.sdd/feat"
run() { ( cd "$work/p" && CLAUDE_PROJECT_DIR="$work/p" bash -c ". '$LIB'; $1" ); }

run "log_event feat '{\"kind\":\"gate\",\"source\":\"script:x\",\"decision\":\"pass\"}'"; rc=$?
assert "append-rc0" "[ $rc -eq 0 ]"
assert "append-one-line" "[ \$(wc -l < '$work/p/.sdd/feat/EVENTS.jsonl') -eq 1 ]"
assert "append-schema" "jq -e '.v == 1 and .slug == \"feat\" and .kind == \"gate\" and .source == \"script:x\" and (.ts | test(\"Z\$\"))' '$work/p/.sdd/feat/EVENTS.jsonl' >/dev/null"
run "log_event '' '{\"kind\":\"gate\"}'"
assert "empty-slug-goes-to-project-log" "[ -f '$work/p/.sdd/_events.jsonl' ]"
before=$(wc -l < "$work/p/.sdd/feat/EVENTS.jsonl" | tr -d ' ')
out=$(run "log_event ../x '{}'; echo rc=\$?" 2>&1)
assert "bad-slug-swallowed" "printf '%s' \"\$out\" | grep -q 'rc=0' && printf '%s' \"\$out\" | grep -q 'bad slug'"
assert "bad-slug-writes-nothing" "[ ! -e '$work/p/x/EVENTS.jsonl' ] && [ ! -e '$work/x/EVENTS.jsonl' ]"
out=$(run "log_event feat 'not json'; echo rc=\$?" 2>&1)
assert "bad-payload-swallowed" "printf '%s' \"\$out\" | grep -q 'rc=0' && printf '%s' \"\$out\" | grep -q 'bad event payload'"
assert "bad-payload-appends-nothing" "[ \$(wc -l < '$work/p/.sdd/feat/EVENTS.jsonl' | tr -d ' ') -eq $before ]"
chmod a-w "$work/p/.sdd/feat/EVENTS.jsonl"
out=$(run "log_event feat '{}'; echo rc=\$?" 2>&1)
assert "unwritable-swallowed" "printf '%s' \"\$out\" | grep -q 'rc=0' && printf '%s' \"\$out\" | grep -q 'event dropped'"
chmod u+w "$work/p/.sdd/feat/EVENTS.jsonl"
printf 'garbage line\n' >> "$work/p/.sdd/feat/EVENTS.jsonl"
n=$(run "read_events feat script:x" | wc -l | tr -d ' ')
assert "read-events-skips-malformed" "[ '$n' = 1 ]"
h=$(run "printf abc | sha256_stdin")
assert "sha256-known-vector" "[ '$h' = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' ]"
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
