#!/usr/bin/env bats
# tests/index_digest.bats — T-IDX-1..4 from SPEC-2026-05-27-ATLAS-ACI-UX-FIXES §6.1
#
# Validates the P3 digest-aware index:
#   T-IDX-1: digest-pulled image (no tag) detected via docker image inspect
#   T-IDX-2: self-built tagged image detected via tag fallback
#   T-IDX-3: no image anywhere → exit 5 with new error wording (no "re-run install")
#   T-IDX-4: stale tag present → distinguished exit 5 message

load helpers

# The docker stub helpers live in aci.bats; we need to duplicate the local
# stubs here or source from aci.bats. Since bats loads the helpers.bash
# setup, we define the same stubs directly here for isolation.

# ─── Local stub helpers ────────────────────────────────────────────────────

FAKE_DIGEST_LOCAL="aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"

# _install_local_docker_stub — base docker stub (no prebuilt image).
#
# Sentinel files honoured by the stub:
#   ${BATS_TEST_TMPDIR}/docker.sentinel              — `docker images` returns a tag.
#   ${BATS_TEST_TMPDIR}/docker.sentinel.inspect      — `docker image inspect` succeeds.
#   ${BATS_TEST_TMPDIR}/docker.images_tag_match      — when present, the tag emitted
#       by `docker images` is the contents of this file (e.g. the live ATLAS_VERSION
#       placeholder, so the tag-fallback grep in detect_index_mode hits).
#       Absent → emits the stale literal ':1.4.2', exercising the stale-tag path.
_install_local_docker_stub() {
  local logfile="$BATS_TEST_TMPDIR/docker.log"
  local sentinel="$BATS_TEST_TMPDIR/docker.sentinel"
  local inspect_sentinel="${sentinel}.inspect"
  local tag_match_file="$BATS_TEST_TMPDIR/docker.images_tag_match"
  local build_fail_file="$BATS_TEST_TMPDIR/docker.build_fail"
  rm -f "$sentinel" "$build_fail_file"
  cat > "$STUBS_DIR/docker" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${logfile}"
case "\$1" in
  images)
    # Repository:Tag format query (tag fallback path).
    if [ -f "${sentinel}" ]; then
      if [ -f "${tag_match_file}" ]; then
        # Test wants tag-fallback HIT — emit whatever tag the test pinned.
        cat "${tag_match_file}"
      else
        # Default: emit a stale tag so the stale-tag probe fires.
        printf 'ghcr.io/rynaro/atlas-aci:1.4.2\n'
      fi
    fi
    exit 0
    ;;
  image)
    # docker image inspect REF — digest-first probe.
    # Only the inspect_sentinel signals digest presence. The plain `sentinel`
    # is the *tag-fallback* sentinel only — keeping them decoupled lets
    # T-IDX-2 exercise tag-fallback (no digest), T-IDX-4 exercise stale-tag
    # (no digest, wrong tag), and T-IDX-1 exercise digest-only (no tag).
    if [ -f "${inspect_sentinel}" ]; then
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
  chmod +x "$STUBS_DIR/docker"
  : > "$logfile"
}

# ─── T-IDX-1 ──────────────────────────────────────────────────────────────

@test "T-IDX-1: digest-pulled image (no tag) detected via docker image inspect" {
  setup_fresh_project

  # Simulate `eidolons mcp atlas-aci pull` scenario:
  # docker image inspect @sha256:... succeeds but docker images returns empty.
  _install_local_docker_stub
  touch "$BATS_TEST_TMPDIR/docker.sentinel.inspect"
  # No atlas-aci on PATH.

  run_aci index
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0 (digest-pulled image detected), got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"Mode: container (docker"* ]] || {
    echo "Expected 'Mode: container (docker' in output:"
    printf '%s\n' "$output"
    return 1
  }
}

# ─── T-IDX-2 ──────────────────────────────────────────────────────────────

@test "T-IDX-2: self-built tagged image without digest match detected via tag fallback" {
  setup_fresh_project

  # Simulate self-built image: docker image inspect fails (no digest ref),
  # but docker images returns a tag for the image ref.
  _install_local_docker_stub
  # Set sentinel so docker images returns the tag; but NOT inspect_sentinel.
  touch "$BATS_TEST_TMPDIR/docker.sentinel"
  # Pin the tag to whatever ATLAS_VERSION is in the source script so the
  # tag-fallback grep hits (handles the __ATLAS_VERSION__ placeholder
  # pre-substitution AND any real version post-substitution).
  local _src_ver
  _src_ver="$(grep '^ATLAS_VERSION=' "$ACI_SCRIPT" | head -n1 | sed 's/ATLAS_VERSION="//;s/"//')"
  printf 'ghcr.io/rynaro/atlas-aci:%s\n' "$_src_ver" > "$BATS_TEST_TMPDIR/docker.images_tag_match"
  # No atlas-aci on PATH.

  run_aci index
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0 (self-built tag fallback), got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"Mode: container"* ]] || {
    echo "Expected container mode in output:"
    printf '%s\n' "$output"
    return 1
  }
}

# ─── T-IDX-3 ──────────────────────────────────────────────────────────────

@test "T-IDX-3: no image anywhere → exit 5 with new wording (no 're-run install')" {
  setup_fresh_project

  # No atlas-aci on PATH, no docker image. Docker command itself may not be
  # present — uninstall it and podman to ensure clean no-image scenario.
  _install_local_docker_stub
  # Ensure both sentinels are absent (image not present).
  # No atlas-aci stub.

  run_aci index
  [ "$status" -eq 5 ] || {
    echo "Expected exit 5 (no installation detected), got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"no installation detected"* ]] || {
    echo "Expected 'no installation detected' in output:"
    printf '%s\n' "$output"
    return 1
  }
  # The old "re-run install" phrasing must NOT appear.
  if [[ "$output" == *"re-run install"* ]]; then
    echo "FAIL: found legacy 're-run install' in exit-5 message"
    printf '%s\n' "$output"
    return 1
  fi
}

# ─── T-IDX-4 ──────────────────────────────────────────────────────────────

@test "T-IDX-4: stale tag present → distinguished exit 5 message" {
  setup_fresh_project

  # Stub: docker image inspect fails (no digest match), but docker images
  # returns an old tag (1.4.2). The stale-tag probe must catch this and
  # emit a version-mismatch message rather than the generic no-image error.
  _install_local_docker_stub
  # Set sentinel so docker images returns the stale 1.4.2 tag.
  touch "$BATS_TEST_TMPDIR/docker.sentinel"
  # Ensure no digest-match by NOT setting inspect_sentinel.
  # Also ensure atlas-aci is NOT on PATH (no host fallback).

  # Override docker images to return only the stale tag (already done
  # by the local stub above — returns 1.4.2 when sentinel is set).

  run_aci index
  [ "$status" -eq 5 ] || {
    echo "Expected exit 5 (stale tag mismatch), got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"image present but version mismatch"* ]] || {
    echo "Expected 'image present but version mismatch' in exit-5 output:"
    printf '%s\n' "$output"
    return 1
  }
}
