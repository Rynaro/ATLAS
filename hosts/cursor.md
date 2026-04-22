# Wiring ATLAS into Cursor

Full install guide: [`INSTALL.md §2b`](../INSTALL.md#2b-cursor). This file is the quick-reference summary.

---

## 1. Install

From inside the consumer repo (after vendoring ATLAS via `bash install.sh --hosts cursor`):

```bash
# Root-level AGENTS.md (Cursor fallback)
ln -sf .eidolons/atlas/AGENTS.md AGENTS.md

# MDC rule wrappers
mkdir -p .cursor/rules
```

Create `.cursor/rules/atlas-00-always.mdc`:

```markdown
---
description: ATLAS v1.0 — read-only codebase scout. Always applied. Refuses write verbs; requires mission.md with DECISION_TARGET; bounded ACI; evidence-anchored claims.
alwaysApply: true
---

See `.eidolons/atlas/AGENTS.md` for the full rule set and `.eidolons/atlas/ATLAS.md` for the spec.

Phases: A (Assess, inline) → T (Traverse, @atlas-traverse) → L (Locate, @atlas-locate) → A (Abstract, @atlas-abstract) → S (Synthesize, @atlas-synthesize)
```

Create `.cursor/rules/atlas-traverse.mdc`:

```markdown
---
description: Phase T (Traverse) — deterministic structural mapping. Zero LLM calls during retrieval. Load when a mission.md brief exists and before any meaning-based search.
globs: ["**/*"]
alwaysApply: false
---

@.eidolons/atlas/skills/traverse/SKILL.md
```

Repeat for `atlas-locate.mdc`, `atlas-abstract.mdc`, `atlas-synthesize.mdc` with matching descriptions from each SKILL.md.

---

## 2. Config

**Cursor MDC frontmatter fields used:**

| Field | Purpose |
|-------|---------|
| `description` | Drives intelligent rule activation when `alwaysApply: false` |
| `alwaysApply` | `true` for the always-on profile; `false` for phase rules |
| `globs` | Path filter for automatic activation (default `["**/*"]` lets description decide) |

**Optional: MCP enforcement.** Create `.cursor/mcp.json` at repo root:

```jsonc
{
  "mcpServers": {
    "atlas-aci": {
      "command": "atlas-aci",
      "args": ["serve", "--repo", "."],
      "transport": "stdio"
    }
  }
}
```

---

## 3. Verify

In Cursor:

1. Open Rules panel (⌘ + Shift + P → "Cursor: Rules"). Confirm `atlas-00-always` shows *Always applied*; the four phase rules show *Agent requested* or *Apply intelligently*.
2. In chat, type `@atlas-traverse` — expected: autocompletes and injects the Traverse skill body.
3. Ask: *"Under ATLAS, map the HTTP entrypoints in this repo."*  
   Expected: Cursor refuses write verbs and asks for a mission brief first.

---

## 4. Troubleshooting

**Wrong phase skill attaches.**
Check `globs:` in the MDC wrappers. Default `["**/*"]` lets Cursor decide via description. Narrow the glob (e.g. `["test/**"]`) or use explicit `@atlas-<phase>` mentions to disambiguate.

**`@atlas-traverse` file reference fails.**
Cursor's `@<path>` syntax requires a path relative to repo root. Confirm the path in the `mdc` wrapper matches your actual install target (e.g. `.eidolons/atlas/skills/traverse/SKILL.md`).

**AGENTS.md not recognized.**
Cursor 0.45+ reads `AGENTS.md` at repo root as a fallback. Earlier versions rely entirely on `.cursor/rules/`. Confirm your Cursor version and upgrade if needed.
