# Phase 3 — PLAN

Eidolon: atlas v1.0.0  
Standard: EIIS v1.0  
Date: 2026-04-20

---

## 1. Summary

ATLAS v1.0.0 is a well-structured Eidolon with strong methodology content, complete skills, templates, schemas, and host-pointer files (`AGENTS.md`, `.github/copilot-instructions.md`, `CLAUDE.md`). It is missing the install surface required by EIIS v1.0: `install.sh`, the four `hosts/*.md` wiring docs, `DESIGN-RATIONALE.md`, `schemas/install.manifest.v1.json`, and the §5 YAML frontmatter block in `AGENTS.md`. After this audit, ATLAS will have a complete install surface: a meta-installer-compatible `install.sh`, per-host docs referencing the detailed guidance already in `INSTALL.md`, a `DESIGN-RATIONALE.md` skeleton extracted from existing spec preambles, the manifest schema, and the required frontmatter. The methodology content (`ATLAS.md`, `skills/**`, `templates/**`) will not be touched.

---

## 2. File Change List

### GAP-01 — CREATE `install.sh`

Create a fully §2-conformant bash script. Flags: `--target`, `--hosts`, `--force`, `--dry-run`, `--non-interactive`, `--manifest-only`, `--version`, `-h/--help`. Behavior:
- Detects consumer host config dirs (`.claude/`, `.github/`, `.cursor/`, `.opencode/`) when `--hosts auto`
- Idempotency: reads `<target>/install.manifest.json` and compares version before overwrite
- Copies core methodology files to `<target>/`: `agent.md`, `ATLAS.md`, `skills/`, `templates/`, `schemas/`, `evals/`
- Creates dispatch files per host (AGENTS.md append, `.github/copilot-instructions.md` pointer, `CLAUDE.md` pointer, `.cursor/rules/atlas.mdc`, `.opencode/agents/atlas.md`)
- Writes `<target>/install.manifest.json` conforming to `schemas/install.manifest.v1.json`
- Measures `agent.md` word count → token estimate; fails `--non-interactive` if >1000
- Prints smoke-test verification prompt on success
- Uses only relative paths internally; no external deps beyond standard bash + awk/shasum

### GAP-02 — CREATE `schemas/install.manifest.v1.json`

Create the JSON Schema draft 2020-12 file from the exact schema specified in EIIS §3. Required properties: `eidolon`, `version`, `methodology`, `installed_at`, `target`, `hosts_wired`, `files_written`. Optional: `handoffs_declared`, `token_budget`, `security`.

### GAP-03 — PATCH `AGENTS.md` (prepend frontmatter)

Prepend a `---` YAML frontmatter block before line 1 of `AGENTS.md`:
```yaml
---
name: atlas
version: 1.0.0
methodology: ATLAS
methodology_version: "1.0"
role: Explorer/Scout — read-only codebase intelligence
handoffs:
  upstream:   []
  downstream: [spectra, apivr-delta]
---
```
No other changes to `AGENTS.md`. The existing body content is correct and complete.

### GAP-04–07 — CREATE `hosts/claude-code.md`, `hosts/copilot.md`, `hosts/cursor.md`, `hosts/opencode.md`

Create `hosts/` directory and four per-host wiring docs. Each file covers: install steps, config locations, frontmatter examples, invocation commands, verification smoke test, troubleshooting. Content will be extracted from the detailed guidance already present in `INSTALL.md` (which covers all four hosts comprehensively). This avoids duplication — the hosts docs will be focused summaries pointing at `INSTALL.md` for full detail.

### GAP-08 — CREATE `DESIGN-RATIONALE.md`

Create a minimal design-rationale file mapping each architectural invariant (I-1 through I-8 from `ATLAS.md`) to its research motivation. Content lifted verbatim from `ATLAS.md` §1 preambles + §0 scope reasoning. No new editorial judgements introduced. Structure: one section per invariant, format: `### I-N: <name>` / `**Decision:** ...` / `**Rationale:** ...` / `**Source:** ATLAS.md §N`.

### GAP-09 — PATCH `CLAUDE.md` (append consumer section)

Append a `## Consumer project usage` section at the end of the existing `CLAUDE.md` (after line 87). Content: the EIIS pointer load-order (agent.md → ATLAS.md → skills → templates) and consumer install command. The existing 87 lines are not touched.

---

## 3. Risk Register

| Risk | Mitigation |
|------|-----------|
| `install.sh` complexity: consumer dispatch logic may break on edge-case dir layouts | All host dispatch writes are guarded by existence checks; `--dry-run` flag allows safe preview before any writes |
| `AGENTS.md` frontmatter prepend may confuse hosts that don't support YAML frontmatter in Markdown | The frontmatter is standard open-standard AGENTS.md format; Copilot/Cursor/OpenCode parse it; GitHub renders it as a code block, not broken content |
| `DESIGN-RATIONALE.md` content extraction may inadvertently summarize/paraphrase methodology content | Strategy is verbatim lift + structural reformatting only; no synthesis |
| `CLAUDE.md` append may conflict with how Claude Code currently reads the file | Append-only; Claude Code reads the full file; the new section adds consumer context without conflicting with the existing project-instructions content |
| `install.sh` shasum portability: macOS uses `shasum -a 256`, Linux uses `sha256sum` | Script will detect OS and use appropriate command with a fallback to `openssl dgst -sha256` |

---

## 4. Token Budget Estimate

- `agent.md` current: **842 tokens** (632 words / 0.75)
- No proposed change touches `agent.md`
- Post-audit `agent.md`: **842 tokens** (unchanged)
- Consumer-side always-loaded budget impact: 842 tokens for `agent.md` (same as now)
- Budget headroom: ~158 tokens remaining before the ≤1000 limit

---

## 5. Rejected Alternatives

**Alt A — Rewrite `CLAUDE.md` to EIIS template format.**  
Rejected: The existing `CLAUDE.md` is checked into the repo and used by Claude Code contributors to understand the project structure and invariants. Replacing it with the slim EIIS pointer template would destroy valuable project documentation that is referenced in the project's own contributor workflow. Append-only PATCH is the correct approach.

**Alt B — Merge `hosts/*.md` content directly into `INSTALL.md`.**  
Rejected: EIIS §1 explicitly requires `hosts/<name>.md` as separate files so the installer can reference them per-host and consumer projects can symlink or copy individual host files. `INSTALL.md` is the human guide; `hosts/*.md` are the machine-reference targets.

**Alt C — Skip `DESIGN-RATIONALE.md` and flag as methodology-adjacent.**  
Rejected: The file's required content (research → decision mapping) can be derived entirely from existing `ATLAS.md` text. No new methodology decisions are introduced. The risk of touching methodology content is low for a verbatim-extraction approach.

---

## 6. Execution Order

1. `schemas/install.manifest.v1.json` (GAP-02) — needed by install.sh
2. `AGENTS.md` frontmatter (GAP-03) — pure prepend, no dependencies
3. `hosts/claude-code.md` (GAP-04)
4. `hosts/copilot.md` (GAP-05)
5. `hosts/cursor.md` (GAP-06)
6. `hosts/opencode.md` (GAP-07)
7. `DESIGN-RATIONALE.md` (GAP-08)
8. `CLAUDE.md` append (GAP-09)
9. `install.sh` (GAP-01) — last, references all above
10. `CHANGELOG.md` — add `[Unreleased]` section
