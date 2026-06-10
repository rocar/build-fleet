// SPDX-License-Identifier: MIT
// workflows/hello.js
//
// M0 EMPIRICAL PROBE — plugin-shipped workflow discovery test.
//
// Why this file exists:
//   The Claude Code workflows docs (https://code.claude.com/docs/en/workflows)
//   only confirm `.claude/workflows/` (project) and `~/.claude/workflows/`
//   (personal) as auto-discovered locations. The exhaustive plugin-components
//   reference at code.claude.com contains ZERO mentions of "workflow."
//   Whether `${CLAUDE_PLUGIN_ROOT}/workflows/<name>.js` is picked up by the
//   runtime as `/build-fleet:hello` is undocumented.
//
//   This file is the cheapest probe: if `/build-fleet:hello` appears in
//   `/` autocomplete (or `/workflows` lists it) after a reload, plugin-shipped
//   workflows auto-discover. If not, v0.2 needs an alternate distribution
//   path (likely: thin command body that points at this file, or a
//   one-time install command that copies it into `.claude/workflows/`).
//
// How to test (manual; requires a live Claude Code session OUTSIDE the
// plugin's own session, so reload semantics apply):
//   1.  Open a fresh terminal:
//         mkdir -p ~/tmp/bf-v0.2-probe && cd ~/tmp/bf-v0.2-probe
//   2.  Launch Claude Code with this plugin mounted:
//         claude --plugin-dir /Users/rocconno/build-fleet
//   3.  Inside the session:
//         /reload-plugins   (only if Claude was already running)
//   4.  Type `/` and check whether `/build-fleet:hello` shows in autocomplete.
//   5.  Run `/workflows` and check whether `hello` appears in the list.
//   6.  If neither #4 nor #5 surfaces it, also try `/help` and inspect the
//       plugin section for any reference to a `hello` workflow.
//   7.  Report back: which (if any) of #4, #5, #6 surfaced the workflow.
//
// SHAPE caveat:
//   The actual workflow-script JavaScript API surface (`task()` signature,
//   how phases are declared, how a return value is delivered to the caller)
//   is not in the workflows page we have. The shape below is best-guess from
//   the `/deep-research` pattern. If the runtime syntactically rejects this,
//   discovery is moot until we ground the API by inspecting a real
//   /deep-research raw script (Ctrl+G at its approval prompt).
//
//   This probe is therefore a layered question:
//     (a) Does the file's PRESENCE surface `/build-fleet:hello`?
//     (b) Does the runtime ACCEPT the file as a valid workflow?
//   We expect (a) to be answered by the autocomplete check alone. Answer (b)
//   only matters if (a) is yes.

export default {
  description: "M0 probe: tests whether plugin-shipped workflows auto-discover.",
  phases: [
    "Hello (single-phase probe — returns immediately)",
  ],

  async run() {
    return {
      build_fleet_version: "0.2-probe",
      verdict: "probe-complete",
      message: "If you can see this in a session, plugin-shipped workflows discovered AND were accepted by the runtime.",
    };
  },
};
