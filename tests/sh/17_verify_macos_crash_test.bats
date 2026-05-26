#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "17_verify_macos_crash_test.sh"
  copy_script_to_fixture "10_run_shell_unit_tests.sh"
  copy_script_to_fixture "16_run_macos_ui_regression_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/src/macos-ui"
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  copy_script_to_fixture "src/scripts/macos_ui_swift_lock.sh"
}

teardown() {
  teardown_shell_test
}

@test "verifies forced-crash replay persists crash artifacts" {
  #R001-T01 #R005-T01 #R010-T01 #R015-T01 #R015-T02 #R020-T01 #R020-T02 #R035-T01
  report_dir="${TEST_TMPDIR}/reports"
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo swift "\$*" >> "${CALLS_LOG}"
if [[ "\${TELLER_MACOS_FORCE_CRASH_ON_LAUNCH:-}" == "1" ]]; then
  exit 134
fi
mkdir -p "${report_dir}"
if [[ -f "${report_dir}/session-active.json" ]]; then
echo "{\"format\":\"unclean_exit\"}" > "${report_dir}/unclean-exit-smoke.json"
echo "CrashReporter: saved unclean termination marker to ${report_dir}/unclean-exit-smoke.json"
fi
echo "crash" > "${report_dir}/crash-smoke.plcrash"
echo "{}" > "${report_dir}/crash-smoke.json"
echo "CrashReporter: saved pending crash report to ${report_dir}/crash-smoke.plcrash"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"

  run bash -c "cd '${TEST_TMPDIR}' && MACOS_UI_DIR='${FIXTURE_ROOT}/src/macos-ui' CRASH_REPORT_DIR='${report_dir}' STARTUP_WAIT_SECONDS=2 '${FIXTURE_ROOT}/17_verify_macos_crash_test.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PLCrashReporter verification passed"* ]]
  [[ "$output" == *"${report_dir}/crash-smoke.plcrash"* ]]
  [[ "$output" == *"${report_dir}/crash-smoke.json"* ]]
}

@test "succeeds when relaunch captures persistence log before timeout" {
  report_dir="${TEST_TMPDIR}/reports-timeout"
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
if [[ "\${TELLER_MACOS_FORCE_CRASH_ON_LAUNCH:-}" == "1" ]]; then
  exit 134
fi
mkdir -p "${report_dir}"
if [[ -f "${report_dir}/session-active.json" ]]; then
echo "{\"format\":\"unclean_exit\"}" > "${report_dir}/unclean-exit-timeout.json"
echo "CrashReporter: saved unclean termination marker to ${report_dir}/unclean-exit-timeout.json"
fi
echo "crash" > "${report_dir}/crash-timeout.plcrash"
echo "{}" > "${report_dir}/crash-timeout.json"
echo "CrashReporter: saved pending crash report to ${report_dir}/crash-timeout.plcrash"
sleep 5
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"

  run env MACOS_UI_DIR="${FIXTURE_ROOT}/src/macos-ui" \
    CRASH_REPORT_DIR="${report_dir}" \
    STARTUP_WAIT_SECONDS=1 \
    bash "${FIXTURE_ROOT}/17_verify_macos_crash_test.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PLCrashReporter verification passed"* ]]
}

@test "recovers from stale SwiftPM checkout state and retries relaunch once" {
  #R045-T01
  report_dir="${TEST_TMPDIR}/reports-recovery"
  state_file="${TEST_TMPDIR}/recovery_state"
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "build" ]]; then
  exit 0
fi
if [[ "\$1" == "package" && "\$2" == "resolve" ]]; then
  echo resolved > "${state_file}"
  exit 0
fi
if [[ "\${TELLER_MACOS_FORCE_CRASH_ON_LAUNCH:-}" == "1" ]]; then
  exit 134
fi
if [[ ! -f "${state_file}" ]]; then
  echo "error: 'swift-custom-dump': the package at '${FIXTURE_ROOT}/src/macos-ui/.build/checkouts/swift-custom-dump' cannot be accessed (${FIXTURE_ROOT}/src/macos-ui/.build/checkouts/swift-custom-dump doesn't exist in file system)" >&2
  echo "error: the package at '${FIXTURE_ROOT}/src/macos-ui/.build/checkouts/swift-custom-dump' cannot be accessed (${FIXTURE_ROOT}/src/macos-ui/.build/checkouts/swift-custom-dump doesn't exist in file system)" >&2
  exit 1
fi
mkdir -p "${report_dir}"
if [[ -f "${report_dir}/session-active.json" ]]; then
echo "{\"format\":\"unclean_exit\"}" > "${report_dir}/unclean-exit-recovery.json"
echo "CrashReporter: saved unclean termination marker to ${report_dir}/unclean-exit-recovery.json"
fi
echo "crash" > "${report_dir}/crash-recovery.plcrash"
echo "{}" > "${report_dir}/crash-recovery.json"
echo "CrashReporter: saved pending crash report to ${report_dir}/crash-recovery.plcrash"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"

  run env MACOS_UI_DIR="${FIXTURE_ROOT}/src/macos-ui" \
    CRASH_REPORT_DIR="${report_dir}" \
    STARTUP_WAIT_SECONDS=2 \
    bash "${FIXTURE_ROOT}/17_verify_macos_crash_test.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Detected stale SwiftPM checkout state; repairing and retrying relaunch once"* ]]
  [[ "$output" == *"PLCrashReporter verification passed"* ]]
}

@test "fails quickly when relaunch does not emit persistence log" {
  #R050-T01
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
if [[ "\${TELLER_MACOS_FORCE_CRASH_ON_LAUNCH:-}" == "1" ]]; then
  exit 134
fi
sleep 5
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"

  run env MACOS_UI_DIR="${FIXTURE_ROOT}/src/macos-ui" \
    STARTUP_WAIT_SECONDS=1 \
    bash "${FIXTURE_ROOT}/17_verify_macos_crash_test.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"relaunch timed out before crash persistence log was observed"* ]]
}

@test "prewarms build before forced crash and relaunch runs" {
  #R060-T01
  report_dir="${TEST_TMPDIR}/reports-prewarm"
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo swift "\$*" >> "${CALLS_LOG}"
if [[ "\$1" == "build" ]]; then
  exit 0
fi
if [[ "\${TELLER_MACOS_FORCE_CRASH_ON_LAUNCH:-}" == "1" ]]; then
  exit 134
fi
mkdir -p "${report_dir}"
if [[ -f "${report_dir}/session-active.json" ]]; then
echo "{\"format\":\"unclean_exit\"}" > "${report_dir}/unclean-exit-prewarm.json"
echo "CrashReporter: saved unclean termination marker to ${report_dir}/unclean-exit-prewarm.json"
fi
echo "crash" > "${report_dir}/crash-prewarm.plcrash"
echo "{}" > "${report_dir}/crash-prewarm.json"
echo "CrashReporter: saved pending crash report to ${report_dir}/crash-prewarm.plcrash"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"

  run env MACOS_UI_DIR="${FIXTURE_ROOT}/src/macos-ui" \
    CRASH_REPORT_DIR="${report_dir}" \
    STARTUP_WAIT_SECONDS=2 \
    bash "${FIXTURE_ROOT}/17_verify_macos_crash_test.sh"
  [ "$status" -eq 0 ]

  first_call="$(sed -n '1p' "${CALLS_LOG}")"
  [[ "$first_call" == "swift build --product TransactionClassifier" ]]
  run_count="$(grep -c '^swift run TransactionClassifier$' "${CALLS_LOG}")"
  [ "$run_count" -eq 3 ]
}

@test "fails when unclean-marker replay log/artifact are missing" {
  #R065-T01
  report_dir="${TEST_TMPDIR}/reports-unclean-missing"
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "build" ]]; then
  exit 0
fi
if [[ "\${TELLER_MACOS_FORCE_CRASH_ON_LAUNCH:-}" == "1" ]]; then
  exit 134
fi
mkdir -p "${report_dir}"
echo "crash" > "${report_dir}/crash-unclean-missing.plcrash"
echo "{}" > "${report_dir}/crash-unclean-missing.json"
echo "CrashReporter: saved pending crash report to ${report_dir}/crash-unclean-missing.plcrash"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"

  run env MACOS_UI_DIR="${FIXTURE_ROOT}/src/macos-ui" \
    CRASH_REPORT_DIR="${report_dir}" \
    STARTUP_WAIT_SECONDS=1 \
    bash "${FIXTURE_ROOT}/17_verify_macos_crash_test.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unclean-marker relaunch"* ]]
}

@test "fails when forced-crash run exits zero" {
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo swift "\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"

  run env MACOS_UI_DIR="${FIXTURE_ROOT}/src/macos-ui" bash "${FIXTURE_ROOT}/17_verify_macos_crash_test.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected forced crash run to exit non-zero"* ]]
}

@test "fails with clear message when macos-ui path is missing" {
  #R030-T01 #R030-T02
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"

  run env MACOS_UI_DIR="${FIXTURE_ROOT}/missing-ui" bash "${FIXTURE_ROOT}/17_verify_macos_crash_test.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"macOS UI package path not found"* ]]
}

@test "remains standalone and is not chained by numbered runners" {
  #R040-T01
  run grep -E 'verify_macos_crash_test|CRASH_REPORTER_SMOKE' "${FIXTURE_ROOT}/10_run_shell_unit_tests.sh"
  [ "$status" -ne 0 ]

  run grep -E 'verify_macos_crash_test|CRASH_REPORTER_SMOKE' "${FIXTURE_ROOT}/16_run_macos_ui_regression_tests.sh"
  [ "$status" -ne 0 ]
}
