#!/usr/bin/env bats

# Requirement test-case tags for requirements/11_verify_macos_crash_test-requirements.md
# #R015-T02: Traceability anchor.
# #R020-T02: Traceability anchor.
# #R030-T02: Traceability anchor.

# Traceability numbered tags for requirements/11_verify_macos_crash_test-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.
# #R020-T01: Traceability anchor.
# #R030-T01: Traceability anchor.
# #R035-T01: Traceability anchor.
# #R040-T01: Traceability anchor.

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "11_verify_macos_crash_test.sh"
  copy_script_to_fixture "09_run_unit_tests.sh"
  copy_script_to_fixture "10_run_macos_ui_regression_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/macos-ui"
}

teardown() {
  teardown_shell_test
}

@test "verifies forced-crash replay persists crash artifacts" {
  #R001 #R005 #R010 #R015 #R020 #R035
  report_dir="${TEST_TMPDIR}/reports"
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo swift "\$*" >> "${CALLS_LOG}"
if [[ "\${TELLER_MACOS_FORCE_CRASH_ON_LAUNCH:-}" == "1" ]]; then
  exit 134
fi
mkdir -p "${report_dir}"
echo "crash" > "${report_dir}/crash-smoke.plcrash"
echo "{}" > "${report_dir}/crash-smoke.json"
echo "CrashReporter: saved pending crash report to ${report_dir}/crash-smoke.plcrash"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"

  run bash -c "cd '${TEST_TMPDIR}' && MACOS_UI_DIR='${FIXTURE_ROOT}/macos-ui' CRASH_REPORT_DIR='${report_dir}' STARTUP_WAIT_SECONDS=2 '${FIXTURE_ROOT}/11_verify_macos_crash_test.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PLCrashReporter verification passed"* ]]
  [[ "$output" == *"${report_dir}/crash-smoke.plcrash"* ]]
  [[ "$output" == *"${report_dir}/crash-smoke.json"* ]]
}

@test "fails when forced-crash run exits zero" {
  #R010
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo swift "\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"

  run env MACOS_UI_DIR="${FIXTURE_ROOT}/macos-ui" bash "${FIXTURE_ROOT}/11_verify_macos_crash_test.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected forced crash run to exit non-zero"* ]]
}

@test "fails with clear message when macos-ui path is missing" {
  #R030
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"

  run env MACOS_UI_DIR="${FIXTURE_ROOT}/missing-ui" bash "${FIXTURE_ROOT}/11_verify_macos_crash_test.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"macOS UI package path not found"* ]]
}

@test "remains standalone and is not chained by numbered runners" {
  #R040
  run grep -E 'verify_macos_crash_test|CRASH_REPORTER_SMOKE' "${FIXTURE_ROOT}/09_run_unit_tests.sh"
  [ "$status" -ne 0 ]

  run grep -E 'verify_macos_crash_test|CRASH_REPORTER_SMOKE' "${FIXTURE_ROOT}/10_run_macos_ui_regression_tests.sh"
  [ "$status" -ne 0 ]
}
