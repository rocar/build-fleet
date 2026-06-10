# hello.js probe — findings (v0.2 M0)

`workflows/hello.js` was a dev-only empirical probe shipped during v0.2 M0 to
answer one question: **are plugin-shipped workflow scripts auto-discovered by
name** (the way `.claude/workflows/` project scripts and `~/.claude/workflows/`
personal scripts are)? The official workflows docs confirmed only those two
locations; the plugin-components reference contained zero mentions of
"workflow", so `${CLAUDE_PLUGIN_ROOT}/workflows/<name>.js` discovery was
undocumented. The probe file was deleted from the shipping plugin during the
2026-06 audit remediation (audit §3.15); this note preserves what it
established.

## What the probe established

- **Distribution is solved by `scriptPath`, not by-name discovery.** SDK source
  inspection (`@anthropic-ai/claude-agent-sdk@0.3.158`, `sdk-tools.d.ts`)
  confirmed `WorkflowInput.scriptPath` takes precedence over `script` and
  `name`. All build-fleet commands invoke the Workflow tool with
  `scriptPath: ${CLAUDE_PLUGIN_ROOT}/workflows/<name>.js` — this works
  regardless of auto-discovery. (CONTROLS.md question 2b, RESOLVED.)
- **By-name auto-discovery of plugin-shipped workflows remains an open
  empirical question**, but it is not a blocker for any release: nothing in the
  plugin depends on it. If it ever matters, repeat the probe: drop a trivial
  workflow file under `workflows/`, mount the plugin in a fresh session
  (`claude --plugin-dir <repo>`), and check whether `/build-fleet:hello`
  appears in `/` autocomplete or `/workflows`.
- **The probe's API shape was wrong by its own admission.** It used a guessed
  `export default { ..., async run() {} }` shape predating the grounded API
  (pure-literal `export const meta`, top-level script body, `agent()` /
  `parallel()` / `phase()` / `log()` globals, `args` for inputs, no
  Date/Math.random). The four shipping workflows are the authoritative shape;
  do not copy the probe's.

## Why the file was deleted

It was a self-disclaimed wrong-shaped dev probe with a hardcoded developer
path, referenced by nothing, shipping in every release and breaking the
README's "four dynamic workflows" count. Its only durable value is the
paragraph above.
