#!/usr/bin/env bash
# ATLAS installer — EIIS v1.4 conformant
# Usage: bash install.sh [OPTIONS]
set -euo pipefail

EIDOLON_NAME="atlas"
EIDOLON_SLUG="atlas"
EIDOLON_VERSION="1.10.0"
METHODOLOGY="ATLAS"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Legacy artefacts swept by cleanup_legacy_v1_2 on upgrade (belt-and-braces,
# in addition to the manifest-driven canonical_inventory_sweep at install-end).
# Basenames of spec/doc files that lived at ${TARGET}/<name> in prior installs.
LEGACY_SPEC_FILES=( "ATLAS.md" "AGENTS.md" )
# Skill directory names that existed as ${TARGET}/skills/<name>/ subdirs in v1.2.
LEGACY_SKILL_DIRS=( \
  "abstract" \
  "locate" \
  "synthesize" \
  "traverse" \
)

# ECL_VERSION — read from repo-root ECL_VERSION file if present.
# The field is omitted from the manifest when the file is absent.
ECL_VERSION_FILE="${SCRIPT_DIR}/ECL_VERSION"
ECL_VERSION_EMITTED=""
if [[ -f "$ECL_VERSION_FILE" ]]; then
  ECL_VERSION_EMITTED="$(tr -d '[:space:]' < "$ECL_VERSION_FILE")"
fi

# --------------------------------------------------------------------------- #
# Defaults
# --------------------------------------------------------------------------- #
TARGET="./.eidolons/${EIDOLON_NAME}"
HOSTS="auto"
FORCE=false
DRY_RUN=false
NON_INTERACTIVE=false
MANIFEST_ONLY=false
SHARED_DISPATCH=false

# --------------------------------------------------------------------------- #
# Help
# --------------------------------------------------------------------------- #
usage() {
  cat <<EOF
Usage: bash install.sh [OPTIONS]

Install the ATLAS v${EIDOLON_VERSION} read-only codebase scout methodology
into the current consumer project.

Options:
  --target DIR            Target install dir (default: ${TARGET})
  --hosts LIST            claude-code,copilot,cursor,opencode,codex,all
                          (default: auto)
  --shared-dispatch       Compose marker-bounded section in root AGENTS.md /
                          CLAUDE.md / .github/copilot-instructions.md (opt-in).
  --no-shared-dispatch    Skip root dispatch files (default). Per-vendor files
                          under .claude/, .github/, .cursor/, .opencode/,
                          .codex/ are always written and are self-sufficient.
                          NB: when 'codex' is wired, root AGENTS.md is still
                          written (Codex's primary instruction surface — EIIS
                          v1.1 §4.1.0); a warning is emitted to stderr.
  --force                 Overwrite existing install without prompting
  --dry-run               Print actions without writing any files
  --non-interactive       No prompts; fail on ambiguity (meta-installer mode)
  --manifest-only         Only emit install.manifest.json (no file copies)
  --version               Print Eidolon version and exit
  -h, --help              Show this help and exit

Host detection (--hosts auto):
  claude-code   detected if CLAUDE.md or .claude/ exists
  copilot       detected if .github/ exists
  cursor        detected if .cursor/ or .cursorrules exists
  opencode      detected if .opencode/ exists
  codex         detected if .codex/ exists, or if AGENTS.md exists at the
                cwd root with no .github/ and no .codex/ (Codex's canonical
                project-instruction file per EIIS v1.1 §4.1.0)

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
    --target)               TARGET="$2"; shift 2 ;;
    --hosts)                HOSTS="$2"; shift 2 ;;
    --shared-dispatch)      SHARED_DISPATCH=true; shift ;;
    --no-shared-dispatch)   SHARED_DISPATCH=false; shift ;;
    --force)                FORCE=true; shift ;;
    --dry-run)              DRY_RUN=true; shift ;;
    --non-interactive)      NON_INTERACTIVE=true; shift ;;
    --manifest-only)        MANIFEST_ONLY=true; shift ;;
    --version)              echo "${EIDOLON_VERSION}"; exit 0 ;;
    -h|--help)              usage; exit 0 ;;
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

# cleanup_legacy_v1_2 <target>
#
# Sweep legacy v1.2-era artefacts left behind by prior installs.
# Called exactly once, early in the install sequence, BEFORE any new content
# is written under <target>. Idempotent: no-op when no legacy file exists.
#
# Reads two top-of-file arrays:
#   LEGACY_SPEC_FILES  — basenames to rm -f at "<target>/<basename>"
#   LEGACY_SKILL_DIRS  — skill names to rm -rf at "<target>/skills/<name>"
#
# Both arrays are declared per-Eidolon and MAY be empty (in which case
# the corresponding loop is a no-op). Never reads/writes outside <target>.
cleanup_legacy_v1_2() {
  local target="$1"
  local legacy
  local legacy_skill_dir

  if [ -z "${target}" ] || [ ! -d "${target}" ]; then
    return 0
  fi

  # Sweep legacy spec filenames (e.g. ATLAS.md, apivr.md, ...)
  for legacy in "${LEGACY_SPEC_FILES[@]}"; do
    if [ -n "${legacy}" ] && [ -f "${target}/${legacy}" ]; then
      rm -f "${target}/${legacy}"
      warn "swept legacy spec file: ${target}/${legacy}"
    fi
  done

  # Sweep legacy subdir-style skills (e.g. skills/traverse/SKILL.md)
  for legacy_skill_dir in "${LEGACY_SKILL_DIRS[@]}"; do
    if [ -n "${legacy_skill_dir}" ] && [ -d "${target}/skills/${legacy_skill_dir}" ]; then
      rm -rf "${target}/skills/${legacy_skill_dir}"
      warn "swept legacy skill subdir: ${target}/skills/${legacy_skill_dir}"
    fi
  done

  return 0
}

# canonical_inventory_sweep <target>
#
# EIIS v1.4 §6.X — manifest-driven install-target cleanup.
# Called AFTER all writes are complete (but before the manifest is finalised).
# Removes any file under <target>/ that is NOT in the current run's
# FILES_WRITTEN array (i.e. not whitelisted by the write pass). Also prunes
# empty directories. Idempotent: safe to call on fresh or upgrade installs.
# Bash 3.2 compatible (no associative arrays; uses string-search).
canonical_inventory_sweep() {
  local target="$1"

  if [ -z "${target}" ] || [ ! -d "${target}" ]; then
    return 0
  fi

  # Build a newline-delimited list of allowed absolute paths from FILES_WRITTEN.
  local allowed=""
  local entry path_raw abs_path
  for entry in "${FILES_WRITTEN[@]+"${FILES_WRITTEN[@]}"}"; do
    # Extract the "path":"..." value from the JSON object string.
    path_raw="$(printf '%s' "$entry" | grep -o '"path":"[^"]*"' | head -n1 | sed 's/"path":"//;s/"//')"
    if [ -n "$path_raw" ]; then
      # Resolve to absolute path (strip leading ./ if present).
      abs_path="${path_raw#./}"
      # Keep only paths that are under the target directory.
      case "$abs_path" in
        "${target#./}/"*|"${target}/"*)
          allowed="${allowed}${path_raw}"$'\n'
          ;;
      esac
    fi
  done

  # Walk every file under target; remove anything not in allowed set.
  while IFS= read -r disk_file; do
    [ -z "$disk_file" ] && continue
    local found=0
    local a
    while IFS= read -r a; do
      [ -z "$a" ] && continue
      local abs_a="${a#./}"
      local abs_d="${disk_file#./}"
      if [ "$abs_a" = "$abs_d" ]; then
        found=1
        break
      fi
    done <<EOF_ALLOWED
$allowed
EOF_ALLOWED
    if [ "$found" -eq 0 ]; then
      rm -f "$disk_file"
      warn "canonical_inventory_sweep: removed non-whitelisted file: ${disk_file}"
    fi
  done < <(find "${target}" -type f 2>/dev/null)

  # Prune empty directories (safe; never touches parent of <target>).
  find "${target}" -type d -empty -delete 2>/dev/null || true

  return 0
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
  # Codex (EIIS v1.1 §4.1.0): .codex/ is the definitive Codex-only signal.
  # AGENTS.md alone (no .github/, no .codex/) also indicates a Codex-only
  # project; when both AGENTS.md and .github/ are present they co-own the
  # file and copilot is detected via .github/ above.
  [[ -d ".codex" ]]                                  && detected+=("codex")
  if [[ -f "AGENTS.md" && ! -d ".github" && ! -d ".codex" ]]; then
    detected+=("codex")
  fi
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
  HOSTS_ARRAY=("claude-code" "copilot" "cursor" "opencode" "codex")
else
  IFS=',' read -ra HOSTS_ARRAY <<< "$HOSTS"
fi

hosts_include() { local h; for h in "${HOSTS_ARRAY[@]}"; do [[ "$h" == "$1" ]] && return 0; done; return 1; }

# EIIS v1.1 §4.1.0 — root AGENTS.md is Codex's primary instruction surface.
# When 'codex' is wired, the marker-bounded block MUST be written even if
# the user passed --no-shared-dispatch. Emit a warning so the override is
# visible; honour --shared-dispatch/--no-shared-dispatch faithfully for the
# other hosts (CLAUDE.md, .github/copilot-instructions.md).
SHARED_DISPATCH_AGENTS_MD=$SHARED_DISPATCH
if hosts_include "codex" && [[ "$SHARED_DISPATCH" != "true" ]]; then
  warn "--no-shared-dispatch ignored for AGENTS.md when hosts include codex; AGENTS.md is Codex's primary instruction surface (EIIS v1.1 §4.1.0)."
  SHARED_DISPATCH_AGENTS_MD=true
fi

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
maybe_mkdir "${TARGET}/commands"
maybe_mkdir "${TARGET}/skills"
maybe_mkdir "${TARGET}/templates"
maybe_mkdir "${TARGET}/schemas"

# Sweep legacy artefacts before writing any new content.
cleanup_legacy_v1_2 "${TARGET}"

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
  # D1: agent.md (role: agent-profile) and SPEC.md (role: spec) — EIIS v1.4 §1.8.6
  copy_file "agent.md"                                  "${TARGET}/agent.md"                          "agent-profile"
  copy_file "SPEC.md"                                   "${TARGET}/SPEC.md"                           "spec"
  # D3: ECL_VERSION install-target copy — EIIS v1.4 §3.7.1
  if [[ -f "${SCRIPT_DIR}/ECL_VERSION" ]]; then
    copy_file "ECL_VERSION"                             "${TARGET}/ECL_VERSION"                       "ecl-version"
  fi
  copy_file "templates/mission-brief.md"                "${TARGET}/templates/mission-brief.md"        "template"
  copy_file "templates/traversal-map.md"                "${TARGET}/templates/traversal-map.md"        "template"
  copy_file "templates/findings.md"                     "${TARGET}/templates/findings.md"             "template"
  copy_file "templates/scout-report.md"                 "${TARGET}/templates/scout-report.md"         "template"
  copy_file "schemas/mission-brief.v1.json"             "${TARGET}/schemas/mission-brief.v1.json"     "other"
  copy_file "schemas/findings.v1.json"                  "${TARGET}/schemas/findings.v1.json"          "other"
  copy_file "schemas/scout-report.v1.json"              "${TARGET}/schemas/scout-report.v1.json"      "other"
  copy_file "schemas/install.manifest.v1.json"          "${TARGET}/schemas/install.manifest.v1.json"  "other"
  copy_file "schemas/scout-report-profile.v1.json"      "${TARGET}/schemas/scout-report-profile.v1.json" "other"
  copy_file "schemas/ecl-envelope.v1.json"              "${TARGET}/schemas/ecl-envelope.v1.json"      "other"
  # ECL envelope template — stored under schemas/ (§1.7.2: MAY vendor additional
  # JSON schemas; templates/ only allows .md per §1.7.1 whitelist).
  copy_file "templates/scout-report.envelope.json"      "${TARGET}/schemas/scout-report.envelope.json"   "other"

  # Commands — aci.sh is the atlas-aci wiring subcommand, dispatched by the
  # nexus at .eidolons/atlas/commands/aci.sh. Copy and substitute the
  # __ATLAS_VERSION__ placeholder so the installed script carries the correct
  # version constant without any hand-editing.
  if [[ -f "${SCRIPT_DIR}/commands/aci.sh" ]]; then
    if [[ "$DRY_RUN" != "true" ]]; then
      mkdir -p "${TARGET}/commands"
      _aci_dst="${TARGET}/commands/aci.sh"
      sed "s/__ATLAS_VERSION__/${EIDOLON_VERSION}/g" \
        "${SCRIPT_DIR}/commands/aci.sh" > "${_aci_dst}"
      chmod +x "${_aci_dst}"
      _aci_chk=$(sha256_file "${_aci_dst}")
      FILES_WRITTEN+=("{\"path\":\"${_aci_dst}\",\"sha256\":\"${_aci_chk}\",\"role\":\"command\",\"mode\":\"created\"}")
    else
      echo "  [dry-run] substitute+copy commands/aci.sh → ${TARGET}/commands/aci.sh"
    fi
  fi
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
Full spec: \`${TARGET}/SPEC.md\`
Cycle:     A (Assess) → T (Traverse) → L (Locate) → A (Abstract) → S (Synthesize)

**P0 (non-negotiable):** read-only (refuse edit/write/commit/deploy/migrate/refactor/fix); mission-first (requires \`mission.md\` + \`DECISION_TARGET\`); bounded ACI (\`view_file\` ≤100, \`search_text\` ≤50, \`list_dir\` ≤200); evidence-anchored claims (\`path:line\` + H|M|L); deterministic retrieval first, LLM search last."

# Shared dispatch — opt-in composition into root AGENTS.md / CLAUDE.md /
# .github/copilot-instructions.md. When false (default), only per-vendor
# skill and agent files are written — each host auto-discovers those.
# AGENTS.md is treated specially when 'codex' is wired (EIIS v1.1 §4.1.0):
# always written regardless of --shared-dispatch.
if [[ "$MANIFEST_ONLY" != "true" && "$SHARED_DISPATCH_AGENTS_MD" == "true" ]]; then
  upsert_eidolon_block "AGENTS.md" "$SHARED_BLOCK" "dispatch"
fi

# --------------------------------------------------------------------------- #
# Per-skill wiring helpers (no symlinks, no cross-vendor shortcuts)
# --------------------------------------------------------------------------- #

# strip_frontmatter <file> → body after the first --- ... --- block
strip_frontmatter() {
  local f="$1"
  if [[ "$(head -1 "$f")" == "---" ]]; then
    awk 'NR==1 && /^---$/ {in_fm=1; next}
         in_fm && /^---$/ {in_fm=0; next}
         !in_fm {print}' "$f"
  else
    cat "$f"
  fi
}

# extract_fm_field <file> <field_name> → value or empty
extract_fm_field() {
  awk -v field="$2" '
    NR==1 && /^---$/ { in_fm=1; next }
    in_fm && /^---$/ { exit }
    in_fm { p=index($0, field ":"); if (p==1) { sub("^" field ":[[:space:]]*", ""); print; exit } }
  ' "$1"
}

# wire_skill <skill_name>
#
# Dual-writes a skill file (EIIS v1.3 §4.2.4):
#   - source-of-truth: ${TARGET}/skills/<skill_name>.md   (flat, per-file)
#   - vendor copy:     .claude/skills/${EIDOLON_SLUG}-<skill_name>/SKILL.md
#
# Also writes copilot (.github/instructions/) and cursor (.cursor/rules/)
# vendor copies when those hosts are wired.
#
# Source file resolved as: ${SCRIPT_DIR}/skills/<skill_name>.md
# Bash 3.2 compatible (no associative arrays, no ${var,,}, no readarray).
wire_skill() {
  local skill="$1"
  local src="${SCRIPT_DIR}/skills/${skill}.md"
  local dst_src="${TARGET}/skills/${skill}.md"
  local dst_vendor=".claude/skills/${EIDOLON_SLUG}-${skill}/SKILL.md"

  if [ ! -f "${src}" ]; then
    warn "skill source not found: ${src}"; return
  fi

  local description
  description="$(extract_fm_field "$src" "description")"
  [ -z "$description" ] && description="${skill}"

  # Source-of-truth write (host-independent, always done)
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [dry-run] copy ${src} → ${dst_src}"
  else
    mkdir -p "$(dirname "${dst_src}")"
    cp "${src}" "${dst_src}"
    local chk; chk=$(sha256_file "${dst_src}")
    FILES_WRITTEN+=("{\"path\":\"${dst_src}\",\"sha256\":\"${chk}\",\"role\":\"skill\",\"mode\":\"created\"}")
  fi

  # Claude Code vendor copy
  if hosts_include "claude-code"; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "  [dry-run] copy ${src} → ${dst_vendor}"
    else
      mkdir -p "$(dirname "${dst_vendor}")"
      cp "${src}" "${dst_vendor}"
      local chk; chk=$(sha256_file "${dst_vendor}")
      FILES_WRITTEN+=("{\"path\":\"${dst_vendor}\",\"sha256\":\"${chk}\",\"role\":\"skill\",\"mode\":\"created\"}")
    fi
  fi

  # Copilot vendor copy (.github/instructions/<eidolon>-<skill>.instructions.md)
  if hosts_include "copilot"; then
    local dst_copilot=".github/instructions/${EIDOLON_SLUG}-${skill}.instructions.md"
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "  [dry-run] write ${dst_copilot}"
    else
      mkdir -p ".github/instructions"
      {
        echo "---"
        echo "applyTo: \"**\""
        echo "description: \"${description}\""
        echo "---"
        strip_frontmatter "$src"
      } > "$dst_copilot"
      local chk; chk=$(sha256_file "$dst_copilot")
      FILES_WRITTEN+=("{\"path\":\"${dst_copilot}\",\"sha256\":\"${chk}\",\"role\":\"skill\",\"mode\":\"created\"}")
    fi
  fi

  # Cursor vendor copy (.cursor/rules/<eidolon>-<skill>.mdc)
  if hosts_include "cursor"; then
    local dst_cursor=".cursor/rules/${EIDOLON_SLUG}-${skill}.mdc"
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "  [dry-run] write ${dst_cursor}"
    else
      mkdir -p ".cursor/rules"
      {
        echo "---"
        echo "description: \"${description}\""
        echo "alwaysApply: false"
        echo "---"
        strip_frontmatter "$src"
      } > "$dst_cursor"
      local chk; chk=$(sha256_file "$dst_cursor")
      FILES_WRITTEN+=("{\"path\":\"${dst_cursor}\",\"sha256\":\"${chk}\",\"role\":\"skill\",\"mode\":\"created\"}")
    fi
  fi
}

# Emit per-skill files for every phase (EIIS v1.3 §4.2.4 dual-write)
if [[ "$MANIFEST_ONLY" != "true" ]]; then
  log "Wiring per-skill files across hosts"
  wire_skill "traverse"
  wire_skill "locate"
  wire_skill "abstract"
  wire_skill "synthesize"
  wire_skill "scatter"
  wire_skill "rescout"
fi

# ---- claude-code (methodology-level subagent + optional shared dispatch) --- #
if hosts_include "claude-code" && [[ "$MANIFEST_ONLY" != "true" ]]; then
  log "Wiring: claude-code"

  [[ "$SHARED_DISPATCH" == "true" ]] && upsert_eidolon_block "CLAUDE.md" "$SHARED_BLOCK" "dispatch"

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

You are ATLAS. Read these two files in order at session start:

1. \`./.eidolons/atlas/agent.md\` — always-loaded P0 rules.
2. \`./.eidolons/atlas/SPEC.md\` — deep on-demand methodology spec.

Skills live at \`./.eidolons/atlas/skills/<skill>.md\` (load on demand)."

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
  log "Wiring: copilot (per-skill instructions already emitted above)"
  [[ "$SHARED_DISPATCH" == "true" ]] && \
    upsert_eidolon_block ".github/copilot-instructions.md" "$SHARED_BLOCK" "dispatch"
fi

# ---- cursor --------------------------------------------------------------- #
if hosts_include "cursor" && [[ "$MANIFEST_ONLY" != "true" ]]; then
  log "Wiring: cursor (per-skill rules already emitted above)"
  # Clean up the methodology-level atlas.mdc from previous installers —
  # per-skill atlas-<phase>.mdc files are now the canonical Cursor surface.
  if [[ -f ".cursor/rules/atlas.mdc" && "$FORCE" == "true" ]]; then
    rm -f ".cursor/rules/atlas.mdc"
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
You are the ATLAS explorer/scout agent.
Always-loaded profile: \`${TARGET}/agent.md\`.
Full spec: \`${TARGET}/SPEC.md\`.
Phase skills: \`${TARGET}/skills/<phase>.md\` — load only the active phase."

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

# ---- codex (EIIS v1.1 §4.5) ---------------------------------------------- #
# Codex subagent contract: .codex/agents/<name>.md with YAML frontmatter
# (`name`, `description` required; `tools`, `model` optional). Source:
# https://developers.openai.com/codex/subagents
# Root AGENTS.md is co-owned by copilot+codex (§4.1.0) — written above when
# SHARED_DISPATCH_AGENTS_MD is true.
if hosts_include "codex" && [[ "$MANIFEST_ONLY" != "true" ]]; then
  log "Wiring: codex"
  do_action "mkdir -p .codex/agents" mkdir -p ".codex/agents"

  CODEX_AGENT="---
name: atlas
description: Read-only codebase scout running the ATLAS five-phase pipeline (Assess, Traverse, Locate, Abstract, Synthesize). Use for codebase exploration, impact analysis, and pre-planning questions; refuses write verbs and hands off to SPECTRA or APIVR-Delta.
---

# ATLAS — Explorer/Scout Subagent (Codex)

You execute the ATLAS methodology: **A**ssess -> **T**raverse -> **L**ocate ->
**A**bstract -> **S**ynthesize. You are **read-only**. If asked to mutate
anything, hand off.

Canonical methodology: \`${TARGET}/agent.md\` (always-loaded profile,
<=1000 tokens). Full spec: \`${TARGET}/SPEC.md\`.

## P0 (non-negotiable)

- Read-only tools only. Refuse \`edit\`, \`write\`, \`commit\`, \`deploy\`,
  \`migrate\`, \`install\`, \`refactor\`, \`fix\`. Hand off to SPECTRA (spec)
  or APIVR-Delta (implementation).
- Mission brief first. Do nothing until \`mission.md\` exists with a
  concrete \`DECISION_TARGET\`.
- Bounded probes: \`view_file\` <=100 lines; \`search_text\` <=50 matches;
  \`list_dir\` <=200 entries.
- Evidence-anchored claims. Every factual statement carries
  \`path:line_start-line_end\` + confidence \`H|M|L\`.
- Deterministic retrieval first (symbol lookup, code-graph, ripgrep). LLM
  search is last resort.

## Invocation

Address as: \"ATLAS, scout this repo for <DECISION_TARGET>\". Emit
\`mission.md\` first, then run Traverse, Locate, Abstract, Synthesize.
Final artefact: \`scout-report.md\` <=3000 tokens with FINDING-XXX IDs."

  # .codex/agents/atlas.md is owned by this Eidolon; overwrite on --force.
  if [[ ! -f ".codex/agents/atlas.md" || "$FORCE" == "true" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "  [dry-run] write .codex/agents/atlas.md"
    else
      printf "%s\n" "$CODEX_AGENT" > ".codex/agents/atlas.md"
      chk=$(sha256_file ".codex/agents/atlas.md")
      FILES_WRITTEN+=("{\"path\":\".codex/agents/atlas.md\",\"sha256\":\"${chk}\",\"role\":\"dispatch\",\"mode\":\"created\"}")
    fi
  else
    log "  skip .codex/agents/atlas.md (exists — pass --force to overwrite)"
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
# EIIS v1.4 §6.X — manifest-driven canonical inventory sweep
# Remove any file under TARGET that is not in FILES_WRITTEN (i.e. not
# whitelisted by the current write pass). Runs AFTER all writes, BEFORE
# the manifest is finalised. Idempotent.
# --------------------------------------------------------------------------- #
if [[ "$DRY_RUN" != "true" && "$MANIFEST_ONLY" != "true" ]]; then
  canonical_inventory_sweep "${TARGET}"
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

# EIIS v1.3: spec_file field (canonical full-spec path)
# Strip any leading "./" from TARGET so the manifest records the canonical
# form (.eidolons/atlas/SPEC.md) regardless of how --target was supplied.
SPEC_FILE_PATH="${TARGET}/SPEC.md"
SPEC_FILE_PATH="${SPEC_FILE_PATH#./}"

# EIIS v1.3: skills array — build JSON for each skill's dual-write pair.
# Source-of-truth SHA is computed from the installed flat file.
build_skills_json() {
  local result="" skill src_path vendor_path src_sha vendor_sha
  for skill in traverse locate abstract synthesize scatter rescout; do
    src_path="${TARGET}/skills/${skill}.md"
    vendor_path=".claude/skills/${EIDOLON_SLUG}-${skill}/SKILL.md"
    if [ -f "${src_path}" ]; then
      src_sha="$(sha256_file "${src_path}")"
    else
      src_sha="0000000000000000000000000000000000000000000000000000000000000000"
    fi
    vendor_sha=""
    if hosts_include "claude-code" && [ -f "${vendor_path}" ]; then
      vendor_sha="$(sha256_file "${vendor_path}")"
    fi
    local entry
    if [ -n "$vendor_sha" ]; then
      entry="{\"name\":\"${skill}\",\"source_path\":\".eidolons/${EIDOLON_SLUG}/skills/${skill}.md\",\"source_sha256\":\"${src_sha}\",\"vendor_path\":\".claude/skills/${EIDOLON_SLUG}-${skill}/SKILL.md\",\"vendor_sha256\":\"${vendor_sha}\"}"
    else
      entry="{\"name\":\"${skill}\",\"source_path\":\".eidolons/${EIDOLON_SLUG}/skills/${skill}.md\",\"source_sha256\":\"${src_sha}\"}"
    fi
    result="${result:+${result},}${entry}"
  done
  printf '%s' "$result"
}

MANIFEST_PATH="${TARGET}/install.manifest.json"

if [[ "$DRY_RUN" != "true" ]]; then
  SKILLS_JSON="$(build_skills_json)"

  # Write cleanly without shell escaping issues.
  # ecl_version_emitted is injected only when ECL_VERSION is present (opt-in field).
  if [[ -n "$ECL_VERSION_EMITTED" ]]; then
    cat > "${MANIFEST_PATH}" <<MANIFEST_EOF
{
  "eidolon": "${EIDOLON_NAME}",
  "version": "${EIDOLON_VERSION}",
  "methodology": "${METHODOLOGY}",
  "canonical_inventory_strict": true,
  "installed_at": "${INSTALLED_AT}",
  "target": "${TARGET}",
  "spec_file": "${SPEC_FILE_PATH}",
  "hosts_wired": [${HOSTS_JSON}],
  "files_written": [${FILES_JSON}],
  "skills": [${SKILLS_JSON}],
  "handoffs_declared": {
    "upstream": [],
    "downstream": ["spectra", "apivr-delta"]
  },
  "token_budget": {
    "entry": ${AGENT_TOKENS},
    "working_set_target": 1000
  },
  "ecl_version_emitted": "${ECL_VERSION_EMITTED}",
  "security": {
    "reads_repo": true,
    "reads_network": false,
    "writes_repo": false,
    "persists": [".atlas/.memex"]
  }
}
MANIFEST_EOF
  else
    cat > "${MANIFEST_PATH}" <<MANIFEST_EOF
{
  "eidolon": "${EIDOLON_NAME}",
  "version": "${EIDOLON_VERSION}",
  "methodology": "${METHODOLOGY}",
  "canonical_inventory_strict": true,
  "installed_at": "${INSTALLED_AT}",
  "target": "${TARGET}",
  "spec_file": "${SPEC_FILE_PATH}",
  "hosts_wired": [${HOSTS_JSON}],
  "files_written": [${FILES_JSON}],
  "skills": [${SKILLS_JSON}],
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
  fi
  log "Manifest: ${MANIFEST_PATH}"
else
  do_action "write ${MANIFEST_PATH}" true
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
