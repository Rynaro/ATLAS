# Installing ATLAS

This guide installs the ATLAS v1.0 scout methodology into any codebase so
that **Claude Code**, **Cursor**, **GitHub Copilot**, or **OpenCode** will
run under its rules. ATLAS is a documentation-only specification — you are
mounting a set of Markdown files that the agent host reads as custom
instructions, skills, or subagents. No runtime required.

A reference **MCP server** (`atlas-aci`, Python) adds mechanical enforcement
of the bounded ACI (`view_file` ≤100 lines, `search_text` ≤50 matches, etc.)
and an AST code graph. The MCP server is **optional** — see Appendix A. You
can install ATLAS without it and rely on the host's native read tools.

---

## Which install do I need?

| I want to… | Minimum install | Recommended |
|---|---|---|
| Try ATLAS on one repo, one host | Step 1 + one host section from Step 2 | + Step 3 verification |
| Run ATLAS on a team codebase | Step 1 + host section + commit results to VCS | + Appendix A (MCP) for enforcement |
| Run ATLAS across multiple hosts (e.g. Claude Code **and** Cursor) | Step 1 + every host section you use | `AGENTS.md` at root covers three of four hosts from one file |
| Get the full mechanical enforcement layer | Step 1 + Step 2 + Appendix A | Also index the repo so graph queries resolve |

**ATLAS vs `atlas-aci`.** ATLAS is the *methodology* (this repo). `atlas-aci`
is the reference *MCP server* that enforces the bounded ACI contract. You
can run ATLAS with either:

- The host's native read tools (Claude Code `Read`/`Grep`/`Glob`, Cursor
  built-in file tools, etc.) — simpler, but bounds are soft (advisory).
- `atlas-aci` — bounds are mechanical, AST code graph is available, and
  `search_symbol` / `graph_query` become first-class tools.

---

## Prerequisites

**Always required:**

- `git` (to vendor ATLAS and check diffs of the scout artifacts)
- One supported host with custom-instruction or skill support:
  - **Claude Code** v1.0+ (filesystem-based skills, `.claude/agents/` subagents)
  - **Cursor** v0.45+ (MDC rules, `.cursor/rules/`, or `AGENTS.md`)
  - **GitHub Copilot** (any IDE/host that loads
    `.github/copilot-instructions.md` or `AGENTS.md`)
  - **OpenCode** latest (custom agents in `.opencode/agents/` or `AGENTS.md`)

**Required if you install the MCP server (Appendix A):**

- `ripgrep` (`brew install ripgrep`, `apt install ripgrep`)
- Python 3.11+ (for `atlas-aci`)
- Tree-sitter — bundled with `atlas-aci`; no separate install.

**Optional but recommended:**

- A code-graph MCP server (Sourcegraph, Prism-codegraph, or `atlas-aci`'s
  built-in tree-sitter graph). Without it, Phase T falls back to `rg`-only.

---

## Step 1 — Vendor ATLAS into your target repo

From inside the target repository (the repo you want ATLAS to explore):

### Option A — git subtree (recommended)

```bash
git subtree add --prefix=.atlas \
  https://github.com/Rynaro/atlas.git main --squash
```

Upgrades are `git subtree pull --prefix=.atlas https://github.com/Rynaro/atlas.git main --squash`.

### Option B — Submodule

```bash
git submodule add https://github.com/Rynaro/atlas.git .atlas
git submodule update --init
```

### Option C — Copy

```bash
curl -L https://github.com/Rynaro/atlas/archive/refs/heads/main.tar.gz \
  | tar -xz --strip-components=1 -C .atlas atlas-main/{agent.md,ATLAS.md,AGENTS.md,skills,templates,schemas}
```

### Target layout

After Step 1 your repo should contain:

```
<your-repo>/
├── .atlas/
│   ├── agent.md                       # always-loaded profile
│   ├── ATLAS.md                       # authoritative spec
│   ├── AGENTS.md                      # open-standard rules file
│   ├── skills/
│   │   ├── traverse/SKILL.md
│   │   ├── locate/SKILL.md
│   │   ├── abstract/SKILL.md
│   │   └── synthesize/SKILL.md
│   ├── templates/                     # fill-in-the-blank artifacts
│   └── schemas/                       # JSON Schema validators
└── … (your source code)
```

> **Why `.atlas/`?** A single vendored directory keeps upgrades atomic and
> makes the methodology files easy to diff. Every host integration in Step 2
> symlinks or copies *into* this directory, so you never duplicate content.

---

## Step 2 — Host integration

Pick the host(s) you use. If you use several, apply multiple sections —
`AGENTS.md` at the repo root is the shared always-on profile and only needs
to be set up once.

### 2a. Claude Code

Claude Code auto-loads:

- `CLAUDE.md` at repo root → always-on project memory
- `.claude/skills/<name>/SKILL.md` → progressive-disclosure skills (loaded
  by description matching)
- `.claude/agents/<name>.md` → subagents invoked via the Agent/Task tool

**2a.1 Always-on profile.** Create a thin `CLAUDE.md` that delegates to the
vendored profile so there is one source of truth:

```bash
cat > CLAUDE.md <<'EOF'
# Project rules

This project runs under the **ATLAS v1.0** read-only scout methodology.
See `.atlas/agent.md` for the always-loaded agent profile and
`.atlas/AGENTS.md` for the full rule set. Skills live in
`.atlas/skills/<phase>/SKILL.md` and load progressively per phase.

**Absolute rules (P0):**
- Read-only: refuse edit/write/commit/deploy/migrate/refactor/fix.
- Mission-first: no exploration without `mission.md` + `DECISION_TARGET`.
- Evidence-anchored claims: every fact carries `path:line_start-line_end` + H|M|L.
EOF
```

**2a.2 Skills.** Wire the four phase skills into Claude Code's discovery
path. The canonical SKILL.md files already carry Claude Code-compatible
frontmatter, so symlinking is sufficient:

```bash
mkdir -p .claude/skills
for phase in traverse locate abstract synthesize; do
  ln -sf ../../.atlas/skills/$phase .claude/skills/atlas-$phase
done
```

After this, `/atlas-traverse`, `/atlas-locate`, `/atlas-abstract`, and
`/atlas-synthesize` appear in the slash-command menu, and Claude Code will
auto-load the skill whose `description` matches the active phase.

If your host does not follow symlinks inside `.claude/`, use `cp -r` instead
and re-run after `git subtree pull`.

**2a.3 Subagent.** Drop the canonical `agent.md` into the subagent slot so
Claude Code can dispatch ATLAS as a task:

```bash
mkdir -p .claude/agents
cp .atlas/agent.md .claude/agents/atlas.md
```

Claude Code's subagent frontmatter uses `tools:` instead of `allowed-tools:`.
Edit the copy to rename that one field (the rest carries over verbatim):

```diff
---
 name: atlas
 description: Read-only codebase scout …
-allowed-tools: view_file list_dir search_text search_symbol graph_query test_dry_run memex_read
+tools: Read, Grep, Glob, Bash(rg:*), Bash(git log:*)
 …
---
```

If you install `atlas-aci` (Appendix A), replace the `tools:` value with
`mcp__atlas_aci__*` to expose the bounded primitives directly.

**2a.4 Verification.** In Claude Code:

1. Run `/atlas-traverse` — it should print the Traverse contract.
2. Ask: *"Map this repo's HTTP entrypoints under ATLAS."*
3. Expected: Claude refuses to start probing before a `mission.md` exists,
   then proposes one, then runs Phase T.
4. Expected: the slash-command list shows `/atlas-traverse`, `/atlas-locate`,
   `/atlas-abstract`, `/atlas-synthesize`.

> Claude Code watches `.claude/skills/` for changes; adding or editing a
> skill takes effect mid-session. If a *new* top-level `.claude/skills/`
> directory appears after the session started, restart Claude Code so it
> can begin watching it.

---

### 2b. Cursor

Cursor reads `.cursor/rules/*.mdc` (MDC = Markdown with YAML frontmatter) and,
as a fallback, `AGENTS.md` at repo root. The canonical ATLAS skills use the
Agent Skills open standard frontmatter, which Cursor does not natively
parse, so you create thin MDC wrappers that point at the real SKILL.md
bodies.

**2b.1 Always-on profile.** `AGENTS.md` is already in `.atlas/AGENTS.md`
(from Step 1). Copy or symlink it to the repo root so Cursor auto-discovers
it:

```bash
ln -sf .atlas/AGENTS.md AGENTS.md
```

**2b.2 Rule wrappers.** Create one `.mdc` file per phase:

```bash
mkdir -p .cursor/rules
```

Create `.cursor/rules/atlas-00-always.mdc`:

```markdown
---
description: ATLAS v1.0 — read-only codebase scout methodology. Always applied. Refuses write verbs; requires mission.md with DECISION_TARGET before exploration; bounded ACI; evidence-anchored claims.
alwaysApply: true
---

See `.atlas/AGENTS.md` for the full rule set and `.atlas/ATLAS.md` for the
v1.0 specification.

The five phases and their skill files:
- Phase A (Assess) — inline, see `.atlas/ATLAS.md` §2.1
- Phase T (Traverse) — `.atlas/skills/traverse/SKILL.md` → see @atlas-traverse
- Phase L (Locate) — `.atlas/skills/locate/SKILL.md` → see @atlas-locate
- Phase A (Abstract) — `.atlas/skills/abstract/SKILL.md` → see @atlas-abstract
- Phase S (Synthesize) — `.atlas/skills/synthesize/SKILL.md` → see @atlas-synthesize
```

Create `.cursor/rules/atlas-traverse.mdc`:

```markdown
---
description: Phase T (Traverse) — deterministic structural mapping. Load when a mission.md brief exists and before any meaning-based search. Zero LLM calls during retrieval.
globs: ["**/*"]
alwaysApply: false
---

@.atlas/skills/traverse/SKILL.md
```

Repeat for `atlas-locate.mdc`, `atlas-abstract.mdc`, `atlas-synthesize.mdc`
with matching descriptions (lifted from the `description:` field of each
canonical SKILL.md).

The `@.atlas/skills/<phase>/SKILL.md` line uses Cursor's file-reference
syntax, so the full skill body loads without duplication.

**2b.3 Verification.** In Cursor:

1. Open the Rules panel (⌘ + Shift + P → "Cursor: Rules") and confirm all
   five rules appear. `atlas-00-always` should show as *Always applied*;
   the four phase rules as *Agent requested* or *Apply intelligently*.
2. In chat, type `@atlas-traverse` — it should autocomplete, then inject
   the Traverse skill body.
3. Ask: *"Under ATLAS, map the HTTP entrypoints in this repo."*
4. Expected: Cursor refuses write verbs and asks for a mission brief first.

---

### 2c. GitHub Copilot

Copilot auto-loads `.github/copilot-instructions.md` (all hosts) and
`AGENTS.md` at repo root (modern hosts). For path-scoped rules, Copilot
also supports `.github/instructions/*.instructions.md` with an `applyTo:`
frontmatter field.

**2c.1 Always-on instructions.** Copy the bundled Copilot entry:

```bash
mkdir -p .github
cp .atlas/.github/copilot-instructions.md .github/copilot-instructions.md
```

This file is a minimal pointer at `AGENTS.md` + the eight invariants; it is
~60 lines and stays well under the recommended size.

**2c.2 Root-level AGENTS.md.** Modern Copilot (VS Code 1.92+, GitHub.com,
the coding agent) loads `AGENTS.md` alongside `copilot-instructions.md`:

```bash
ln -sf .atlas/AGENTS.md AGENTS.md    # idempotent — skip if you did this in 2b.1
```

**2c.3 Path-scoped rules (optional).** If you want Copilot to enforce
phase-specific guidance only when touching certain paths, create
`.github/instructions/atlas-traverse.instructions.md`:

```markdown
---
applyTo: "**"
---

When discussing codebase structure, routing, entrypoints, or module layout
under this repository, operate under **ATLAS Phase T (Traverse)**:

- Zero LLM calls during retrieval. Symbol index → Tree-sitter → `rg` →
  `git log`, in that order.
- Output is a `map.md` derived from `.atlas/templates/traversal-map.md`.
- See `.atlas/skills/traverse/SKILL.md` for the full contract.
```

Repeat for Locate, Abstract, Synthesize with different `applyTo:` globs
if your project has a natural split (e.g. `applyTo: "test/**"` for a
Locate variant focused on test files).

**2c.4 Verification.** In Copilot Chat:

1. Ask: *"What rules are you operating under?"* Expected: Copilot cites
   `copilot-instructions.md` and/or `AGENTS.md` and lists the ATLAS P0
   rules.
2. Ask: *"Refactor `src/foo.ts` to use async/await."* Expected: Copilot
   refuses the refactor verb and offers a `→ APIVR-Δ` handoff instead.
3. Check Copilot Code Review on a PR — it should reference the ATLAS
   rules when suggesting changes.

---

### 2d. OpenCode

OpenCode loads `AGENTS.md` at repo root for rules and
`.opencode/agents/<name>.md` for custom agents (primary and subagent
modes).

**2d.1 Rules.** Same `AGENTS.md` symlink as 2b.1 / 2c.2:

```bash
ln -sf .atlas/AGENTS.md AGENTS.md    # idempotent
```

**2d.2 Primary agent.** Create `.opencode/agents/atlas.md`:

```bash
mkdir -p .opencode/agents
```

```markdown
---
description: Read-only codebase scout running the ATLAS v1.0 five-phase pipeline (Assess → Traverse → Locate → Abstract → Synthesize). Use for exploration, impact analysis, and pre-planning questions. Refuses write verbs.
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

You are the ATLAS explorer/scout agent. Full rules: `.atlas/AGENTS.md`.
Always-loaded profile: `.atlas/agent.md`. Phase skills live in
`.atlas/skills/<phase>/SKILL.md`.

When switching phases, load only the matching SKILL.md for that phase.
See `.atlas/ATLAS.md` §2 for the full phase spec.
```

**2d.3 Phase subagents.** Create one `.opencode/agents/atlas-<phase>.md`
per phase with `mode: subagent`. Example for Traverse:

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

Load the Traverse contract from `.atlas/skills/traverse/SKILL.md` and
execute Phase T for the parent mission. Emit `map.md` using
`.atlas/templates/traversal-map.md`. Return ONE structured summary to the
parent — never the raw transcript.
```

Repeat for `atlas-locate.md`, `atlas-abstract.md`, `atlas-synthesize.md`.

**2d.4 Verification.** In `opencode`:

1. Press **Tab** to switch to the `atlas` primary agent.
2. Type `@atlas-traverse` — expected: the subagent autocompletes.
3. Ask: *"Under ATLAS, find all writers to the sessions table."*
4. Expected: opencode refuses to proceed until a `mission.md` exists,
   then runs Assess → Traverse → Locate in sequence, spawning subagents
   where appropriate.

---

## Step 3 — Verify the install end-to-end

Run this smoke test on any of the four hosts after Step 2.

**Input mission** (paste into chat):

> Under ATLAS, answer the following DECISION_TARGET: *"List every public
> HTTP endpoint in this repository and identify the single FlowObject or
> controller action that handles each."* Use scope `**/*` and a budget of
> 30 tool calls. Emit a `mission.md` first, then run Traverse, then Locate,
> then Synthesize.

**Expected observations:**

- The agent **does not** begin with a generic `rg` or file walk. It emits
  `mission.md` first.
- Phase T produces a `map.md` (or inlined equivalent) with `MAP-ROOTS`
  enumerating routes as `path:line` entries.
- Phase L returns `FINDING-001`, `FINDING-002`, … with `H|M|L` tiers and
  `path:line_start-line_end` anchors.
- Phase S emits a `scout-report.md` ≤3000 tokens with a handoff block
  (`→ SPECTRA`, `→ APIVR-Δ`, `→ human`, or `→ ATLAS`).
- Asking the agent to *fix* or *refactor* any file produces a refusal and
  a labeled handoff suggestion.

**Regression gate.** For CI, run any mission from `.atlas/evals/canary-missions.md`
(15 available) and compare against the `expected/answer.md` ground truth.
Target ≥80% pass rate across the full suite per §5 of `ATLAS.md`.

---

## Appendix A — Installing the `atlas-aci` MCP server

`atlas-aci` is the reference MCP implementation. It enforces all bounds
mechanically, ships a Tree-sitter + SQLite code graph, and provides the
seven read-only primitives (`view_file`, `list_dir`, `search_text`,
`search_symbol`, `graph_query`, `test_dry_run`, `memex_read`).

### Install

```bash
pipx install atlas-aci
# or
git clone https://github.com/Rynaro/atlas-aci.git
cd atlas-aci && pip install -e .
```

Verify the binary: `atlas-aci --version`.

### Index the target repo

```bash
cd <your-repo>
atlas-aci index --repo . --memex-root .atlas/.memex
```

This builds the tree-sitter + SQLite code graph in `.atlas-aci/` and the
content-addressable Memex in `.atlas/.memex/`. Re-run after major refactors.
Incremental indexing is the default; add `--force` for a full rebuild.

### Wire into each host

#### Claude Code

```bash
claude mcp add atlas-aci -- atlas-aci serve --repo .
```

Then edit `.claude/agents/atlas.md` to grant the MCP tools:

```yaml
tools: mcp__atlas_aci__view_file, mcp__atlas_aci__search_symbol, mcp__atlas_aci__search_text, mcp__atlas_aci__list_dir, mcp__atlas_aci__graph_query, mcp__atlas_aci__test_dry_run, mcp__atlas_aci__memex_read
```

#### Cursor

Create or edit `.cursor/mcp.json` at repo root:

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

#### GitHub Copilot (VS Code)

Add to VS Code `settings.json` (workspace scope):

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

#### OpenCode

Add to `.opencode/opencode.json`:

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

### Verify MCP

From any host, call `search_symbol("<a class name in your codebase>")` and
confirm it returns both the definition and references with `path:line`
anchors. If it returns nothing, re-run `atlas-aci index`.

See `tools/mcp-server-reference.md` for the normative tool manifest and
enforcement pseudocode, and the canonical `Rynaro/atlas-aci` repo for the
full server README.

---

## Appendix B — Token budget tuning

`agent.md` targets ≤1000 tokens so it fits the always-loaded context slot
without squeezing the working window. If you mount multiple methodologies
(e.g. ATLAS + your company style guide), you may need to trim further.

**Safe trims:**

- Remove the "Progressive disclosure — skill load order" section and link
  to the one in `AGENTS.md` instead.
- Remove the Telemetry block and inline the two thresholds (60% / 85%) into
  the P0 rules list.
- Drop the "Identity" section — it is stylistic, not load-bearing.

**Unsafe trims (do not remove):**

- The P0 rules (numbered 1–9). These are the kernel of the methodology.
- The handoff label list — downstream parsers key off the exact labels.

**Telemetry thresholds per host:**

| Host | How to read `context_used_pct` | Notes |
|---|---|---|
| Claude Code | `claude-code status` or `/compact` | 60/85% thresholds map to auto-compact |
| Cursor | Status bar shows tokens used | Fold manually when badge hits ~60% |
| Copilot | Not directly exposed | Fold at every phase boundary regardless |
| OpenCode | `/compact` command | 60/85% thresholds match the command's defaults |

---

## Appendix C — Upgrading ATLAS

ATLAS is versioned at the spec level (`methodology_version: "1.0"` in
frontmatter). Breaking changes require a minor-version bump.

```bash
# subtree-based install
git subtree pull --prefix=.atlas https://github.com/Rynaro/atlas.git main --squash

# submodule-based install
git submodule update --remote .atlas
```

After upgrade:

1. Re-read `CHANGELOG.md` in `.atlas/` for breaking changes.
2. If `schemas/*.v1.json` changed, re-validate any persisted mission/findings
   artifacts you have in the repo.
3. If host frontmatter formats diverged (e.g. Claude Code renamed a field),
   edit the per-host wrappers in `.claude/`, `.cursor/`, `.github/`,
   `.opencode/` — the canonical files under `.atlas/` do not need changes.

---

## Troubleshooting

**"My Claude Code / Cursor skill isn't triggering when I ask an exploratory
question."**
The skill's `description` field drives intelligent activation. Open the
canonical `.atlas/skills/<phase>/SKILL.md` and confirm the first 200 chars
of `description` include the phase name and at least two trigger phrases
("trace", "find where", "map the"). If you edited the description, Claude
Code truncates at 1,536 chars — front-load the key use case.

**"Cursor attaches the wrong phase skill."**
Check `globs:` in your `.cursor/rules/atlas-<phase>.mdc` wrappers. Default
`globs: ["**/*"]` lets Cursor decide via description; narrowing the glob to
`test/**` or `src/**` can disambiguate. Or set `alwaysApply: false` and
rely on explicit `@atlas-<phase>` mentions.

**"Copilot ignores `AGENTS.md`."**
Not all Copilot hosts have shipped the AGENTS.md feature yet. The
`.github/copilot-instructions.md` fallback is always loaded; confirm it
exists and contains the ATLAS rules summary.

**"OpenCode agent has write access I didn't grant."**
Verify the `permission:` block in `.opencode/agents/atlas.md`. The shape
is:

```yaml
permission:
  edit: deny
  write: deny
  bash:
    "<pattern>": allow | ask | deny
    "*": deny
```

The final `"*": deny` under `bash` is critical — without it, unmatched
commands default to allow.

**"`mission.md` keeps failing schema validation."**
Confirm you copied the whole `.atlas/templates/mission-brief.md` and did
not paraphrase field names. The JSON Schema in `.atlas/schemas/mission-brief.v1.json`
is strict about `MISSION-ID` pattern (`^[0-9]{8}-[0-9]{3}$`) and the
`DT-N` sub-question naming.

**"`search_symbol` returns nothing under `atlas-aci`."**
The index hasn't been built or is stale. Run
`atlas-aci index --repo . --force` and re-try. For monorepos, index each
package root separately or pass `--scope '<glob>'`.

**"Agent keeps paraphrasing the artifact templates instead of filling them."**
The P0 rules and the handoff labels are mechanical. Add a short sentence to
your `CLAUDE.md` / `.cursor/rules/atlas-00-always.mdc` / `AGENTS.md`:
*"Templates in `.atlas/templates/` are fill-in-the-blank. Preserve every
field name verbatim; downstream schemas parse them."*

---

## See also

- `ATLAS.md` — authoritative v1.0 specification
- `AGENTS.md` — open-standard rule set (Copilot / Cursor / OpenCode)
- `agent.md` — always-loaded agent profile
- `skills/<phase>/SKILL.md` — progressive-disclosure phase skills
- `tools/bounded-aci-spec.md` — ACI primitive specification
- `tools/mcp-server-reference.md` — normative MCP tool manifest
- `evals/canary-missions.md` — 15-mission verification dataset
- [Rynaro/atlas-aci](https://github.com/Rynaro/atlas-aci) — reference MCP server
