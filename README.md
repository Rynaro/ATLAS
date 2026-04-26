# ATLAS

**A**ssess · **T**raverse · **L**ocate · **A**bstract · **S**ynthesize

[![Version](https://img.shields.io/badge/spec-v1.0-blue)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE)
[![Reference implementation](https://img.shields.io/badge/impl-atlas--aci-orange)](https://github.com/Rynaro/atlas-aci)

A tooling-independent methodology and reference agent for **read-only
codebase exploration and planning** — the "Scout" or "Plan Mode" that must
happen before any implementation agent touches source.

ATLAS is a sibling to two other open-source methodologies:

- **SPECTRA** — spec & planning
- **APIVR-Δ** — implementation loop

ATLAS is upstream of both. Its output is a structured **scout report** that
SPECTRA or APIVR-Δ consume directly.

---

## Why this exists

Frontier agentic systems (Claude Code Plan Mode, Cursor, Copilot, SWE-agent)
all converge on the same pattern: a read-dominant exploration loop that
maps an unfamiliar codebase before any mutation. They also all couple that
loop to proprietary harnesses, telemetry, and context-management tricks.

ATLAS is the distilled methodology, expressed as:

- a phase contract that survives model swaps
- a set of fill-in-the-blank templates that enforce artifact consistency
- a bounded Agent-Computer Interface specification
- progressive-disclosure skills (≤200 lines each)
- a canary evaluation dataset

Implementations can live on top of GitHub Copilot custom agents, Claude
Code subagents, Cursor agents, LangGraph, or a local agent harness over
open-weight models. MCP is the recommended transport but not required.

---

## Architectural invariants (the non-negotiable bits)

- **Read-only tool surface.** No `edit`, `write`, `commit`, or `deploy`.
- **Bounded ACI.** Every read is windowed (≤100 lines); every search is
  capped (≤50 matches); every directory listing is paginated (≤200 entries).
- **90/10 deterministic/probabilistic.** Symbol indexes, AST queries, and
  `rg` run before any LLM-authored search.
- **Operator pattern.** Subagents run in ephemeral contexts and return one
  structured `FINDING` each. Their transcripts never merge upward.
- **AgentFold at phase boundaries.** Raw excerpts go to Memex; working
  memory keeps only IDs + anchors + confidences.
- **Evidence-anchored claims.** Every factual statement carries
  `path:line_start-line_end` + confidence tier (`H | M | L`).
- **Explicit stop conditions.** Missions declare a `DECISION_TARGET`; ATLAS
  halts when it is answered, not when the model feels done.

See `ATLAS.md` for the full specification.

---

## Repository layout

```
atlas/
├── README.md                   # this file
├── INSTALL.md                  # cross-platform installation guide
├── AGENTS.md                   # open-standard rule set (Copilot/Cursor/OpenCode)
├── ATLAS.md                    # methodology specification (authoritative)
├── agent.md                    # always-loaded agent profile (≤1000 tokens)
│
├── .github/
│   └── copilot-instructions.md # GitHub Copilot primary entry point
│
├── skills/                     # progressive-disclosure skills (YAML frontmatter)
│   ├── traverse/SKILL.md       # Phase T — structural mapping
│   ├── locate/SKILL.md         # Phase L — bounded probes, scatter
│   ├── abstract/SKILL.md       # Phase A — AgentFold + Memex
│   └── synthesize/SKILL.md     # Phase S — scout report
│
├── templates/                  # fill-in-the-blank artifact templates
│   ├── mission-brief.md
│   ├── traversal-map.md
│   ├── findings.md
│   └── scout-report.md
│
├── tools/
│   ├── bounded-aci-spec.md     # ACI primitive specification
│   └── mcp-server-reference.md # normative MCP tool manifest + enforcement spec
│
├── commands/                   # eidolons-nexus subcommands shipped by ATLAS
│   └── aci.sh                  # `eidolons atlas aci` — wire atlas-aci MCP into a project
│
├── schemas/                    # JSON Schema v2020-12 validators
│   ├── mission-brief.v1.json
│   ├── findings.v1.json
│   └── scout-report.v1.json
│
├── tests/                      # bats suite for commands/aci.sh
│   ├── helpers.bash
│   └── *.bats                  # T6–T29 from the atlas-aci-integration spec
│
└── evals/
    └── canary-missions.md      # 15-mission evaluation set
```

---

## Reference implementation

**[Rynaro/atlas-aci](https://github.com/Rynaro/atlas-aci)** is the canonical
MCP server conforming to this spec. It ships:

- All seven read-only tools (`view_file`, `list_dir`, `search_text`,
  `search_symbol`, `graph_query`, `test_dry_run`, `memex_read`)
- Mechanical enforcement layer (bounds, read-only guard, path-traversal guard,
  rate limiting at 200 calls/min, full telemetry)
- tree-sitter + SQLite code graph indexer
- Hashed-directory Memex (upgradeable to sqlite-vec)
- Host integration guides for Claude Code, GitHub Copilot, and Cursor

See [atlas-aci/SETUP.md](https://github.com/Rynaro/atlas-aci/blob/main/SETUP.md)
for the end-to-end installation playbook.

---

## Install

Full cross-platform installation guide: **[INSTALL.md](INSTALL.md)**. It
covers Claude Code, Cursor, GitHub Copilot, and OpenCode, plus the
optional `atlas-aci` MCP server for mechanical enforcement.

Three-line quickstart (from inside the repo you want ATLAS to explore):

```bash
# 1. Vendor ATLAS into the target repo
git subtree add --prefix=.atlas https://github.com/Rynaro/atlas.git main --squash

# 2. Wire the always-on profile (Cursor / Copilot / OpenCode)
ln -sf .atlas/AGENTS.md AGENTS.md

# 3. Claude Code only — wire skills and subagent
mkdir -p .claude/skills .claude/agents && \
  for p in traverse locate abstract synthesize; do \
    ln -sf ../../.atlas/skills/$p .claude/skills/atlas-$p; done && \
  cp .atlas/agent.md .claude/agents/atlas.md
```

Then run any canary mission from `evals/canary-missions.md` to verify your
install reaches the ≥80% pass target.

## Conceptual flow (for implementers)

1. **Mount ATLAS as an agent** in your harness. `agent.md` is ≤1000 tokens
   and belongs in the always-loaded slot.
2. **Wire the ACI.** Either install [atlas-aci](https://github.com/Rynaro/atlas-aci)
   as an MCP server, or adapt `tools/bounded-aci-spec.md` to your host's
   native read tools.
3. **Index the repo** with `atlas-aci index --repo <path>` (once; re-run
   after major refactors).
4. **Provide a Memex root** via `--memex-root`. A hashed-file directory is
   the zero-dependency default.
5. **Run the canaries** in `evals/canary-missions.md` to verify ≥80% pass
   before going live.

---

## Relationship to other methodologies

```
       ┌──────────┐       scout-report        ┌──────────┐
user → │  ATLAS   │ ────────────────────────▶ │ SPECTRA  │
       │ (scout)  │                           │ (plan)   │
       └──────────┘                           └──────────┘
                                                    │
                                                    │ spec.md
                                                    ▼
                                              ┌──────────┐
                                              │ APIVR-Δ  │
                                              │ (build)  │
                                              └──────────┘
```

ATLAS does not invoke SPECTRA or APIVR-Δ directly. Handoffs are explicit
and labeled in the scout report. Each methodology is independently useful.

---

## Status

**v1.0** — initial specification. Breaking changes to phase contracts or
artifact schemas require a minor-version bump.

Implementations declare ATLAS version compatibility in their agent
frontmatter (`methodology: ATLAS`, `methodology_version: 1.0`).

See [CHANGELOG.md](CHANGELOG.md) for release history.

---

## License

Apache-2.0. See [LICENSE](LICENSE).
