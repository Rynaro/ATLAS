# Changelog

All notable changes to the ATLAS specification are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) — but for a spec, "breaking" means any change to phase contracts or JSON schemas that requires existing implementations to be updated.

---

## [Unreleased]

### Fixed

- **`commands/aci.sh` container index: pre-create `.atlas/memex/` + add `-u UID:GID`
  (P-A fix, spec atlas-aci-mcp-install-fix-2026-05-04 T4 / S2):**
  On a fresh project where `.atlas/memex/` does not pre-exist, rootful Docker
  (Fedora) creates the bind-mount directory as root-owned inside the container,
  preventing the in-container user from writing `codegraph.db`. The fix
  pre-creates `.atlas/memex/` on the host before the `docker run` and adds
  `-u "$(id -u):$(id -g)"` to the index `docker run` so the container writes
  with the host user's ownership. Also adds a writable `-v .atlas/memex:/memex`
  bind for consistency with the `serve` configuration.

- **`commands/aci.sh` image reuse: skip `docker build` when pinned image already
  loaded (P-B fix, spec S1):**
  Before invoking `docker build`, `ensure_image` now resolves the pinned image
  ref (from `.mcp.json`, optional `eidolons mcp atlas-aci --print-pinned-ref`,
  or the `ATLAS_ACI_IMAGE_DIGEST` constant) and runs `docker image inspect
  <ref>`. If the image is already in the local store (e.g. from a prior
  `eidolons mcp atlas-aci pull`), the build is skipped entirely, eliminating the
  redundant multi-minute rebuild that produced the same digest.

### Added

- **`commands/aci.sh` header invariant comment:** Documents the fail-closed write
  boundary ("No MCP config files were modified.") as a pinned invariant.
- **`_resolve_pinned_image_ref` function in `commands/aci.sh`:** Resolves the
  image ref to check from `.mcp.json`, optional nexus CLI, or constant fallback
  (Bash 3.2 safe).
- **Three new bats cases in `tests/aci.bats`:**
  - T4-1: fresh project — `.atlas/memex/` created before docker run; docker run
    contains `-u` and a writable `/memex` bind.
  - T4-2: image already loaded (inspect-only sentinel) — `docker build` not
    invoked; "image already loaded" in stderr.
  - T4-3: index failure — no MCP config files written; verbatim error strings;
    non-zero exit.

### Added (earlier, preserved from prior Unreleased section)

- **`.github/workflows/release.yml`** — adopts the eidolons-nexus
  release-integrity contract by wrapping the reusable
  `Rynaro/eidolons/.github/workflows/eidolon-release-template.yml`
  workflow. Dispatched manually with a SemVer; the template runs
  `bats tests/`, validates EIIS-1.1 conformance, tags the commit, attests
  the release artifacts, and publishes a `release-manifest.json` (with
  `commit`, `tree`, `archive_sha256`, optional `manifest_sha256`, and
  `provenance.github_attestation: true`) so the nexus `roster-intake.yml`
  workflow can populate `versions.releases.<v>` for ATLAS.

---

## [1.3.0] - 2026-05-01 — GHCR-prefixed canonical body + container security hardening

### Changed

- **`commands/aci.sh` canonical body — registry-prefixed image reference (spec T4):**
  Container-mode canonical bodies for all four MCP host targets (`.mcp.json`,
  `.cursor/mcp.json`, `.codex/config.toml`, `.github/agents/*.agent.md`) now
  reference `ghcr.io/rynaro/atlas-aci@sha256:<digest>` instead of the bare
  `atlas-aci@sha256:<digest>` form. The bare form resolved to
  `docker.io/library/atlas-aci`, which 404s — this was a known bug fixed here.
- **`ATLAS_ACI_IMAGE_REF` + `ATLAS_ACI_IMAGE_DIGEST` constants:** Replace the
  parent spec's local-image-id capture step (D3 — `docker images --no-trunc`).
  The digest is the registry pin constant `ATLAS_ACI_IMAGE_DIGEST` (pinned to
  `sha256:386677f06b0ce23cb4883f6c0f91d8eac22328cd7d9451ae241e2f183207ad96`,
  the first signed GHCR publish, multi-arch, cosign + SBOM + provenance,
  Trivy gate green). The full pull reference is composed as
  `${ATLAS_ACI_IMAGE_REF}@${ATLAS_ACI_IMAGE_DIGEST}`.
- **Security hardening (spec H3):** All four MCP emit paths now include
  `--cap-drop ALL` and `--security-opt no-new-privileges` immediately before
  the image reference in the docker/podman `args` array.
- **Fail-closed comparator (R2) — transition window:** The comparator now
  accepts BOTH the old bare-ref body (legacy, from before 1.3.0) AND the new
  registry-prefixed body. On detecting a legacy body, it upgrades rather than
  refuses. Once consumers re-run `--container` with 1.3.0, the bare-ref form
  is overwritten; the legacy matcher can be dropped in a follow-up release.
- **`EIDOLON_VERSION`** bumped `1.2.2 → 1.3.0`.
- **`ATLAS_VERSION`** in `commands/aci.sh` bumped `1.2.2 → 1.3.0`.

### Notes

- Spec references: T4 + H3 in
  `.spectra/plans/atlas-aci-ghcr-distribution-2026-05-01/spec.md`
  (`Rynaro/eidolons` nexus).

---

## [1.2.2] - 2026-04-29 — Claude Code subagent allowlist now grants atlas-aci MCP tools

### Fixed
- **ATLAS subagent fell back to native Read/Grep instead of using
  atlas-aci MCP tools.** `.claude/agents/atlas.md` (written by
  `install.sh`) ships a `tools:` line that allowlists only
  `Read, Grep, Glob, Bash(rg:*), Bash(git log:*), Bash(git show:*)`.
  When `eidolons atlas aci install` wires the atlas-aci MCP server
  into `.mcp.json`, Claude Code connects to it successfully — the
  warning resolves, the seven tools (`view_file`, `list_dir`,
  `search_text`, `search_symbol`, `graph_query`, `test_dry_run`,
  `memex_read`) become available at the project level — but the
  ATLAS subagent's allowlist does not include the
  `mcp__atlas-aci__<tool>` namespaces, so the subagent silently
  cannot invoke any of them and falls back to native `Read`/`Grep`.
  The expensive index sits idle.

  `eidolons atlas aci install` now also rewrites the `tools:` line in
  `.claude/agents/atlas.md` to include all seven `mcp__atlas-aci__*`
  entries alongside the BASE tools. `eidolons atlas aci remove`
  restores the BASE list. The agent body and the rest of the
  frontmatter are untouched. Idempotent (canonical strings produce
  byte-identical output across re-runs); awk-only rewrite, no yq
  dependency for the edit.

  The base/extended tool lists are kept inside `commands/aci.sh`
  rather than `install.sh` — this keeps the install→aci-install→
  aci-remove cycle symmetric and means the BASE list is the only
  thing on disk when atlas-aci is not wired.

  Note: this only affects Claude Code's subagent allowlist. The MCP
  server itself was wired correctly in 1.2.1. Cursor and Codex don't
  gate MCP tools per-subagent the same way Claude Code does, so no
  parallel work is needed there.

### Added
- **`tests/aci.bats` SUB-1 .. SUB-6** — six new bats cases covering:
  install extends the allowlist (container mode), install extends
  the allowlist (uv/host mode), idempotency across consecutive
  installs, remove restores the BASE list, `--dry-run` emits a
  `MODIFY` action verb without touching disk, and graceful no-op
  when `.claude/agents/atlas.md` is absent (atlas-aci does not
  recreate it — that remains `install.sh`'s job).
- **`tests/helpers.bash` `seed_claude_atlas_subagent`** — fixture
  that writes the canonical BASE-tools subagent file used by the
  SUB-* tests.

### Changed
- **`EIDOLON_VERSION`** bumped `1.2.1` → `1.2.2`. Patch release: bug
  fix only, no public CLI surface change.
- **`ATLAS_VERSION`** bumped `1.2.1` → `1.2.2` in lock-step. Image
  tag follows: `atlas-aci:1.2.2`.

## [1.2.1] - 2026-04-29 — MCP config writes absolute project path (Claude Code warning fix)

### Fixed
- **`.mcp.json` / `.cursor/mcp.json` / `.codex/config.toml` / copilot
  agent file** — atlas-aci entries previously embedded the literal
  `${workspaceFolder}` placeholder for `--repo`, `--memex-root`, and
  the docker `-v` bind mount paths. Cursor / VSCode expand this
  variable natively, but **Claude Code parses `${VAR}` as an env-var
  reference** and so emitted, on every project load:

  ```
  [Warning] [atlas-aci] mcpServers.atlas-aci: Missing environment variables: workspaceFolder
  ```

  After which the docker mount dereferenced the literal `${workspaceFolder}`
  string and the MCP server failed to attach. All host bodies now bake
  the absolute project path (`$PWD` at install time) directly. Six
  call sites touched:
  `container_json_fragment`, `json_server_fragment`,
  `_copilot_command_array` (uv + container branches),
  the copilot uv-mode yq merge (refactored to use the same env-injected
  pattern as the container branch), and `_codex_canonical_body_container`.

  Trade-off: `.mcp.json` bodies are now machine-specific. Re-run
  `eidolons atlas aci install` after relocating a project; consider
  gitignoring the file in team workflows where each developer's path
  differs.

### Added
- **`tests/aci.bats` ABS-1 / ABS-2 / ABS-3** — three regression tests
  pinning the post-install body shape: container-mode `.mcp.json`,
  uv-mode `.mcp.json`, and container-mode `.codex/config.toml` must
  all contain the absolute project path verbatim and **must not**
  contain `${workspaceFolder}` anywhere. Prevents a silent regression
  if someone re-introduces the placeholder.

### Changed
- **`EIDOLON_VERSION`** bumped `1.2.0` → `1.2.1`. Patch release: bug
  fix only, no public surface change.
- **`ATLAS_VERSION`** bumped `1.2.0` → `1.2.1` in lock-step. Container
  image tag follows: `atlas-aci:1.2.1`. The version bump cache-busts
  any stale local image from 1.2.0 (which would otherwise silently
  re-use the broken-config path).

## [1.2.0] - 2026-04-28 — `eidolons atlas aci index` subcommand

### Added
- **`commands/aci.sh` index action** — new positional subcommand
  `eidolons atlas aci index` (and equivalent `--index` flag) re-runs
  `atlas-aci index` against the current project without rebuilding
  the image, modifying MCP configs, or touching `.gitignore`. Bypasses
  the install-side `.atlas/manifest.yaml` short-circuit (T24) so
  re-indexing always actually re-indexes — the install path keeps the
  gate via the new `force` parameter on `run_index`.
- **Mode auto-detection for `index`** — `detect_index_mode` probes
  `command -v atlas-aci` first (host mode preferred: simpler, faster,
  no daemon dep), then falls back to `docker images` / `podman images`
  for `atlas-aci:<ATLAS_VERSION>` (container mode). Errors with exit 5
  and an actionable hint when neither is available. `--container` /
  `--runtime` flags override auto-detection.
- **`tests/aci.bats` IDX-1..IDX-9** — nine new bats cases covering
  positional vs flag form, host-mode happy path, container-mode
  auto-detect, prereq-missing exit, gate bypass on existing manifest,
  dry-run no-op, no MCP/.gitignore writes, explicit `--container`
  override, and conflict between positional `index` and `--remove`.

### Changed
- **`EIDOLON_VERSION`** bumped `1.1.1` → `1.2.0`. Minor release: new
  public CLI surface (the `index` action), no breaking change to
  existing `install` / `remove` flows, no methodology change.
- **`ATLAS_VERSION`** bumped `1.1.1` → `1.2.0` in lock-step. Local
  image tag follows: `atlas-aci:1.2.0`.
- **`run_index` signature** — now accepts an optional `force` boolean
  (default `false`). Install path passes nothing (preserves T24
  idempotency); index action passes `true`.
- **Usage banner reorganised** — actions now documented as positional
  subcommands (`install` / `index` / `remove`) with flag forms noted
  underneath, matching how most CLIs document subcommand-style APIs.

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
