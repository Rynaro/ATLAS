#!/usr/bin/env bats
# tests/wire_rename.bats — T-WIRE-1..4 from SPEC-2026-05-27-ATLAS-ACI-UX-FIXES §6.1
#
# Validates the P1 rename: `install` → `wire` (hard rename, no alias).
# Exit-2 paths assert the exact error strings the spec mandates.

load helpers

# ─── T-WIRE-1 ─────────────────────────────────────────────────────────────

@test "T-WIRE-1: default action (no positional) runs wire" {
  setup_fresh_project
  setup_stubs
  seed_claude_host

  run_aci --host claude-code --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Expected exit 0 for default action, got $status"
    printf '%s\n' "$output"
    return 1
  }
  # Wire should produce the wired-ok message.
  [[ "$output" == *"wired"* ]] || [[ "$output" == *"wire"* ]] || [[ "$output" == *"✓"* ]] || {
    echo "Expected wire success output:"
    printf '%s\n' "$output"
    return 1
  }
}

# ─── T-WIRE-2 ─────────────────────────────────────────────────────────────

@test "T-WIRE-2: positional install exits 2 with rename hint" {
  setup_fresh_project

  run_aci install
  [ "$status" -eq 2 ] || {
    echo "Expected exit 2 for legacy 'install' positional, got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"Unknown action: install"* ]] || {
    echo "Expected 'Unknown action: install' in output:"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"did you mean 'wire'"* ]] || {
    echo "Expected \"did you mean 'wire'\" in output:"
    printf '%s\n' "$output"
    return 1
  }
}

# ─── T-WIRE-3 ─────────────────────────────────────────────────────────────

@test "T-WIRE-3: --install flag exits 2 with rename hint" {
  setup_fresh_project

  run_aci --install
  [ "$status" -eq 2 ] || {
    echo "Expected exit 2 for legacy --install flag, got $status"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"Unknown option: --install"* ]] || {
    echo "Expected 'Unknown option: --install' in output:"
    printf '%s\n' "$output"
    return 1
  }
  [[ "$output" == *"did you mean 'wire'"* ]] || {
    echo "Expected \"did you mean 'wire'\" in output:"
    printf '%s\n' "$output"
    return 1
  }
}

# ─── T-WIRE-4 ─────────────────────────────────────────────────────────────

@test "T-WIRE-4: wire is idempotent across two runs" {
  setup_fresh_project
  setup_stubs
  seed_claude_host

  # First run.
  run_aci wire --host claude-code --non-interactive
  [ "$status" -eq 0 ] || {
    echo "First wire run failed:"
    printf '%s\n' "$output"
    return 1
  }

  # Snapshot mtimes after first run.
  local after_first
  after_first="$(snapshot_mtimes "$TEST_PROJECT")"

  # Second run.
  run_aci wire --host claude-code --non-interactive
  [ "$status" -eq 0 ] || {
    echo "Second wire run failed:"
    printf '%s\n' "$output"
    return 1
  }

  local after_second
  after_second="$(snapshot_mtimes "$TEST_PROJECT")"

  # File mtimes must not change on idempotent run.
  [ "$after_first" = "$after_second" ] || {
    echo "Files changed on second wire run (expected idempotent):"
    diff <(printf '%s\n' "$after_first") <(printf '%s\n' "$after_second")
    return 1
  }
}
