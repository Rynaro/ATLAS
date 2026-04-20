# Phase 1 — SCOUT

Eidolon: **atlas**  
Version: **1.0.0** (source: `CHANGELOG.md:10`, `README.md` badge)  
Methodology: **ATLAS**  
Methodology version: **1.0** (source: `agent.md:7`)  
Audit mode: **fresh** (no `.eidolons-audit/` or `install.manifest.json` found)  
Audit date: 2026-04-20

---

## 1. Identity

- [FINDING-001] Eidolon slug is `atlas` — evidence: `agent.md:2` (`name: atlas`)
- [FINDING-002] Version is `1.0.0` — evidence: `CHANGELOG.md:10` (`## [1.0.0] — 2026-04-14`)
- [FINDING-003] Methodology field is `ATLAS`, version field is `"1.0"` — evidence: `agent.md:6-7`
- [FINDING-004] `agent.md` word count = 632, approx token count = 842 (within ≤1000 budget) — evidence: `wc -w agent.md`

---

## 2. EIIS §1 File Inventory

| Path | Present | Notes |
|------|---------|-------|
| `AGENTS.md` | ✅ | Exists; missing §5 YAML frontmatter |
| `CLAUDE.md` | ✅ | Exists; full project instructions, not EIIS pointer format |
| `.github/copilot-instructions.md` | ✅ | Exists; references ATLAS by name and points at `ATLAS.md` |
| `README.md` | ✅ | Exists; complete |
| `INSTALL.md` | ✅ | Exists; comprehensive cross-host guide |
| `CHANGELOG.md` | ✅ | Exists; Keep-a-Changelog format |
| `DESIGN-RATIONALE.md` | ❌ | MISSING |
| `agent.md` | ✅ | Exists; 842 tokens (within budget) |
| `ATLAS.md` | ✅ | Exists; authoritative spec |
| `install.sh` | ❌ | MISSING |
| `hosts/claude-code.md` | ❌ | MISSING (`hosts/` directory absent) |
| `hosts/copilot.md` | ❌ | MISSING |
| `hosts/cursor.md` | ❌ | MISSING |
| `hosts/opencode.md` | ❌ | MISSING |
| `evals/canary-missions.md` | ✅ | Exists; 15-mission set |
| `skills/traverse/SKILL.md` | ✅ | Exists |
| `skills/locate/SKILL.md` | ✅ | Exists |
| `skills/abstract/SKILL.md` | ✅ | Exists |
| `skills/synthesize/SKILL.md` | ✅ | Exists |
| `templates/mission-brief.md` | ✅ | Exists |
| `templates/traversal-map.md` | ✅ | Exists |
| `templates/findings.md` | ✅ | Exists |
| `templates/scout-report.md` | ✅ | Exists |
| `schemas/mission-brief.v1.json` | ✅ | Exists |
| `schemas/findings.v1.json` | ✅ | Exists |
| `schemas/scout-report.v1.json` | ✅ | Exists |
| `schemas/install.manifest.v1.json` | ❌ | MISSING — required by §3 |

---

## 3. `install.sh` audit

- [FINDING-005] `install.sh` does not exist at repo root — evidence: filesystem check
- §3 interface contract cannot be verified; this is a blocker gap.

---

## 4. `AGENTS.md` frontmatter audit (§5)

- [FINDING-006] `AGENTS.md` has no YAML frontmatter — evidence: `AGENTS.md:1` begins `# AGENTS.md — ATLAS methodology (v1.0)` with no `---` block
- Required fields absent: `name`, `version`, `methodology`, `methodology_version`, `role`, `handoffs`
- Content below the missing frontmatter is rich and correct — only the frontmatter block needs to be prepended.

---

## 5. `.github/copilot-instructions.md` audit

- [FINDING-007] File exists and references ATLAS by name — evidence: `.github/copilot-instructions.md:1` (`# GitHub Copilot — ATLAS methodology`)
- [FINDING-008] Points at `AGENTS.md` and `ATLAS.md` — evidence: `.github/copilot-instructions.md:71-73`
- §1 satisfied for this file; no gap.

---

## 6. `hosts/` directory audit

- [FINDING-009] `hosts/` directory does not exist — evidence: filesystem check
- All four required per-host wiring files are absent: `hosts/claude-code.md`, `hosts/copilot.md`, `hosts/cursor.md`, `hosts/opencode.md`

---

## 7. `CLAUDE.md` audit

- [FINDING-010] `CLAUDE.md` exists as full project instructions rather than the EIIS-specified slim pointer format — evidence: `CLAUDE.md:1-87`
- The current content is project-specific instructions for Claude Code contributors (repo structure, invariants, schema validation guidance). This is NOT the EIIS consumer pointer.
- Per EIIS spec, `CLAUDE.md` should contain a load-order pointer (`agent.md` → `ATLAS.md` → skills → templates) AND a consumer project usage section.
- **Decision: PATCH** — append the EIIS consumer pointer section at the bottom without touching the existing project-instructions content. The existing content is valid and useful; it just needs the consumer-facing pointer added.

---

## 8. `DESIGN-RATIONALE.md` audit

- [FINDING-011] `DESIGN-RATIONALE.md` does not exist — evidence: filesystem check
- This is a §1 required file. However, its content (research → decision mapping) is methodology-adjacent. A minimal skeleton can be created without editorial judgement.

---

## 9. `schemas/install.manifest.v1.json` audit

- [FINDING-012] `schemas/install.manifest.v1.json` does not exist — evidence: filesystem check
- This schema must be committed to the Eidolon repo per §3. The schema content is fully specified in the EIIS spec.

---

## 10. Token budget

- `agent.md` current: **842 tokens** (estimate)
- Budget limit: ≤1000
- Remaining headroom: ~158 tokens
- No proposed change touches `agent.md` content, so token budget is safe.
