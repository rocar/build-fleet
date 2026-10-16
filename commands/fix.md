---
description: Take a bug from symptom to a verified, shipped fix
argument-hint: "<symptom>"
allowed-tools: Read, Write, Edit, Grep, Glob, Skill, Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/lite-next.sh":*)
---

# /build-fleet:fix

This command's name is `fix`. It files the bug, writes a failing reproduction, proposes
a root cause and has it challenged, applies and verifies the fix, and hands off to
devops. It stops at devops' OK, at devops' refusal, or on an escalation.

<!-- LITE-LOOP START -->
## The loop

You are a thin driver. You never choose the next step yourself; the router does.

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lite-next.sh" <name> $ARGUMENTS`, where `<name>`
   is this command's name (above). Pass `$ARGUMENTS` on the first pass only; on every later
   pass run it with `<name>` alone.
2. Read its one `BUILD_FLEET_LITE_NEXT:` line.
   - `"stop"` → write two to four lines on what this run did, then print
     `BUILD_FLEET_LITE_DONE: {"stop":"<stop>","next":"<next>"}` (leave out `next` when the
     line has none) and end.
   - `"step":"action:hypothesis"` → carry out the hypothesis action below, then go to 1.
   - any other `"step"` → invoke the Skill tool with skill `build-fleet:<step>` and the
     line's `args`. If the step prints `BUILD_FLEET_WORKFLOW_LAUNCHED`, wait for that
     workflow's completion notification and read its result before you go on.
3. If the step printed a `BUILD_FLEET_*` line whose tag ends in `_REFUSE`, `_REFUSED`,
   `_FAIL` or `_INCOMPLETE`, or a workflow result has `verdict` `incomplete` or
   `invalid-args` or `scribe_apply: "failed"`: relay it verbatim and end with
   `BUILD_FLEET_LITE_DONE: {"stop":"step-refused","step":"<step>"}`.
4. If the step printed `BUILD_FLEET_DEVOPS_OK`: end with
   `BUILD_FLEET_LITE_DONE: {"stop":"shipped"}`. If it printed
   `BUILD_FLEET_TRIAGE_KNOWN_CAUSE` (triage found the cause already known and closed the
   bug), end with `BUILD_FLEET_LITE_DONE: {"stop":"known-cause","next":"/build-fleet:start <the fix to make>"}`,
   naming the fix triage recommends.
5. Guards. Before each step, note the active item's `PROGRESS.md` and `spec.md` (or
   `diagnosis.md`). If the router names the same step twice in a row and those files did
   not change in between, end with `BUILD_FLEET_LITE_DONE: {"stop":"no-progress","step":"<step>"}`.
   After 12 steps in this run, end with `BUILD_FLEET_LITE_DONE: {"stop":"step-cap"}`;
   running the command again resumes.
6. Go to 1.

Never pass a step's own "next command" hints on to the user. The only next command you
name is the one in your `BUILD_FLEET_LITE_DONE` line. `build`, `ship` and `status` are
human-only, so they never appear in your own command list; the router's `next` is still
correct. Relay it verbatim and never substitute a hidden step for it.
<!-- LITE-LOOP END -->

## The hypothesis action

This is the one write you make yourself.

1. Read `.sdd/<slug>/diagnosis.md`, the reproducing test it names, and, if
   `.sdd/<slug>/REVIEW.md` exists, the refutations from the latest cycle.
2. Investigate the code read-only (Read, Grep, Glob).
3. Edit only the `## Root-cause hypothesis`, `## Blast radius` and `## Fix strategy`
   sections of `diagnosis.md` (`diagnose` refuses while any is empty). State one
   falsifiable root cause that explains the reproduction and answers the earlier
   refutations, what it reaches, and the smallest fix.
4. Make the step's `args` (`HYPOTHESIS_CYCLE: <n>`) the first line under
   `## Root-cause hypothesis`, replacing any earlier `HYPOTHESIS_CYCLE:` line.
5. Write nothing else.
