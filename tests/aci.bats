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
  # inspect_sentinel: separate file — set when image is loaded by digest but
  # NOT tagged locally (simulates `eidolons mcp atlas-aci pull` scenario).
  local inspect_sentinel="${sentinel}.inspect"
  cat > "$STUBS_DIR/$name" <<STUB
#!/usr/bin/env bash
# Auto-generated $name stub — tests/aci.bats
printf '%s\n' "\$*" >> "${logfile}"

case "\$1" in
  images)
    if echo "\$*" | grep -q 'no-trunc'; then
      if [ -f "${sentinel}" ]; then
        printf 'sha256:${fake_digest}\n'
      fi
      exit 0
    fi
    # Repository:Tag format query (image_exists uses this path).
    if [ -f "${sentinel}" ]; then
      printf 'ghcr.io/rynaro/atlas-aci:1.4.2\n'
    fi
    exit 0
    ;;
  image)
    # Handle: docker image inspect REF
    # Used by ensure_image pinned-ref short-circuit (atlas-aci-mcp-install-fix S1/P-B).
    # Returns 0 when either the build sentinel OR the inspect-only sentinel exists.
    if [ -f "${sentinel}" ] || [ -f "${inspect_sentinel}" ]; then
      exit 0
    fi
    exit 1
    ;;
  build)
    if [ -f "${build_fail_file}" ]; then
      printf 'simulated build error\n' >&2
      exit 1
    fi
    touch "${sentinel}"
    exit 0
    ;;
  run)
    # Simulate successful index / serve — create manifest.yaml if indexing.
    # If the run-fail sentinel exists, exit non-zero (index-failure test).
    if echo "\$*" | grep -q 'index'; then
      if [ -f "${sentinel}.run_fail" ]; then
        printf 'simulated index error\n' >&2
        exit 1
      fi
      # simulate_perm_denied: container exits 0 but emits parse_failed + files_indexed=0
      # (SELinux/UID bind-mount mismatch — silent failure path, G2 test).
      if [ -f "${sentinel}.simulate_perm_denied" ]; then
        printf '2026-05-05T20:23:52.947160Z [warning  ] parse_failed                   error='"'"'IO error: Permission denied (os error 13)'"'"' path=/repo/x.ts\n' >&2
        printf '2026-05-05T20:23:59.370231Z [info     ] index_done                     files_indexed=0 refs=0 symbols=0\n' >&2
        exit 0
      fi
      # simulate_empty_lang: container exits 0 with files_indexed=0 but NO parse_failed
      # (docs-only or unsupported-language repo — must NOT trigger the silent-success guard).
      if [ -f "${sentinel}.simulate_empty_lang" ]; then
        printf '2026-05-05T20:23:59.370231Z [info     ] index_done                     files_indexed=0 refs=0 symbols=0\n' >&2
        exit 0
      fi
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

# install_docker_stub_digest_only — image is loaded by digest (docker image inspect returns 0)
# but docker images (tagged) returns empty. Simulates `eidolons mcp atlas-aci pull` having
# been run before `eidolons atlas aci --install`, which is the P-B scenario.
install_docker_stub_digest_only() {
  local fake_digest="${1:-$FAKE_DIGEST}"
  install_docker_stub "$fake_digest"
  touch "$BATS_TEST_TMPDIR/docker.sentinel.inspect"
}

# set_docker_index_run_fail — next docker run with 'index' arg exits 1.
# Used by the "index failure: no MCP config files written" test.
set_docker_index_run_fail() {
  touch "$BATS_TEST_TMPDIR/docker.sentinel.run_fail"
}

# set_docker_index_perm_denied — docker run with 'index' exits 0 but emits
# parse_failed + files_indexed=0 (SELinux/UID silent failure, G2 test).
set_docker_index_perm_denied() {
  touch "$BATS_TEST_TMPDIR/docker.sentinel.simulate_perm_denied"
}

# set_docker_index_empty_lang — docker run with 'index' exits 0 with
# files_indexed=0 and NO parse_failed (docs-only repo, G3 test).
set_docker_index_empty_lang() {
  touch "$BATS_TEST_TMPDIR/docker.sentinel.simulate_empty_lang"
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

# ─── ABS-1 / ABS-2 / ABS-3: absolute project path in MCP bodies ──────────
# Regression coverage for the bug where `.mcp.json` shipped
# `${workspaceFolder}` literal — Cursor expands it natively, but Claude
# Code treats `${VAR}` as env-var lookup and emits "Missing environment
# variables: workspaceFolder" with the docker `-v` mount failing.
# `1.2.1` switched to absolute paths baked at install time; these tests
# pin that down so it can't silently regress.

@test "ABS-1: --container install writes absolute project path in .mcp.json (no \${workspaceFolder})" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ]
  [ -f ".mcp.json" ]

  # The body must NOT contain the legacy placeholder anywhere.
  if grep -q '\${workspaceFolder}' .mcp.json; then
    echo "Regression — .mcp.json still contains \${workspaceFolder}:"
    cat .mcp.json
    return 1
  fi

  # Both -v mounts must reference the absolute project root (cwd at
  # install time = $PWD = the test project dir).
  # Use index-agnostic lookup (matching H3 convention) so future arg
  # insertions don't require updating integer positions here.
  # indices("-v") finds every position of the "-v" flag; adding 1 gives
  # the corresponding mount value position.
  run jq -r '.mcpServers["atlas-aci"].args as $a | $a | indices("-v")[0] + 1 | $a[.]' .mcp.json
  [ "$output" = "${PWD}:/repo:ro" ] || {
    echo "Expected first -v mount = '${PWD}:/repo:ro', got: $output"
    cat .mcp.json
    return 1
  }
  run jq -r '.mcpServers["atlas-aci"].args as $a | $a | indices("-v")[1] + 1 | $a[.]' .mcp.json
  [ "$output" = "${PWD}/.atlas/memex:/memex" ] || {
    echo "Expected second -v mount = '${PWD}/.atlas/memex:/memex', got: $output"
    cat .mcp.json
    return 1
  }
}

@test "ABS-2: uv install writes absolute project path in .mcp.json" {
  setup_fresh_project
  setup_stubs
  seed_claude_host

  run_aci --install --non-interactive
  [ "$status" -eq 0 ]
  [ -f ".mcp.json" ]

  if grep -q '\${workspaceFolder}' .mcp.json; then
    echo "Regression — uv-mode .mcp.json still contains \${workspaceFolder}:"
    cat .mcp.json
    return 1
  fi

  run jq -r '.mcpServers["atlas-aci"].args[2]' .mcp.json
  [ "$output" = "$PWD" ] || {
    echo "Expected --repo arg = '$PWD', got: $output"
    cat .mcp.json
    return 1
  }
  run jq -r '.mcpServers["atlas-aci"].args[4]' .mcp.json
  [ "$output" = "${PWD}/.atlas/memex" ] || {
    echo "Expected --memex-root arg = '${PWD}/.atlas/memex', got: $output"
    cat .mcp.json
    return 1
  }
}

@test "ABS-3: --container install writes absolute path in .codex/config.toml" {
  setup_fresh_project
  setup_container_stubs
  install_stub "atlas-aci" 0 ':'
  : > AGENTS.md   # codex host marker

  run_aci --install --container --runtime docker --non-interactive --host codex
  [ "$status" -eq 0 ]
  [ -f ".codex/config.toml" ]

  if grep -q '\${workspaceFolder}' .codex/config.toml; then
    echo "Regression — .codex/config.toml still contains \${workspaceFolder}:"
    cat .codex/config.toml
    return 1
  fi
  # Must contain the absolute project path verbatim in the args line.
  grep -qF "$PWD:/repo:ro" .codex/config.toml || {
    echo "Expected '$PWD:/repo:ro' literal in .codex/config.toml:"
    cat .codex/config.toml
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

@test "G19: container install writes registry-prefixed image ref to .mcp.json" {
  setup_fresh_project
  seed_claude_host

  # T4: digest is now the ATLAS_ACI_IMAGE_DIGEST constant, not captured from
  # the local docker store. Verify the written .mcp.json uses the full
  # registry-prefixed form: ghcr.io/rynaro/atlas-aci@sha256:<hex>.
  install_stub "git" 0
  install_docker_stub

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ]
  [ -f ".mcp.json" ] || { echo ".mcp.json not created on first install"; return 1; }

  # The args must contain ghcr.io/rynaro/atlas-aci@sha256: (registry-prefixed).
  run jq -r '.mcpServers["atlas-aci"].args | .[] | select(startswith("ghcr.io/rynaro/atlas-aci@sha256:"))' ".mcp.json"
  local ref="$output"
  [ -n "$ref" ] || {
    echo "Expected ghcr.io/rynaro/atlas-aci@sha256:... in .mcp.json args, got nothing."
    jq . ".mcp.json"
    return 1
  }
  [[ "$ref" == "ghcr.io/rynaro/atlas-aci@sha256:"* ]] || {
    echo "Expected registry-prefixed image ref in .mcp.json, got: $ref"
    jq . ".mcp.json"
    return 1
  }

  # The command must be 'docker' (container mode).
  run jq -r '.mcpServers["atlas-aci"].command' ".mcp.json"
  [ "$output" = "docker" ] || {
    echo "Expected 'docker' command in .mcp.json, got: $output"
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

# ─── `index` subcommand ───────────────────────────────────────────────────
# IDX-1 .. IDX-9 cover the new `eidolons atlas aci index` action. The
# command re-runs atlas-aci index against the current project — host or
# container mode auto-detected; no image build, no MCP/.gitignore writes.

@test "IDX-1: positional 'index' runs atlas-aci index in host mode" {
  setup_fresh_project
  install_stub "atlas-aci" 0 'case "$1" in
  index) shift; mkdir -p ./.atlas && printf "regenerated: true\n" > ./.atlas/manifest.yaml ;;
  *) : ;;
esac'

  run_aci index
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0, got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"Mode: host"* ]] || {
    echo "Expected host-mode banner:"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"Re-index complete"* ]] || {
    echo "Expected Re-index complete:"
    printf '%s\n' "$output"
    return 1
  }
  # atlas-aci stub was invoked with `index` as first arg.
  grep -q '^index' "$BATS_TEST_TMPDIR/atlas-aci.log" || {
    echo "atlas-aci index was not invoked"
    cat "$BATS_TEST_TMPDIR/atlas-aci.log" 2>/dev/null || true
    return 1
  }
}

@test "IDX-2: --index flag form is equivalent to positional index" {
  setup_fresh_project
  install_stub "atlas-aci" 0 'case "$1" in
  index) shift; mkdir -p ./.atlas && printf "ok\n" > ./.atlas/manifest.yaml ;;
  *) : ;;
esac'

  run_aci --index
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0, got $status"
    printf '%s\n' "$output"
    return 1
  }
  grep -q '^index' "$BATS_TEST_TMPDIR/atlas-aci.log"
}

@test "IDX-3: index in container mode auto-detects when atlas-aci not on PATH" {
  setup_fresh_project
  install_docker_stub_prebuilt
  # Deliberately no install_stub "atlas-aci" — auto-detect must fall back
  # to container.

  run_aci index
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0, got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"Mode: container (docker, ghcr.io/rynaro/atlas-aci:1.4.2)"* ]] || {
    echo "Expected container-mode banner:"
    printf '%s\n' "$output"
    return 1
  }
  # docker run must have been called with `index`.
  grep -q '^run.*index' "$BATS_TEST_TMPDIR/docker.log" || {
    echo "docker run index was not invoked:"
    cat "$BATS_TEST_TMPDIR/docker.log" 2>/dev/null || true
    return 1
  }
  # No build during index — image was already prebuilt.
  local build_count
  build_count="$(docker_build_count)"
  [ "$build_count" -eq 0 ] || {
    echo "docker build was called $build_count times during index"
    return 1
  }
}

@test "IDX-4: index with no atlas-aci installed anywhere → exit 5" {
  setup_fresh_project
  # No atlas-aci stub, no docker/podman stub. Auto-detect must fail
  # with the prereq-missing exit code.

  run_aci index
  [ "$status" -eq 5 ] || {
    echo "Expected exit 5 (prereq), got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"cannot find an installed atlas-aci"* ]] || {
    echo "Expected actionable error message:"
    printf '%s\n' "$output"
    return 1
  }
}

@test "IDX-5: index forces re-index even when .atlas/manifest.yaml exists (bypasses install gate)" {
  setup_fresh_project
  install_stub "atlas-aci" 0 'case "$1" in
  index) shift; mkdir -p ./.atlas && printf "regenerated: true\n" > ./.atlas/manifest.yaml ;;
  *) : ;;
esac'

  # Pre-existing manifest must NOT short-circuit the index action.
  mkdir -p ./.atlas
  printf 'stale: true\n' > ./.atlas/manifest.yaml

  run_aci index
  [ "$status" -eq 0 ]
  # atlas-aci was actually invoked (gate bypassed).
  grep -q '^index' "$BATS_TEST_TMPDIR/atlas-aci.log" || {
    echo "Index gate was not bypassed — atlas-aci index never ran:"
    cat "$BATS_TEST_TMPDIR/atlas-aci.log" 2>/dev/null || echo "(no log)"
    return 1
  }
  # Manifest was rewritten (stub overwrites it).
  grep -q 'regenerated' ./.atlas/manifest.yaml
}

@test "IDX-6: index --dry-run emits INDEX and touches no disk state" {
  setup_fresh_project
  install_stub "atlas-aci" 0 ':'

  run_aci index --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"INDEX"*".atlas/"* ]] || {
    echo "Expected INDEX action verb in dry-run output:"
    printf '%s\n' "$output"
    return 1
  }
  # No atlas-aci invocation during dry-run.
  [ ! -f "$BATS_TEST_TMPDIR/atlas-aci.log" ] \
    || ! grep -q '^index' "$BATS_TEST_TMPDIR/atlas-aci.log" || {
      echo "atlas-aci was invoked during --dry-run"
      return 1
  }
}

@test "IDX-7: index does NOT write MCP config or .gitignore" {
  setup_fresh_project
  seed_claude_host
  install_stub "atlas-aci" 0 'case "$1" in
  index) shift; mkdir -p ./.atlas && printf "ok\n" > ./.atlas/manifest.yaml ;;
  *) : ;;
esac'

  # Pre-condition: no .mcp.json, no .gitignore.
  [ ! -f .mcp.json ]
  [ ! -f .gitignore ]

  run_aci index
  [ "$status" -eq 0 ]

  # Post-condition: still no .mcp.json, still no .gitignore. Index is a
  # pure data refresh — host wiring stays exactly as the user left it.
  [ ! -f .mcp.json ] || {
    echo ".mcp.json was created by index (should be install's job only)"
    return 1
  }
  [ ! -f .gitignore ] || {
    echo ".gitignore was created by index (should be install's job only)"
    return 1
  }
}

@test "IDX-8: index --container --runtime docker forces container mode even if atlas-aci is on PATH" {
  setup_fresh_project
  install_stub "atlas-aci" 0 ':'      # host binary present …
  install_docker_stub_prebuilt        # … and docker prebuilt image present.

  # User explicitly forces container mode → should ignore the host stub.
  run_aci index --container --runtime docker
  [ "$status" -eq 0 ]
  [[ "$output" == *"Mode: container"* ]]
  grep -q '^run.*index' "$BATS_TEST_TMPDIR/docker.log"
  # Host atlas-aci must NOT have been called.
  [ ! -s "$BATS_TEST_TMPDIR/atlas-aci.log" ] || {
    echo "atlas-aci host binary was called despite --container override"
    cat "$BATS_TEST_TMPDIR/atlas-aci.log"
    return 1
  }
}

# ─── SUB-1 .. SUB-6: Claude Code subagent tools allowlist ────────────────
# Without this, even though .mcp.json wires the atlas-aci MCP server,
# Claude Code refuses to expose its tools to the ATLAS subagent because
# the subagent's `tools:` allowlist doesn't permit `mcp__atlas-aci__*`.
# The agent silently falls back to native Read+Grep instead of using
# the indexed graph. SUB-1..SUB-6 pin the install→remove cycle.

@test "SUB-1: --container --install adds mcp__atlas-aci__* entries to .claude/agents/atlas.md" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host
  seed_claude_atlas_subagent

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ]

  local tools_line
  tools_line="$(grep -E '^tools:' .claude/agents/atlas.md)"
  for tool in view_file list_dir search_text search_symbol graph_query test_dry_run memex_read; do
    [[ "$tools_line" == *"mcp__atlas-aci__$tool"* ]] || {
      echo "Expected mcp__atlas-aci__$tool in tools line:"
      echo "$tools_line"
      return 1
    }
  done
  # Base tools must still be present (extension, not replacement).
  [[ "$tools_line" == *"Read"* ]] && [[ "$tools_line" == *"Grep"* ]] && [[ "$tools_line" == *"Glob"* ]]
}

@test "SUB-2: uv --install also adds mcp__atlas-aci__* entries (host mode → MCP still wired)" {
  setup_fresh_project
  setup_stubs
  seed_claude_host
  seed_claude_atlas_subagent

  run_aci --install --non-interactive
  [ "$status" -eq 0 ]

  grep -E '^tools:.*mcp__atlas-aci__search_symbol' .claude/agents/atlas.md || {
    echo "uv-mode install did not extend the subagent allowlist:"
    grep -E '^tools:' .claude/agents/atlas.md
    return 1
  }
}

@test "SUB-3: two consecutive installs produce byte-identical .claude/agents/atlas.md" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host
  seed_claude_atlas_subagent

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ]
  local first
  first="$(cat .claude/agents/atlas.md)"

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ]
  local second
  second="$(cat .claude/agents/atlas.md)"

  [ "$first" = "$second" ] || {
    echo "Subagent file changed between consecutive installs:"
    diff <(printf '%s\n' "$first") <(printf '%s\n' "$second")
    return 1
  }
}

@test "SUB-4: --remove restores BASE tools allowlist (no mcp__atlas-aci__* entries)" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host
  seed_claude_atlas_subagent

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ]
  grep -q 'mcp__atlas-aci__' .claude/agents/atlas.md   # sanity: install extended

  run_aci --remove --host claude-code --non-interactive
  [ "$status" -eq 0 ]

  ! grep -q 'mcp__atlas-aci__' .claude/agents/atlas.md || {
    echo "Remove did not strip mcp__atlas-aci__* entries:"
    grep -E '^tools:' .claude/agents/atlas.md
    return 1
  }
  grep -qE '^tools: Read, Grep, Glob, Bash\(rg:\*\), Bash\(git log:\*\), Bash\(git show:\*\)$' .claude/agents/atlas.md || {
    echo "Remove did not produce the canonical BASE tools line:"
    grep -E '^tools:' .claude/agents/atlas.md
    return 1
  }
}

@test "SUB-5: --dry-run emits MODIFY .claude/agents/atlas.md and touches no disk state" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host
  seed_claude_atlas_subagent

  local before
  before="$(cat .claude/agents/atlas.md)"

  run_aci --install --container --runtime docker --dry-run --non-interactive
  [ "$status" -eq 0 ]

  [[ "$output" == *"MODIFY"*".claude/agents/atlas.md"* ]] || {
    echo "Expected MODIFY .claude/agents/atlas.md in dry-run output:"
    printf '%s\n' "$output"
    return 1
  }

  local after
  after="$(cat .claude/agents/atlas.md)"
  [ "$before" = "$after" ] || {
    echo "Subagent file modified during --dry-run"
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after")
    return 1
  }
}

@test "SUB-6: install when subagent file is absent is a graceful no-op" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host
  # Deliberately do NOT seed .claude/agents/atlas.md.

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"subagent file absent"* ]] || {
    echo "Expected info message about absent subagent file:"
    printf '%s\n' "$output"
    return 1
  }
  [ ! -f .claude/agents/atlas.md ]   # we did NOT create it (install.sh's job)
}

@test "IDX-9: positional index conflicts with --remove → exit 2" {
  setup_fresh_project
  install_stub "atlas-aci" 0 ':'

  run_aci index --remove
  [ "$status" -eq 2 ] || {
    echo "Expected exit 2 for conflicting actions, got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"Conflicting actions"* ]]
}

# ─── T4 — Registry-prefixed canonical body (spec T4 / ATLAS 1.3.0) ───────
# These tests assert:
#   1. .mcp.json canonical body contains ghcr.io/rynaro/atlas-aci@sha256:
#   2. .codex/config.toml canonical body contains the registry-prefixed form
#   3. The fail-closed comparator accepts both legacy (bare-ref) and
#      registry-prefixed forms during the 1.3.0 transition window.

@test "T4: .mcp.json container canonical body uses ghcr.io/rynaro/atlas-aci@sha256:" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0, got $status:"
    printf '%s\n' "$output"
    return 1
  }
  [ -f ".mcp.json" ] || { echo ".mcp.json was not created"; return 1; }

  # The args array must contain the registry-prefixed image reference.
  run jq -r '.mcpServers["atlas-aci"].args | .[] | select(startswith("ghcr.io/rynaro/atlas-aci@sha256:"))' ".mcp.json"
  [ -n "$output" ] || {
    echo ".mcp.json args do not contain ghcr.io/rynaro/atlas-aci@sha256:..."
    jq . ".mcp.json"
    return 1
  }
  [[ "$output" == "ghcr.io/rynaro/atlas-aci@sha256:"* ]] || {
    echo "Expected registry-prefixed ref, got: $output"
    return 1
  }

  # The bare-ref form (atlas-aci@sha256:) must NOT appear (regression guard).
  run jq -r '.mcpServers["atlas-aci"].args | .[] | select(startswith("atlas-aci@sha256:"))' ".mcp.json"
  [ -z "$output" ] || {
    echo "Found legacy bare-ref atlas-aci@sha256: in .mcp.json — T4 regression:"
    printf '%s\n' "$output"
    jq . ".mcp.json"
    return 1
  }

  # H3: --cap-drop ALL must appear in the args array.
  run jq -r '.mcpServers["atlas-aci"].args | index("--cap-drop")' ".mcp.json"
  [ "$output" != "null" ] || {
    echo "H3: --cap-drop missing from .mcp.json args"
    jq . ".mcp.json"
    return 1
  }
  run jq -r '.mcpServers["atlas-aci"].args | index("ALL")' ".mcp.json"
  [ "$output" != "null" ] || {
    echo "H3: ALL (cap-drop value) missing from .mcp.json args"
    jq . ".mcp.json"
    return 1
  }

  # H3: --security-opt no-new-privileges must appear in the args array.
  run jq -r '.mcpServers["atlas-aci"].args | index("--security-opt")' ".mcp.json"
  [ "$output" != "null" ] || {
    echo "H3: --security-opt missing from .mcp.json args"
    jq . ".mcp.json"
    return 1
  }
  run jq -r '.mcpServers["atlas-aci"].args | index("no-new-privileges")' ".mcp.json"
  [ "$output" != "null" ] || {
    echo "H3: no-new-privileges missing from .mcp.json args"
    jq . ".mcp.json"
    return 1
  }
}

@test "T4: .codex/config.toml container canonical body uses ghcr.io/rynaro/atlas-aci@sha256:" {
  setup_fresh_project
  setup_container_stubs
  mkdir -p .codex

  run_aci --install --container --runtime docker --host codex --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0, got $status:"
    printf '%s\n' "$output"
    return 1
  }
  [ -f ".codex/config.toml" ] || { echo ".codex/config.toml was not created"; return 1; }

  # The args line must contain the registry-prefixed image reference.
  grep -q 'ghcr\.io/rynaro/atlas-aci@sha256:' ".codex/config.toml" || {
    echo ".codex/config.toml does not contain ghcr.io/rynaro/atlas-aci@sha256:"
    cat ".codex/config.toml"
    return 1
  }

  # The bare-ref form must NOT appear (regression guard).
  if grep -q '"atlas-aci@sha256:' ".codex/config.toml"; then
    echo "Found legacy bare-ref atlas-aci@sha256: in .codex/config.toml — T4 regression:"
    cat ".codex/config.toml"
    return 1
  fi

  # H3: security flags must appear in the TOML args line.
  grep -q '"--cap-drop"' ".codex/config.toml" || {
    echo "H3: --cap-drop missing from .codex/config.toml args"
    cat ".codex/config.toml"
    return 1
  }
  grep -q '"ALL"' ".codex/config.toml" || {
    echo "H3: ALL (cap-drop value) missing from .codex/config.toml args"
    cat ".codex/config.toml"
    return 1
  }
  grep -q '"--security-opt"' ".codex/config.toml" || {
    echo "H3: --security-opt missing from .codex/config.toml args"
    cat ".codex/config.toml"
    return 1
  }
  grep -q '"no-new-privileges"' ".codex/config.toml" || {
    echo "H3: no-new-privileges missing from .codex/config.toml args"
    cat ".codex/config.toml"
    return 1
  }
}

@test "T4: fail-closed comparator accepts legacy bare-ref body (transition window)" {
  # Spec T4: the comparator accepts BOTH the old bare-ref body AND the
  # new registry-prefixed body during the 1.3.0 transition window. A
  # pre-existing .mcp.json with the legacy bare-ref form must be upgraded
  # (not refused) when --container is re-run.
  setup_fresh_project
  setup_container_stubs
  seed_claude_host

  # Seed .mcp.json with the legacy bare-ref container body (pre-1.3.0 form).
  cat > ".mcp.json" <<'EOF'
{
  "mcpServers": {
    "atlas-aci": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i", "--read-only",
        "-v", "${workspaceFolder}:/repo:ro",
        "-v", "${workspaceFolder}/.atlas/memex:/memex",
        "atlas-aci@sha256:aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899",
        "serve", "--repo", "/repo", "--memex-root", "/memex"
      ]
    }
  }
}
EOF

  # Re-run --container: should NOT refuse; should upgrade to registry-prefixed form.
  run_aci --install --container --runtime docker --host claude-code --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0 (legacy body accepted + upgraded), got $status:"
    printf '%s\n' "$output"
    return 1
  }

  # After upgrade, the args must contain the registry-prefixed form.
  run jq -r '.mcpServers["atlas-aci"].args | .[] | select(startswith("ghcr.io/rynaro/atlas-aci@sha256:"))' ".mcp.json"
  [ -n "$output" ] || {
    echo "After legacy-upgrade, expected ghcr.io/rynaro/atlas-aci@sha256: in .mcp.json"
    jq . ".mcp.json"
    return 1
  }
}

# ─── H3 — Security-flag hardening (spec H3 / ATLAS 1.3.0) ────────────────
# These tests assert:
#   1. --cap-drop ALL and --security-opt no-new-privileges appear in the
#      rendered canonical body for .mcp.json, .codex/config.toml, and
#      the copilot agent.md output.
#   2. Negative: --privileged, --cap-add, and --security-opt seccomp=unconfined
#      must NOT appear in any canonical body (escalation-flag guard).

@test "H3: copilot agent.md canonical body includes --cap-drop ALL and --security-opt no-new-privileges" {
  setup_fresh_project
  setup_container_stubs
  # Set up a copilot .agent.md file with the required frontmatter.
  mkdir -p ".github/agents"
  cat > ".github/agents/atlas.agent.md" <<'EOF'
---
name: atlas-aci
tools:
  mcp_servers: []
---
ATLAS agent.
EOF

  run_aci --install --container --runtime docker --host copilot --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0, got $status:"
    printf '%s\n' "$output"
    return 1
  }

  local agent_file=".github/agents/atlas.agent.md"
  [ -f "$agent_file" ] || { echo "$agent_file was not found"; return 1; }

  # The command field in the YAML frontmatter must contain the security flags.
  grep -q '\-\-cap-drop' "$agent_file" || {
    echo "H3: --cap-drop missing from $agent_file"
    cat "$agent_file"
    return 1
  }
  grep -q 'ALL' "$agent_file" || {
    echo "H3: ALL (cap-drop value) missing from $agent_file"
    cat "$agent_file"
    return 1
  }
  grep -q '\-\-security-opt' "$agent_file" || {
    echo "H3: --security-opt missing from $agent_file"
    cat "$agent_file"
    return 1
  }
  grep -q 'no-new-privileges' "$agent_file" || {
    echo "H3: no-new-privileges missing from $agent_file"
    cat "$agent_file"
    return 1
  }
}

@test "H3: canonical body must NOT include escalation flags (--privileged, --cap-add, seccomp=unconfined)" {
  # Negative test: no escalation flags must appear in the rendered canonical
  # body for .mcp.json or .codex/config.toml.
  setup_fresh_project
  setup_container_stubs
  seed_claude_host
  mkdir -p .codex

  # Install claude-code host (writes .mcp.json).
  run_aci --install --container --runtime docker --host claude-code --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0, got $status:"
    printf '%s\n' "$output"
    return 1
  }

  # Install codex host (writes .codex/config.toml).
  run_aci --install --container --runtime docker --host codex --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0 (codex), got $status:"
    printf '%s\n' "$output"
    return 1
  }

  # .mcp.json must not contain escalation flags.
  run jq -r '.mcpServers["atlas-aci"].args | .[]' ".mcp.json"
  printf '%s\n' "$output" | grep -q -- '--privileged' && {
    echo "ESCALATION: --privileged found in .mcp.json args"
    jq . ".mcp.json"
    return 1
  }
  printf '%s\n' "$output" | grep -q -- '--cap-add' && {
    echo "ESCALATION: --cap-add found in .mcp.json args"
    jq . ".mcp.json"
    return 1
  }
  printf '%s\n' "$output" | grep -q 'seccomp=unconfined' && {
    echo "ESCALATION: seccomp=unconfined found in .mcp.json args"
    jq . ".mcp.json"
    return 1
  }

  # .codex/config.toml must not contain escalation flags.
  if grep -q -- '--privileged' ".codex/config.toml" 2>/dev/null; then
    echo "ESCALATION: --privileged found in .codex/config.toml"
    cat ".codex/config.toml"
    return 1
  fi
  if grep -q -- '--cap-add' ".codex/config.toml" 2>/dev/null; then
    echo "ESCALATION: --cap-add found in .codex/config.toml"
    cat ".codex/config.toml"
    return 1
  fi
  if grep -q 'seccomp=unconfined' ".codex/config.toml" 2>/dev/null; then
    echo "ESCALATION: seccomp=unconfined found in .codex/config.toml"
    cat ".codex/config.toml"
    return 1
  fi
  true
}

# ─── T4 tests (atlas-aci-mcp-install-fix-2026-05-04) ─────────────────────
# Three cases covering: fresh-project memex pre-creation + UID flag,
# image-already-loaded build skip, and fail-closed write boundary.

@test "T4-1: fresh project with no .atlas/memex/: index succeeds, docker run has -u and writable /memex" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host

  # Confirm .atlas/memex does NOT exist before the install.
  [ ! -d ".atlas/memex" ] || {
    rm -rf .atlas
  }

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0, got $status:"
    printf '%s\n' "$output"
    return 1
  }

  # .atlas/memex must have been created.
  [ -d ".atlas/memex" ] || {
    echo ".atlas/memex was not created before docker run"
    return 1
  }

  # The docker run line in docker.log must contain -u (UID:GID flag).
  grep -q '\-u' "$BATS_TEST_TMPDIR/docker.log" || {
    echo "docker run log missing -u flag:"
    cat "$BATS_TEST_TMPDIR/docker.log"
    return 1
  }

  # The /memex bind in docker.log must NOT have a :ro suffix
  # (it must be writable — docker.log records args as a single space-separated line).
  if grep '\.atlas/memex:/memex:ro' "$BATS_TEST_TMPDIR/docker.log" 2>/dev/null; then
    echo "docker.log shows .atlas/memex:/memex:ro — memex mount must be writable:"
    cat "$BATS_TEST_TMPDIR/docker.log"
    return 1
  fi
  # And it must appear at all.
  grep -q '\.atlas/memex:/memex' "$BATS_TEST_TMPDIR/docker.log" || {
    echo "docker.log missing .atlas/memex:/memex mount:"
    cat "$BATS_TEST_TMPDIR/docker.log"
    return 1
  }
}

@test "T4-2: image already loaded via docker image inspect: build is skipped" {
  setup_fresh_project
  # Stub with inspect-only sentinel — docker image inspect returns 0
  # but docker images (tagged) returns empty. This simulates the P-B scenario
  # where `eidolons mcp atlas-aci pull` loaded the image by digest reference
  # but the local tag does not exist yet.
  install_stub "git" 0
  install_docker_stub_digest_only
  seed_claude_host

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0, got $status:"
    printf '%s\n' "$output"
    return 1
  }

  # docker build must NOT have been invoked.
  local build_count
  build_count="$(docker_build_count)"
  [ "$build_count" -eq 0 ] || {
    echo "Expected 0 docker build invocations, got $build_count:"
    cat "$BATS_TEST_TMPDIR/docker.log"
    return 1
  }

  # stderr (captured in $output by bats run) must mention "image already loaded".
  [[ "$output" == *"image already loaded"* ]] || {
    echo "Expected 'image already loaded' in stderr output:"
    printf '%s\n' "$output"
    return 1
  }
}

@test "T4-3: index failure: no MCP config files written, verbatim error strings on stderr, non-zero exit" {
  setup_fresh_project
  setup_container_stubs
  set_docker_index_run_fail
  seed_claude_host

  # Capture pre-install state of config files that must NOT be created.
  local mcp_before codex_before agents_before
  mcp_before="$(cat ".mcp.json" 2>/dev/null || printf 'ABSENT')"
  codex_before="$(cat ".codex/config.toml" 2>/dev/null || printf 'ABSENT')"
  agents_before="$(cat "AGENTS.md" 2>/dev/null || printf 'ABSENT')"

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -ne 0 ] || {
    echo "Expected non-zero exit on index failure, got 0"
    printf '%s\n' "$output"
    return 1
  }

  # Verbatim error strings must appear in stderr output.
  [[ "$output" == *"atlas-aci container index failed — aborting before MCP config writes."* ]] || {
    echo "Missing verbatim error string 1 in output:"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"No MCP config files were modified."* ]] || {
    echo "Missing verbatim error string 2 in output:"
    printf '%s\n' "$output"
    return 1
  }

  # Config files must be byte-identical to pre-install state (i.e., absent = still absent).
  local mcp_after codex_after agents_after
  mcp_after="$(cat ".mcp.json" 2>/dev/null || printf 'ABSENT')"
  codex_after="$(cat ".codex/config.toml" 2>/dev/null || printf 'ABSENT')"
  agents_after="$(cat "AGENTS.md" 2>/dev/null || printf 'ABSENT')"

  [ "$mcp_after" = "$mcp_before" ] || {
    echo ".mcp.json was modified despite index failure"
    echo "before: $mcp_before"
    echo "after:  $mcp_after"
    return 1
  }
  [ "$codex_after" = "$codex_before" ] || {
    echo ".codex/config.toml was modified despite index failure"
    return 1
  }
  [ "$agents_after" = "$agents_before" ] || {
    echo "AGENTS.md was modified despite index failure"
    return 1
  }
}

# ─── T1 tests (atlas-aci-container-uid-perm-fix-2026-05-05) ──────────────
# G2: silent-success guard — files_indexed=0 + parse_failed → fail loudly.
# G3: empty-lang repo (files_indexed=0, no parse_failed) → success, MCP written.
# G-T1.selinux-suffix-when-enforcing: :Z appended when SELinux Enforcing.
# G-T1.canonical-body-includes-u-flag: .mcp.json args contains -u <uid>:<gid>.

@test "G2-T1.silent-success-fires: files_indexed=0 + parse_failed triggers exit_index_fail, no MCP writes" {
  setup_fresh_project
  setup_container_stubs
  set_docker_index_perm_denied
  seed_claude_host

  # Capture pre-install state of config files that must NOT be created.
  local mcp_before codex_before agents_before
  mcp_before="$(cat ".mcp.json" 2>/dev/null || printf 'ABSENT')"
  codex_before="$(cat ".codex/config.toml" 2>/dev/null || printf 'ABSENT')"
  agents_before="$(cat "AGENTS.md" 2>/dev/null || printf 'ABSENT')"

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -ne 0 ] || {
    echo "Expected non-zero exit on silent-success (perm denied) path, got 0"
    printf '%s\n' "$output"
    return 1
  }

  # Verbatim error strings must appear in stderr output.
  [[ "$output" == *"atlas-aci indexed 0 files but emitted parse_failed warnings"* ]] || {
    echo "Missing verbatim silent-success error string in output:"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"No MCP config files were modified."* ]] || {
    echo "Missing 'No MCP config files were modified.' in output:"
    printf '%s\n' "$output"
    return 1
  }

  # Config files must be byte-identical to pre-install state.
  local mcp_after codex_after agents_after
  mcp_after="$(cat ".mcp.json" 2>/dev/null || printf 'ABSENT')"
  codex_after="$(cat ".codex/config.toml" 2>/dev/null || printf 'ABSENT')"
  agents_after="$(cat "AGENTS.md" 2>/dev/null || printf 'ABSENT')"

  [ "$mcp_after" = "$mcp_before" ] || {
    echo ".mcp.json was modified despite silent-success guard"
    echo "before: $mcp_before"
    echo "after:  $mcp_after"
    return 1
  }
  [ "$codex_after" = "$codex_before" ] || {
    echo ".codex/config.toml was modified despite silent-success guard"
    return 1
  }
  [ "$agents_after" = "$agents_before" ] || {
    echo "AGENTS.md was modified despite silent-success guard"
    return 1
  }
}

@test "G3-T1.empty-lang-no-false-fail: files_indexed=0 without parse_failed succeeds and writes MCP config" {
  setup_fresh_project
  setup_container_stubs
  set_docker_index_empty_lang
  seed_claude_host

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0 for empty-lang repo (no parse_failed), got $status:"
    printf '%s\n' "$output"
    return 1
  }

  # Output must contain the success message.
  [[ "$output" == *"Indexed → .atlas/"* ]] || {
    echo "Expected 'Indexed → .atlas/' in output:"
    printf '%s\n' "$output"
    return 1
  }

  # .mcp.json must have been written.
  [ -f ".mcp.json" ] || {
    echo ".mcp.json was not written for empty-lang repo"
    return 1
  }
  assert_mcp_json_contains ".mcp.json" "atlas-aci"
}

@test "G-T1.selinux-suffix-when-enforcing: :Z appended to volume mounts when SELinux Enforcing (Linux only)" {
  # Skip on non-Linux — SELinux is a Linux kernel feature.
  if [ "$(uname -s)" != "Linux" ]; then
    skip "SELinux test only runs on Linux"
  fi

  setup_fresh_project
  seed_claude_host

  # Stub getenforce to return "Enforcing".
  install_stub "getenforce" 0 'printf "Enforcing\n"'
  # Stub uname to report Linux (it already is, but be explicit in PATH).
  install_stub "git" 0
  install_docker_stub

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0 with getenforce=Enforcing, got $status:"
    printf '%s\n' "$output"
    return 1
  }

  # docker.log must contain :Z in the volume mount arguments for the index run.
  grep -q ':Z' "$BATS_TEST_TMPDIR/docker.log" || {
    echo "Expected :Z in docker.log volume mounts (SELinux Enforcing path):"
    cat "$BATS_TEST_TMPDIR/docker.log"
    return 1
  }
}

@test "G-T1.selinux-no-suffix-when-permissive: no :Z when getenforce returns Permissive (Linux only)" {
  if [ "$(uname -s)" != "Linux" ]; then
    skip "SELinux test only runs on Linux"
  fi

  setup_fresh_project
  seed_claude_host

  # Stub getenforce to return "Permissive".
  install_stub "getenforce" 0 'printf "Permissive\n"'
  install_stub "git" 0
  install_docker_stub

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0 with getenforce=Permissive, got $status:"
    printf '%s\n' "$output"
    return 1
  }

  # docker.log must NOT contain :Z for volume mounts.
  if grep -q ':Z' "$BATS_TEST_TMPDIR/docker.log" 2>/dev/null; then
    echo "Unexpected :Z in docker.log (getenforce=Permissive should not add :Z):"
    cat "$BATS_TEST_TMPDIR/docker.log"
    return 1
  fi
}

@test "G-T1.canonical-body-includes-u-flag: .mcp.json args contains -u <uid>:<gid>" {
  setup_fresh_project
  setup_container_stubs
  seed_claude_host

  run_aci --install --container --runtime docker --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0, got $status:"
    printf '%s\n' "$output"
    return 1
  }

  [ -f ".mcp.json" ] || {
    echo ".mcp.json not created"
    return 1
  }

  local expected_uid_gid
  expected_uid_gid="$(id -u):$(id -g)"

  # .mcp.json args array must contain "-u" followed by "<uid>:<gid>".
  local has_u_flag
  has_u_flag="$(jq -r '
    .mcpServers["atlas-aci"].args
    | to_entries[]
    | select(.value == "-u")
    | .key
  ' ".mcp.json" 2>/dev/null)"

  [ -n "$has_u_flag" ] || {
    echo "Expected -u flag in .mcp.json args:"
    jq '.mcpServers["atlas-aci"].args' ".mcp.json"
    return 1
  }

  # The element immediately after -u must be "<uid>:<gid>".
  local u_val
  u_val="$(jq -r --arg idx "$has_u_flag" '
    .mcpServers["atlas-aci"].args[($idx | tonumber) + 1]
  ' ".mcp.json" 2>/dev/null)"

  [ "$u_val" = "$expected_uid_gid" ] || {
    echo "Expected -u value '$expected_uid_gid', got '$u_val'"
    jq '.mcpServers["atlas-aci"].args' ".mcp.json"
    return 1
  }
}
