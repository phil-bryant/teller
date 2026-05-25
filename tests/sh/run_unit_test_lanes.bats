#!/usr/bin/env bats

# Requirement test-case tags for requirements/src/scripts/run_unit_test_lanes-requirements.md
# #R001-T01: Verify repo-root execution and lane toggles.
# #R005-T01: Verify SQL preflight failures fail fast with clear diagnostics.
# #R010-T01: Verify Swift lane uses lock helper and stale-cache retry path.
# #R015-T01: Verify lane failures propagate non-zero status.
# #R020-T01: Verify stale-checkout-only retry behavior.
# #R025-T01: Verify DB profile export helper is required for SQL lane preflight.
# #R030-T01: Verify helper keeps crash verification out of shared unit-test lanes.
# #R035-T01: Verify setup diagnostics on DB profile export failures.

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  mkdir -p "${FIXTURE_ROOT}/src/scripts" "${FIXTURE_ROOT}/src/macos-ui/Tests"
  cp "$(repo_root)/src/scripts/run_unit_test_lanes.sh" "${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh"
  chmod +x "${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh"
}

teardown() {
  teardown_shell_test
}

@test "runs from repo root and honors disabled lanes" {
  #R001 #R030
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=local"
echo "PG_HOST=localhost"
echo "PG_PORT=5432"
echo "PG_DBNAME=prod"
echo "PG_USER=teller"
echo "PG_SSLMODE=disable"
echo "PG_ONEPSA_ITEM=localhost_postgres_teller"
echo "PWD_CAPTURE=$(pwd)"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"

  run bash -c "
    cd '${TEST_TMPDIR}'
    RUN_SHELL_TESTS=false RUN_PYTHON_TESTS=false RUN_SQL_TESTS=false RUN_SWIFT_TESTS=false \
      '${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh'
  "
  [ "$status" -eq 0 ]
}

@test "fails fast when db profile helper is missing" {
  #R005 #R025 #R035 #R015
  run bash -c "
    cd '${FIXTURE_ROOT}'
    RUN_SHELL_TESTS=false RUN_PYTHON_TESTS=false RUN_SQL_TESTS=false RUN_SWIFT_TESTS=false \
      '${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh'
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"DB profile helper is missing or not executable"* ]]
}

@test "swift lane invokes lock helper and retries stale-cache failure once" {
  #R010 #R020 #R015
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=local"
echo "PG_HOST=localhost"
echo "PG_PORT=5432"
echo "PG_DBNAME=prod"
echo "PG_USER=teller"
echo "PG_SSLMODE=disable"
echo "PG_ONEPSA_ITEM=localhost_postgres_teller"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"

  cat > "${FIXTURE_ROOT}/src/scripts/macos_ui_swift_lock.sh" <<'EOF'
#!/usr/bin/env bash
macos_ui_with_swiftpm_lock() {
  echo "lock:$1:$2:$3" >> "${CALLS_LOG}"
  shift 3
  "$@"
}
EOF

  cat > "${STUB_BIN}/swift" <<'EOF'
#!/usr/bin/env bash
echo "swift $*" >> "${CALLS_LOG}"
if [[ "$*" == *"swift test --package-path ./src/macos-ui"* ]]; then
  marker="${TEST_TMPDIR}/swift-first"
  if [[ ! -f "$marker" ]]; then
    touch "$marker"
    echo "cannot be accessed .build/" >&2
    exit 1
  fi
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"

  run bash -c "
    cd '${FIXTURE_ROOT}'
    RUN_SHELL_TESTS=false RUN_PYTHON_TESTS=false RUN_SQL_TESTS=false RUN_SWIFT_TESTS=true \
      '${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh'
  "
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"lock:"* ]]
  [[ "$calls" == *"swift test --package-path ./src/macos-ui"* ]]
}
