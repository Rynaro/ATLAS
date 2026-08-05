# SPECTRA spec — atlas-changelog-110-backfill

> Retroactively document the missing `[1.1.0]` release in `Rynaro/ATLAS`'s
> `CHANGELOG.md`. Pure docs change. No source files, no version bumps,
> no tags.

| Field            | Value                                  |
|------------------|----------------------------------------|
| Spec id          | `atlas-changelog-110-backfill`         |
| Cycle            | S → P → E → C → T → R → A              |
| Mode             | Retroactive documentation              |
| Risk             | Low                                    |
| Implementer      | Single-file edit (CHANGELOG.md)        |
| Validation cost  | Visual diff + Markdown lint (no CI)    |

---

## S — Scout context (input)

`Rynaro/ATLAS` shipped `v1.1.0` via PR #11 (`feat/aci-container-mode`,
merge commit `75a4d65`, implementation commit `7b24b8b`). The PR delivered
a feature release — `--container` runtime mode for `commands/aci.sh` — but
omitted a `CHANGELOG.md` entry. The release was then superseded by
`v1.1.1` (`2026-04-28`) which **does** have a CHANGELOG entry that, by its
own wording ("the broken 1.1.0 build"), retroactively assumes a `1.1.0`
section the reader can scroll back to. That section does not exist. The
result is a load-bearing dangling reference: the existing
`[1.1.1]` paragraph reads as a hot-fix to a release that the changelog
itself never announced.

The downstream nexus (`Rynaro/eidolons`) already has a polished `Added`
paragraph for the same feature in its CHANGELOG; that prose is the
fidelity baseline. The implementation file `commands/aci.sh` (lines
1–80) and `ATLAS.md` §8 ("atlas-aci MCP server — container mode (v1.1.0)")
are the two source-of-truth references for what actually shipped.

---

## P — Problem

**Missing CHANGELOG section between `[1.1.1]` and `[1.0.6]`.**

The repo's `CHANGELOG.md` follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and orders
sections newest-first. The current order is:

```
[1.1.1] 2026-04-28
[1.0.6] 2026-04-27   ← gap: where [1.1.0] should be
[1.0.5] 2026-04-26
[1.0.4] 2026-04-25
[Unreleased] — EIIS-1.0 conformance
[1.0.0] 2026-04-14
```

A reader auditing the changelog cannot:

1. See what `1.1.0` actually delivered (the `--container` mode).
2. Resolve `1.1.1`'s reference to "the broken 1.1.0 build".
3. Locate the new exit codes (7, 8, 9) introduced in `1.1.0`.
4. Confirm the `EIDOLON_VERSION 1.0.6 → 1.1.0` minor bump rationale.

This is purely retroactive — `v1.1.0` is already tagged in git and pinned
in the nexus roster. No version bump, tag, or behavioural change is
proposed. The fix is one inserted Markdown section.

---

## E — Evidence (anchors)

| Claim                                                                                                  | Anchor                                                       |
|--------------------------------------------------------------------------------------------------------|--------------------------------------------------------------|
| `--container` and `--runtime` flag definitions                                                         | `commands/aci.sh:154–192`                                    |
| New exit codes 7, 8, 9                                                                                 | `commands/aci.sh:79–82, 123–133`                             |
| Build-locally model (D2): `<runtime> build … <git-url>#<ref>:mcp-server`                                | `commands/aci.sh:399–426` (`build_image`)                    |
| Always-prompt runtime selection (D1)                                                                   | `commands/aci.sh:342–377` (`select_runtime`)                 |
| Non-interactive without `--runtime` → exit 9                                                           | `commands/aci.sh:349–353`                                    |
| sha256 digest pinning of locally built image (D3)                                                      | `commands/aci.sh:389–397, 433–448`                           |
| GHCR-pull deferral (F1) — local build only                                                             | `commands/aci.sh:34–42` header note                          |
| `EIDOLON_VERSION` / `ATLAS_VERSION` `1.0.6 → 1.1.0` (later superseded by `1.1.1`)                       | `commands/aci.sh:54–56` (now `1.1.1`); `[1.1.1]` entry §Changed |
| §8 "container mode (v1.1.0)" prose                                                                     | `ATLAS.md:307–326`                                           |
| Date of `v1.1.0` tag                                                                                   | merge commit `75a4d65`; `git log -1 --format=%ad --date=short 75a4d65` |
| Existing wording style (Added / Changed / Fixed; bold-leading; italic file path)                       | `CHANGELOG.md:34–95` (`[1.0.6]` and `[1.0.4]`)               |
| Self-contained-vs-link convention                                                                      | `[1.1.1]` uses link-ref `[aci-1]`; `[1.0.6]` is fully self-contained; both styles coexist |

---

## C — Decisions

### D1. Date

Use **`2026-04-28`** as the release date, matching the merge commit
`75a4d65` and the pin-capture comments in `commands/aci.sh:38–42, 51`
(both annotate `Pin captured 2026-04-28`). The implementer should
verify with:

```sh
git log -1 --format=%ad --date=short 75a4d65
```

If the merge date is in fact different, prefer the merge-commit date
over the textual annotation.

### D2. Heading separator

Use the em-dash form `## [1.1.0] - 2026-04-28 — <summary>` matching
`[1.1.1]` and `[1.0.6]`. Note: `[1.0.4]` and `[1.0.5]` use the em-dash
**also** as the date separator (`[1.0.5] — 2026-04-26 —`); newer entries
have switched to ASCII `-` for the date. Match the newer convention.

### D3. One-line summary

`atlas-aci container-runtime mode (--container)`. Mirrors the imperative
voice of the implementation commit (`feat(aci): container-runtime mode
(--container)`) and §8's heading.

### D4. Subsection structure

Use `### Added` and `### Changed` (no `### Fixed`, no `### Verified` —
this was a feature release without bugfixes). This matches `[1.0.4]`'s
structure.

### D5. Self-contained vs. PR link

Keep the entry **self-contained** (no PR link footer). Rationale:

- `[1.0.6]` and `[1.0.4]` are both self-contained — the recently merged
  larger entries set the precedent.
- `[1.1.1]` only uses a link-ref because it points at an *external* repo
  (`atlas-aci#1`); PR #11 lives in `Rynaro/ATLAS` itself, so anyone
  reading the changelog is already in that repo's git history.
- The implementer may, at their discretion, add a `[atlas#11]` link-ref
  footer if they prefer; the spec does not require it.

### D6. Drift items / design points

Inline-mention `D1` (always-prompt), `D2` (build-locally), `D3` (sha256
digest pin), and `F1` (GHCR-pull deferred) as parenthetical design tags
— this matches the architectural-decision callouts already used in
`[1.0.6]` ("EIIS v1.1 §4.1.0", "R2 mitigation") and in `[Unreleased]`
("§4.7", "EIIS v1.0 §2"). Do **not** create a separate "Design points"
subsection — Keep a Changelog only sanctions Added / Changed / Fixed /
Removed / Deprecated / Security.

### D7. Version-bump line

Mirror the `[1.0.4]` style: include a `### Changed` bullet documenting
`EIDOLON_VERSION` and `ATLAS_VERSION` `1.0.6 → 1.1.0`. Note in the
bullet that the bump is a **minor** version (additive feature: a new
optional flag set; existing uv-mode invocations are unchanged).

---

## T — Targets / Acceptance criteria

A1. `CHANGELOG.md` contains a new section whose heading is exactly
    `## [1.1.0] - 2026-04-28 — atlas-aci container-runtime mode (--container)`,
    inserted between the existing `[1.1.1]` and `[1.0.6]` sections.

A2. The new section includes both `### Added` and `### Changed`
    subsections and no other subsections.

A3. The `### Added` body documents, at minimum:
    - The `--container` flag.
    - The `--runtime <docker|podman>` flag.
    - Always-prompt runtime selection (D1) + `--non-interactive` without
      `--runtime` → exit 9 contract.
    - Local image build (D2) via `<runtime> build … <git-url>#<ref>:mcp-server`.
    - sha256 digest pinning (D3) of the locally built image.
    - The three new exit codes: 7, 8, 9 (with their meanings).
    - A note that GHCR-pull is deferred (F1).

A4. The `### Changed` body documents:
    - `EIDOLON_VERSION` `1.0.6 → 1.1.0`.
    - `ATLAS_VERSION` `1.0.6 → 1.1.0` (kept in sync; used as the local
      image tag `atlas-aci:<ATLAS_VERSION>`).
    - Pinned atlas-aci ref captured `2026-04-28`.

A5. No content elsewhere in `CHANGELOG.md` is modified. No file other
    than `CHANGELOG.md` is touched.

A6. `markdownlint CHANGELOG.md` (if run by the implementer) reports no
    new violations relative to `main`.

A7. The entry's wording does not contradict `commands/aci.sh:1–80` or
    `ATLAS.md` §8.

---

## R — Rubric (scoring)

| Dim                | 0                    | 1                                      | 2 (target)                              |
|--------------------|----------------------|----------------------------------------|-----------------------------------------|
| Placement          | Wrong section / order | Correct location, wrong heading style  | Correct location + style matches `[1.1.1]` |
| Completeness       | Missing flag / exit code | All flags listed, exit codes partial | All flags + all 3 exit codes + design tags |
| Fidelity to source | Contradicts aci.sh   | Generic but not contradictory          | Verbatim-aligned with aci.sh + ATLAS.md §8 |
| Style consistency  | New format           | Mixes voice w/ adjacent entries        | Matches `[1.0.6]` / `[1.0.4]` voice & casing |
| Out-of-scope churn | Edits other files    | Reformats unrelated CHANGELOG entries  | Only the new section is added           |

Pass = total ≥ 9/10 and no dimension at 0.

---

## Validation gates

| Gate | Check                                                                                | How                                                              |
|------|--------------------------------------------------------------------------------------|------------------------------------------------------------------|
| G1   | Diff is one inserted Markdown section, no other lines changed                        | `git diff --stat CHANGELOG.md` shows one file, additions only   |
| G2   | Heading exactly matches the canonical heading from A1                                | `grep -n '^## \[1.1.0\]' CHANGELOG.md`                          |
| G3   | New section sits between `[1.1.1]` and `[1.0.6]`                                     | `grep -n '^## \[' CHANGELOG.md` line ordering                    |
| G4   | Date matches the merge commit                                                        | `git log -1 --format=%ad --date=short 75a4d65` equals heading date |
| G5   | All three exit codes (7, 8, 9) are mentioned with meanings                           | `grep -E 'exit (code )?[789]' CHANGELOG.md`                      |
| G6   | Both flags `--container` and `--runtime` appear                                      | `grep -E '\-\-(container|runtime)' CHANGELOG.md`                 |
| G7   | `EIDOLON_VERSION` and `ATLAS_VERSION` bump bullets present                           | `grep -E 'EIDOLON_VERSION.*1\.0\.6.*1\.1\.0' CHANGELOG.md`       |
| G8   | Markdown still parses with the same rules as `main` (no broken link refs introduced) | `markdownlint CHANGELOG.md` (advisory)                           |

---

## Out of scope

- Any change to `commands/aci.sh`, `install.sh`, `ATLAS.md`, `agent.md`,
  `schemas/`, `templates/`, `tests/`, or `evals/`.
- Bumping `EIDOLON_VERSION` or `ATLAS_VERSION` (already at `1.1.1`; the
  `1.1.0` bump itself is being **documented**, not re-applied).
- Creating, moving, or rewriting tags. `v1.1.0` already exists in git.
- Re-ordering, reformatting, or rewording any existing CHANGELOG entry.
- Adding a `### Fixed` or `### Verified` section to the new entry.
- Adding GHCR pull support (F1 deferral is restated, not resolved).

---

## A — Artifact: the CHANGELOG insert (verbatim)

Insert the block below into `CHANGELOG.md` so that it sits **between** the
existing `## [1.1.1] - 2026-04-28 — atlas-aci container index fix` section
and the existing `## [1.0.6] - 2026-04-27 — Codex MCP host support…`
section. Preserve a single blank line above and below the new section,
matching the spacing of adjacent entries.

```markdown
## [1.1.0] - 2026-04-28 — atlas-aci container-runtime mode (--container)

### Added

- **`commands/aci.sh` `--container` mode** — opt-in container-runtime
  path that builds the `atlas-aci` MCP server image locally (D2:
  build-locally, no GHCR pull) and wires MCP host configs to launch it
  via `<runtime> run --rm -i --read-only` per session. Mirrors the
  existing uv-mode flow (`.gitignore` → index → host writes) but
  substitutes a `<runtime> build` step and a digest-pinned canonical
  body. Implementation: `commands/aci.sh` lines 379–448 (`image_tag`,
  `image_exists`, `capture_local_digest`, `build_image`, `ensure_image`)
  and lines 1318–1360 (`main_install_container`).
- **`--runtime <docker|podman>`** — explicit runtime selector. Implies
  `--container`. When omitted in interactive mode the script prompts
  `[1] docker  [2] podman` (D1: always-prompt, max 3 retries). When
  omitted in `--non-interactive` mode the script exits 9.
- **sha256 digest pin (D3)** — after `<runtime> build`, the local image
  ID is captured (`<runtime> images --no-trunc --format '{{.ID}}'`) and
  the resulting `sha256:<hex>` is embedded in every host config the
  installer writes (`atlas-aci@sha256:<hex>` in `.mcp.json`,
  `.cursor/mcp.json`, `.codex/config.toml`, and `.github/agents/*.agent.md`).
  A second `eidolons atlas aci --container` run with an unchanged image
  digest is a true no-op (`_container_configs_up_to_date`).
- **New exit codes**:
  - **`7`** — container runtime not on PATH (when `--runtime` was
    explicitly set, or when neither `docker` nor `podman` is installed
    and the user did not supply `--runtime`).
  - **`8`** — `<runtime> build` exited non-zero (build log streamed to
    stderr).
  - **`9`** — `--container` invoked in `--non-interactive` mode without
    `--runtime` (D1 contract: never silently pick a runtime in CI).
- **`ATLAS.md` §8 "atlas-aci MCP server — container mode (v1.1.0)"** —
  smoke test, exit-code reference, and design-decision summary for the
  container path.

### Changed

- **`EIDOLON_VERSION`** bumped `1.0.6` → `1.1.0`. Minor release: the
  feature is additive — `eidolons atlas aci` without `--container`
  retains identical behaviour and prereqs to v1.0.6.
- **`ATLAS_VERSION`** bumped `1.0.6` → `1.1.0`, kept in sync with
  `EIDOLON_VERSION` and reused as the local image tag
  `atlas-aci:<ATLAS_VERSION>`.
- **`ATLAS_ACI_PIN` / `ATLAS_ACI_REF`** — pinned atlas-aci git ref
  captured 2026-04-28 from `Rynaro/atlas-aci@main`. Used by
  `<runtime> build … <git-url>#<ref>:mcp-server` to fix the build
  context. F1 (deferred): replace the local build with a GHCR pull when
  `atlas-aci` cuts its first tagged release.
```

---

## Implementer notes

1. Open `CHANGELOG.md`. The current line `34` is the heading
   `## [1.0.6] - 2026-04-27 — Codex MCP host support in `commands/aci.sh``.
   Insert the new section *before* that line, with a blank line above
   and below.

2. Verify the date with
   `git log -1 --format=%ad --date=short 75a4d65`. If the merge actually
   landed on a different day, update both the heading date and the
   bullet that mentions `2026-04-28` accordingly.

3. Do **not** retag, do **not** push to `main` directly. Open a PR named
   `docs(changelog): backfill v1.1.0 entry` against `main`. The branch
   convention used elsewhere in this repo is `docs/changelog-110-backfill`.

4. After merge, the downstream nexus (`Rynaro/eidolons`) needs no
   action — `roster/index.yaml` already pins ATLAS at `1.1.0` and
   `1.1.1`; the changelog is informational only.
