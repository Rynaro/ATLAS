#!/usr/bin/env bats
# tests/ecl-2.0.bats — ECL 2.0 adoption sweep tests.
#
# Asserts:
#   E1: schemas/ecl-envelope.v2.json exists, is valid JSON, and the legacy
#       schemas/ecl-envelope.v1.json is gone (superseded, not duplicated).
#   E2: templates/scout-report.envelope.json declares envelope_version "2.0"
#       and references the v2 schema in its guidance comment.
#   E3: templates/scout-report.envelope.json carries an `ise` block with
#       assertion_grade "self-attested" and the receiver_authorization triple.
#   E4: schemas/ecl-envelope.v2.json's ise $def requires assertion_grade and
#       enumerates the four ECL v2.0 §6.5 grades.
#   D1: no stale "ECL v1.0" prose remains outside CHANGELOG.md (historical).
#   D2: no stale "ecl-envelope.v1" path reference remains outside
#       CHANGELOG.md (historical).
#   H1: skills/esl-hop.md exists, names the DISCOVER hop, and preserves the
#       read-only refusal boundary (never calls a tonberry write verb).
#   H2: agent.md wires skills/esl-hop.md into its skill-load table.
#   H3: install.sh installs skills/esl-hop.md and records it in the manifest
#       (mirrors the verify-incoming.bats S3 pattern).
#   T1: agent.md stays within the ≤1000-token budget after this sweep.

load helpers

# ─── E1 ─────────────────────────────────────────────────────────────────────

@test "E1: schemas/ecl-envelope.v2.json exists and is valid JSON; v1 is gone" {
  [ -f "$ATLAS_ROOT/schemas/ecl-envelope.v2.json" ] || {
    echo "schemas/ecl-envelope.v2.json not found"
    return 1
  }
  run jq empty "$ATLAS_ROOT/schemas/ecl-envelope.v2.json"
  [ "$status" -eq 0 ] || {
    echo "schemas/ecl-envelope.v2.json is not valid JSON:"
    echo "$output"
    return 1
  }
  [ ! -f "$ATLAS_ROOT/schemas/ecl-envelope.v1.json" ] || {
    echo "schemas/ecl-envelope.v1.json still present — should be superseded by v2, not duplicated"
    return 1
  }
}

# ─── E2 ─────────────────────────────────────────────────────────────────────

@test "E2: scout-report.envelope.json template declares envelope_version 2.0" {
  local tmpl="$ATLAS_ROOT/templates/scout-report.envelope.json"
  [ -f "$tmpl" ] || {
    echo "templates/scout-report.envelope.json not found"
    return 1
  }
  run jq -r '.envelope_version' "$tmpl"
  [ "$status" -eq 0 ] && [ "$output" = "2.0" ] || {
    echo "envelope_version is not \"2.0\": got '$output'"
    return 1
  }
  grep -q 'ecl-envelope.v2.json' "$tmpl" || {
    echo "template guidance comment does not reference schemas/ecl-envelope.v2.json"
    return 1
  }
}

# ─── E3 ─────────────────────────────────────────────────────────────────────

@test "E3: scout-report.envelope.json template carries a self-attested ise block" {
  local tmpl="$ATLAS_ROOT/templates/scout-report.envelope.json"
  run jq -r '.ise.assertion_grade' "$tmpl"
  [ "$status" -eq 0 ] && [ "$output" = "self-attested" ] || {
    echo "ise.assertion_grade is not \"self-attested\": got '$output'"
    return 1
  }
  run jq -r '.ise.receiver_authorization.auto_route' "$tmpl"
  [ "$output" = "true" ] || { echo "ise.receiver_authorization.auto_route != true"; return 1; }
  run jq -r '.ise.receiver_authorization.auto_merge' "$tmpl"
  [ "$output" = "false" ] || { echo "ise.receiver_authorization.auto_merge != false"; return 1; }
  run jq -r '.ise.receiver_authorization.auto_deploy' "$tmpl"
  [ "$output" = "false" ] || { echo "ise.receiver_authorization.auto_deploy != false"; return 1; }
  run jq -r '.ise.provenance.methodology_version' "$tmpl"
  case "$output" in
    atlas-*) : ;;
    *) echo "ise.provenance.methodology_version does not start with 'atlas-': got '$output'"; return 1 ;;
  esac
}

# ─── E4 ─────────────────────────────────────────────────────────────────────

@test "E4: vendored v2 schema requires ise.assertion_grade with the four ECL grades" {
  local schema="$ATLAS_ROOT/schemas/ecl-envelope.v2.json"
  run jq -e '.["$defs"].ise.required | index("assertion_grade")' "$schema"
  [ "$status" -eq 0 ] || {
    echo "ise \$def does not require assertion_grade"
    return 1
  }
  run jq -r '.["$defs"].ise.properties.assertion_grade.enum | sort | join(",")' "$schema"
  [ "$output" = "human-reviewed,self-attested,unverified,validated" ] || {
    echo "assertion_grade enum mismatch: got '$output'"
    return 1
  }
}

# ─── D1 ─────────────────────────────────────────────────────────────────────

@test "D1: no stale 'ECL v1.0' prose remains outside CHANGELOG.md" {
  run grep -rn "ECL v1\.0" \
    --include="*.md" --include="*.sh" --include="*.json" \
    "$ATLAS_ROOT"
  if [ "$status" -eq 0 ]; then
    local leftover
    leftover="$(printf '%s\n' "$output" | grep -v '/CHANGELOG\.md:' || true)"
    [ -z "$leftover" ] || {
      echo "Stale 'ECL v1.0' prose found outside CHANGELOG.md:"
      echo "$leftover"
      return 1
    }
  fi
}

# ─── D2 ─────────────────────────────────────────────────────────────────────

@test "D2: no stale 'ecl-envelope.v1' path reference remains outside CHANGELOG.md" {
  run grep -rn "ecl-envelope\.v1" \
    --include="*.md" --include="*.sh" --include="*.json" \
    "$ATLAS_ROOT"
  if [ "$status" -eq 0 ]; then
    local leftover
    leftover="$(printf '%s\n' "$output" | grep -v '/CHANGELOG\.md:' || true)"
    [ -z "$leftover" ] || {
      echo "Stale 'ecl-envelope.v1' reference found outside CHANGELOG.md:"
      echo "$leftover"
      return 1
    }
  fi
}

# ─── H1 ─────────────────────────────────────────────────────────────────────

@test "H1: skills/esl-hop.md exists, names the DISCOVER hop, preserves refusal boundary" {
  local skill="$ATLAS_ROOT/skills/esl-hop.md"
  [ -f "$skill" ] || {
    echo "skills/esl-hop.md not found"
    return 1
  }
  grep -qi 'DISCOVER' "$skill" || {
    echo "skills/esl-hop.md does not name the DISCOVER hop"
    return 1
  }
  grep -q 'proposed' "$skill" || {
    echo "skills/esl-hop.md does not mention the 'proposed' ESL stage"
    return 1
  }
  # Refusal boundary: ATLAS must never call a tonberry write verb itself.
  grep -q 'never calls a tonberry write verb' "$skill" || {
    echo "skills/esl-hop.md does not explicitly state it never calls a tonberry write verb"
    return 1
  }
  # Negative assertion: the skill must not itself invoke a tonberry write verb.
  run grep -E 'mcp__tonberry__(propose|transition|archive|verify)\(' "$skill"
  [ "$status" -ne 0 ] || {
    echo "skills/esl-hop.md appears to invoke a tonberry write verb directly (boundary regression):"
    echo "$output"
    return 1
  }
}

# ─── H2 ─────────────────────────────────────────────────────────────────────

@test "H2: agent.md wires skills/esl-hop.md into the skill-load table" {
  grep -q 'skills/esl-hop.md' "$ATLAS_ROOT/agent.md" || {
    echo "agent.md does not reference skills/esl-hop.md"
    return 1
  }
}

# ─── H3 ─────────────────────────────────────────────────────────────────────

@test "H3: install.sh installs skills/esl-hop.md and records it in the manifest" {
  local install_target="$BATS_TEST_TMPDIR/install_target"
  mkdir -p "$install_target"

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

  local skill_path="$install_target/skills/esl-hop.md"
  [ -f "$skill_path" ] || {
    echo "skills/esl-hop.md not found at $skill_path after install"
    ls "$install_target/skills/" 2>/dev/null || true
    return 1
  }

  local schema_path="$install_target/schemas/ecl-envelope.v2.json"
  [ -f "$schema_path" ] || {
    echo "schemas/ecl-envelope.v2.json not found at $schema_path after install"
    ls "$install_target/schemas/" 2>/dev/null || true
    return 1
  }
  [ ! -f "$install_target/schemas/ecl-envelope.v1.json" ] || {
    echo "stale schemas/ecl-envelope.v1.json was installed — should be v2 only"
    return 1
  }

  local manifest="$install_target/install.manifest.json"
  [ -f "$manifest" ] || {
    echo "install.manifest.json not found at $manifest"
    return 1
  }

  grep -q '"esl-hop"' "$manifest" || {
    echo "install.manifest.json does not contain \"esl-hop\":"
    grep '"skills"' "$manifest" || true
    return 1
  }

  run jq -r '.ecl_version_emitted' "$manifest"
  [ "$output" = "2.0" ] || {
    echo "manifest ecl_version_emitted is not \"2.0\": got '$output'"
    return 1
  }
}

# ─── T1 ─────────────────────────────────────────────────────────────────────

@test "T1: agent.md stays within the <=1000-token budget" {
  local words tokens
  words=$(wc -w < "$ATLAS_ROOT/agent.md")
  tokens=$(awk "BEGIN {printf \"%d\", ${words}/0.75}")
  [ "$tokens" -le 1000 ] || {
    echo "agent.md estimated at ${tokens} tokens (words=${words}), exceeds the 1000-token budget"
    return 1
  }
}
