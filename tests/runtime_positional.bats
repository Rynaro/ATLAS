#!/usr/bin/env bats
# tests/runtime_positional.bats — T-RT-1..8 from SPEC-2026-05-27-ATLAS-ACI-UX-FIXES §6.1
#
# Validates the P2 positional runtime:
#   atlas aci wire [docker|podman]   — container mode
#   atlas aci wire                   — host mode (no positional)
#   atlas aci wire <unknown>         — exit 2 with hint
#   atlas aci wire podman            — exit 7 if podman absent
#   --container / --runtime flags    — exit 2 (removed in v1.8.0)
#   atlas aci index docker           — positional also applies to index

load helpers

# ─── Local stub helpers ────────────────────────────────────────────────────

# _rt_install_docker_stub — minimal happy-path docker stub.
_rt_install_docker_stub() {
  local logfile="$BATS_TEST_TMPDIR/docker.log"
  local sentinel="$BATS_TEST_TMPDIR/docker.sentinel"
  local inspect_sentinel="${sentinel}.inspect"
  rm -f "$sentinel"
  cat > "$STUBS_DIR/docker" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${logfile}"
case "\$1" in
  images)
    if [ -f "${sentinel}" ]; then
      printf 'ghcr.io/rynaro/atlas-aci:placeholder\n'
    fi
    exit 0 ;;
  image)
    if [ -f "${sentinel}" ] || [ -f "${inspect_sentinel}" ]; then exit 0; fi
    exit 1 ;;
  build)
    touch "${sentinel}"; exit 0 ;;
  run)
    if echo "\$*" | grep -q 'index'; then
      mkdir -p ./.atlas
      printf 'generated: true\n' > ./.atlas/manifest.yaml
    fi
    exit 0 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$STUBS_DIR/docker"
  : > "$logfile"
}

# _rt_install_podman_stub — minimal happy-path podman stub.
_rt_install_podman_stub() {
  local logfile="$BATS_TEST_TMPDIR/podman.log"
  local sentinel="$BATS_TEST_TMPDIR/podman.sentinel"
  local inspect_sentinel="${sentinel}.inspect"
  rm -f "$sentinel"
  cat > "$STUBS_DIR/podman" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${logfile}"
case "\$1" in
  images)
    if [ -f "${sentinel}" ]; then
      printf 'ghcr.io/rynaro/atlas-aci:placeholder\n'
    fi
    exit 0 ;;
  image)
    if [ -f "${sentinel}" ] || [ -f "${inspect_sentinel}" ]; then exit 0; fi
    exit 1 ;;
  build)
    touch "${sentinel}"; exit 0 ;;
  run)
    if echo "\$*" | grep -q 'index'; then
      mkdir -p ./.atlas
      printf 'generated: true\n' > ./.atlas/manifest.yaml
    fi
    exit 0 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$STUBS_DIR/podman"
  : > "$logfile"
}

# _rt_install_docker_prebuilt — docker with image already present.
_rt_install_docker_prebuilt() {
  _rt_install_docker_stub
  touch "$BATS_TEST_TMPDIR/docker.sentinel.inspect"
}

# ─── T-RT-1 ───────────────────────────────────────────────────────────────

@test "T-RT-1: wire with no runtime positional → host mode" {
  setup_fresh_project
  setup_stubs
  seed_claude_host

  run_aci wire --host claude-code --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0 for host mode, got $status"
    printf '%s\n' "$output"
    return 1
  }
  # Host mode: Mode: host banner is emitted during wire.
  [[ "$output" == *"Mode: host"* ]] || [[ "$output" == *"uv"* ]] || {
    echo "Expected host mode output (Mode: host or uv):"
    printf '%s\n' "$output"
    return 1
  }
}

# ─── T-RT-2 ───────────────────────────────────────────────────────────────

@test "T-RT-2: wire docker positional → container/docker" {
  setup_fresh_project
  install_stub "git" 0
  _rt_install_docker_stub
  seed_claude_host

  run_aci wire docker --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0 for wire docker, got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"Mode: container (docker"* ]] || {
    echo "Expected 'Mode: container (docker' in output:"
    printf '%s\n' "$output"
    return 1
  }
}

# ─── T-RT-3 ───────────────────────────────────────────────────────────────

@test "T-RT-3: wire podman positional → container/podman" {
  setup_fresh_project
  install_stub "git" 0
  _rt_install_podman_stub
  seed_claude_host

  run_aci wire podman --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0 for wire podman, got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"Mode: container (podman"* ]] || {
    echo "Expected 'Mode: container (podman' in output:"
    printf '%s\n' "$output"
    return 1
  }
}

# ─── T-RT-4 ───────────────────────────────────────────────────────────────

@test "T-RT-4: wire with unknown runtime positional → exit 2" {
  setup_fresh_project
  seed_claude_host

  run_aci wire foo --non-interactive
  [ "$status" -eq 2 ] || {
    echo "Expected exit 2 for unknown runtime 'foo', got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"Unknown runtime: foo"* ]] || {
    echo "Expected 'Unknown runtime: foo' in output:"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"allowed: docker, podman"* ]] || {
    echo "Expected 'allowed: docker, podman' in output:"
    printf '%s\n' "$output"
    return 1
  }
}

# ─── T-RT-5 ───────────────────────────────────────────────────────────────

@test "T-RT-5: wire podman with podman absent → exit 7" {
  setup_fresh_project
  install_stub "git" 0
  # Ensure podman is NOT on PATH.
  uninstall_stub "podman"
  seed_claude_host

  run_aci wire podman --non-interactive
  [ "$status" -eq 7 ] || {
    echo "Expected exit 7 (requested runtime not on PATH), got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"requested runtime 'podman' is not on PATH"* ]] || {
    echo "Expected PATH-error message for podman:"
    printf '%s\n' "$output"
    return 1
  }
}

# ─── T-RT-6 ───────────────────────────────────────────────────────────────

@test "T-RT-6: --container flag → exit 2 (removed in v1.8.0)" {
  setup_fresh_project
  seed_claude_host

  run_aci --container --non-interactive
  [ "$status" -eq 2 ] || {
    echo "Expected exit 2 for removed --container flag, got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"Unknown option: --container"* ]] || {
    echo "Expected 'Unknown option: --container' in output:"
    printf '%s\n' "$output"
    return 1
  }
}

# ─── T-RT-7 ───────────────────────────────────────────────────────────────

@test "T-RT-7: --runtime flag → exit 2 (removed in v1.8.0)" {
  setup_fresh_project
  seed_claude_host

  run_aci --runtime docker --non-interactive
  [ "$status" -eq 2 ] || {
    echo "Expected exit 2 for removed --runtime flag, got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"Unknown option: --runtime"* ]] || {
    echo "Expected 'Unknown option: --runtime' in output:"
    printf '%s\n' "$output"
    return 1
  }
}

# ─── T-RT-8 ───────────────────────────────────────────────────────────────

@test "T-RT-8: index docker positional → container mode honoured" {
  setup_fresh_project
  _rt_install_docker_prebuilt
  # Deliberately no install_stub "atlas-aci" — user explicitly requests docker.

  run_aci index docker
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0 for 'index docker', got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"Mode: container (docker"* ]] || {
    echo "Expected 'Mode: container (docker' in output:"
    printf '%s\n' "$output"
    return 1
  }
}
