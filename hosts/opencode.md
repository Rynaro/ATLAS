# Wiring ATLAS into OpenCode

Full install guide: [`INSTALL.md §2d`](../INSTALL.md#2d-opencode). This file is the quick-reference summary.

---

## 1. Install

From inside the consumer repo (after vendoring ATLAS via `bash install.sh --hosts opencode`):

```bash
# Root-level AGENTS.md
ln -sf agents/atlas/AGENTS.md AGENTS.md

# Primary agent
mkdir -p .opencode/agents
```

Create `.opencode/agents/atlas.md`:

```markdown
---
description: Read-only codebase scout running the ATLAS v1.0 five-phase pipeline (Assess → Traverse → Locate → Abstract → Synthesize). Use for exploration, impact analysis, and pre-planning. Refuses write verbs.
mode: primary
permission:
  edit: deny
  write: deny
  bash:
    "rg *": allow
    "git log *": allow
    "git show *": allow
    "*": deny
---

You are the ATLAS explorer/scout agent. Full rules: `agents/atlas/AGENTS.md`.
Always-loaded profile: `agents/atlas/agent.md`.
Phase skills: `agents/atlas/skills/<phase>/SKILL.md` — load only the active phase.
Full spec: `agents/atlas/ATLAS.md`.
```

**Optional: phase subagents.** Create `.opencode/agents/atlas-traverse.md`:

```markdown
---
description: ATLAS Phase T — deterministic structural mapping. Spawn when a mission brief exists and Traverse has not yet run.
mode: subagent
permission:
  edit: deny
  write: deny
  bash:
    "rg *": allow
    "git log *": allow
    "*": deny
---

Load `agents/atlas/skills/traverse/SKILL.md` and execute Phase T for the parent mission.
Emit `map.md` using `agents/atlas/templates/traversal-map.md`.
Return ONE structured summary to the parent — never the raw transcript.
```

Repeat for `atlas-locate.md`, `atlas-abstract.md`, `atlas-synthesize.md`.

---

## 2. Config

**`permission:` block is required.** The final `"*": deny` under `bash` is critical — without it, unmatched commands default to allow.

**Optional: MCP enforcement.** Add to `.opencode/opencode.json`:

```jsonc
{
  "mcp": {
    "servers": {
      "atlas-aci": {
        "type": "stdio",
        "command": ["atlas-aci", "serve", "--repo", "."]
      }
    }
  }
}
```

---

## 3. Verify

In `opencode`:

1. Press **Tab** to switch to the `atlas` primary agent.
2. Type `@atlas-traverse` — expected: subagent autocompletes.
3. Ask: *"Under ATLAS, find all writers to the sessions table."*  
   Expected: opencode refuses until a `mission.md` exists, then runs Assess → Traverse → Locate in sequence, spawning subagents where appropriate.

---

## 4. Troubleshooting

**Agent has unexpected write access.**
Verify the `permission:` block in `.opencode/agents/atlas.md`. The `"*": deny` under `bash` must be the last entry. See the `permission:` block example above.

**Subagent transcripts leaking into parent context.**
Subagents must return a single structured `FINDING` object — not free-form text. Edit the subagent body to include: *"Return ONE structured summary to the parent — never the raw transcript."*

**`AGENTS.md` not auto-loaded.**
OpenCode loads `AGENTS.md` from the repo root. Confirm the symlink resolves: `ls -la AGENTS.md` should show it pointing at `agents/atlas/AGENTS.md`.
