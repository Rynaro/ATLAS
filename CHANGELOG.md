# Changelog

All notable changes to the ATLAS specification are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) — but for a spec, "breaking" means any change to phase contracts or JSON schemas that requires existing implementations to be updated.

---

## [1.7.2] — 2026-05-27 — Canary DSL migration

### Changed

- feat(canary): migrate evals/canary-missions.md to v1.13.0 DSL (smoke-default mission). Full 15-mission battery preserved as historical reference.

---

## [1.7.1] — 2026-05-26 — SPEC.md text sweep

### Fixed

- fix: SPEC.md text references updated to match canonical v1.4 layout (envelope.json relocated to schemas/).

---

## [1.7.0] — 2026-05-26 — EIIS v1.4 canonical inventory

### Changed

- Declares EIIS v1.4 conformance (`EIIS_VERSION = 1.4`).
- **BREAKING (install-target):** `AGENTS.md` is no longer copied to
  `<target>/`. The source-repo `AGENTS.md` at the ATLAS root is preserved per
  EIIS §1.1; only the install-target copy is retired.
- `agent.md` role in `files_written[]` changed from `"entry-point"` to
  `"agent-profile"` (EIIS v1.4 §1.8.6).
- `.claude/agents/atlas.md` heredoc rewritten per EIIS v1.4 §4.2.6: now
  references both `agent.md` (P0 always-loaded rules) and `SPEC.md` (deep
  on-demand methodology spec). Legacy `ATLAS.md` and `AGENTS.md` references
  removed.
- Non-whitelisted install-target directories (`evals/`, `.github/`,
  `commands/`) are no longer created or populated under `<target>/`; these
  artefacts live in the source repo only.

### Added

- `<target>/ECL_VERSION` is now written by `install.sh` with
  `role: "ecl-version"` (EIIS v1.4 §3.7.1; closes scout G3). ATLAS source
  declares `ECL_VERSION = 2.0`.
- Manifest-driven canonical-inventory sweep (`canonical_inventory_sweep`
  helper) runs after all writes and before manifest finalization (EIIS v1.4
  §6.X). Belt-and-braces: `"AGENTS.md"` also added to `LEGACY_SPEC_FILES`
  for early sweep on upgrade from v1.5.3.
- Manifest now includes `"eiis_version": "1.4"` and
  `"canonical_inventory_strict": true` (EIIS v1.4 §2.3).

---

## [1.6.1] — 2026-05-26

### Fixed

- `install.sh` now sweeps legacy v1.2-era artefacts on upgrade: removes stale
  `<TARGET>/ATLAS.md` and any `<TARGET>/skills/{abstract,locate,synthesize,traverse}/`
  subdir trees left behind by pre-v1.3 installs. Fresh installs are unaffected.

---

## [1.6.0] — 2026-05-25 — EIIS v1.3 install layout normalization

### Changed

- **BREAKING:** Full-spec source file renamed `ATLAS.md` → `SPEC.md`. The
  installed destination at `.eidolons/atlas/SPEC.md` was `ATLAS.md` in prior
  releases; any consumer that hard-codes the old path must update their
  reference. (EIIS v1.3 §1.8.)
- **BREAKING:** Skills layout flattened from `skills/<phase>/SKILL.md`
  (sub-directory per phase) to `skills/<phase>.md` (flat file per phase).
  Installed paths change from `.eidolons/atlas/skills/traverse/SKILL.md` →
  `.eidolons/atlas/skills/traverse.md` (and similarly for `locate`,
  `abstract`, `synthesize`). Vendor copies at
  `.claude/skills/atlas-<phase>/SKILL.md` are **unchanged** in path.
- `install.sh` `wire_skill` helper refactored: single helper now performs
  both the source-of-truth write (flat `.md`) and the Claude Code vendor copy
  (`atlas-<phase>/SKILL.md`), plus Copilot and Cursor vendor copies. The
  previous helper only handled vendor writes.
- `agent.md`: skill file references updated (`skills/<phase>/SKILL.md` →
  `skills/<phase>.md`); spec reference updated (`ATLAS.md` → `SPEC.md`).
- `CLAUDE.md`, `README.md`: filename literal `ATLAS.md` → `SPEC.md` where it
  refers to the spec file; the methodology name "ATLAS" is unchanged.

### Added

- Manifest now includes `eiis_version: "1.3"`, `spec_file` (canonical
  spec path), and `skills[]` array (dual-write source + vendor SHA pairs)
  per EIIS v1.3 §1.8 and §4.2.4.

### Compliance

- `EIIS_VERSION` bumped from `1.1` to `1.3`.

---

## [1.5.2] — 2026-05-13 — declare ECL v2.0 conformance

### Changed
- `ECL_VERSION` file: `1.2` → `2.0`. Targets the latest ECL spec
  (`Rynaro/eidolons-ecl@v2.0.0`); ATLAS's emit envelopes remain
  byte-compatible (v2.0 is backward-compatible with v1.x per ECL §7.3
  12-month compatibility window through 2027-05-13).
- `agent.md` + `AGENTS.md` frontmatter: `comm.envelope_version`
  `"1.2"` → `"2.0"`.
- `install.sh`: `EIDOLON_VERSION` `1.5.1` → `1.5.2` (PATCH bump —
  declaration-only change; no behaviour change, no schema change, no
  envelope-shape change).

### Notes
- No envelope-format changes. Envelopes already emitted by older ATLAS
  releases are valid under v2.0 conformance (ECL §7.3 12-month
  backward-compatibility window).
- ECL v2.0.0 introduces the ISE (Inter-Session Envelope) trust hierarchy
  in `spec/ecl-2.0.md`. ATLAS emit envelopes (currently v1.0/1.2-shape)
  are byte-compatible with the v2.0 envelope contract.
- Companion patches follow for SPECTRA, APIVR-Δ, IDG, FORGE, and VIGIL.
- Refs: `Rynaro/eidolons-ecl@v2.0.0`.

## [1.5.1] — 2026-05-12 — Declare ECL v1.2 conformance

### Changed
- `ECL_VERSION` file: `1.0` → `1.2`. Targets the latest ECL spec
  (`Rynaro/eidolons-ecl@v1.2.0`); ATLAS's emit envelopes remain
  byte-compatible (v1.2 is backward-compatible with v1.0 per ECL §1.1.1).
- `agent.md` + `AGENTS.md` frontmatter: `comm.envelope_version`
  `"1.0"` → `"1.2"`.
- `install.sh`: `EIDOLON_VERSION` `1.5.0` → `1.5.1` (PATCH bump —
  declaration-only change; no behaviour change).

### Notes
- No envelope-format changes. v1.0 envelopes already emitted by older
  ATLAS releases are valid under v1.2 conformance (ECL §7.3 12-month
  backward-compatibility window).
- HMAC-SHA-256 at `trust_level=high` is now RECOMMENDED per ECL v1.1
  (gate I-5). ATLAS's worked examples use `trust_level=standard` so
  no change required for canonical edges.

## [1.5.0] - 2026-05-08 — ECL v1.0 emission adoption

### Added

- **`ECL_VERSION`** — new repo-root file declaring `1.0`, the targeted ECL
  (Eidolons Communication Layer) spec version. Mirrors the shape of
  `EIIS_VERSION`. Presence of this file enables the optional
  `ecl_version_emitted` field in the install manifest.

- **`schemas/ecl-envelope.v1.json`** — vendored copy of the central ECL v1.0
  envelope schema (`eidolons-ecl/schemas/envelope.v1.json`) for self-contained
  ATLAS validation. ATLAS install copies this to the consumer's
  `.eidolons/atlas/schemas/` directory.

- **`schemas/scout-report-profile.v1.json`** — vendored copy of the central
  ECL per-Eidolon scout-report profile
  (`eidolons-ecl/schemas/per-eidolon/scout-report.v1.json`) for self-contained
  ATLAS validation. Validates the ECL envelope YAML frontmatter for
  ATLAS-emitted scout reports; the body structure remains governed by
  `schemas/scout-report.v1.json`. Includes a schema-level comment explaining
  the `scope.{entrypoints,modules,excluded}` (envelope frontmatter) vs
  `mission_recap.scope.{include,exclude}` (body) naming divergence so
  implementors don't conflate the two layers.

- **`templates/scout-report.envelope.json`** — fill-in-the-blank skeleton for
  the ECL v1.0 envelope sidecar emitted alongside `scout-report.md` at Phase S.
  Uses `x_atlas_comment` vendor-extension field (allowed by the central schema's
  `patternProperties: "^x_[a-z][a-z0-9_]*$"`) to embed guidance without
  violating `additionalProperties: false`.

- **`schemas/install.manifest.v1.json`** — hand-extended (locally, ahead of
  EIIS v1.2 GA) to accept an optional `ecl_version_emitted` string field
  matching the pattern `^[0-9]+\.[0-9]+(\.[0-9]+)?$`. Will be re-vendored from
  EIIS v1.2 once tagged. Top-level `description` updated to document the
  hand-extension.

- **`ATLAS.md §1` I-9 architectural invariant** — Phase S MUST emit a v1.0
  envelope sidecar adjacent to the scout report; envelope is a terminal
  Phase-S artefact (not a tool — preserves I-1 read-only).

- **`skills/synthesize/SKILL.md` — Envelope sidecar sub-section** — added
  immediately after the existing `<handoff>` block guidance (which is
  preserved as-is for one minor cycle per the v1.5 design call). Instructs
  envelope construction: SHA-256 + `size_bytes` calculation, `from`/`to`/
  `performative=PROPOSE` fields, and reference to
  `eidolons-ecl/contracts/atlas-to-spectra.yaml`.

- **`skills/synthesize/SKILL.md` — Exit gate 7th item** — `[ ] Envelope
  sidecar emitted, schema-valid against schemas/ecl-envelope.v1.json,
  integrity.sha256 matches payload`.

### Changed

- **`install.sh`** — `EIDOLON_VERSION` bumped `1.4.2` → `1.5.0`. Reads
  `ECL_VERSION` at install time and conditionally injects
  `"ecl_version_emitted"` into both the dry-run preview (`MANIFEST_CONTENT`)
  and the live heredoc write. Field is omitted entirely when `ECL_VERSION` is
  absent (opt-in, Bash 3.2 compatible). New `copy_file` calls propagate the
  three new files (`schemas/scout-report-profile.v1.json`,
  `schemas/ecl-envelope.v1.json`, `templates/scout-report.envelope.json`) to
  the consumer's install target.

- **`agent.md` frontmatter** — `comm.envelope_version: "1.0"` block added.
  Signals ECL envelope emission capability to roster and host tooling.

- **`AGENTS.md` frontmatter** — same `comm.envelope_version: "1.0"` block.

- **`ATLAS.md §2.5 Phase S contract`** — Outputs section now lists both
  `scout-report.md` and `scout-report.envelope.json`; Hard constraints section
  explicitly classifies the envelope as a terminal artefact emission (not a
  tool), preserving I-1.

- **`ATLAS.md §7 Versioning`** — one-line ECL compatibility statement added.

- **`templates/scout-report.md §7`** — §7.1 "Envelope sidecar" sub-section
  added after the `<handoff>` block, pointing to the envelope template and
  documenting the scope-field naming divergence in a HTML comment.

- **`DESIGN-RATIONALE.md`** — I-9 entry appended (after I-8), following the
  I-1..I-8 format. Cites ECL §1 (envelope shape) and §3 (per-Eidolon profile).

- **`CLAUDE.md §Schema Validation`** — one-line addendum noting
  `ecl-envelope.v1.json`.

- **`CLAUDE.md §Versioning Policy`** — one-line ECL adoption statement.

### Notes

- ECL adoption is opt-in. Existing `scout-report.md` consumers continue to
  work without envelope-aware tooling; the sidecar is additive.
- The release workflow's `eiis-version` pin stays at `"1.1"` — bumping to
  `"1.2"` before `Rynaro/eidolons-eiis` PR #1 (EIIS v1.2) is merged and
  tagged would CI-break.
- The `<handoff>` XML stub in `skills/synthesize/SKILL.md` and
  `templates/scout-report.md §7` is intentionally preserved for this minor
  cycle. It will be removed in v1.6.

---

## [1.4.2] - 2026-05-06 — Defensive `-e HOME=/tmp` + SELinux `:Z` + silent-success guard

### Fixed

- **`commands/aci.sh`: emit `-e HOME=/tmp` in docker invocations to defend
  against atlas-aci images whose baked `$HOME` (`/home/atlas` mode `0700`) is
  unreadable when `-u` is overridden to host UID:**
  `tree_sitter_language_pack` performs `$HOME`-relative I/O during
  `parser.parse()`. The atlas-aci image bakes `USER atlas:10001` with
  `/home/atlas` mode `0700`; when eidolons CLI overrides `-u` to the host UID,
  the process cannot read `$HOME` → EACCES → every source file `parse_failed`.
  Adding `-e HOME=/tmp` to all four emitter paths (`run_index_container`,
  `container_json_fragment`, `_copilot_command_array`, and
  `_codex_canonical_body_container`) plus the index-time `docker run` makes
  `$HOME` point at a world-readable, tmpfs-friendly path regardless of which UID
  runs the container. Belt-and-braces: Layer 1 (atlas-aci `ENV HOME=/tmp`) is the
  primary fix; this Layer 2 emitter change protects consumers who manually pinned
  an older `@sha256:` digest or set `ATLAS_ACI_IMAGE_REF` to an older tag.

- **Fedora SELinux Enforcing hosts: silent `files_indexed=0` with
  `Permission denied` on every source file
  (spec `atlas-aci-container-uid-perm-fix-2026-05-05`):**
  The wrapper previously printed `✓ Indexed → .atlas/` even when the container
  indexed 0 files because every bind-mount path was denied by SELinux. The
  silent-success guard (see Added above) and the `:Z` relabel (see Added above)
  together prevent this: the guard fails loudly if the user has not yet added
  `:Z`; after re-running with the fix, `:Z` is baked and the index succeeds.

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

- **SELinux `:Z` mount-relabel for `/repo` and `/memex` binds
  (spec `atlas-aci-container-uid-perm-fix-2026-05-05`):**
  When running on a Linux host with SELinux Enforcing, `_atlas_aci_volume_opts`
  now appends `:Z` to bind-mount option strings. This relabels the bind with a
  private MCS label so the container process can read/write the mounted paths
  without a `Permission denied (os error 13)` from the kernel. The `:Z` suffix
  is threaded through both the index leg (`run_index_container`) and the
  canonical serve body written to `.mcp.json` by `container_json_fragment`.
  Composed via two new helpers: `_atlas_aci_selinux_enforcing` (returns 0 on
  Linux+SELinux Enforcing) and `_atlas_aci_volume_opts` (builds the
  comma-separated opts string). Both are Bash 3.2 safe.

- **Silent-success guard in `run_index_container`
  (spec `atlas-aci-container-uid-perm-fix-2026-05-05` P-B):**
  When the container exits 0 but its output contains both `files_indexed=0`
  and a `parse_failed` warning line, the wrapper now calls `exit_index_fail`
  instead of printing a green checkmark. This distinguishes UID/SELinux
  bind-mount failures (every file emits `IO error: Permission denied`) from
  legitimate empty-language repos (which also emit `files_indexed=0` but
  produce no `parse_failed` lines). The error message includes a diagnostic
  one-liner so the user can confirm the root cause.

- **Eight new bats cases in `tests/aci.bats`:**
  - G2-T1.silent-success-fires: container exits 0 with `parse_failed` +
    `files_indexed=0` → `exit_index_fail`, no MCP writes.
  - G3-T1.empty-lang-no-false-fail: `files_indexed=0` with no `parse_failed`
    → success, `.mcp.json` written.
  - G-T1.selinux-suffix-when-enforcing: stubbed `getenforce=Enforcing` →
    docker.log contains `:Z` (Linux only, skipped on macOS).
  - G-T1.selinux-no-suffix-when-permissive: stubbed `getenforce=Permissive`
    → docker.log does NOT contain `:Z` (Linux only, skipped on macOS).
  - G-T1.canonical-body-includes-u-flag: `.mcp.json` args array contains
    `-u <uid>:<gid>` baked at install time.
  - T4-1: fresh project — `.atlas/memex/` created before docker run; docker run
    contains `-u` and a writable `/memex` bind.
  - T4-2: image already loaded (inspect-only sentinel) — `docker build` not
    invoked; "image already loaded" in stderr.
  - T4-3: index failure — no MCP config files written; verbatim error strings;
    non-zero exit.

- **`commands/aci.sh` header invariant comment:** Documents the fail-closed write
  boundary ("No MCP config files were modified.") as a pinned invariant.
- **`_resolve_pinned_image_ref` function in `commands/aci.sh`:** Resolves the
  image ref to check from `.mcp.json`, optional nexus CLI, or constant fallback
  (Bash 3.2 safe).
- **`.github/workflows/release.yml`** — adopts the eidolons-nexus
  release-integrity contract by wrapping the reusable
  `Rynaro/eidolons/.github/workflows/eidolon-release-template.yml`
  workflow. Dispatched manually with a SemVer; the template runs
  `bats tests/`, validates EIIS-1.1 conformance, tags the commit, attests
  the release artifacts, and publishes a `release-manifest.json` (with
  `commit`, `tree`, `archive_sha256`, optional `manifest_sha256`, and
  `provenance.github_attestation: true`) so the nexus `roster-intake.yml`
  workflow can populate `versions.releases.<v>` for ATLAS.

### Changed

- **`tests/aci.bats` ABS-1 — rewrite to index-agnostic `-v` mount assertions:**
  The test previously pinned the first and second `-v` mount values by integer
  index (`args[7]`, `args[9]`). Rewritten to use `jq indices("-v")` lookup
  matching the H3 test convention, so future arg insertions do not require
  updating numeric positions.

- **`ATLAS_VERSION` / `EIDOLON_VERSION` bumped `1.3.0 → 1.4.2`.**

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
