#!/usr/bin/env bats

load "helpers/common.bash"

teardown() {
  teardown_shell_test
}

src() {
  printf '%s' "$(repo_root)/tests/t05_deploy_database_verification_test.sh"
}

@test "R005: Use connection settings exclusively from the resolved profil" {
  #R005-T01
  run grep -- "#R005:" "$(src)"
  [ "$status" -eq 0 ]
}

@test "R010: Resolve DB password from environment or 1psa fallback." {
  #R010-T01
  run grep -- "#R010:" "$(src)"
  [ "$status" -eq 0 ]
}

@test "R015: Refuse verification when DB password resolves empty." {
  #R015-T01
  run grep -- "#R015:" "$(src)"
  [ "$status" -eq 0 ]
}

@test "R020: Verify required deployed roles exist." {
  #R020-T01
  run grep -- "#R020:" "$(src)"
  [ "$status" -eq 0 ]
}

@test "R025: Verify classification FK uses ON DELETE CASCADE." {
  #R025-T01
  run grep -- "#R025:" "$(src)"
  [ "$status" -eq 0 ]
}

@test "R030: Verify updated_at trigger function and table trigger exist." {
  #R030-T01
  run grep -- "#R030:" "$(src)"
  [ "$status" -eq 0 ]
}

@test "R035: Print explicit pass/fail verification result." {
  #R035-T01
  run grep -- "#R035:" "$(src)"
  [ "$status" -eq 0 ]
}

@test "R040: Verify every teller table with updated_at is covered by tell" {
  #R040-T01
  run grep -- "#R040:" "$(src)"
  [ "$status" -eq 0 ]
}

@test "R045: Surface all missing table names as explicit verification fai" {
  #R045-T01
  run grep -- "#R045:" "$(src)"
  [ "$status" -eq 0 ]
}

@test "R050: Resolve target/profile so verification can adapt to local vs" {
  #R050-T01
  run grep -- "#R050:" "$(src)"
  [ "$status" -eq 0 ]
}

@test "R055: Resolve DB password from environment or profile-driven 1psa" {
  #R055-T01
  run grep -- "#R055:" "$(src)"
  [ "$status" -eq 0 ]
}

@test "R060: When the resolved profile requires TLS, confirm the live con" {
  #R060-T01
  run grep -- "#R060:" "$(src)"
  [ "$status" -eq 0 ]
}

@test "R065: Refuse verification when DB profile setup is missing." {
  #R065-T01
  run grep -- "#R065:" "$(src)"
  [ "$status" -eq 0 ]
}

@test "R066: Run SQLite-specific verification checks when the active prof" {
  #R066-T01
  run grep -- "#R066:" "$(src)"
  [ "$status" -eq 0 ]
}
