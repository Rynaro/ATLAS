#!/usr/bin/env bats
# tests/aci.bats — container-mode tests for G5–G11, G17–G19.
#
# Spec anchor: .spectra/atlas-aci-container.yaml in Rynaro/eidolons nexus.
#
# These tests exercise the --container path of commands/aci.sh without
# pulling or building real images. A mock `docker` stub is placed on PATH;
# it records invocations, emits a stable fake image ID, and succeeds by
# default. Individual tests override the stub behaviour via sentinel files
# to simulate error paths.
#
# Stub state (all file-based for cross-process visibility):
#   $BATS_TEST_TMPDIR/docker.sentinel   — when present, image "exists"
#   $BATS_TEST_TMPDIR/docker.log        — one line per invocation
#   $BATS_TEST_TMPDIR/docker.build_fail — when present, build exits 1
#
# Gate coverage:
#   G5  --container --dry-run emits BUILD and canonical body actions
#   G6  two consecutive --container installs produce byte-identical .mcp.json
#   G7  uv → container mode-switch overwrites once, then idempotent
#   G8  --container --remove removes only mcpServers.atlas-aci, peers preserved
#   G9  missing docker AND podman → exit 7
#   G10 hand-edited TOML body (matches neither canonical) triggers fail-closed
#   G11 uv canonical body, --container invoked → overwritten cleanly
#   G17 --container --non-interactive without --runtime → exit 9
#   G18 --container against unchanged image is a no-op (no host writes)
#   G19 ATLAS_ACI_REF bump triggers rebuild → new digest → host configs updated

load helpers

# ─── Constants ────────────────────────────────────────────────────────────

# FAKE_DIGEST — stable 64-char hex string used as the fake sha256 id.
FAKE_DIGEST="aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"
FAKE_DIGEST_V2="0011223344556677889900aabbccddee0011223344556677889900aabbccddee"

# ─── Stub installation helpers ────────────────────────────────────────────

# _write_docker_stub RUNTIME LOGFILE SENTINEL BUILD_FAIL_FILE DIGEST
# Writes the stub script that docker/podman maps to.
# The stub uses file sentinels so state is visible across child processes.
_write_runtime_stub() {
  local name="$1" logfile="$2" sentinel="$3" build_fail_file="$4" fake_digest="$5"
  cat > "$STUBS_DIR/$name" <<STUB
#!/usr/bin/env bash
# Auto-generated $name stub — tests/aci.bats
printf '%s\n' "\$*" >> "${logfile}"

case "\$1" in
  images)
    if echo "\$*" | grep -q 'no-trunc'; then
      # Return digest only if sentinel exists (image was built).
      if [ -f "${sentinel}" ]; then
        printf 'sha256:${fake_digest}\n'
      fi
      exit 0
    fi
    # Repository:Tag format query.
    if [ -f "${sentinel}" ]; then
      printf 'atlas-aci:1.1.0\n'
    fi
    exit 0
    ;;
  build)
    if [ -f "${build_fail_file}" ]; then
      printf 'simulated build error\n' >&2
      exit 1
    fi
    # Mark image as existing.
    touch "${sentinel}"
    exit 0
    ;;
  run)
    # Simulate successful index / serve — create manifest.yaml if indexing.
    if echo "\$*" | grep -q 'index'; then
      mkdir -p ./.atlas
      printf 'generated: true\n' > ./.atlas/manifest.yaml
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
STUB
  chmod +x "$STUBS_DIR/$name"
  : > "$logfile"
}

# install_docker_stub [DIGEST]
install_docker_stub() {
  local fake_digest="${1:-$FAKE_DIGEST}"
  local logfile="$BATS_TEST_TMPDIR/docker.log"
  local sentinel="$BATS_TEST_TMPDIR/docker.sentinel"
  local build_fail="$BATS_TEST_TMPDIR/docker.build_fail"
  rm -f "$sentinel" "$build_fail"
  _write_runtime_stub "docker" "$logfile" "$sentinel" "$build_fail" "$fake_digest"
}

# install_docker_stub_prebuilt [DIGEST] — image already exists from the start.
install_docker_stub_prebuilt() {
  local fake_digest="${1:-$FAKE_DIGEST}"
  install_docker_stub "$fake_digest"
  touch "$BATS_TEST_TMPDIR/docker.sentinel"
}

# set_docker_build_fail — next docker build will exit 1.
set_docker_build_fail() {
  touch "$BATS_TEST_TMPDIR/docker.build_fail"
}

# docker_build_count — number of times `docker build` was invoked.
docker_build_count() {
  awk '/^build/{c++} END{print c+0}' "$BATS_TEST_TMPDIR/docker.log" 2>/dev/null || printf '0'
}

# install_podman_stub [DIGEST]
install_podman_stub() {
  local fake_digest="${1:-$FAKE_DIGEST}"
  local logfile="$BATS_TEST_TMPDIR/podman.log"
  local sentinel="$BATS_TEST_TMPDIR/podman.sentinel"
  local build_fail="$BATS_TEST_TMPDIR/podman.build_fail"
  rm -f "$sentinel" "$build_fail"
  _write_runtime_stub "podman" "$logfile" "$sentinel" "$build_fail" "$fake_digest"
}

# install_podman_stub_prebuilt [DIGEST]
install_podman_stub_prebuilt() {
  local fake_digest="${1:-$FAKE_DIGEST}"
  install_podman_stub "$fake_digest"
  touch "$BATS_TEST_TMPDIR/podman.sentinel"
}

# setup_container_stubs — install git + docker stubs for container mode.
setup_container_stubs() {
  install_stub "git" 0
  install_docker_stub
}

# seed_uv_mcp_json [TARGET] — seed a .mcp.json with uv canonical body.
seed_uv_mcp_json() {
  local target="${1:-.mcp.json}"
  local dir; dir="$(dirname "$target")"
  mkdir -p "$dir"
  cat > "$target" <<'EOF'
{
  "mcpServers": {
    "atlas-aci": {
      "command": "atlas-aci",
      "args": [
        "serve",
        "--repo",
        "${workspaceFolder}",
        "--memex-root",
        "${workspaceFolder}/.atlas/memex"
      ]
    }
  }
}
EOF
}

# ─── G5 ──────────────────────────────────────────────────────────────────

@test "G5: --container --dry-run emits BUILD and canonical body actions" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host

  run_aci --install --container --runtime docker --dry-run --non-interactive
  [ "$status" -eq 0 ]

  # Stdout must contain BUILD action for the image.
  [[ "$output" == *"BUILD"* ]] || {
    echo "Expected BUILD in dry-run output:"
    printf '%s\n' "$output"
    return 1
  }
  # Stdout must contain CREATE or MODIFY for .mcp.json.
  [[ "$output" == *"CREATE"*".mcp.json"* ]] || [[ "$output" == *"MODIFY"*".mcp.json"* ]] || {
    echo "Expected CREATE/MODIFY .mcp.json in dry-run output:"
    printf '%s\n' "$output"
    return 1
  }
  # INDEX must appear.
  [[ "$output" == *"INDEX"* ]] || {
    echo "Expected INDEX in dry-run output:"
    printf '%s\n' "$output"
    return 1
  }
  # No files must have been created.
  [ ! -f ".mcp.json" ] || { echo ".mcp.json was created by dry-run"; return 1; }
  [ ! -d ".atlas" ]    || { echo ".atlas/ was created by dry-run"; return 1; }
}

@test "G5: --container --dry-run with --runtime podman emits BUILD" {
  setup_fresh_project
  install_stub "git" 0
  install_podman_stub
  uninstall_stub "docker"
  seed_claude_host

  run_aci --install --container --runtime podman --dry-run --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"BUILD"* ]] || {
    echo "Expected BUILD in dry-run output (podman):"
    printf '%s\n' "$output"
    return 1
  }
}

# ─── G6 ──────────────────────────────────────────────────────────────────

@test "G6: two consecutive --container installs produce byte-identical .mcp.json" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host

  # First install: image absent → stub builds it (creates sentinel).
  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ]
  [ -f ".mcp.json" ] || { echo ".mcp.json not created on first install"; return 1; }
  local first
  first="$(normalise_json .mcp.json)"

  # Second install: image exists (sentinel present), configs already match → noop.
  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ]
  local second
  second="$(normalise_json .mcp.json)"

  [ "$first" = "$second" ] || {
    echo "Byte mismatch between first and second --container install:"
    echo "--- first"
    printf '%s\n' "$first"
    echo "--- second"
    printf '%s\n' "$second"
    return 1
  }
}

# ─── G7 ──────────────────────────────────────────────────────────────────

@test "G7: uv install then --container install overwrites, then idempotent" {
  setup_fresh_project
  setup_stubs
  seed_claude_host

  # Step 1: uv install.
  run_aci --install --host claude-code --non-interactive
  [ "$status" -eq 0 ]
  [ -f ".mcp.json" ] || { echo ".mcp.json not created by uv install"; return 1; }
  run jq -r '.mcpServers["atlas-aci"].command' .mcp.json
  [ "$output" = "atlas-aci" ] || {
    echo "Expected uv canonical command 'atlas-aci', got: $output"
    return 1
  }

  # Step 2: container install → must overwrite uv body with docker body.
  install_stub "git" 0
  install_docker_stub
  run_aci --install --container --runtime docker --host claude-code --non-interactive
  [ "$status" -eq 0 ]
  run jq -r '.mcpServers["atlas-aci"].command' .mcp.json
  [ "$output" = "docker" ] || {
    echo "Expected container canonical command 'docker' after mode switch, got: $output"
    return 1
  }
  local after_switch
  after_switch="$(normalise_json .mcp.json)"

  # Step 3: second container install → idempotent (same digest → noop).
  run_aci --install --container --runtime docker --host claude-code --non-interactive
  [ "$status" -eq 0 ]
  local after_second
  after_second="$(normalise_json .mcp.json)"
  [ "$after_switch" = "$after_second" ] || {
    echo ".mcp.json changed on second container install (should be noop):"
    echo "--- after first container install"
    printf '%s\n' "$after_switch"
    echo "--- after second container install"
    printf '%s\n' "$after_second"
    return 1
  }
}

# ─── G8 ──────────────────────────────────────────────────────────────────

@test "G8: --container --remove removes only mcpServers.atlas-aci, peers preserved" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host

  # Pre-seed a .mcp.json with atlas-aci (container) + a peer server.
  cat > ".mcp.json" <<'EOF'
{
  "mcpServers": {
    "other-server": {
      "command": "node",
      "args": ["./other.js"]
    },
    "atlas-aci": {
      "command": "docker",
      "args": ["run", "--rm", "-i", "--read-only",
               "-v", "${workspaceFolder}:/repo:ro",
               "-v", "${workspaceFolder}/.atlas/memex:/memex",
               "atlas-aci@sha256:aabbccddeeff",
               "serve", "--repo", "/repo", "--memex-root", "/memex"]
    }
  }
}
EOF

  run_aci --remove --host claude-code --non-interactive
  [ "$status" -eq 0 ]

  assert_mcp_json_missing ".mcp.json" "atlas-aci"

  run jq -e '.mcpServers["other-server"]' ".mcp.json"
  [ "$status" -eq 0 ] || {
    echo "Peer other-server was removed:"
    cat ".mcp.json"
    return 1
  }
}

# ─── G9 ──────────────────────────────────────────────────────────────────

@test "G9: missing docker AND podman → exit 7" {
  setup_fresh_project
  install_stub "git" 0
  uninstall_stub "docker"
  uninstall_stub "podman"
  seed_claude_host

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 7 ] || {
    echo "Expected exit 7, got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"docker"* ]] || [[ "$output" == *"podman"* ]] || {
    echo "Expected runtime mention in error output"
    printf '%s\n' "$output"
    return 1
  }
}

@test "G9: no runtime on PATH (no --runtime) in non-interactive → exit 7 or 9" {
  setup_fresh_project
  install_stub "git" 0
  uninstall_stub "docker"
  uninstall_stub "podman"
  seed_claude_host

  run_aci --install --container --non-interactive
  # Could exit 7 (no runtime found) or 9 (non-interactive without --runtime)
  # depending on whether prereq check fires before runtime selection.
  [ "$status" -eq 7 ] || [ "$status" -eq 9 ] || {
    echo "Expected exit 7 or 9, got $status"
    printf '%s\n' "$output"
    return 1
  }
}

# ─── G10 ─────────────────────────────────────────────────────────────────

@test "G10: hand-edited TOML body triggers fail-closed (codex host)" {
  setup_fresh_project
  setup_container_stubs
  mkdir -p .codex

  # Seed TOML with hand-edited body matching neither uv nor container canonical.
  cat > ".codex/config.toml" <<'EOF'
[mcp_servers.atlas-aci]
command = "atlas-aci"
args = ["serve", "--repo", "/custom/override/path"]
env = {MY_KEY = "1"}
EOF

  run_aci --install --container --runtime docker --host codex --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0 (warn+refuse), got $status"
    printf '%s\n' "$output"
    return 1
  }

  # Warning must appear.
  [[ "$output" == *"non-canonical"* ]] || [[ "$output" == *"Refusing"* ]] || {
    echo "Expected refusal warning in output:"
    printf '%s\n' "$output"
    return 1
  }

  # File must NOT have been overwritten.
  grep -q '/custom/override/path' ".codex/config.toml" || {
    echo "File was overwritten despite R2 guard:"
    cat ".codex/config.toml"
    return 1
  }
}

# ─── G11 ─────────────────────────────────────────────────────────────────

@test "G11: uv canonical .mcp.json, --container invoked → overwritten cleanly" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host

  seed_uv_mcp_json ".mcp.json"

  run_aci --install --container --runtime docker --host claude-code --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0 after mode switch, got $status"
    printf '%s\n' "$output"
    return 1
  }

  run jq -r '.mcpServers["atlas-aci"].command' ".mcp.json"
  [ "$output" = "docker" ] || {
    echo "Expected 'docker' command after mode switch from uv, got: $output"
    cat ".mcp.json"
    return 1
  }

  run jq -r '.mcpServers["atlas-aci"].args[0]' ".mcp.json"
  [ "$output" = "run" ] || {
    echo "Expected args[0]='run', got: $output"
    return 1
  }
}

# ─── G17 ─────────────────────────────────────────────────────────────────

@test "G17: --container --non-interactive without --runtime → exit 9" {
  setup_fresh_project
  install_stub "git" 0
  install_docker_stub
  seed_claude_host

  run_aci --install --container --non-interactive
  [ "$status" -eq 9 ] || {
    echo "Expected exit 9 (non-interactive without --runtime), got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"--runtime"* ]] || {
    echo "Expected --runtime mention in error message:"
    printf '%s\n' "$output"
    return 1
  }
}

# ─── G18 ─────────────────────────────────────────────────────────────────

@test "G18: --container against unchanged image is a no-op (no host writes)" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host

  # First install: builds image, writes .mcp.json.
  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ]
  [ -f ".mcp.json" ] || { echo ".mcp.json not created on first install"; return 1; }
  local first_content
  first_content="$(cat .mcp.json)"

  # Count docker build invocations after first run.
  local first_build_count
  first_build_count="$(docker_build_count)"

  # Second install: image present (sentinel set by first build), configs match → noop.
  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ]

  local second_content
  second_content="$(cat .mcp.json)"
  [ "$first_content" = "$second_content" ] || {
    echo ".mcp.json was rewritten on second install (should be noop):"
    echo "--- first"
    printf '%s\n' "$first_content"
    echo "--- second"
    printf '%s\n' "$second_content"
    return 1
  }

  # docker build must NOT have been called again on second run.
  local second_build_count
  second_build_count="$(docker_build_count)"
  [ "$second_build_count" = "$first_build_count" ] || {
    echo "docker build was called again on noop run (first: $first_build_count, second: $second_build_count)"
    cat "$BATS_TEST_TMPDIR/docker.log"
    return 1
  }
}

# ─── G19 ─────────────────────────────────────────────────────────────────

@test "G19: different digest on second run triggers host config update" {
  setup_fresh_project
  seed_claude_host

  # First run: build with FAKE_DIGEST.
  install_stub "git" 0
  install_docker_stub "$FAKE_DIGEST"

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ]
  [ -f ".mcp.json" ] || { echo ".mcp.json not created on first install"; return 1; }

  run jq -r '.mcpServers["atlas-aci"].args | .[] | select(startswith("atlas-aci@sha256:"))' ".mcp.json"
  local first_ref="$output"
  [[ "$first_ref" == *"$FAKE_DIGEST"* ]] || {
    echo "Expected first digest $FAKE_DIGEST in .mcp.json, got: $first_ref"
    cat ".mcp.json"
    return 1
  }

  # Second run: reinstall docker stub with FAKE_DIGEST_V2.
  # Remove the sentinel so image_exists() returns false → forces rebuild.
  rm -f "$BATS_TEST_TMPDIR/docker.sentinel"
  install_docker_stub "$FAKE_DIGEST_V2"

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ]

  run jq -r '.mcpServers["atlas-aci"].args | .[] | select(startswith("atlas-aci@sha256:"))' ".mcp.json"
  local second_ref="$output"
  [[ "$second_ref" == *"$FAKE_DIGEST_V2"* ]] || {
    echo "Expected updated digest $FAKE_DIGEST_V2 in .mcp.json, got: $second_ref"
    cat ".mcp.json"
    return 1
  }

  [ "$first_ref" != "$second_ref" ] || {
    echo "Digest did not change between runs (both: $first_ref)"
    return 1
  }
}

# ─── Additional coverage ──────────────────────────────────────────────────

@test "container mode: --runtime docker bypasses interactive prompt" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0 when --runtime docker provided, got $status"
    printf '%s\n' "$output"
    return 1
  }
}

@test "container mode: build failure → exit 8" {
  setup_fresh_project
  install_stub "git" 0
  install_docker_stub
  set_docker_build_fail
  seed_claude_host

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 8 ] || {
    echo "Expected exit 8 on build failure, got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"build"* ]] || [[ "$output" == *"Build"* ]] || {
    echo "Expected build failure message:"
    printf '%s\n' "$output"
    return 1
  }
}

@test "container mode: --dry-run does not invoke docker build" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host

  run_aci --install --container --runtime docker --dry-run --non-interactive
  [ "$status" -eq 0 ]

  local build_count
  build_count="$(docker_build_count)"
  [ "$build_count" -eq 0 ] || {
    echo "docker build was called $build_count times during dry-run"
    cat "$BATS_TEST_TMPDIR/docker.log"
    return 1
  }
}

@test "container mode: .atlas/memex created before container index run" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0, got $status"
    printf '%s\n' "$output"
    return 1
  }

  [ -d ".atlas/memex" ] || {
    echo ".atlas/memex directory was not created"
    return 1
  }
}

@test "container mode: unknown --runtime value → exit 2" {
  setup_fresh_project
  seed_claude_host

  run_aci --install --container --runtime nerdctl --non-interactive
  [ "$status" -eq 2 ] || {
    echo "Expected exit 2 for unknown runtime, got $status"
    printf '%s\n' "$output"
    return 1
  }
}
