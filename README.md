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
├── ATLAS.md                    # methodology specification (authoritative)
├── agent.md                    # always-loaded agent profile (≤1000 tokens)
│
├── skills/                     # progressive-disclosure skills
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
├── schemas/                    # JSON Schema v2020-12 validators
│   ├── mission-brief.v1.json
│   ├── findings.v1.json
│   └── scout-report.v1.json
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

## Quick start (conceptual)

1. **Mount ATLAS as an agent** in your harness of choice. The agent profile
   (`agent.md`) is ≤1000 tokens and should be in the always-loaded slot.
2. **Wire the ACI.** Install [atlas-aci](https://github.com/Rynaro/atlas-aci)
   as your MCP server, or adapt `tools/bounded-aci-spec.md` to your harness's
   native tool surface.
3. **Index the repo.** Run `atlas-aci index --repo <path>` once (or after major
   refactors) to build the tree-sitter + SQLite code graph.
4. **Provide a Memex root.** Pass `--memex-root` to the server. A
   hashed-file directory is the zero-dependency default.
5. **Run the canaries** in `evals/canary-missions.md` to verify your
   implementation reaches ≥80% pass rate before going live.

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
