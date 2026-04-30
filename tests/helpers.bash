#!/usr/bin/env bash
# tests/helpers.bash — shared fixtures for the atlas-aci bats suite.
#
# Destination in Rynaro/ATLAS: tests/helpers.bash
#
# Every test sources this file. The suite exercises the real
# commands/aci.sh by invoking it as a subprocess with:
#   - cwd = a fresh tmp "consumer project"
#   - PATH = a stubs dir first, then a curated allowlist
#   - $HOME / $XDG_CONFIG_HOME = fake dirs under $BATS_TEST_TMPDIR so T29
#     can assert nothing leaked outside cwd.
#
# Stubs record every invocation to $BATS_TEST_TMPDIR/<tool>.log so tests
# can assert call-count / args. Each stub honours an env var to inject a
# non-zero exit for failure-path tests.
#
# Bash 3.2 rules (P5): no associative arrays, no ${var,,}, no
# readarray/mapfile, no &>>. Mirror cli/tests/helpers.bash in the
# Rynaro/eidolons nexus for style.

# Absolute path to the ATLAS repo root (two levels up from this file).
ATLAS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ATLAS_ROOT

# Path to the script under test. In Rynaro/ATLAS this is commands/aci.sh.
ACI_SCRIPT="$ATLAS_ROOT/commands/aci.sh"
export ACI_SCRIPT

setup() {
  # Each test runs in its own pristine project dir.
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"

  # Fake HOME / XDG so T29 can assert nothing leaked outside cwd.
  FAKE_HOME="$BATS_TEST_TMPDIR/fakehome"
  FAKE_XDG="$BATS_TEST_TMPDIR/fakexdg"
  mkdir -p "$FAKE_HOME" "$FAKE_XDG"
  export HOME="$FAKE_HOME"
  export XDG_CONFIG_HOME="$FAKE_XDG"

  # Stubs dir — PATH is rewritten to put this first.
  STUBS_DIR="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS_DIR"

  # Shadow dir — used by uninstall_stub to mask specific host binaries
  # without dropping their containing directories from PATH. Dropping a
  # whole dir (the previous strategy) is unsafe on Linux where coreutils
  # like /usr/bin/{rm,mkdir,cat} share a directory with docker/podman/awk.
  SHADOW_DIR="$BATS_TEST_TMPDIR/shadow"
  mkdir -p "$SHADOW_DIR"
  # Space-separated list of names currently masked via uninstall_stub.
  _STUB_UNINSTALLED=""

  # Curated PATH: stubs first, then a minimal allowlist of real tools
  # the host box provides but we do NOT want to stub (coreutils etc).
  # jq/yq/shellcheck tests use the real binaries since we test the
  # script's integration with them.
  _STUB_REAL_TOOLS_PATH="$(real_tools_path)"
  # Snapshot the real-tools PATH at setup time. uninstall_stub rebuilds
  # SHADOW_DIR against this snapshot, never against the current $PATH,
  # so PATH mutation never compounds across calls.
  _STUB_BASE_PATH="$_STUB_REAL_TOOLS_PATH"
  export PATH="$STUBS_DIR:$_STUB_REAL_TOOLS_PATH"
}

teardown() {
  cd "$ATLAS_ROOT"
}

# ─── Stub fabrication ────────────────────────────────────────────────────

# real_tools_path — echoes a PATH made of the directories containing
# real coreutils + jq + yq + bash + awk + sed + python3. We assemble this
# from `command -v <tool>` against the host's real PATH so the stub dir
# can shadow things without losing access to essentials.
real_tools_path() {
  # Snapshot the test process's inbound PATH before we rewrite it.
  # (bats inherits the host PATH; BATS_ORIGINAL_PATH may be set in some
  # bats versions — fall back to PATH.)
  local snapshot="${BATS_ORIGINAL_PATH:-$PATH}"
  echo "$snapshot"
}

# install_stub NAME EXIT_CODE [BODY]
#   Creates an executable at $STUBS_DIR/NAME that:
#     - appends one line to $BATS_TEST_TMPDIR/NAME.log per invocation,
#       formatted "<timestamp-ish> <all-args>"
#     - optionally runs BODY (a snippet evaluated in the stub's shell —
#       lets individual tests shape output)
#     - exits with EXIT_CODE (or whatever $STUB_NAME_EXIT overrides to
#       at call time, uppercased).
install_stub() {
  local name="$1" exit_code="$2" body="${3:-}"
  local upper_env
  # Bash 3.2 cannot do ${var^^}. Upper-case via tr.
  upper_env="STUB_$(echo "$name" | tr '[:lower:]-' '[:upper:]_')_EXIT"
  local logfile="$BATS_TEST_TMPDIR/${name}.log"
  local stub_path="$STUBS_DIR/$name"
  cat > "$stub_path" <<EOF
#!/usr/bin/env bash
# Auto-generated stub for \`$name\` — do not edit in place.
printf '%s\n' "\$*" >> "$logfile"
${body}
_override="\${${upper_env}:-}"
if [ -n "\$_override" ]; then exit "\$_override"; fi
exit ${exit_code}
EOF
  chmod +x "$stub_path"
  : > "$logfile"
}

# uninstall_stub NAME — removes the stub AND scrubs any host-PATH entry
# that resolves NAME, so `command -v NAME` fails inside the script under
# test. Without the scrub, a stub for `rg` (or any tool that the host
# box happens to have installed via brew/apt) would fall through to the
# real binary and the prereq check would never trip.
#
# Strategy: build $SHADOW_DIR as a directory of symlinks pointing at every
# executable found on $_STUB_BASE_PATH EXCEPT the names in
# $_STUB_UNINSTALLED. PATH is then $STUBS_DIR:$SHADOW_DIR — no original
# host PATH dirs remain, so masking is total, but coreutils stay reachable
# because their symlinks are in $SHADOW_DIR. This is the Linux-portable
# replacement for the old "drop the dir from PATH" approach, which broke
# whenever a target binary lived alongside coreutils in /usr/bin
# (the typical Linux layout, including GitHub Actions runners).
uninstall_stub() {
  local name="$1"
  rm -f "$STUBS_DIR/$name"
  # Track the masked name (idempotent — avoid duplicate entries).
  case " $_STUB_UNINSTALLED " in
    *" $name "*) : ;;
    *) _STUB_UNINSTALLED="${_STUB_UNINSTALLED:+$_STUB_UNINSTALLED }$name" ;;
  esac
  _stub_rebuild_shadow_path
}

# _stub_rebuild_shadow_path — internal. Refresh $SHADOW_DIR from
# $_STUB_BASE_PATH minus $_STUB_UNINSTALLED names, then re-export PATH.
# Bash 3.2-safe (no associative arrays).
_stub_rebuild_shadow_path() {
  # The rebuild itself shells out to `rm`, `mkdir`, `ln`, `basename` —
  # all of which resolve via PATH. Run with the original real-tools
  # PATH so we don't depend on the (about-to-be-rewritten) shadow.
  local _saved_path="$PATH"
  export PATH="$_STUB_BASE_PATH"

  rm -rf "$SHADOW_DIR"
  mkdir -p "$SHADOW_DIR"

  local old_IFS dir entry base masked
  old_IFS="$IFS"
  IFS=':'
  for dir in $_STUB_BASE_PATH; do
    IFS="$old_IFS"
    if [ -z "$dir" ] || [ ! -d "$dir" ]; then
      IFS=':'
      continue
    fi
    # Iterate every executable in $dir; symlink into $SHADOW_DIR unless
    # already shadowed (first dir in PATH wins, like real PATH lookup)
    # or in the masked list.
    for entry in "$dir"/*; do
      [ -e "$entry" ] || continue
      [ -d "$entry" ] && continue
      [ -x "$entry" ] || continue
      base="${entry##*/}"
      # Already symlinked from an earlier (higher-priority) PATH dir?
      [ -e "$SHADOW_DIR/$base" ] && continue
      # In the masked list?
      masked=0
      case " $_STUB_UNINSTALLED " in
        *" $base "*) masked=1 ;;
      esac
      [ "$masked" -eq 1 ] && continue
      ln -s "$entry" "$SHADOW_DIR/$base" 2>/dev/null || true
    done
    IFS=':'
  done
  IFS="$old_IFS"

  export PATH="$STUBS_DIR:$SHADOW_DIR"
  # Suppress unused-var warning from set -u if helpers ever flips it on.
  : "$_saved_path"
}

# setup_stubs — install the default happy-path stubs every install test
# relies on. Individual tests can override by reinstalling a stub or
# setting STUB_<NAME>_EXIT at the @test level.
setup_stubs() {
  install_stub "uv" 0
  install_stub "rg" 0
  install_stub "python3" 0 'case "$1" in
  --version) echo "Python 3.11.7"; exit 0 ;;
esac'
  install_stub "atlas-aci" 0 'case "$1" in
  index) shift; mkdir -p ./.atlas && printf "generated: true\n" > ./.atlas/manifest.yaml ;;
  *) : ;;
esac'
  # jq and yq are genuine dependencies of the script logic — we let the
  # host box supply them via the PATH tail. If a test needs to stub them
  # (e.g. to force a parse failure), it can call install_stub "jq" 1
  # explicitly.
}

# stub_log_count NAME — echoes the number of times the stub was invoked.
stub_log_count() {
  local logfile="$BATS_TEST_TMPDIR/${1}.log"
  if [ -f "$logfile" ]; then
    wc -l < "$logfile" | tr -d ' '
  else
    echo 0
  fi
}

# ─── Fixture builders ────────────────────────────────────────────────────

# setup_fresh_project — seed the atlas install manifest so the §4.3 guard
# passes, then return. Caller cd's into $TEST_PROJECT (setup did that).
setup_fresh_project() {
  mkdir -p ./.eidolons/atlas
  cat > ./.eidolons/atlas/install.manifest.json <<'EOF'
{
  "name": "atlas",
  "version": "1.0.0",
  "hosts_wired": ["claude-code"],
  "files": []
}
EOF
}

# seed_claude_host — create the marker that detect_hosts_mcp picks up
# for the claude-code host (either CLAUDE.md or .claude/).
seed_claude_host() {
  mkdir -p .claude
  : > CLAUDE.md
}

# seed_claude_atlas_subagent — seed .claude/agents/atlas.md with the
# canonical BASE tools allowlist (matches install.sh's output). Used by
# subagent-tools tests to verify that aci install extends the line and
# aci remove restores it. Body is intentionally minimal — these tests
# only care about the `tools:` line in the YAML frontmatter.
seed_claude_atlas_subagent() {
  mkdir -p .claude/agents
  cat > .claude/agents/atlas.md <<'EOF'
---
name: atlas
description: Test fixture subagent (frontmatter-only).
when_to_use: tests
tools: Read, Grep, Glob, Bash(rg:*), Bash(git log:*), Bash(git show:*)
methodology: ATLAS
methodology_version: "1.0"
role: Explorer/Scout
handoffs: [spectra, apivr]
---

# ATLAS — Explorer/Scout Agent (test fixture)
EOF
}

# seed_cursor_host — marker for cursor host detection.
seed_cursor_host() {
  mkdir -p .cursor
}

# seed_copilot_host_with_agent — marker for copilot host plus one agent
# file containing a non-trivial YAML frontmatter and a markdown body.
seed_copilot_host_with_agent() {
  mkdir -p .github/agents
  cat > .github/agents/example.agent.md <<'EOF'
---
name: example
description: a test agent
tools:
  shell: true
---
# Example agent

This is the markdown body. It must survive byte-for-byte through
install and remove per T15.

- bullet one
- bullet two
EOF
}

# seed_copilot_host_empty — .github/ present but no .github/agents/.
# Triggers T14.
seed_copilot_host_empty() {
  mkdir -p .github
}

# seed_mcp_json_with_peer FILE — write a valid .mcp.json / .cursor/mcp.json
# with a pre-existing mcpServers.other-server entry so T9 / T10 can
# assert byte-level preservation.
seed_mcp_json_with_peer() {
  local target="$1"
  local dir
  dir="$(dirname "$target")"
  mkdir -p "$dir"
  cat > "$target" <<'EOF'
{
  "mcpServers": {
    "other-server": {
      "command": "node",
      "args": ["./other-server.js"],
      "env": {
        "OTHER_TOKEN": "keep-me"
      }
    }
  }
}
EOF
}

# seed_copilot_agent_with_peer — agent file whose frontmatter already has
# a peer MCP server entry. T9c / T10c preserve it.
seed_copilot_agent_with_peer() {
  mkdir -p .github/agents
  cat > .github/agents/example.agent.md <<'EOF'
---
name: example
description: peer test
tools:
  mcp_servers:
    - name: other-server
      transport: stdio
      command: ["node", "./other-server.js"]
---
# Peer preservation body

Body content under T9c / T10c.
EOF
}

# ─── Assertions ──────────────────────────────────────────────────────────

assert_mcp_json_contains() {
  local target="$1" key="$2"
  run jq -e --arg k "$key" '.mcpServers[$k] // empty' "$target"
  [ "$status" -eq 0 ] || {
    echo "expected mcpServers.$key in $target; got:"
    cat "$target"
    return 1
  }
}

assert_mcp_json_missing() {
  local target="$1" key="$2"
  run jq -e --arg k "$key" '.mcpServers[$k] // empty' "$target"
  [ "$status" -ne 0 ] || {
    echo "did not expect mcpServers.$key in $target; got:"
    cat "$target"
    return 1
  }
}

# assert_peer_preserved FILE — confirms mcpServers.other-server matches
# the original seeded shape byte-for-byte (after jq -S normalisation).
assert_peer_preserved() {
  local target="$1"
  local actual
  actual="$(jq -S '.mcpServers["other-server"]' "$target")"
  [ "$actual" = "$(cat <<'EOF' | jq -S .
{
  "command": "node",
  "args": ["./other-server.js"],
  "env": {"OTHER_TOKEN": "keep-me"}
}
EOF
)" ] || {
    echo "peer mcpServers.other-server was disturbed in $target:"
    echo "$actual"
    return 1
  }
}

assert_agent_md_body_preserved() {
  local target="$1" expected_body="$2"
  local actual_body
  # Extract body: everything after the second '---' line.
  actual_body="$(awk '
    /^---$/ { c++; if (c == 2) { capture = 1; next } }
    capture { print }
  ' "$target")"
  [ "$actual_body" = "$expected_body" ] || {
    echo "agent body was disturbed in $target"
    echo "--- expected"
    printf "%s\n" "$expected_body"
    echo "--- actual"
    printf "%s\n" "$actual_body"
    return 1
  }
}

# assert_agent_md_has_atlas_aci FILE — confirms tools.mcp_servers[] has a
# name: atlas-aci entry.
assert_agent_md_has_atlas_aci() {
  local target="$1"
  local fm
  fm="$(awk 'NR>1 && /^---$/ { exit } NR>1 { print }' "$target")"
  run bash -c "printf '%s' '$fm' | yq eval '.tools.mcp_servers[] | select(.name == \"atlas-aci\")' -"
  [ "$status" -eq 0 ] && [ -n "$output" ] || {
    echo "agent $target lacks tools.mcp_servers[name=atlas-aci]:"
    cat "$target"
    return 1
  }
}

# normalise_json FILE — echoes the jq -S (sorted-keys) rendering so
# idempotency tests can cmp across runs without false-failing on key
# order noise.
normalise_json() {
  jq -S . "$1"
}

# snapshot_mtimes DIR — echoes "<path>\t<mtime>" lines for every file
# under DIR. Used by T25 to prove --dry-run touched nothing.
#
# stat(1) is incompatibly split between BSD (`-f FMT`) and GNU (`-c FMT`).
# On Linux GNU coreutils, `stat -f '%N %m'` is interpreted as
# `--file-system` plus a positional file arg `%N %m`, which dumps
# filesystem stats whose Free/Available block counts fluctuate between
# calls regardless of whether any file under DIR changed. That makes T25
# false-positive on Linux. Detect the mode by sniffing `stat --version`:
# GNU prints "coreutils" on `--version`; BSD/macOS errors out.
snapshot_mtimes() {
  if stat --version >/dev/null 2>&1; then
    # GNU coreutils — supports -c FMT.
    find "$1" -type f -print0 2>/dev/null \
      | xargs -0 stat -c '%n %Y' 2>/dev/null
  else
    # BSD (macOS) — supports -f FMT.
    find "$1" -type f -print0 2>/dev/null \
      | xargs -0 stat -f '%N %m' 2>/dev/null
  fi
}

# run_aci ARGS... — invoke the script under test from the current
# project cwd. Bats captures $output and $status.
run_aci() {
  run bash "$ACI_SCRIPT" "$@"
}
