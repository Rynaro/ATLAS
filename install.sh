#!/usr/bin/env bash
# ATLAS installer — EIIS v1.0 conformant
# Usage: bash install.sh [OPTIONS]
set -euo pipefail

EIDOLON_NAME="atlas"
EIDOLON_VERSION="1.0.0"
METHODOLOGY="ATLAS"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --------------------------------------------------------------------------- #
# Defaults
# --------------------------------------------------------------------------- #
TARGET="./.eidolons/${EIDOLON_NAME}"
HOSTS="auto"
FORCE=false
DRY_RUN=false
NON_INTERACTIVE=false
MANIFEST_ONLY=false

# --------------------------------------------------------------------------- #
# Help
# --------------------------------------------------------------------------- #
usage() {
  cat <<EOF
Usage: bash install.sh [OPTIONS]

Install the ATLAS v${EIDOLON_VERSION} read-only codebase scout methodology
into the current consumer project.

Options:
  --target DIR          Target install dir (default: ${TARGET})
  --hosts LIST          claude-code,copilot,cursor,opencode,all (default: auto)
  --force               Overwrite existing install without prompting
  --dry-run             Print actions without writing any files
  --non-interactive     No prompts; fail on ambiguity (meta-installer mode)
  --manifest-only       Only emit install.manifest.json (no file copies)
  --version             Print Eidolon version and exit
  -h, --help            Show this help and exit

Host detection (--hosts auto):
  claude-code   detected if CLAUDE.md or .claude/ exists
  copilot       detected if .github/ exists
  cursor        detected if .cursor/ or .cursorrules exists
  opencode      detected if .opencode/ exists

Examples:
  bash install.sh
  bash install.sh --target ./vendor/atlas --hosts claude-code,copilot
  bash install.sh --dry-run
  bash install.sh --non-interactive --force
EOF
}

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)           TARGET="$2"; shift 2 ;;
    --hosts)            HOSTS="$2"; shift 2 ;;
    --force)            FORCE=true; shift ;;
    --dry-run)          DRY_RUN=true; shift ;;
    --non-interactive)  NON_INTERACTIVE=true; shift ;;
    --manifest-only)    MANIFEST_ONLY=true; shift ;;
    --version)          echo "${EIDOLON_VERSION}"; exit 0 ;;
    -h|--help)          usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# --------------------------------------------------------------------------- #
# Utilities
# --------------------------------------------------------------------------- #
log()  { echo "[atlas] $*"; }
warn() { echo "[atlas] WARN: $*" >&2; }

do_action() {
  # do_action <description> <command...>
  local desc="$1"; shift
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [dry-run] ${desc}"
  else
    "$@"
  fi
}

sha256_file() {
  local f="$1"
  if command -v shasum &>/dev/null; then
    shasum -a 256 "$f" | awk '{print $1}'
  elif command -v sha256sum &>/dev/null; then
    sha256sum "$f" | awk '{print $1}'
  elif command -v openssl &>/dev/null; then
    openssl dgst -sha256 "$f" | awk '{print $NF}'
  else
    echo "0000000000000000000000000000000000000000000000000000000000000000"
  fi
}

# --------------------------------------------------------------------------- #
# Host detection
# --------------------------------------------------------------------------- #
detect_hosts() {
  local detected=()
  [[ -f "CLAUDE.md" || -d ".claude" ]]              && detected+=("claude-code")
  [[ -d ".github" ]]                                 && detected+=("copilot")
  [[ -d ".cursor" || -f ".cursorrules" ]]            && detected+=("cursor")
  [[ -d ".opencode" ]]                               && detected+=("opencode")
  printf "%s\n" "${detected[@]:-}"
}

if [[ "$HOSTS" == "auto" ]]; then
  HOSTS_ARRAY=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && HOSTS_ARRAY+=("$line")
  done < <(detect_hosts)
  if [[ ${#HOSTS_ARRAY[@]} -eq 0 ]]; then
    warn "No host config directories detected. Using raw install only."
    HOSTS_ARRAY=("raw")
  fi
elif [[ "$HOSTS" == "all" ]]; then
  HOSTS_ARRAY=("claude-code" "copilot" "cursor" "opencode")
else
  IFS=',' read -ra HOSTS_ARRAY <<< "$HOSTS"
fi

hosts_include() { local h; for h in "${HOSTS_ARRAY[@]}"; do [[ "$h" == "$1" ]] && return 0; done; return 1; }

# --------------------------------------------------------------------------- #
# Idempotency check
# --------------------------------------------------------------------------- #
EXISTING_MANIFEST="${TARGET}/install.manifest.json"
if [[ -f "$EXISTING_MANIFEST" && "$FORCE" != "true" ]]; then
  EXISTING_VER=$(grep -o '"version":"[^"]*"' "$EXISTING_MANIFEST" 2>/dev/null | head -1 | cut -d'"' -f4 || echo "unknown")
  if [[ "$EXISTING_VER" == "$EIDOLON_VERSION" ]]; then
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
      echo "Already installed v${EXISTING_VER} at ${TARGET}. Pass --force to overwrite." >&2
      exit 3
    fi
    read -rp "[atlas] Already installed v${EXISTING_VER} at ${TARGET}. Overwrite? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
  fi
fi

# --------------------------------------------------------------------------- #
# Announce
# --------------------------------------------------------------------------- #
log "Installing ATLAS v${EIDOLON_VERSION} → ${TARGET}"
log "Hosts: ${HOSTS_ARRAY[*]}"
[[ "$DRY_RUN" == "true" ]]          && log "Mode: dry-run (no files written)"
[[ "$MANIFEST_ONLY" == "true" ]]    && log "Mode: manifest-only"

# --------------------------------------------------------------------------- #
# Directory creation
# --------------------------------------------------------------------------- #
FILES_WRITTEN=()   # accumulate manifest entries as JSON strings

maybe_mkdir() {
  local dir="$1"
  do_action "mkdir -p ${dir}" mkdir -p "${dir}"
}

maybe_mkdir "${TARGET}"
maybe_mkdir "${TARGET}/skills/traverse"
maybe_mkdir "${TARGET}/skills/locate"
maybe_mkdir "${TARGET}/skills/abstract"
maybe_mkdir "${TARGET}/skills/synthesize"
maybe_mkdir "${TARGET}/templates"
maybe_mkdir "${TARGET}/schemas"
maybe_mkdir "${TARGET}/evals"
maybe_mkdir "${TARGET}/.github"

# --------------------------------------------------------------------------- #
# Copy methodology files
# --------------------------------------------------------------------------- #
copy_file() {
  local src="$1" dst="$2" role="$3"
  do_action "copy ${src} → ${dst}" cp "${SCRIPT_DIR}/${src}" "${dst}"
  if [[ "$DRY_RUN" != "true" ]]; then
    local chk; chk=$(sha256_file "${dst}")
    FILES_WRITTEN+=("{\"path\":\"${dst}\",\"sha256\":\"${chk}\",\"role\":\"${role}\",\"mode\":\"created\"}")
  fi
}

if [[ "$MANIFEST_ONLY" != "true" ]]; then
  copy_file "agent.md"                                  "${TARGET}/agent.md"                          "entry-point"
  copy_file "ATLAS.md"                                  "${TARGET}/ATLAS.md"                          "spec"
  copy_file "AGENTS.md"                                 "${TARGET}/AGENTS.md"                         "entry-point"
  copy_file "skills/traverse/SKILL.md"                  "${TARGET}/skills/traverse/SKILL.md"          "skill"
  copy_file "skills/locate/SKILL.md"                    "${TARGET}/skills/locate/SKILL.md"            "skill"
  copy_file "skills/abstract/SKILL.md"                  "${TARGET}/skills/abstract/SKILL.md"          "skill"
  copy_file "skills/synthesize/SKILL.md"                "${TARGET}/skills/synthesize/SKILL.md"        "skill"
  copy_file "templates/mission-brief.md"                "${TARGET}/templates/mission-brief.md"        "template"
  copy_file "templates/traversal-map.md"                "${TARGET}/templates/traversal-map.md"        "template"
  copy_file "templates/findings.md"                     "${TARGET}/templates/findings.md"             "template"
  copy_file "templates/scout-report.md"                 "${TARGET}/templates/scout-report.md"         "template"
  copy_file "schemas/mission-brief.v1.json"             "${TARGET}/schemas/mission-brief.v1.json"     "other"
  copy_file "schemas/findings.v1.json"                  "${TARGET}/schemas/findings.v1.json"          "other"
  copy_file "schemas/scout-report.v1.json"              "${TARGET}/schemas/scout-report.v1.json"      "other"
  copy_file "schemas/install.manifest.v1.json"          "${TARGET}/schemas/install.manifest.v1.json"  "other"
  copy_file "evals/canary-missions.md"                  "${TARGET}/evals/canary-missions.md"          "other"
  copy_file ".github/copilot-instructions.md"           "${TARGET}/.github/copilot-instructions.md"   "dispatch"
fi

# --------------------------------------------------------------------------- #
# Host dispatch files
# --------------------------------------------------------------------------- #
append_or_create() {
  local dst="$1" content="$2" role="$3"
  if [[ "$DRY_RUN" == "true" ]]; then
    local mode="created"
    [[ -f "$dst" ]] && mode="appended"
    echo "  [dry-run] ${mode} ${dst}"
    return
  fi
  local mode="created"
  if [[ -f "$dst" ]]; then
    # Only append if our marker is not already present
    if grep -qF "<!-- atlas-eiis-dispatch -->" "$dst" 2>/dev/null; then
      log "  skip (already dispatched): ${dst}"
      return
    fi
    mode="appended"
    printf "\n%s\n" "$content" >> "$dst"
  else
    mkdir -p "$(dirname "$dst")"
    printf "%s\n" "$content" > "$dst"
  fi
  local chk; chk=$(sha256_file "$dst")
  FILES_WRITTEN+=("{\"path\":\"${dst}\",\"sha256\":\"${chk}\",\"role\":\"${role}\",\"mode\":\"${mode}\"}")
}

# ---- claude-code ---------------------------------------------------------- #
if hosts_include "claude-code" && [[ "$MANIFEST_ONLY" != "true" ]]; then
  log "Wiring: claude-code"

  CLAUDE_BLOCK="<!-- atlas-eiis-dispatch -->
## ATLAS methodology

This project runs under the **ATLAS v${EIDOLON_VERSION}** read-only scout methodology.
See \`${TARGET}/agent.md\` for the always-loaded agent profile and
\`${TARGET}/AGENTS.md\` for the full rule set.
Skills live in \`${TARGET}/skills/<phase>/SKILL.md\` and load progressively per phase.

**Absolute rules (P0):**
- Read-only: refuse edit/write/commit/deploy/migrate/refactor/fix.
- Mission-first: no exploration without \`mission.md\` + \`DECISION_TARGET\`.
- Evidence-anchored claims: every fact carries \`path:line_start-line_end\` + H|M|L."

  append_or_create "CLAUDE.md" "$CLAUDE_BLOCK" "dispatch"

  # Wire skills
  do_action "mkdir -p .claude/skills" mkdir -p ".claude/skills"
  for phase in traverse locate abstract synthesize; do
    do_action "wire skill ${phase}" ln -sf "../../${TARGET}/skills/${phase}" ".claude/skills/atlas-${phase}" 2>/dev/null || true
  done

  # Wire subagent
  do_action "mkdir -p .claude/agents" mkdir -p ".claude/agents"

  AGENT_CONTENT="---
name: atlas
description: Read-only codebase scout and Plan-Mode methodology. Use when the user asks \"where is X\", \"how does Y work\", \"trace the flow of Z\", \"audit Q\", or any exploratory / pre-planning question. Runs the five-phase ATLAS pipeline (Assess → Traverse → Locate → Abstract → Synthesize) and emits a scout-report.md. Refuses write verbs (edit, fix, refactor, migrate, deploy) and hands off to SPECTRA or APIVR-Δ.
when_to_use: Any codebase exploration, impact analysis, or scout mission; before SPECTRA (spec) or APIVR-Δ (implementation); when the user asks for \"plan mode\" or a decision-ready summary of an unfamiliar area.
tools: Read, Grep, Glob, Bash(rg:*), Bash(git log:*), Bash(git show:*)
methodology: ATLAS
methodology_version: \"1.0\"
role: Explorer/Scout — read-only codebase intelligence
handoffs: [spectra, apivr]
---

# ATLAS — Explorer/Scout Agent

You execute the ATLAS methodology: **A**ssess → **T**raverse → **L**ocate →
**A**bstract → **S**ynthesize. You are **read-only**. If asked to mutate
anything, hand off. Full spec: \`${TARGET}/ATLAS.md\`.

See \`${TARGET}/agent.md\` for the full P0 rules and progressive disclosure table."

  if [[ "$DRY_RUN" != "true" ]]; then
    printf "%s\n" "$AGENT_CONTENT" > ".claude/agents/atlas.md"
    chk=$(sha256_file ".claude/agents/atlas.md")
    FILES_WRITTEN+=("{\"path\":\".claude/agents/atlas.md\",\"sha256\":\"${chk}\",\"role\":\"dispatch\",\"mode\":\"created\"}")
  else
    echo "  [dry-run] created .claude/agents/atlas.md"
  fi
fi

# ---- copilot -------------------------------------------------------------- #
if hosts_include "copilot" && [[ "$MANIFEST_ONLY" != "true" ]]; then
  log "Wiring: copilot"
  do_action "mkdir -p .github" mkdir -p ".github"

  COPILOT_CONTENT="<!-- atlas-eiis-dispatch -->
# GitHub Copilot — ATLAS methodology

> This file is the primary custom-instructions entry for GitHub Copilot.
> The authoritative rule set is \`${TARGET}/AGENTS.md\`.

See \`${TARGET}/AGENTS.md\` for the full ATLAS rule set and
\`${TARGET}/ATLAS.md\` for the v${EIDOLON_VERSION} specification.

## Non-negotiable rules

1. **Read-only.** Refuse \`edit\`, \`write\`, \`commit\`, \`deploy\`, \`migrate\`, \`refactor\`, \`fix\`. Hand off.
2. **Mission-first.** No exploration without \`mission.md\` + \`DECISION_TARGET\`.
3. **Bounded ACI.** \`view_file\` ≤100 lines; \`search_text\` ≤50 matches; \`list_dir\` ≤200 entries.
4. **Evidence-anchored claims.** Every fact carries \`path:line_start-line_end\` + H|M|L.
5. **Deterministic-first retrieval.** Symbol index → code graph → rg → AST. LLM search is last resort."

  append_or_create ".github/copilot-instructions.md" "$COPILOT_CONTENT" "dispatch"

  # Root-level AGENTS.md pointer
  if [[ ! -f "AGENTS.md" ]]; then
    do_action "create AGENTS.md → symlink to ${TARGET}/AGENTS.md" \
      ln -sf "${TARGET}/AGENTS.md" "AGENTS.md"
    if [[ "$DRY_RUN" != "true" ]]; then
      chk=$(sha256_file "${TARGET}/AGENTS.md")
      FILES_WRITTEN+=("{\"path\":\"AGENTS.md\",\"sha256\":\"${chk}\",\"role\":\"dispatch\",\"mode\":\"created\"}")
    fi
  fi
fi

# ---- cursor --------------------------------------------------------------- #
if hosts_include "cursor" && [[ "$MANIFEST_ONLY" != "true" ]]; then
  log "Wiring: cursor"
  do_action "mkdir -p .cursor/rules" mkdir -p ".cursor/rules"

  CURSOR_MDC="---
description: ATLAS v${EIDOLON_VERSION} — read-only codebase scout. Always applied. Refuses write verbs; requires mission.md with DECISION_TARGET; bounded ACI; evidence-anchored claims.
alwaysApply: true
---

<!-- atlas-eiis-dispatch -->
See \`${TARGET}/AGENTS.md\` for the full rule set and \`${TARGET}/ATLAS.md\` for the spec.

Phases: A (Assess) → T (Traverse, @atlas-traverse) → L (Locate, @atlas-locate) → A (Abstract, @atlas-abstract) → S (Synthesize, @atlas-synthesize)"

  append_or_create ".cursor/rules/atlas.mdc" "$CURSOR_MDC" "dispatch"

  # Root-level AGENTS.md
  if [[ ! -f "AGENTS.md" ]]; then
    do_action "symlink AGENTS.md" ln -sf "${TARGET}/AGENTS.md" "AGENTS.md"
    if [[ "$DRY_RUN" != "true" ]]; then
      chk=$(sha256_file "${TARGET}/AGENTS.md")
      FILES_WRITTEN+=("{\"path\":\"AGENTS.md\",\"sha256\":\"${chk}\",\"role\":\"dispatch\",\"mode\":\"created\"}")
    fi
  fi
fi

# ---- opencode ------------------------------------------------------------- #
if hosts_include "opencode" && [[ "$MANIFEST_ONLY" != "true" ]]; then
  log "Wiring: opencode"
  do_action "mkdir -p .opencode/agents" mkdir -p ".opencode/agents"

  OPENCODE_AGENT="---
description: Read-only codebase scout running the ATLAS v${EIDOLON_VERSION} five-phase pipeline. Refuses write verbs.
mode: primary
permission:
  edit: deny
  write: deny
  bash:
    \"rg *\": allow
    \"git log *\": allow
    \"git show *\": allow
    \"*\": deny
---

<!-- atlas-eiis-dispatch -->
You are the ATLAS explorer/scout agent. Full rules: \`${TARGET}/AGENTS.md\`.
Always-loaded profile: \`${TARGET}/agent.md\`.
Phase skills: \`${TARGET}/skills/<phase>/SKILL.md\` — load only the active phase.
Full spec: \`${TARGET}/ATLAS.md\`."

  append_or_create ".opencode/agents/atlas.md" "$OPENCODE_AGENT" "dispatch"

  # Root-level AGENTS.md
  if [[ ! -f "AGENTS.md" ]]; then
    do_action "symlink AGENTS.md" ln -sf "${TARGET}/AGENTS.md" "AGENTS.md"
    if [[ "$DRY_RUN" != "true" ]]; then
      chk=$(sha256_file "${TARGET}/AGENTS.md")
      FILES_WRITTEN+=("{\"path\":\"AGENTS.md\",\"sha256\":\"${chk}\",\"role\":\"dispatch\",\"mode\":\"created\"}")
    fi
  fi
fi

# --------------------------------------------------------------------------- #
# Token measurement
# --------------------------------------------------------------------------- #
AGENT_MD_PATH="${TARGET}/agent.md"
if [[ "$DRY_RUN" != "true" && -f "$AGENT_MD_PATH" ]]; then
  WORD_COUNT=$(wc -w < "$AGENT_MD_PATH")
  AGENT_TOKENS=$(awk "BEGIN {printf \"%d\", ${WORD_COUNT}/0.75}")
else
  # Measure from source when dry-run
  WORD_COUNT=$(wc -w < "${SCRIPT_DIR}/agent.md")
  AGENT_TOKENS=$(awk "BEGIN {printf \"%d\", ${WORD_COUNT}/0.75}")
fi

if [[ "$AGENT_TOKENS" -gt 1000 ]]; then
  warn "agent.md exceeds 1000-token budget (estimated ${AGENT_TOKENS} tokens)."
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    echo "Error: agent.md token budget exceeded in --non-interactive mode." >&2
    exit 4
  fi
fi

# --------------------------------------------------------------------------- #
# Write install.manifest.json
# --------------------------------------------------------------------------- #
INSTALLED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")"
HOSTS_JSON="$(printf '"%s",' "${HOSTS_ARRAY[@]}" | sed 's/,$//')"

FILES_JSON=""
if [[ ${#FILES_WRITTEN[@]} -gt 0 ]]; then
  FILES_JSON="$(printf '%s,' "${FILES_WRITTEN[@]}" | sed 's/,$//')"
fi

MANIFEST_CONTENT="{
  \"eidolon\": \"${EIDOLON_NAME}\",
  \"version\": \"${EIDOLON_VERSION}\",
  \"methodology\": \"${METHODOLOGY}\",
  \"installed_at\": \"${INSTALLED_AT}\",
  \"target\": \"${TARGET}\",
  \"hosts_wired\": [${HOSTS_JSON}],
  \"files_written\": [${FILES_JSON}],
  \"handoffs_declared\": {
    \"upstream\": [],
    \"downstream\": [\"spectra\", \"apivr-delta\"]
  },
  \"token_budget\": {
    \"entry\": ${AGENT_TOKENS},
    \"working_set_target\": 1000
  },
  \"security\": {
    \"reads_repo\": true,
    \"reads_network\": false,
    \"writes_repo\": false,
    \"persists\": [\".atlas/.memex\"]
  }
}"

MANIFEST_PATH="${TARGET}/install.manifest.json"
do_action "write ${MANIFEST_PATH}" bash -c "printf '%s\n' '${MANIFEST_CONTENT//\'/\'\\\'\'}' > '${MANIFEST_PATH}'"

if [[ "$DRY_RUN" != "true" ]]; then
  # Write cleanly without shell escaping issues
  cat > "${MANIFEST_PATH}" <<MANIFEST_EOF
{
  "eidolon": "${EIDOLON_NAME}",
  "version": "${EIDOLON_VERSION}",
  "methodology": "${METHODOLOGY}",
  "installed_at": "${INSTALLED_AT}",
  "target": "${TARGET}",
  "hosts_wired": [${HOSTS_JSON}],
  "files_written": [${FILES_JSON}],
  "handoffs_declared": {
    "upstream": [],
    "downstream": ["spectra", "apivr-delta"]
  },
  "token_budget": {
    "entry": ${AGENT_TOKENS},
    "working_set_target": 1000
  },
  "security": {
    "reads_repo": true,
    "reads_network": false,
    "writes_repo": false,
    "persists": [".atlas/.memex"]
  }
}
MANIFEST_EOF
  log "Manifest: ${MANIFEST_PATH}"
fi

# --------------------------------------------------------------------------- #
# Success banner
# --------------------------------------------------------------------------- #
echo ""
echo "✓ ATLAS v${EIDOLON_VERSION} installed → ${TARGET}"
echo "✓ agent.md: ${AGENT_TOKENS} tokens (budget: ≤1000)"
echo "✓ Hosts wired: ${HOSTS_ARRAY[*]}"
echo ""
echo "Smoke test — paste this into your AI host:"
echo "─────────────────────────────────────────────────────────────────────────"
echo "Under ATLAS, answer the following DECISION_TARGET: \"List every public"
echo "HTTP endpoint in this repository and identify the single controller"
echo "action that handles each.\" Use scope **/* and a budget of 30 tool calls."
echo "Emit mission.md first, then run Traverse, then Locate, then Synthesize."
echo "─────────────────────────────────────────────────────────────────────────"
echo ""
echo "Expected: agent emits mission.md before any search, then map.md, then"
echo "findings.md with FINDING-XXX IDs and path:line anchors, then"
echo "scout-report.md ≤3000 tokens with → SPECTRA / → APIVR-Δ handoff labels."
echo ""
echo "Full install guide: ${TARGET}/INSTALL.md (if copied) or the source INSTALL.md"
echo "Per-host wiring:    ${TARGET}/hosts/<host>.md (if copied) or source hosts/"
