---
description: Start a feature (or the next backlog one) and get its spec review-clean
argument-hint: "[idea | --product \"<vision>\"]"
allowed-tools: Read, Skill, Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/lite-next.sh":*)
---

# /build-fleet:start

This command's name is `start`. It takes a feature from an idea to a spec that is ready
to build. With no idea, it takes the next unblocked feature from the product backlog.
With `--product "<vision>"`, it sets up the product plan and stops for you to ratify it.

It stops when the spec is ready (run `/build-fleet:build` to approve it), when the
product plan awaits `/build-fleet:status ratify`, when another item is in flight
(`/build-fleet:status park <reason>`), or on an escalation.

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

`start` never receives it. If it appears, end with
`BUILD_FLEET_LITE_DONE: {"stop":"unknown-state"}`.
