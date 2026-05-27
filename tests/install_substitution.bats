#!/usr/bin/env bats
# tests/install_substitution.bats — T-SUBST-1 from SPEC-2026-05-27-ATLAS-ACI-UX-FIXES §6.1
#
# Validates P3-S3: the EIDOLON_VERSION from install.sh is substituted into the
# installed aci.sh's ATLAS_VERSION constant, eliminating the "stale constant" class
# of bug. The source commands/aci.sh carries __ATLAS_VERSION__ as a placeholder.

load helpers

# ─── T-SUBST-1 ────────────────────────────────────────────────────────────

@test "T-SUBST-1: installed aci.sh carries ATLAS_VERSION from install.sh EIDOLON_VERSION" {
  setup_fresh_project
  setup_stubs

  # Run install.sh into a temp target dir.
  local install_target="$BATS_TEST_TMPDIR/install_target"
  mkdir -p "$install_target"

  bash "$ATLAS_ROOT/install.sh" \
    --target "$install_target" \
    --hosts raw \
    --non-interactive \
    --force 2>/dev/null || true

  # The installed aci.sh must exist.
  local installed_aci="$install_target/commands/aci.sh"
  [ -f "$installed_aci" ] || {
    echo "Installed commands/aci.sh not found at $installed_aci"
    ls "$install_target/" 2>/dev/null || true
    return 1
  }

  # Extract ATLAS_VERSION from the installed script.
  local installed_ver
  installed_ver="$(grep '^ATLAS_VERSION=' "$installed_aci" | head -n1 | sed 's/ATLAS_VERSION="//;s/"//')"
  [ -n "$installed_ver" ] || {
    echo "Could not extract ATLAS_VERSION from installed aci.sh"
    grep 'ATLAS_VERSION' "$installed_aci" | head -n3
    return 1
  }

  # Extract EIDOLON_VERSION from install.sh.
  local install_ver
  install_ver="$(grep '^EIDOLON_VERSION=' "$ATLAS_ROOT/install.sh" | head -n1 | sed 's/EIDOLON_VERSION="//;s/"//')"
  [ -n "$install_ver" ] || {
    echo "Could not extract EIDOLON_VERSION from install.sh"
    return 1
  }

  # The versions must match.
  [ "$installed_ver" = "$install_ver" ] || {
    echo "Version mismatch:"
    echo "  install.sh EIDOLON_VERSION = '$install_ver'"
    echo "  installed  ATLAS_VERSION   = '$installed_ver'"
    return 1
  }

  # The placeholder must NOT appear in the installed version.
  if [ "$installed_ver" = "__ATLAS_VERSION__" ]; then
    echo "FAIL: placeholder __ATLAS_VERSION__ was not substituted in installed aci.sh"
    return 1
  fi
}
