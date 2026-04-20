# Wiring ATLAS into GitHub Copilot

Full install guide: [`INSTALL.md §2c`](../INSTALL.md#2c-github-copilot). This file is the quick-reference summary.

---

## 1. Install

From inside the consumer repo (after vendoring ATLAS via `bash install.sh --hosts copilot`):

```bash
# Always-on custom instructions
mkdir -p .github
cp agents/atlas/.github/copilot-instructions.md .github/copilot-instructions.md

# Root-level AGENTS.md for modern Copilot hosts
ln -sf agents/atlas/AGENTS.md AGENTS.md
```

---

## 2. Config

**`.github/copilot-instructions.md`** — already bundled in `agents/atlas/.github/`. Contents: minimal pointer at `AGENTS.md` + the eight P0 invariants. ~60 lines, well under Copilot's recommended size.

**`AGENTS.md` at repo root** — loaded by VS Code Copilot 1.92+, GitHub.com Copilot Chat, the Copilot coding agent. Contains the full ATLAS rule set with frontmatter.

**Optional: path-scoped rules.** Create `.github/instructions/atlas-traverse.instructions.md`:

```markdown
---
applyTo: "**"
---

When discussing codebase structure, routing, entrypoints, or module layout,
operate under **ATLAS Phase T (Traverse)**. Zero LLM calls during retrieval.
Output is `map.md`. See `agents/atlas/skills/traverse/SKILL.md`.
```

Repeat for Locate, Abstract, Synthesize with appropriate `applyTo:` globs.

**Optional: MCP enforcement** (VS Code `settings.json`, workspace scope):

```jsonc
{
  "github.copilot.chat.mcp.servers": {
    "atlas-aci": {
      "command": "atlas-aci",
      "args": ["serve", "--repo", "${workspaceFolder}"],
      "transport": "stdio"
    }
  }
}
```

---

## 3. Verify

In Copilot Chat:

1. Ask: *"What rules are you operating under?"*  
   Expected: Copilot cites `copilot-instructions.md` and/or `AGENTS.md` and lists the ATLAS P0 rules.

2. Ask: *"Refactor `src/foo.ts` to use async/await."*  
   Expected: Copilot refuses the refactor verb and offers a `→ APIVR-Δ` handoff.

3. Check Copilot Code Review on a PR — it should reference the ATLAS invariants when commenting.

---

## 4. Troubleshooting

**Copilot ignores `AGENTS.md`.**
Not all Copilot hosts have shipped `AGENTS.md` support. The `.github/copilot-instructions.md` fallback is always loaded. Confirm it exists and contains the ATLAS rules summary.

**Instructions too long.**
Copilot recommends ≤8,000 chars for `copilot-instructions.md`. The bundled file is ~60 lines. If you've appended other content, trim or split into path-scoped `.github/instructions/*.instructions.md` files.

**Copilot Code Review missing ATLAS context.**
Code Review loads `copilot-instructions.md` automatically. If reviews don't cite ATLAS, check that the file is at `.github/copilot-instructions.md` (not a subdirectory).
