# SPECTRA Spec: aci-subagent-tools-multi-host

- **id:** `aci-subagent-tools-multi-host`
- **status:** draft
- **owner:** TBD
- **upstream:** ATLAS#16 (Claude Code subagent tools allowlist fix, released 1.2.2)
- **downstream:** APIVR-Δ implementers (per-host)
- **created:** 2026-04-28
- **target repo:** `Rynaro/ATLAS`
- **target branch convention:** `fix/aci-subagent-tools-<host>` per slot

---

## Frame

### The gap pattern (Claude Code, just fixed in PR 16)

ATLAS ships an installer (`install.sh`) that writes per-host subagent / agent /
rule files into the consumer project. Most carry a tool allowlist or
permission block in YAML frontmatter (or a TOML/MDC equivalent).

When the user runs `eidolons atlas aci install`, `commands/aci.sh` wires the
**atlas-aci MCP server** into each host's MCP config (`.mcp.json`,
`.cursor/mcp.json`, `.codex/config.toml`, or `.github/agents/*.agent.md`'s
`tools.mcp_servers` array). The MCP server exposes seven tools at runtime:
`view_file`, `list_dir`, `search_text`, `search_symbol`, `graph_query`,
`test_dry_run`, `memex_read`. In Claude Code's MCP namespace they appear as
`mcp__atlas-aci__<tool>`.

For **Claude Code**, the gap was:

- `.claude/agents/atlas.md` `tools:` allowlist permits only
  `Read, Grep, Glob, Bash(rg:*), Bash(git log:*), Bash(git show:*)`.
- `aci install` correctly wires `.mcp.json` so the MCP server connects, BUT
  the subagent's allowlist doesn't name the seven `mcp__atlas-aci__*`
  namespaces — Claude Code's per-subagent permission gate refuses to expose
  them. The subagent silently falls back to native Read/Grep. Index sits idle.
- Fix shape: `aci install` rewrites the `tools:` line to add the seven MCP
  entries; `aci remove` restores the BASE list. Lifecycle stays symmetric
  (install.sh writes BASE; aci install extends; aci remove restores).
  Awk-based atomic rewrite, idempotent, body untouched.

Claude Code helpers in `commands/aci.sh` (canonical reference shape):
- `_subagent_canonical_tools_base` (line 1250-1252)
- `_subagent_canonical_tools_with_mcp` (line 1254-1260)
- `_subagent_set_tools_line` (line 1267-1284)
- `subagent_extend_tools` (line 1289-1299) — call site: `apply_host_install`
  claude-code branch, line 1317
- `subagent_restore_tools` (line 1303-1310) — call site: `apply_host_remove`
  claude-code branch, line 1351

### The audit question (per host)

> Does the per-host subagent / agent / rule file gate MCP-tool exposure
> per-agent? If yes, the gap exists; if no (e.g. tools are global at the
> project level, or the host's installer does not emit a tool-allowlist
> field that would shadow the global MCP wiring), no fix is needed.

The audit below answers this for each non-Claude-Code host that ATLAS
already supports: **codex, copilot, cursor, opencode**.

---

## Audit

### Host: codex

- **Subagent file written by `install.sh`:** `.codex/agents/atlas.md`
  (install.sh:540-591)
- **Frontmatter shape (install.sh:544-547):**
  ```
  ---
  name: atlas
  description: Read-only codebase scout running the ATLAS five-phase pipeline …
  ---
  ```
- **MCP wiring location:** `.codex/config.toml`, `[mcp_servers.atlas-aci]`
  table (aci.sh:1036, `wire_codex` at 1081-1185).
- **Permission model summary:** Codex's subagent contract (see install.sh:537
  comment: "Codex subagent contract: .codex/agents/<name>.md with YAML
  frontmatter (`name`, `description` required; `tools`, `model` optional).
  Source: https://developers.openai.com/codex/subagents") permits an optional
  `tools:` field. When `tools:` is **absent**, Codex inherits the project's
  available tool set — including MCP tools wired via `.codex/config.toml`. The
  installer does **not** emit a `tools:` line.

- **VERDICT: NO GAP.**

- **Rationale:** install.sh:544-547 defines `CODEX_AGENT` with only `name`
  and `description`. There is no `tools:` field shipped that would shadow the
  global `[mcp_servers.atlas-aci]` wiring in `.codex/config.toml`. The MCP
  tools surface to the codex subagent through the project-level config; the
  Claude-Code-style per-agent narrowing simply does not exist in the file
  the installer creates. Adding a `tools:` line — and then having to extend
  it on `aci install` — would be net new behaviour, not a bug fix. If a
  user later hand-edits `.codex/agents/atlas.md` to add a `tools:` field,
  that's outside the installer's contract; ATLAS won't silently extend
  user-authored fields. **No code change required.**

- **Future-watch note (non-blocking):** if the codex contract evolves to
  require a `tools:` allowlist for MCP tools to surface, re-open this
  decision and add a slot mirroring the Claude Code shape.

---

### Host: copilot

- **Subagent files written by `install.sh`:** none directly. `install.sh`
  writes `.github/copilot-instructions.md` (line 482-484, opt-in via
  `--shared-dispatch`) and `.github/instructions/<skill>.instructions.md`
  (per-skill, line 395-412). It does **not** create `.github/agents/*.agent.md`.
- **`.github/agents/*.agent.md` ownership:** these files are authored by the
  end user (or another tool), not by ATLAS install.sh. `aci.sh` operates on
  whatever agent files happen to be present (`copilot_list_all_agents` at
  aci.sh:858-864 globs `.github/agents/*.agent.md`).
- **MCP wiring location:** `tools.mcp_servers[]` array inside the YAML
  frontmatter of each existing `.github/agents/*.agent.md` (aci.sh
  `copilot_install_one` at line 886-962, `copilot_remove_one` at 964-1004).
- **Permission model summary:** Copilot agent files use `tools` as a **map**
  whose `mcp_servers` key holds the per-server entries (see existing fixture
  in tests/helpers.bash:262-273). The MCP entries themselves *are* the
  permission grant — there is no separate per-tool allowlist field that
  shadows them once the server is registered. The Claude-Code pattern (a
  flat string list of permitted tool names that must include the MCP tool
  namespace explicitly) does not appear in copilot's frontmatter.

- **VERDICT: NO GAP.**

- **Rationale:** aci.sh already manages copilot's MCP exposure correctly:
  it inserts `{name: atlas-aci, transport: stdio, command: […]}` into
  `tools.mcp_servers` (aci.sh:907-945) on install and removes it on remove.
  Copilot agents do not maintain a separate `tools:` flat allowlist that
  must additionally name `mcp__atlas-aci__<tool>` entries — the presence of
  the server entry in `tools.mcp_servers` is the grant. Adding a parallel
  flat-list rewrite would duplicate the permission and risk drift. **No
  code change required.**

- **Future-watch note (non-blocking):** if a future Copilot release adopts
  a flat per-tool allowlist field (analogous to Claude Code's `tools:`
  string), re-open this decision.

---

### Host: cursor

- **Per-skill rule files written by `install.sh`:** `.cursor/rules/atlas-<phase>.mdc`
  via `wire_skill` (install.sh:414-432), one per phase
  (traverse/locate/abstract/synthesize). Methodology-level
  `.cursor/rules/atlas.mdc` is intentionally removed by install.sh:491-493
  when `--force` is set; per-skill files are the canonical Cursor surface.
- **Frontmatter shape (install.sh:421-426):**
  ```
  ---
  description: "<skill description>"
  alwaysApply: false
  ---
  ```
- **MCP wiring location:** `.cursor/mcp.json`, project-global
  `mcpServers."atlas-aci"` (aci.sh:1319, `json_install "./.cursor/mcp.json"`).
- **Permission model summary:** Cursor's MDC frontmatter exposes
  `description`, `alwaysApply`, and (optionally) `globs`/`agents` matchers.
  There is no per-rule `tools:` allowlist field. MCP tools are scoped at the
  project level via `.cursor/mcp.json`; rule files do not gate or filter them.

- **VERDICT: NO GAP.**

- **Rationale:** install.sh:421-426 confirms the MDC frontmatter contains
  no tool-allowlist field. Cursor's MCP exposure is project-global through
  `.cursor/mcp.json` (already correctly wired by aci.sh `json_install`).
  No equivalent of Claude Code's per-subagent `tools:` gate exists.
  **No code change required.**

---

### Host: opencode

- **Subagent file written by `install.sh`:** `.opencode/agents/atlas.md`
  (install.sh:496-532).
- **Frontmatter shape (install.sh:501-512):**
  ```yaml
  ---
  description: …
  mode: primary
  permission:
    edit: deny
    write: deny
    bash:
      "rg *": allow
      "git log *": allow
      "git show *": allow
      "*": deny
  ---
  ```
- **MCP wiring location:** **None.** opencode is **explicitly excluded** from
  the MCP host detection in `detect_hosts_mcp` (aci.sh:525-526 comment:
  "opencode is NOT included: its MCP capability is not confirmed in this
  spec revision (§2.1 G2)"). aci.sh does not write any MCP config for
  opencode today.
- **Permission model summary:** The `permission` block has three top-level
  scopes: `edit`, `write`, `bash`. The wildcard `"*": deny` (install.sh:511)
  applies **only inside the `bash:` namespace** — it is the catch-all for
  unmatched bash commands, not a global tool deny-all. There is no
  `permission.mcp` or equivalent scope; MCP tool exposure is not gated at
  the agent file level in opencode's current contract.

- **VERDICT: NO GAP.**

- **Rationale:** Two reasons compound:
  1. aci.sh does not wire MCP for opencode at all (aci.sh:525-526). There
     is no MCP config write to which a subagent allowlist could be a
     missing gate.
  2. Even if opencode MCP wiring is later added, the existing `permission`
     block does not have a per-MCP-tool allowlist field. The wildcard
     `"*": deny` is scoped to bash commands only and would not affect MCP
     tool exposure. The Claude-Code-style per-subagent `tools:` flat list
     does not have an analogue in opencode's frontmatter.

  **No code change required.** When opencode MCP wiring lands (separate
  spec, not this one), revisit whether the contract has evolved to include
  a per-tool allowlist field; if so, add a slot then.

---

## Audit summary

| Host        | Verdict   | Evidence                                                                                          |
|-------------|-----------|---------------------------------------------------------------------------------------------------|
| codex       | NO GAP    | `tools:` field absent from installer-shipped `.codex/agents/atlas.md` (install.sh:544-547)        |
| copilot     | NO GAP    | MCP exposure managed via `tools.mcp_servers[]` map; no parallel flat allowlist (aci.sh:886-962)  |
| cursor      | NO GAP    | `.cursor/rules/*.mdc` frontmatter has no tool-allowlist field (install.sh:421-426)                |
| opencode    | NO GAP    | No MCP wiring; `"*": deny` scoped to `permission.bash` only (install.sh:504-511, aci.sh:525-526)  |

**Implementation slots needed: 0.**

The user's hypothesis ("probably will do the same with other toolings") is
not borne out by the evidence: each non-Claude-Code host either (a) does
not gate MCP tools per-agent (cursor, opencode), or (b) gates them through
a different mechanism that aci.sh already manages correctly (copilot's
`tools.mcp_servers` map), or (c) does not currently emit a tool-allowlist
field at all (codex). The Claude Code fix in PR 16 is therefore complete
for the supported hosts.

---

## Per-host implementation contracts

**(none — all four audited hosts returned NO GAP)**

If a future revision of any host's contract introduces a per-subagent flat
tool allowlist that shadows global MCP wiring, the implementation contract
template below can be cloned into a new spec. The orthogonal namespacing
plan (function-name reservations) is recorded so a future audit need not
re-derive it.

### Reserved namespaces (for future use)

If/when a host requires the same fix shape, use the following function-name
reservations to avoid collisions with the existing Claude Code helpers:

| Slot      | Helper namespace                                    | Call sites                                  |
|-----------|-----------------------------------------------------|---------------------------------------------|
| codex     | `_subagent_codex_canonical_tools_base`              | `apply_host_install` codex branch (≈1320)   |
|           | `_subagent_codex_canonical_tools_with_mcp`          | `apply_host_remove` codex branch (≈1354)    |
|           | `_subagent_codex_set_tools_line`                    |                                             |
|           | `subagent_codex_extend_tools`                       |                                             |
|           | `subagent_codex_restore_tools`                      |                                             |
| copilot   | `_subagent_copilot_canonical_tools_base`            | inside `copilot_install_one` after merge    |
|           | `_subagent_copilot_canonical_tools_with_mcp`        | inside `copilot_remove_one` after del       |
|           | `_subagent_copilot_set_tools_line`                  |                                             |
|           | `subagent_copilot_extend_tools`                     |                                             |
|           | `subagent_copilot_restore_tools`                    |                                             |
| cursor    | `_subagent_cursor_canonical_tools_base`             | `apply_host_install` cursor branch (≈1319)  |
|           | `_subagent_cursor_canonical_tools_with_mcp`         | `apply_host_remove` cursor branch (≈1353)   |
|           | `_subagent_cursor_set_tools_line`                   |                                             |
|           | `subagent_cursor_extend_tools`                      |                                             |
|           | `subagent_cursor_restore_tools`                     |                                             |
| opencode  | `_subagent_opencode_canonical_tools_base`           | (host not yet wired for MCP — slot dormant) |
|           | `_subagent_opencode_canonical_tools_with_mcp`       |                                             |
|           | `_subagent_opencode_set_tools_line`                 |                                             |
|           | `subagent_opencode_extend_tools`                    |                                             |
|           | `subagent_opencode_restore_tools`                   |                                             |

**Bats test-case ID range reserved: SUB-7 .. SUB-30.**
- codex: SUB-7..SUB-12 (mirroring SUB-1..SUB-6)
- copilot: SUB-13..SUB-18
- cursor: SUB-19..SUB-24
- opencode: SUB-25..SUB-30

Reserving the IDs even with no fix today prevents collision if/when any
host's contract changes and an APIVR-Δ slot is opened later.

---

## Orchestration plan

### Slots required: 0

No APIVR-Δ implementation work is needed. This spec resolves to a
verdict-only artefact: the audit closes the question raised by the
"probably will do the same with other toolings" hypothesis with explicit
per-host evidence.

### If future audits flip a verdict

The orchestration template (recorded for future use):

- **Merge point:** all slots write to `commands/aci.sh` (single file).
- **Conflict avoidance:** each slot owns a distinct function namespace
  (table above) and a distinct branch inside `apply_host_install` /
  `apply_host_remove`. Multiple APIVR-Δ worktrees can run in parallel
  without colliding on common helpers because the helpers are
  per-host-prefixed.
- **Integration order:** alphabetical by host name (codex, copilot, cursor,
  opencode), serialised at merge time. Each PR is independently reviewable
  and ships an extension to `apply_host_install`/`apply_host_remove` plus
  a SUB-<N> test block.
- **Shared helpers (read-only across slots):** `_subagent_set_tools_line`
  is Claude-Code-specific (operates on flat-string `tools:`). Each new
  host gets its own `_set_tools_line` variant tailored to the host's
  frontmatter shape; the Claude Code helper is **not** generalised.
- **Branch convention:** `fix/aci-subagent-tools-<host>` (matches the
  repo's existing `fix/<scope>-<detail>` pattern).
- **Version bump:** patch-level on the implementing PR only (e.g. 1.2.3,
  1.2.4 …); roster bump in `Rynaro/eidolons` follows the same
  `fix/roster-atlas-<version>` flow described in CLAUDE.md.

---

## Validation gates

Even with zero implementation work, the spec itself must be reviewable.
The validation gates below apply to the spec artefact today; the
implementation gates apply if/when a future audit flips a verdict.

### Spec validation (today)

- [ ] All four host sections cite specific `install.sh` and/or `aci.sh`
      line references for their permission-model claim.
- [ ] No source files (`commands/aci.sh`, `install.sh`, `tests/aci.bats`)
      were modified by this spec.
- [ ] YAML manifest mirrors the markdown structure (host_audits[],
      implementation_contracts[], orchestration{}, validation_gates[]).

### Implementation validation (template, only if a future verdict flips)

- [ ] `bats tests/aci.bats` passes including new SUB-<N> cases.
- [ ] `shellcheck -x -S error commands/aci.sh` reports no errors.
- [ ] Two consecutive `aci install` runs produce byte-identical host files
      (idempotency).
- [ ] `aci remove` restores the installer-shipped baseline byte-for-byte.
- [ ] `--dry-run` emits `MODIFY <path>` for the host's subagent file and
      touches no disk state.
- [ ] Body of the host file (markdown content after frontmatter) is
      preserved byte-for-byte across install→remove cycle.
- [ ] No regressions in SUB-1..SUB-6 (Claude Code) or G5..G19 (container
      mode) or IDX-1..IDX-9 (index action).

---

## Out of scope

- **Behavioural change to Claude Code wiring.** PR 16 (1.2.2) is the
  authoritative implementation; this spec does not revisit it.
- **Reorganisation of `install.sh`.** Per-host wiring blocks
  (claude-code/copilot/cursor/opencode/codex) stay where they are.
- **Generalisation of `_subagent_set_tools_line` into a host-agnostic
  helper.** Each host's frontmatter shape is different enough that a
  parameterised helper would be premature; per-host variants stay
  isolated under their reserved namespaces.
- **opencode MCP wiring.** Tracked separately under §2.1 G2 in the
  governing aci.sh spec (aci.sh:526). Not this spec's concern.
- **Codex `tools:` field emission by `install.sh`.** Even if a future
  decision adds a `tools:` line to `.codex/agents/atlas.md`, that change
  belongs in install.sh's codex block (not aci.sh) and would be a new
  spec, not an aci.sh-side rewrite.
- **End-user hand-edits to `.codex/agents/atlas.md` adding a `tools:`
  field.** ATLAS's contract is "we manage what we author"; user-authored
  frontmatter fields are out of scope for aci.sh rewrites.

---

## References

- ATLAS PR 16 — Claude Code subagent tools allowlist fix (1.2.2 release).
- `commands/aci.sh:1229-1310` — Claude Code helpers (canonical reference shape).
- `commands/aci.sh:1313-1375` — `apply_host_install` / `apply_host_remove` dispatch.
- `install.sh:443-591` — per-host wiring blocks.
- `tests/aci.bats:911-1038` — SUB-1..SUB-6 (Claude Code subagent tools).
- `tests/helpers.bash:182-198` — `seed_claude_atlas_subagent` fixture pattern.
- Codex subagent contract: https://developers.openai.com/codex/subagents
  (cited in install.sh:537).
