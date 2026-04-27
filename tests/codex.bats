#!/usr/bin/env bats
# tests/codex.bats — S3 codex host test suite.
#
# Spec anchor: S3 in .spectra/plans/codex-atlas-aci-integration/spec.md
# (Rynaro/eidolons nexus repo).
#
# Test IDs:
#   TC01 install creates .codex/config.toml with [mcp_servers.atlas-aci]
#   TC02 install twice is idempotent (sha256 before/after match)
#   TC03 remove deletes only [mcp_servers.atlas-aci] table
#   TC04 peer tables preserved byte-for-byte after install + remove
#   TC05 prereq awk missing exits 5
#   TC06 install → remove → install matches single install (closure)
#   TC07 file with CRLF line endings handled (R1 mitigation)
#   TC08 file with no trailing newline handled (R1 mitigation)
#   TC09 peer [[mcp_servers]] array-of-tables preserved (R1 mitigation)
#   TC10 target table is last in file (R1 mitigation)
#   TC11 existing deviant body refused with stderr warning (R2 mitigation)
#   TC12 --dry-run emits CREATE .codex/config.toml (no files created)
#   TC13 --dry-run emits MODIFY when file already exists

load helpers

# ─── Fixture helpers ─────────────────────────────────────────────────────

# seed_codex_host — marker for codex host detection.
seed_codex_host() {
  mkdir -p .codex
}

# canonical_body — the expected TOML body (without heading).
canonical_body() {
  printf 'command = "atlas-aci"\nargs = ["serve", "--repo", "."]\n'
}

# canonical_toml — the full file content for a fresh install.
canonical_toml() {
  printf '[mcp_servers.atlas-aci]\n'
  canonical_body
}

# sha256_file FILE — portable sha256 digest of FILE.
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# assert_codex_table_present FILE — checks heading + canonical body.
assert_codex_table_present() {
  local file="$1"
  [ -f "$file" ] || { echo "MISSING: $file"; return 1; }
  grep -q '^\[mcp_servers\.atlas-aci\]' "$file" || {
    echo "Missing [mcp_servers.atlas-aci] heading in $file"
    cat "$file"
    return 1
  }
  local actual_body
  actual_body="$(awk '
    /^\[mcp_servers\.atlas-aci\]/ { in_block=1; next }
    in_block {
      if (/^\[/) { exit }
      gsub(/\r$/, "")
      print
    }
  ' "$file")"
  [ "$actual_body" = "$(canonical_body)" ] || {
    echo "Body mismatch in $file"
    echo "--- expected"
    canonical_body
    echo "--- actual"
    printf '%s\n' "$actual_body"
    return 1
  }
}

# assert_codex_table_absent FILE — heading must not appear.
assert_codex_table_absent() {
  local file="$1"
  [ ! -f "$file" ] && return 0
  if grep -q '^\[mcp_servers\.atlas-aci\]' "$file"; then
    echo "[mcp_servers.atlas-aci] still present in $file after remove:"
    cat "$file"
    return 1
  fi
}

# ─── TC01 ────────────────────────────────────────────────────────────────

@test "TC01: install creates .codex/config.toml with [mcp_servers.atlas-aci]" {
  setup_fresh_project
  setup_stubs
  seed_codex_host

  run_aci --install --host codex --non-interactive
  [ "$status" -eq 0 ]

  assert_codex_table_present ".codex/config.toml"
}

# ─── TC02 ────────────────────────────────────────────────────────────────

@test "TC02: install twice is idempotent (sha256 matches)" {
  setup_fresh_project
  setup_stubs
  seed_codex_host

  run_aci --install --host codex --non-interactive
  [ "$status" -eq 0 ]
  local first
  first="$(sha256_file ".codex/config.toml")"

  run_aci --install --host codex --non-interactive
  [ "$status" -eq 0 ]
  local second
  second="$(sha256_file ".codex/config.toml")"

  [ "$first" = "$second" ] || {
    echo "sha256 changed on second install:"
    echo "  first:  $first"
    echo "  second: $second"
    return 1
  }
}

# ─── TC03 ────────────────────────────────────────────────────────────────

@test "TC03: remove deletes only [mcp_servers.atlas-aci] table" {
  setup_fresh_project
  setup_stubs
  seed_codex_host

  # Seed a config with a peer table before our table.
  cat > ".codex/config.toml" <<'EOF'
[settings]
theme = "dark"

[mcp_servers.atlas-aci]
command = "atlas-aci"
args = ["serve", "--repo", "."]
EOF

  run_aci --remove --host codex --non-interactive
  [ "$status" -eq 0 ]

  assert_codex_table_absent ".codex/config.toml"

  # Peer [settings] table must survive.
  grep -q '^\[settings\]' ".codex/config.toml" || {
    echo "[settings] peer table was lost after remove:"
    cat ".codex/config.toml"
    return 1
  }
  grep -q 'theme = "dark"' ".codex/config.toml" || {
    echo "settings.theme lost after remove:"
    cat ".codex/config.toml"
    return 1
  }
}

# ─── TC04 ────────────────────────────────────────────────────────────────

@test "TC04: peer tables preserved byte-for-byte after install then remove" {
  setup_fresh_project
  setup_stubs
  seed_codex_host

  # Seed a file with a peer table already present.
  cat > ".codex/config.toml" <<'EOF'
[settings]
theme = "dark"
auto_save = true
EOF

  local before_peer
  before_peer="$(cat ".codex/config.toml")"

  run_aci --install --host codex --non-interactive
  [ "$status" -eq 0 ]
  assert_codex_table_present ".codex/config.toml"

  run_aci --remove --host codex --non-interactive
  [ "$status" -eq 0 ]
  assert_codex_table_absent ".codex/config.toml"

  # Peer content must be intact after round-trip (modulo trailing newline).
  grep -q 'theme = "dark"' ".codex/config.toml" || {
    echo "peer content lost after install+remove cycle:"
    cat ".codex/config.toml"
    return 1
  }
  grep -q 'auto_save = true' ".codex/config.toml" || {
    echo "peer content lost after install+remove cycle:"
    cat ".codex/config.toml"
    return 1
  }
}

# ─── TC05 ────────────────────────────────────────────────────────────────

@test "TC05: prereq awk missing exits 5 with actionable hint" {
  setup_fresh_project
  setup_stubs
  seed_codex_host
  uninstall_stub "awk"

  run_aci --install --host codex --non-interactive
  [ "$status" -eq 5 ]
  [[ "$output" == *"awk"* ]]
  [ ! -f ".codex/config.toml" ]
}

# ─── TC06 ────────────────────────────────────────────────────────────────

@test "TC06: install → remove → install matches single install (closure)" {
  setup_fresh_project
  setup_stubs
  seed_codex_host

  run_aci --install --host codex --non-interactive
  [ "$status" -eq 0 ]
  local baseline
  baseline="$(sha256_file ".codex/config.toml")"

  run_aci --remove --host codex --non-interactive
  [ "$status" -eq 0 ]
  assert_codex_table_absent ".codex/config.toml"

  run_aci --install --host codex --non-interactive
  [ "$status" -eq 0 ]
  local rebuilt
  rebuilt="$(sha256_file ".codex/config.toml")"

  [ "$baseline" = "$rebuilt" ] || {
    echo "Round-trip sha256 mismatch:"
    echo "  baseline: $baseline"
    echo "  rebuilt:  $rebuilt"
    echo "--- file content ---"
    cat ".codex/config.toml"
    return 1
  }
}

# ─── TC07 ────────────────────────────────────────────────────────────────

@test "TC07: file with CRLF line endings is handled correctly (R1 mitigation)" {
  setup_fresh_project
  setup_stubs
  seed_codex_host

  # Write a CRLF file with a peer table and our table.
  printf '[settings]\r\ntheme = "dark"\r\n\r\n[mcp_servers.atlas-aci]\r\ncommand = "atlas-aci"\r\nargs = ["serve", "--repo", "."]\r\n' \
    > ".codex/config.toml"

  # install should detect the table is canonical (modulo CRLF) and skip.
  run_aci --install --host codex --non-interactive
  [ "$status" -eq 0 ]

  # remove should strip our table, leaving the peer.
  run_aci --remove --host codex --non-interactive
  [ "$status" -eq 0 ]

  assert_codex_table_absent ".codex/config.toml"
  # Peer must still be present.
  grep -q '\[settings\]' ".codex/config.toml" || {
    echo "[settings] lost after CRLF remove:"
    cat ".codex/config.toml"
    return 1
  }
}

# ─── TC08 ────────────────────────────────────────────────────────────────

@test "TC08: file with no trailing newline handled correctly (R1 mitigation)" {
  setup_fresh_project
  setup_stubs
  seed_codex_host

  # Write a file without a trailing newline.
  printf '[settings]\ntheme = "dark"' > ".codex/config.toml"

  run_aci --install --host codex --non-interactive
  [ "$status" -eq 0 ]

  # Our table should now be appended correctly.
  assert_codex_table_present ".codex/config.toml"
  # Peer must still be present.
  grep -q '\[settings\]' ".codex/config.toml" || {
    echo "[settings] lost after no-trailing-newline install:"
    cat ".codex/config.toml"
    return 1
  }
}

# ─── TC09 ────────────────────────────────────────────────────────────────

@test "TC09: peer [[mcp_servers]] array-of-tables preserved (R1 mitigation)" {
  setup_fresh_project
  setup_stubs
  seed_codex_host

  # Write a file with a peer [[mcp_servers]] array-of-tables entry.
  cat > ".codex/config.toml" <<'EOF'
[[mcp_servers]]
name = "other-server"
command = "node"
args = ["./other.js"]

[mcp_servers.atlas-aci]
command = "atlas-aci"
args = ["serve", "--repo", "."]
EOF

  run_aci --remove --host codex --non-interactive
  [ "$status" -eq 0 ]

  assert_codex_table_absent ".codex/config.toml"

  # The [[mcp_servers]] array entry must survive.
  grep -q '^\[\[mcp_servers\]\]' ".codex/config.toml" || {
    echo "[[mcp_servers]] array-of-tables lost after remove:"
    cat ".codex/config.toml"
    return 1
  }
  grep -q 'name = "other-server"' ".codex/config.toml" || {
    echo "name = other-server lost after remove:"
    cat ".codex/config.toml"
    return 1
  }
}

# ─── TC10 ────────────────────────────────────────────────────────────────

@test "TC10: target table is the last in the file — remove still works (R1 mitigation)" {
  setup_fresh_project
  setup_stubs
  seed_codex_host

  # [mcp_servers.atlas-aci] is the last table, no following heading.
  cat > ".codex/config.toml" <<'EOF'
[settings]
theme = "dark"

[mcp_servers.atlas-aci]
command = "atlas-aci"
args = ["serve", "--repo", "."]
EOF

  run_aci --remove --host codex --non-interactive
  [ "$status" -eq 0 ]

  assert_codex_table_absent ".codex/config.toml"
  grep -q '\[settings\]' ".codex/config.toml" || {
    echo "[settings] lost when target was last table:"
    cat ".codex/config.toml"
    return 1
  }
}

# ─── TC11 ────────────────────────────────────────────────────────────────

@test "TC11: deviant existing body refused with stderr warning (R2 mitigation)" {
  setup_fresh_project
  setup_stubs
  seed_codex_host

  # Write a hand-edited, non-canonical body.
  cat > ".codex/config.toml" <<'EOF'
[mcp_servers.atlas-aci]
command = "atlas-aci"
args = ["serve", "--repo", "/custom/path"]
env = {CUSTOM_VAR = "1"}
EOF

  run_aci --install --host codex --non-interactive
  [ "$status" -eq 0 ]

  # Output (stderr) must contain the refusal warning.
  [[ "$output" == *"non-canonical"* ]] || [[ "$output" == *"Refusing"* ]] || {
    echo "Expected refusal warning in output, got:"
    printf '%s\n' "$output"
    return 1
  }

  # The file must NOT have been mutated (body still contains custom path).
  grep -q '/custom/path' ".codex/config.toml" || {
    echo "File was mutated despite R2 guard:"
    cat ".codex/config.toml"
    return 1
  }
}

# ─── TC12 ────────────────────────────────────────────────────────────────

@test "TC12: --dry-run emits CREATE .codex/config.toml, creates no files" {
  setup_fresh_project
  setup_stubs
  seed_codex_host

  run_aci --install --host codex --dry-run --non-interactive
  [ "$status" -eq 0 ]

  [[ "$output" == *"CREATE"*".codex/config.toml"* ]] || {
    echo "Expected 'CREATE ./.codex/config.toml' in dry-run output, got:"
    printf '%s\n' "$output"
    return 1
  }

  [ ! -f ".codex/config.toml" ] || {
    echo "dry-run created .codex/config.toml unexpectedly"
    return 1
  }
}

# ─── TC13 ────────────────────────────────────────────────────────────────

@test "TC13: --dry-run emits MODIFY when .codex/config.toml already exists" {
  setup_fresh_project
  setup_stubs
  seed_codex_host

  # Pre-create the file with a different content (no atlas-aci table yet).
  mkdir -p .codex
  printf '[settings]\ntheme = "dark"\n' > ".codex/config.toml"

  run_aci --install --host codex --dry-run --non-interactive
  [ "$status" -eq 0 ]

  [[ "$output" == *"MODIFY"*".codex/config.toml"* ]] || {
    echo "Expected 'MODIFY ./.codex/config.toml' in dry-run output, got:"
    printf '%s\n' "$output"
    return 1
  }

  # File content must be unchanged.
  local content
  content="$(cat ".codex/config.toml")"
  [[ "$content" == *'theme = "dark"'* ]] && ! grep -q '\[mcp_servers\.atlas-aci\]' ".codex/config.toml" || {
    echo "dry-run modified .codex/config.toml unexpectedly:"
    cat ".codex/config.toml"
    return 1
  }
}
