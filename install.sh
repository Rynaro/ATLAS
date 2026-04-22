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
# upsert_eidolon_block <file> <content_literal> <role>
#
# Owns a marker-bounded region in a composable dispatch file (CLAUDE.md,
# AGENTS.md, .github/copilot-instructions.md). If the region already exists,
# rewrites its body in place. Otherwise appends a new block. Cleans up any
# pre-existing symlink at the target path (legacy ATLAS installer wiring).
upsert_eidolon_block() {
  local dst="$1" content="$2" role="$3"
  local start="<!-- eidolon:${EIDOLON_NAME} start -->"
  local end="<!-- eidolon:${EIDOLON_NAME} end -->"

  if [[ "$DRY_RUN" == "true" ]]; then
    local action="append"
    [[ -f "$dst" ]] && grep -qF "$start" "$dst" 2>/dev/null && action="rewrite"
    echo "  [dry-run] ${action} eidolon:${EIDOLON_NAME} block in ${dst}"
    return
  fi

  mkdir -p "$(dirname "$dst")" 2>/dev/null || true

  # Legacy cleanup: some earlier installers symlinked root AGENTS.md.
  # Convert symlink → real file before upserting.
  if [[ -L "$dst" ]]; then
    rm -f "$dst"
  fi

  local content_file mode tmp
  content_file="$(mktemp)"
  printf '%s\n' "$content" > "$content_file"

  if [[ -f "$dst" ]] && grep -qF "$start" "$dst" 2>/dev/null; then
    mode="rewritten"
    tmp="$(mktemp)"
    awk -v start="$start" -v end="$end" -v cf="$content_file" '
      BEGIN { in_block = 0 }
      $0 == start {
        print start
        while ((getline line < cf) > 0) print line
        close(cf)
        in_block = 1
        next
      }
      $0 == end {
        print end
        in_block = 0
        next
      }
      !in_block { print }
    ' "$dst" > "$tmp"
    mv "$tmp" "$dst"
  elif [[ -f "$dst" ]]; then
    mode="appended"
    {
      printf '\n%s\n' "$start"
      cat "$content_file"
      printf '%s\n' "$end"
    } >> "$dst"
  else
    mode="created"
    {
      printf '%s\n' "$start"
      cat "$content_file"
      printf '%s\n' "$end"
    } > "$dst"
  fi

  rm -f "$content_file"

  local chk; chk=$(sha256_file "$dst")
  FILES_WRITTEN+=("{\"path\":\"${dst}\",\"sha256\":\"${chk}\",\"role\":\"${role}\",\"mode\":\"${mode}\"}")
}

# --------------------------------------------------------------------------- #
# Shared dispatch block (identical content in CLAUDE.md / AGENTS.md /
# .github/copilot-instructions.md — composable, every Eidolon emits its own
# marker-bounded section).
# --------------------------------------------------------------------------- #
SHARED_BLOCK="## ATLAS — Read-only codebase scout (v${EIDOLON_VERSION})

Entry:     \`${TARGET}/agent.md\`
Full spec: \`${TARGET}/ATLAS.md\`
Cycle:     A (Assess) → T (Traverse) → L (Locate) → A (Abstract) → S (Synthesize)

**P0 (non-negotiable):** read-only (refuse edit/write/commit/deploy/migrate/refactor/fix); mission-first (requires \`mission.md\` + \`DECISION_TARGET\`); bounded ACI (\`view_file\` ≤100, \`search_text\` ≤50, \`list_dir\` ≤200); evidence-anchored claims (\`path:line\` + H|M|L); deterministic retrieval first, LLM search last."

# Emit the shared block to the open-standard AGENTS.md unconditionally —
# it is the host-agnostic root dispatch file and is read by GitHub Copilot,
# Cursor, OpenCode, and any host implementing the agents.md standard.
if [[ "$MANIFEST_ONLY" != "true" ]]; then
  upsert_eidolon_block "AGENTS.md" "$SHARED_BLOCK" "dispatch"
fi

# ---- claude-code ---------------------------------------------------------- #
if hosts_include "claude-code" && [[ "$MANIFEST_ONLY" != "true" ]]; then
  log "Wiring: claude-code"

  upsert_eidolon_block "CLAUDE.md" "$SHARED_BLOCK" "dispatch"

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
  upsert_eidolon_block ".github/copilot-instructions.md" "$SHARED_BLOCK" "dispatch"
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

  # .cursor/rules/atlas.mdc is owned by this Eidolon (one file per Eidolon);
  # overwrite when --force, skip otherwise.
  if [[ ! -f ".cursor/rules/atlas.mdc" || "$FORCE" == "true" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "  [dry-run] write .cursor/rules/atlas.mdc"
    else
      printf "%s\n" "$CURSOR_MDC" > ".cursor/rules/atlas.mdc"
      chk=$(sha256_file ".cursor/rules/atlas.mdc")
      FILES_WRITTEN+=("{\"path\":\".cursor/rules/atlas.mdc\",\"sha256\":\"${chk}\",\"role\":\"dispatch\",\"mode\":\"created\"}")
    fi
  else
    log "  skip .cursor/rules/atlas.mdc (exists — pass --force to overwrite)"
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

  # .opencode/agents/atlas.md is owned by this Eidolon; overwrite on --force.
  if [[ ! -f ".opencode/agents/atlas.md" || "$FORCE" == "true" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "  [dry-run] write .opencode/agents/atlas.md"
    else
      printf "%s\n" "$OPENCODE_AGENT" > ".opencode/agents/atlas.md"
      chk=$(sha256_file ".opencode/agents/atlas.md")
      FILES_WRITTEN+=("{\"path\":\".opencode/agents/atlas.md\",\"sha256\":\"${chk}\",\"role\":\"dispatch\",\"mode\":\"created\"}")
    fi
  else
    log "  skip .opencode/agents/atlas.md (exists — pass --force to overwrite)"
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
