#!/usr/bin/env bats
# tests/install_substitution.bats — T-SUBST-1 from SPEC-2026-05-27-ATLAS-ACI-UX-FIXES §6.1
#
# Validates P3-S3: the EIDOLON_VERSION from install.sh is substituted into the
# installed aci.sh's ATLAS_VERSION constant, eliminating the "stale constant" class
# of bug. The source commands/aci.sh carries __ATLAS_VERSION__ as a placeholder.

load helpers

# ─── T-SUBST-1 ────────────────────────────────────────────────────────────
