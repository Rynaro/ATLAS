#!/usr/bin/env bats
# tests/verify-incoming.bats — verify-incoming skill gate tests.
#
# Asserts:
#   S1: skills/verify-incoming/SKILL.md exists in the repo and declares BLOCKING posture.
#   S2: skills/verify-incoming/SKILL.md does NOT declare warn-only / process-anyway.
#   S3: install.sh (non-interactive, into a temp target) installs
#       skills/verify-incoming/SKILL.md and records it in the install manifest.

load helpers

# ─── S1 ─────────────────────────────────────────────────────────────────────

@test "S1: skills/verify-incoming/SKILL.md exists and declares BLOCKING posture" {
  [ -f "$ATLAS_ROOT/skills/verify-incoming/SKILL.md" ] || {
    echo "skills/verify-incoming/SKILL.md not found in ATLAS repo"
    return 1
  }
  grep -qE 'REFUSE|SHALL NOT|blocking' "$ATLAS_ROOT/skills/verify-incoming/SKILL.md" || {
    echo "skills/verify-incoming/SKILL.md does not declare a BLOCKING posture (REFUSE/SHALL NOT/blocking)"
    return 1
  }
}

# ─── S2 ─────────────────────────────────────────────────────────────────────

@test "S2: skills/verify-incoming/SKILL.md does NOT declare warn-only or process-anyway" {
  [ -f "$ATLAS_ROOT/skills/verify-incoming/SKILL.md" ] || {
    echo "skills/verify-incoming/SKILL.md not found"
    return 1
  }
  # Negative assertions — these exact prescriptive phrases would indicate
  # regression to the old warn-only posture (instructing the receiver to
  # continue processing despite a failed/absent verify_pass). Historical
  # contrast phrases ("superseded", "Blocking, not warn-only") are fine.
  run grep -E 'payload is always processed' \
    "$ATLAS_ROOT/skills/verify-incoming/SKILL.md"
  [ "$status" -ne 0 ] || {
    echo "skills/verify-incoming/SKILL.md contains 'payload is always processed' (warn-only regression):"
    echo "$output"
    return 1
  }
  # Ensure the skill does not prescribe WARN-ONLY mode as the current behavior.
  run grep -E 'WARN.ONLY|warn_only' \
    "$ATLAS_ROOT/skills/verify-incoming/SKILL.md"
  [ "$status" -ne 0 ] || {
    echo "skills/verify-incoming/SKILL.md contains WARN-ONLY language (regression):"
    echo "$output"
    return 1
  }
}

# ─── S3 ─────────────────────────────────────────────────────────────────────
