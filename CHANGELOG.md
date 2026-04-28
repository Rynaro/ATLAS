# Changelog

All notable changes to the ATLAS specification are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) — but for a spec, "breaking" means any change to phase contracts or JSON schemas that requires existing implementations to be updated.

---

## [1.1.1] - 2026-04-28 — atlas-aci container index fix

### Fixed
- **`commands/aci.sh` atlas-aci pin** — bumped `ATLAS_ACI_PIN` and
  `ATLAS_ACI_REF` to `8ce17f0e69f135f9324dad718415043276029eb4`, the
  merge of [atlas-aci#1][aci-1]. Earlier pin (`ccc40bb…`) inherited a
  Dockerfile that re-resolved transitive deps from PyPI at install time,
  ignoring `mcp-server/uv.lock`. Upstream `tree-sitter-language-pack`
  shipped 1.6.3 with a restructured wheel (only a `_native/` subpackage,
  no top-level `tree_sitter_language_pack` module), so every fresh
  `eidolons atlas aci --container` build silently produced an image that
  failed at `atlas-aci index` runtime with `ModuleNotFoundError`. The
  new pin includes both a tightened `pyproject.toml` constraint
  (`<1.6.3`) and a lock-respecting Dockerfile build.

### Changed
- **`EIDOLON_VERSION`** bumped `1.1.0` → `1.1.1`. Patch release: no
  methodology change, no host-wiring change, no schema change.
- **`ATLAS_VERSION`** bumped `1.1.0` → `1.1.1` (kept in sync — used as
  the local image tag `atlas-aci:<ATLAS_VERSION>`, so the bump also
  cache-busts any stale local image from the broken 1.1.0 build).

[aci-1]: https://github.com/Rynaro/atlas-aci/pull/1

## [1.0.6] - 2026-04-27 — Codex MCP host support in `commands/aci.sh`

### Added
- **`commands/aci.sh` codex branch** — `wire_codex` and `unwire_codex` register the atlas-aci stdio MCP server in `./.codex/config.toml` under the `[mcp_servers.atlas-aci]` table. Idempotent line-bounded TOML rewrite via POSIX `awk` (no `tomlq`/Python dep), atomic tmpfile + `mv`. Mirrors the existing `wire_claude_code` (`.mcp.json`) / `wire_cursor` / `wire_copilot` pattern.
- **`--host codex` allow-list entry** — `apply_host_install`, `apply_host_remove`, `detect_hosts_mcp`, the `--dry-run` preview, and the `main_remove` sweep all recognise the codex token. `detect_hosts_mcp` emits `codex` when `.codex/` exists, when `AGENTS.md` exists, or when both `AGENTS.md` and `.github/` are present (matches install.sh's host detection truth table).
- **Early `awk` prereq guard** — exits 5 with an actionable hint before any `awk` invocation in the script body.
- **`tests/codex.bats`** — 13 cases covering install/remove/idempotency closure (sha256), peer-table preservation, CRLF input handling, missing-trailing-newline, `[[mcp_servers]]` array-of-tables peers, last-table-in-file, awk-missing exit 5, R2 deviant-body refused-with-warning guard, and dry-run `CREATE`/`MODIFY` preview.

## [1.0.5] - 2026-04-26 — Re-vendor EIIS v1.1 schema (codex enum)

### Fixed
- `schemas/install.manifest.v1.json` re-vendored from EIIS v1.1 — the previously bundled copy lacked `codex` in the `hosts_wired` enum, causing the EIIS conformance checker's M14 (JSON Schema validation) to fail when a validator (`ajv` / `python -m jsonschema`) was on PATH. Pure schema fix; no install.sh behaviour change.

## [1.0.4] — 2026-04-25 — EIIS-1.1 conformance + OpenAI Codex host support

### Added

- **`EIIS_VERSION`** — root-level file declaring `1.1`, the targeted EIIS
  minor (resolves drift D-6).
- **`install.sh` codex host wiring** — recognises `codex` in `--hosts` parsing
  and the `all` expansion (`claude-code,copilot,cursor,opencode,codex`).
  Auto-detection adds `codex` when `.codex/` exists or when `AGENTS.md`
  exists at the cwd root with no `.github/` and no `.codex/` directory
  (per EIIS v1.1 §4.1.0).
- **`.codex/agents/atlas.md`** — per-Eidolon Codex subagent file emitted
  on install. YAML frontmatter contains `name: atlas` and a non-empty
  `description`; body mirrors the ATLAS Claude subagent prompt
  (read-only P0 rules, methodology pointer to
  `./.eidolons/atlas/agent.md`). Source:
  <https://developers.openai.com/codex/subagents>.
- **Marker-bounded block in root `AGENTS.md`** — written when `codex` is
  in the wired host list (Codex's primary instruction surface per EIIS
  v1.1 §4.1.0). Idempotent via the existing `upsert_eidolon_block`
  helper. When the user passes `--no-shared-dispatch` together with
  `codex`, the AGENTS.md write is preserved with a stderr warning;
  CLAUDE.md and `.github/copilot-instructions.md` still honour the
  flag faithfully.
- **`examples/install.manifest.json`** — sample manifest fixture
  reflecting a Codex-only install (`hosts_wired: ["codex"]`,
  `files_written` lists both `AGENTS.md` and `.codex/agents/atlas.md`).
  Lets the EIIS conformance checker validate the manifest schema
  without running the installer.

### Changed

- **`install.sh` header banner** — now reads "EIIS v1.1 conformant".
- **`EIDOLON_VERSION`** bumped from `1.0.0` to `1.0.4` to match the
  patch release. Additive host support follows the patch convention
  (no breaking change to the methodology or to existing host wiring).
- **`install.manifest.json` emission** — `hosts_wired` now records
  `"codex"` when the installer is invoked with a host list containing
  it; `files_written` lists `AGENTS.md` and `.codex/agents/atlas.md`
  with `role: dispatch`.

### Verified

- `shellcheck -x -S error install.sh` — clean.
- Smoke: `bash install.sh --hosts codex --non-interactive --force` against
  an empty tmp dir produces both `AGENTS.md` (marker-bounded) and
  `.codex/agents/atlas.md` (valid YAML frontmatter); a second invocation
  produces byte-identical files (except the manifest's `installed_at`).
- EIIS conformance checker exits 0 against the patched repo.

---

## [Unreleased] — EIIS-1.0 conformance

### Added

- **commands/aci.sh** — opt-in `eidolons atlas aci` subcommand that wires the
  [atlas-aci](https://github.com/Rynaro/atlas-aci) MCP server into a consumer
  project (claude-code, cursor, copilot). Idempotent install/remove, atomic
  writes, peer-preserving JSON / YAML-frontmatter merges, and bounded prereq
  checks (`uv`, `rg`, `python3 >= 3.11`, `atlas-aci`, `jq`, `mikefarah/yq`).
  Pinned to atlas-aci main @ `ccc40bbd464ecea2eb069c7cdbb0bb1b383e413c`
  (2026-04-15). Scope: project-local files only — never writes outside `$PWD`.
  Spec: [Rynaro/eidolons docs/specs/atlas-aci-integration.md](https://github.com/Rynaro/eidolons/pull/20).
- **tests/** — bats suite covering T6–T29 from the atlas-aci-integration spec
  (idempotency, peer preservation, host filters, copilot frontmatter handling,
  gitignore semantics, prereq exits, index ordering, dry-run no-write, and the
  "no writes outside cwd" boundary). 33 tests organised by concern:
  `idempotency.bats`, `peer_preservation.bats`, `host_filter.bats`,
  `copilot.bats`, `gitignore.bats`, `prereqs.bats`, `index.bats`,
  `operational.bats`. Stubs `uv`, `rg`, `python3`, and `atlas-aci` so CI does
  not need to install the real prereqs; `jq` and `mikefarah/yq` are real deps.
- **install.sh** — idempotent installer conforming to EIIS v1.0 §2 interface
  contract: all required flags (`--target`, `--hosts`, `--force`, `--dry-run`,
  `--non-interactive`, `--manifest-only`, `--version`), auto host detection,
  consumer dispatch file creation, manifest emission, token measurement, and
  smoke-test banner.

### Changed

- **install.sh** — now also ships `commands/aci.sh` to
  `<TARGET>/commands/aci.sh` (preserving the executable bit) so the
  Eidolons-nexus dispatcher (`cli/src/dispatch_eidolon.sh`) can surface
  `eidolons atlas aci` once ATLAS is installed in a project.
- **schemas/install.manifest.v1.json** — JSON Schema draft 2020-12 for the
  `install.manifest.json` artifact emitted by `install.sh`.
- **hosts/claude-code.md** — per-host wiring quick-reference for Claude Code.
- **hosts/copilot.md** — per-host wiring quick-reference for GitHub Copilot.
- **hosts/cursor.md** — per-host wiring quick-reference for Cursor.
- **hosts/opencode.md** — per-host wiring quick-reference for OpenCode.
- **DESIGN-RATIONALE.md** — research-to-decision mapping for all eight
  architectural invariants (I-1 through I-8) plus the progressive-disclosure
  and three-strike-halt design choices.

### Changed

- **AGENTS.md** — prepended EIIS §5 YAML frontmatter block (`name`, `version`,
  `methodology`, `methodology_version`, `role`, `handoffs`). No body changes.
- **CLAUDE.md** — appended `## Consumer project usage` section with EIIS
  load-order pointer and quick-install command. No changes to existing content.

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
