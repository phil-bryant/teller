#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "t14_run_macos_ui_regression_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/src/macos-ui"
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  copy_script_to_fixture "src/scripts/macos_ui_swift_lock.sh"
  #R085: Make the Swift smoke suite available so delay-padding guards can scan it.
  mkdir -p "${FIXTURE_ROOT}/src/macos-ui/UITests"
  cp "$(repo_root)/src/macos-ui/UITests/TransactionClassifierUITests.swift" \
    "${FIXTURE_ROOT}/src/macos-ui/UITests/TransactionClassifierUITests.swift"
}

teardown() {
  teardown_shell_test
}

@test "fails when snapshot step fails" {
  #R001-T01
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo swift "\$@" >> "${CALLS_LOG}"
exit 1
EOF
  chmod +x "${STUB_BIN}/swift"
  cat > "${STUB_BIN}/xcodebuild" <<EOF
#!/usr/bin/env bash
echo xcodebuild "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/xcodebuild"
  run bash -c "cd '${FIXTURE_ROOT}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    RUN_SNAPSHOT_TESTS=true RUN_XCUITESTS=true \
    ./t14_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 1 ]
}

@test "resolves against repository root for relative paths" {
  #R005-T01
  mkdir -p "${FIXTURE_ROOT}/src/macos-ui/TransactionClassifierUIAutomation.xcodeproj"
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo swift "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
  cat > "${STUB_BIN}/xcodebuild" <<EOF
#!/usr/bin/env bash
echo xcodebuild "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/xcodebuild"
  run bash -c "cd '${TEST_TMPDIR}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    RUN_SNAPSHOT_TESTS=true RUN_XCUITESTS=true \
    ${FIXTURE_ROOT}/t14_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$(grep -F -- '--package-path ./src/macos-ui' "${CALLS_LOG}" | head -1)" != "" ]]
}

@test "snapshot lane honors RUN_SNAPSHOT_TESTS and snapshot record" {
  #R010-T01 #R010-T02 #R015-T01
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo swift "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
  cat > "${STUB_BIN}/xcodebuild" <<EOF
#!/usr/bin/env bash
echo xcodebuild "\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/xcodebuild"
  run bash -c "cd '${FIXTURE_ROOT}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    RUN_SNAPSHOT_TESTS=true RUN_XCUITESTS=false \
    ./t14_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  grep -F "ContentViewSnapshotTests" "${CALLS_LOG}"
  : > "${CALLS_LOG}"
  run bash -c "cd '${FIXTURE_ROOT}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    RUN_SNAPSHOT_TESTS=true SNAPSHOT_RECORD=true RUN_XCUITESTS=false \
    ./t14_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  grep -F "ContentViewSnapshotTests" "${CALLS_LOG}"
}

@test "XCUITest gate fails with missing xcode project" {
  #R020-T01 #R020-T02
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo swift "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
  cat > "${STUB_BIN}/xcodebuild" <<EOF
#!/usr/bin/env bash
echo xcodebuild "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/xcodebuild"
  run bash -c "cd '${FIXTURE_ROOT}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    RUN_SNAPSHOT_TESTS=false RUN_XCUITESTS=true \
    XCUITEST_PROJECT=./nope/TransactionClassifier.xcodeproj \
    ./t14_run_macos_ui_regression_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"XCUITest project not found"* ]]
}

@test "XCUITest runner exits promptly after post-success linger" {
  #R020-T03
  mkdir -p "${FIXTURE_ROOT}/src/macos-ui/TransactionClassifierUIAutomation.xcodeproj"
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo swift "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
  cat > "${STUB_BIN}/xcodebuild" <<EOF
#!/usr/bin/env bash
echo xcodebuild "\$@" >> "${CALLS_LOG}"
if [[ "\$1" == "-checkFirstLaunchStatus" ]]; then
  exit 0
fi
if [[ "\$1" == "-license" && "\$2" == "check" ]]; then
  exit 0
fi
printf '%s\n' "** TEST SUCCEEDED **"
while true; do
  :
done
EOF
  chmod +x "${STUB_BIN}/xcodebuild"
  run bash -c "cd '${FIXTURE_ROOT}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    RUN_SNAPSHOT_TESTS=false RUN_XCUITESTS=true \
    XCUITEST_TIMEOUT_SECONDS=8 XCUITEST_SUCCESS_GRACE_SECONDS=1 \
    ./t14_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reported success; stopping lingering xcodebuild"* ]]
}

@test "XCUITest can be disabled while snapshot runs" {
  #R025-T01
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo swift "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
  cat > "${STUB_BIN}/xcodebuild" <<EOF
#!/usr/bin/env bash
echo xcodebuild "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/xcodebuild"
  run bash -c "cd '${FIXTURE_ROOT}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    RUN_SNAPSHOT_TESTS=true RUN_XCUITESTS=false \
    ./t14_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  if grep -q "xcodebuild" "${CALLS_LOG}"; then
    return 1
  fi
  [[ "$output" == *"RUN_XCUITESTS=false"* ]]
}

@test "defaults run snapshot and xcodebuild when env vars unset" {
  #R030-T01 #R075-T01
  touch "${FIXTURE_ROOT}/src/macos-ui/TransactionClassifierUIAutomation.xcodeproj/placeholder" 2>/dev/null || \
    mkdir -p "${FIXTURE_ROOT}/src/macos-ui/TransactionClassifierUIAutomation.xcodeproj"
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo swift "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
  cat > "${STUB_BIN}/xcodebuild" <<EOF
#!/usr/bin/env bash
echo xcodebuild "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/xcodebuild"
  run bash -c "cd '${FIXTURE_ROOT}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    unset RUN_SNAPSHOT_TESTS RUN_XCUITESTS && \
    ./t14_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  grep "swift" "${CALLS_LOG}"
  grep "xcodebuild" "${CALLS_LOG}"
  [[ "$output" == *"1-33"* ]]
}

@test "extended profile includes advanced filter scenarios" {
  #R075-T02
  mkdir -p "${FIXTURE_ROOT}/src/macos-ui/TransactionClassifierUIAutomation.xcodeproj"
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo swift "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
  cat > "${STUB_BIN}/xcodebuild" <<EOF
#!/usr/bin/env bash
echo xcodebuild "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/xcodebuild"
  run bash -c "cd '${FIXTURE_ROOT}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    XCUITEST_PROFILE=extended \
    ./t14_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1-33"* ]]
}

@test "passes xcodebuild project scheme destination and derived data overrides" {
  #R035-T01
  mkdir -p "${FIXTURE_ROOT}/src/macos-ui/proj.xcodeproj"
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo swift "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
  cat > "${STUB_BIN}/xcodebuild" <<EOF
#!/usr/bin/env bash
echo xcodebuild "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/xcodebuild"
  run bash -c "cd '${FIXTURE_ROOT}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    RUN_SNAPSHOT_TESTS=false RUN_XCUITESTS=true \
    XCUITEST_PROJECT=./src/macos-ui/proj.xcodeproj \
    XCUITEST_SCHEME=CustomScheme \
    XCUITEST_DESTINATION=platform=macOS,arch=arm64 \
    XCUITEST_DERIVED_DATA_PATH=./src/macos-ui/.dd-ui \
    ./t14_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  grep -F -- "-project" "${CALLS_LOG}" | grep -F "src/macos-ui/proj.xcodeproj"
  grep -F "CustomScheme" "${CALLS_LOG}"
  grep -F "platform=macOS,arch=arm64" "${CALLS_LOG}"
  grep -F "src/macos-ui/.dd-ui" "${CALLS_LOG}"
}

@test "runs only selected XCUITest scenarios by numeric selectors" {
  #R040-T01
  mkdir -p "${FIXTURE_ROOT}/src/macos-ui/TransactionClassifierUIAutomation.xcodeproj"
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo swift "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
  cat > "${STUB_BIN}/xcodebuild" <<EOF
#!/usr/bin/env bash
echo "XCUITEST_STEPS=\${XCUITEST_STEPS:-}" >> "${CALLS_LOG}"
echo xcodebuild "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/xcodebuild"

  run bash -c "cd '${FIXTURE_ROOT}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    RUN_SNAPSHOT_TESTS=false RUN_XCUITESTS=true \
    ./t14_run_macos_ui_regression_tests.sh 1,3,5-6"
  [ "$status" -eq 0 ]

  grep -F "testMacOSUISmokeSuite" "${CALLS_LOG}"
  grep -F "XCUITEST_STEPS=1,3,5,6" "${CALLS_LOG}"
  [[ "$output" == *"Selecting XCUITest scenarios by index: 1,3,5-6"* ]]

  only_testing_count=$(grep -c -- "-only-testing:" "${CALLS_LOG}" || true)
  [ "$only_testing_count" -eq 1 ]

  : > "${CALLS_LOG}"
  run bash -c "cd '${FIXTURE_ROOT}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    RUN_SNAPSHOT_TESTS=false RUN_XCUITESTS=true \
    ./t14_run_macos_ui_regression_tests.sh 12"
  [ "$status" -eq 0 ]
  grep -F "testMacOSUISmokeSuite" "${CALLS_LOG}"
  grep -F "XCUITEST_STEPS=12" "${CALLS_LOG}"
}

@test "fails when selector references non-existent scenario numbers" {
  #R045-T01
  mkdir -p "${FIXTURE_ROOT}/src/macos-ui/TransactionClassifierUIAutomation.xcodeproj"
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo swift "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
  cat > "${STUB_BIN}/xcodebuild" <<EOF
#!/usr/bin/env bash
echo xcodebuild "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/xcodebuild"

  run bash -c "cd '${FIXTURE_ROOT}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    RUN_SNAPSHOT_TESTS=false RUN_XCUITESTS=true \
    ./t14_run_macos_ui_regression_tests.sh 99"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown UI regression scenario number"* ]]

  if grep -q "xcodebuild" "${CALLS_LOG}"; then
    return 1
  fi
}

@test "does not invoke macOS crash reporter verification script" {
  #R050-T01
  run grep -E 'verify_macos_crash_test|CRASH_REPORTER_SMOKE' "${FIXTURE_ROOT}/t14_run_macos_ui_regression_tests.sh"
  [ "$status" -ne 0 ]
}

@test "runner and swift suite avoid fixed sleep-based interaction padding" {
  #R085-T01
  run grep -nE '(^|[^[:alnum:]_])sleep[[:space:]]+[0-9]' "${FIXTURE_ROOT}/t14_run_macos_ui_regression_tests.sh"
  [ "$status" -ne 0 ]

  # The Swift smoke suite must also stay free of fixed interaction delays
  # (sleep()/usleep/Thread.sleep/Task.sleep/DispatchQueue.asyncAfter padding).
  run grep -nE 'sleep\(|usleep|asyncAfter' \
    "${FIXTURE_ROOT}/src/macos-ui/UITests/TransactionClassifierUITests.swift"
  [ "$status" -ne 0 ]
}
