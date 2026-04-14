# Changelog

All notable changes to the ATLAS specification are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) — but for a spec, "breaking" means any change to phase contracts or JSON schemas that requires existing implementations to be updated.

---

## [1.0.0] — 2026-04-14

Initial public release of the ATLAS specification.

### Added

- **ATLAS.md** — authoritative v1.0 methodology specification covering all five
  phases (Assess, Traverse, Locate, Abstract, Synthesize) and eight architectural
  invariants.
- **agent.md** — always-loaded agent profile (≤1000 tokens) with nine P0 rules,
  load order, artifact template references, and handoff format.
- **skills/** — four progressive-disclosure phase skills:
  - `traverse/SKILL.md` — deterministic structural mapping (four retrieval tiers)
  - `locate/SKILL.md` — bounded probes, operator pattern, three-strike halt
  - `abstract/SKILL.md` — AgentFold contract, Memex hygiene, clean-context rule
  - `synthesize/SKILL.md` — scout report structure, handoff emission
- **templates/** — four fill-in-the-blank artifact templates:
  `mission-brief.md`, `traversal-map.md`, `findings.md`, `scout-report.md`
- **schemas/** — three JSON Schema v2020-12 validators:
  `mission-brief.v1.json`, `findings.v1.json`, `scout-report.v1.json`
- **tools/bounded-aci-spec.md** — normative specification for the seven read-only
  ACI primitives and their mechanical bounds.
- **tools/mcp-server-reference.md** — reference MCP server design showing how to
  expose the ACI over JSON-RPC 2.0; normative spec for the tool manifest.
- **evals/canary-missions.md** — 15-mission evaluation dataset (easy / medium /
  hard) with ground-truth answers and CI gate criteria (≥80% pass rate).
- **Reference implementation:** [`Rynaro/atlas-aci`](https://github.com/Rynaro/atlas-aci)
  — a conformant Python MCP server with tree-sitter indexing, ripgrep search,
  SQLite code graph, and hashed-directory Memex.
