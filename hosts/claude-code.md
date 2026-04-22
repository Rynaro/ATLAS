# Wiring ATLAS into Claude Code

Full install guide: [`INSTALL.md §2a`](../INSTALL.md#2a-claude-code). This file is the quick-reference summary.

---

## 1. Install

From inside the consumer repo (after vendoring ATLAS via `bash install.sh --hosts claude-code`):

```bash
# Wire always-on profile
cat >> CLAUDE.md <<'EOF'

## ATLAS methodology

This project runs under the **ATLAS v1.0** read-only scout methodology.
See `.eidolons/atlas/agent.md` for the always-loaded agent profile and
`.eidolons/atlas/AGENTS.md` for the full rule set.
EOF

# Wire progressive-disclosure skills
mkdir -p .claude/skills
for phase in traverse locate abstract synthesize; do
  ln -sf ../../.eidolons/atlas/skills/$phase .claude/skills/atlas-$phase
done

# Wire subagent
mkdir -p .claude/agents
cp .eidolons/atlas/agent.md .claude/agents/atlas.md
# Edit the copy: rename `allowed-tools:` → `tools:` and map to host-native tools
```

---

## 2. Config

**`.claude/agents/atlas.md` frontmatter adjustment** (required — Claude Code uses `tools:` not `allowed-tools:`):

```diff
---
 name: atlas
-allowed-tools: view_file list_dir search_text search_symbol graph_query test_dry_run memex_read
+tools: Read, Grep, Glob, Bash(rg:*), Bash(git log:*), Bash(git show:*)
---
```

If `atlas-aci` MCP server is installed:

```yaml
tools: mcp__atlas_aci__view_file, mcp__atlas_aci__search_symbol, mcp__atlas_aci__search_text, mcp__atlas_aci__list_dir, mcp__atlas_aci__graph_query, mcp__atlas_aci__test_dry_run, mcp__atlas_aci__memex_read
```

MCP wiring:

```bash
claude mcp add atlas-aci -- atlas-aci serve --repo .
```

---

## 3. Verify

In Claude Code:

1. Run `/atlas-traverse` — expected: the Traverse contract prints.
2. Confirm the slash-command list shows `/atlas-traverse`, `/atlas-locate`, `/atlas-abstract`, `/atlas-synthesize`.
3. Paste the smoke-test mission:

   > *"Under ATLAS, answer: List every public HTTP endpoint in this repository and identify the controller handling each. Use scope `**/*`, budget 30 tool calls. Emit `mission.md` first, then run Traverse, then Locate, then Synthesize."*

   Expected: agent emits `mission.md` before any search, produces `map.md`, then `findings.md` with `FINDING-XXX` IDs and `path:line` anchors, then `scout-report.md` ≤3000 tokens.

---

## 4. Troubleshooting

**Skill not triggering automatically.**
The `description` field in each SKILL.md drives intelligent activation. Confirm it includes the phase name and trigger phrases ("trace", "find where", "map the"). Claude Code truncates descriptions at 1,536 chars — front-load the key use case.

**Subagent not appearing in `/agents` list.**
Ensure `.claude/agents/atlas.md` exists and the `name:` field in frontmatter matches `atlas`. Restart Claude Code after adding a new agents/ file.

**Bounds not enforced mechanically.**
Native Claude Code tools (`Read`, `Grep`, `Glob`) are advisory-bounded. For mechanical enforcement install `atlas-aci` as an MCP server — see `INSTALL.md` Appendix A.

**agent.md token count.**
`wc -w .eidolons/atlas/agent.md | awk '{print $1/0.75}'` — must be ≤1000. See `INSTALL.md` Appendix B for safe trims.
