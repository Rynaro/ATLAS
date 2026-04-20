# Phase 2 — GAP ANALYSIS

Eidolon: atlas v1.0.0  
Standard: EIIS v1.0  
Date: 2026-04-20

---

| Gap ID | File | Class | Severity | Reason | Proposed Action |
|--------|------|-------|----------|--------|-----------------|
| GAP-01 | `install.sh` | CREATE | blocker | §2 requires idempotent installer with full flag interface; file absent entirely | Create from template with full §2 contract: all flags, host detection, idempotency check, manifest emission, token measurement, smoke-test banner |
| GAP-02 | `schemas/install.manifest.v1.json` | CREATE | blocker | §3 requires this schema committed to the repo; absent; installer references it | Create with the exact JSON Schema from §3 of the EIIS spec |
| GAP-03 | `AGENTS.md` (frontmatter) | PATCH | major | §5 requires YAML frontmatter with `name`, `version`, `methodology`, `methodology_version`, `role`, `handoffs`; block is entirely absent | Prepend `---` YAML block to `AGENTS.md` |
| GAP-04 | `hosts/claude-code.md` | CREATE | major | §1 requires per-host wiring doc; `hosts/` directory absent | Create `hosts/` dir + file using host-doc template |
| GAP-05 | `hosts/copilot.md` | CREATE | major | Same as GAP-04 | Create using host-doc template |
| GAP-06 | `hosts/cursor.md` | CREATE | major | Same as GAP-04 | Create using host-doc template |
| GAP-07 | `hosts/opencode.md` | CREATE | major | Same as GAP-04 | Create using host-doc template |
| GAP-08 | `DESIGN-RATIONALE.md` | CREATE | minor | §1 requires this file; absent | Create minimal skeleton mapping key ATLAS design decisions to research rationale; content lifted from `ATLAS.md` preambles |
| GAP-09 | `CLAUDE.md` (consumer pointer section) | PATCH | minor | Current file is project-contributor instructions; missing EIIS consumer pointer load-order and consumer project usage section | Append EIIS consumer pointer section at end of existing file |

---

## Notes

**GAP-03 (AGENTS.md frontmatter):** The existing `AGENTS.md` body is rich and correct. Only the frontmatter prepend is needed. The body already contains P0 rules, phase pipeline, handoff labels, and telemetry. No body edits required.

**GAP-09 (CLAUDE.md):** The existing content (`CLAUDE.md:1-87`) is the project-contributor guide — it is correct and useful for Claude Code contributors to this repo. It is NOT in conflict with EIIS; it just needs the consumer-facing section appended at the bottom. The EIIS template `CLAUDE.md` format will be appended as a `## Consumer project usage` section. **This file is on the flag line** — the existing content references repo internals (invariants, schema validation guidance) that are project-instructions, not EIIS pointer content. Strategy: append only; do not touch lines 1-87.

**DESIGN-RATIONALE.md (GAP-08):** This is methodology-adjacent in that its *content* (why ATLAS made specific design decisions) lives in `ATLAS.md` §0 and §1 preambles. The file skeleton will be created with those sections extracted into a rationale format, but no new editorial judgements will be introduced. If the user wants richer content they can expand it.

**install.sh (GAP-01):** The INSTALL.md already describes the subtree-based install process. The `install.sh` will implement the §2 contract programmatically, adapting the INSTALL.md's described steps into the bash skeleton from the EIIS template.
