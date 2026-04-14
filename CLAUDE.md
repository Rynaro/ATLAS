# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

ATLAS (**A**ssess · **T**raverse · **L**ocate · **A**bstract · **S**ynthesize) is a **documentation-only specification** for a read-only codebase exploration methodology. There is no source code, build system, or runtime — all deliverables are Markdown documents and JSON schemas.

ATLAS is the first agent in a three-part pipeline: **ATLAS (scout) → SPECTRA (plan) → APIVR-Δ (implement)**.

## Repository Structure

```
atlas/
├── ATLAS.md                          # Authoritative full specification
├── agent.md                          # Always-loaded agent profile (≤1000 tokens)
├── skills/                           # Progressive-disclosure phase skills
│   ├── traverse/SKILL.md             # Phase T — deterministic structural mapping
│   ├── locate/SKILL.md               # Phase L — bounded probes + operator pattern
│   ├── abstract/SKILL.md             # Phase A — AgentFold + Memex
│   └── synthesize/SKILL.md           # Phase S — scout report emission
├── templates/                        # Fill-in-the-blank output artifacts
├── tools/                            # Implementation guides (ACI spec, MCP reference)
├── schemas/                          # JSON Schema validators for artifacts
└── evals/canary-missions.md          # 15-mission evaluation dataset (target ≥80% pass)
```

## The Five-Phase Pipeline

Each phase produces a schema-validated artifact:

| Phase | Output | Hard Constraint |
|-------|--------|----------------|
| **A — Assess** | `mission.md` | Refuses missions without `DECISION_TARGET`; refuses write-scoped verbs |
| **T — Traverse** | `map.md` | Zero LLM calls; pure deterministic tooling (Tree-sitter, ripgrep, git log) |
| **L — Locate** | `findings.md` | Probe hierarchy: symbol → graph → lexical → windowed read → test dry-run |
| **A — Abstract** | Working memory + Memex | Fold at every phase boundary; raw excerpts to Memex, IDs/anchors to working memory |
| **S — Synthesize** | `scout-report.md` | Hard cap 3000 tokens; every claim cited with `FINDING-XXX` |

## Architectural Invariants

These are non-negotiable and must be preserved in any edits to the spec:

1. **Read-only tool surface** — only `view_file`, `search_symbol`, `search_text`, `list_dir`, `graph_query`, `test_dry_run`, `memex.read`
2. **Bounded ACI** — `view_file` ≤100 lines; `search_text` ≤50 matches; `list_dir` ≤200 entries; overflow → pagination cursor
3. **90/10 deterministic/probabilistic** — symbol/AST/ripgrep before any LLM-authored search
4. **Operator pattern** — subagents return one structured `FINDING` each; raw transcripts never merge upward
5. **AgentFold at phase boundaries** — trajectory folded at every transition
6. **Telemetry-driven compaction** — at ≥60% context trigger async fold; at ≥85% halt and checkpoint
7. **Evidence-anchored claims** — every claim carries `path:line_start-line_end` + confidence tier (`H|M|L`); unanchored claims fail validation
8. **Explicit stop conditions** — ATLAS halts when `DECISION_TARGET` is answered, not when the model feels done

## Key Design Patterns

- **Progressive Disclosure**: Skills loaded/unloaded per phase to avoid tool-definition bloat
- **Operator Pattern**: Independent sub-questions scatter to ephemeral subagents; parent sees only structured `FINDING` records, never transcripts
- **AgentFold**: Raw excerpts → Memex (SHA-256 keyed); working memory keeps only IDs/anchors (≤2000 tokens)
- **Confidence Tiers**: `H` (directly observed) | `M` (short inference) | `L` (plausible but unanchored)
- **Three-Strike Guard in Locate**: Three consecutive low-confidence probes → halt, record in `GAPS`

## Schema Validation

Three JSON schemas in `schemas/` enforce artifact structure:
- `mission-brief.v1.json` — validates `mission.md`
- `findings.v1.json` — validates `findings.md` (FINDING records + gaps + escalation_log)
- `scout-report.v1.json` — validates the final `scout-report.md`

Any changes to artifact templates must keep the templates compliant with their schemas.

## Evaluation

The `evals/canary-missions.md` contains 15 hand-curated missions with ground-truth answers. Pass criteria per mission:
1. `DECISION_TARGET` answer matches expected claims
2. All required FINDING IDs produced
3. Handoff recipient matches expected label (`→ SPECTRA`, `→ APIVR-Δ`, `→ human`, `→ ATLAS`)

Target pass rate: ≥80%.

## Key Metrics

- **η (search efficiency)**: relevant-tokens ÷ total-tokens (target ≥0.25)
- **fold_ratio**: fold-tokens ÷ locate-tokens (target ≤0.1)

## Versioning Policy

`ATLAS.md` is the authoritative spec. Breaking changes to phase contracts or JSON schemas require a minor-version bump. Implementations declare `methodology: ATLAS` and `methodology_version: 1.0` in their `agent.md` frontmatter.
