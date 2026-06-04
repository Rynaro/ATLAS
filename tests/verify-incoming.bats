#!/usr/bin/env bats
# tests/verify-incoming.bats — verify-incoming skill gate tests.
#
# Asserts:
#   S1: skills/verify-incoming.md exists in the repo and declares BLOCKING posture.
#   S2: skills/verify-incoming.md does NOT declare warn-only / process-anyway.
#   S3: install.sh (non-interactive, into a temp target) installs
#       skills/verify-incoming.md and records it in the install manifest.

load helpers

# ─── S1 ─────────────────────────────────────────────────────────────────────

@test "S1: skills/verify-incoming.md exists and declares BLOCKING posture" {
  [ -f "$ATLAS_ROOT/skills/verify-incoming.md" ] || {
    echo "skills/verify-incoming.md not found in ATLAS repo"
    return 1
  }
  grep -qE 'REFUSE|SHALL NOT|blocking' "$ATLAS_ROOT/skills/verify-incoming.md" || {
    echo "skills/verify-incoming.md does not declare a BLOCKING posture (REFUSE/SHALL NOT/blocking)"
    return 1
  }
}

# ─── S2 ─────────────────────────────────────────────────────────────────────

@test "S2: skills/verify-incoming.md does NOT declare warn-only or process-anyway" {
  [ -f "$ATLAS_ROOT/skills/verify-incoming.md" ] || {
    echo "skills/verify-incoming.md not found"
    return 1
  }
  # Negative assertions — these exact prescriptive phrases would indicate
  # regression to the old warn-only posture (instructing the receiver to
  # continue processing despite a failed/absent verify_pass). Historical
  # contrast phrases ("superseded", "Blocking, not warn-only") are fine.
  run grep -E 'payload is always processed' \
    "$ATLAS_ROOT/skills/verify-incoming.md"
  [ "$status" -ne 0 ] || {
    echo "skills/verify-incoming.md contains 'payload is always processed' (warn-only regression):"
    echo "$output"
    return 1
  }
  # Ensure the skill does not prescribe WARN-ONLY mode as the current behavior.
  run grep -E 'WARN.ONLY|warn_only' \
    "$ATLAS_ROOT/skills/verify-incoming.md"
  [ "$status" -ne 0 ] || {
    echo "skills/verify-incoming.md contains WARN-ONLY language (regression):"
    echo "$output"
    return 1
  }
}

# ─── S3 ─────────────────────────────────────────────────────────────────────

@test "S3: install.sh installs skills/verify-incoming.md and records it in the manifest" {
  local install_target="$BATS_TEST_TMPDIR/install_target"
  mkdir -p "$install_target"

  # Run install.sh with --hosts raw to skip host-specific vendor writes
  # and keep the test hermetic (mirrors install_substitution.bats pattern).
  bash "$ATLAS_ROOT/install.sh" \
    --target "$install_target" \
    --hosts raw \
    --non-interactive \
    --force 2>/dev/null
  local rc=$?
  [ "$rc" -eq 0 ] || {
    echo "install.sh exited $rc (expected 0)"
    return 1
  }

  # The skill source-of-truth file must be present under the target.
  local skill_path="$install_target/skills/verify-incoming.md"
  [ -f "$skill_path" ] || {
    echo "skills/verify-incoming.md not found at $skill_path after install"
    ls "$install_target/skills/" 2>/dev/null || true
    return 1
  }

  # The install manifest must record verify-incoming in the skills array.
  local manifest="$install_target/install.manifest.json"
  [ -f "$manifest" ] || {
    echo "install.manifest.json not found at $manifest"
    return 1
  }

  grep -q '"verify-incoming"' "$manifest" || {
    echo "install.manifest.json does not contain \"verify-incoming\":"
    grep '"skills"' "$manifest" || true
    return 1
  }
}
