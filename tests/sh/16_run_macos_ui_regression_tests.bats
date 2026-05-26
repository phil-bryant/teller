#!/usr/bin/env bats

# Requirement test-case tags for requirements/16_run_macos_ui_regression_tests-requirements.md
# #R010-T02: Traceability anchor.
# #R020-T02: Traceability anchor.

# Traceability numbered tags for requirements/16_run_macos_ui_regression_tests-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.
# #R020-T01: Traceability anchor.
# #R025-T01: Traceability anchor.
# #R030-T01: Traceability anchor.
# #R035-T01: Traceability anchor.
# #R040-T01: Traceability anchor.
# #R045-T01: Traceability anchor.
# #R050-T01: Traceability anchor.

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "16_run_macos_ui_regression_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/src/macos-ui"
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  copy_script_to_fixture "src/scripts/macos_ui_swift_lock.sh"
}

teardown() {
  teardown_shell_test
}

@test "fails when snapshot step fails" {
  #R001
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
    ./16_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 1 ]
}

@test "resolves against repository root for relative paths" {
  #R005
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
    ${FIXTURE_ROOT}/16_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$(grep -F -- '--package-path ./src/macos-ui' "${CALLS_LOG}" | head -1)" != "" ]]
}

@test "snapshot lane honors RUN_SNAPSHOT_TESTS and snapshot record" {
  #R010 #R015
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
    ./16_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  grep -F "ContentViewSnapshotTests" "${CALLS_LOG}"
  : > "${CALLS_LOG}"
  run bash -c "cd '${FIXTURE_ROOT}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    RUN_SNAPSHOT_TESTS=true SNAPSHOT_RECORD=true RUN_XCUITESTS=false \
    ./16_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  grep -F "ContentViewSnapshotTests" "${CALLS_LOG}"
}

@test "XCUITest gate fails with missing xcode project" {
  #R020
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
    ./16_run_macos_ui_regression_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"XCUITest project not found"* ]]
}

@test "XCUITest can be disabled while snapshot runs" {
  #R025
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
    ./16_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  if grep -q "xcodebuild" "${CALLS_LOG}"; then
    return 1
  fi
  [[ "$output" == *"RUN_XCUITESTS=false"* ]]
}

@test "defaults run snapshot and xcodebuild when env vars unset" {
  #R030
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
    ./16_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  grep "swift" "${CALLS_LOG}"
  grep "xcodebuild" "${CALLS_LOG}"
}

@test "passes xcodebuild project scheme destination and derived data overrides" {
  #R035
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
    ./16_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  grep -F -- "-project" "${CALLS_LOG}" | grep -F "src/macos-ui/proj.xcodeproj"
  grep -F "CustomScheme" "${CALLS_LOG}"
  grep -F "platform=macOS,arch=arm64" "${CALLS_LOG}"
  grep -F "src/macos-ui/.dd-ui" "${CALLS_LOG}"
}

@test "runs only selected XCUITest scenarios by numeric selectors" {
  #R040
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
    ./16_run_macos_ui_regression_tests.sh 1,3,5-6"
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
    ./16_run_macos_ui_regression_tests.sh 12"
  [ "$status" -eq 0 ]
  grep -F "testMacOSUISmokeSuite" "${CALLS_LOG}"
  grep -F "XCUITEST_STEPS=12" "${CALLS_LOG}"
}

@test "fails when selector references non-existent scenario numbers" {
  #R045
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
    ./16_run_macos_ui_regression_tests.sh 99"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown UI regression scenario number"* ]]

  if grep -q "xcodebuild" "${CALLS_LOG}"; then
    return 1
  fi
}

@test "does not invoke macOS crash reporter verification script" {
  #R050
  run grep -E 'verify_macos_crash_test|CRASH_REPORTER_SMOKE' "${FIXTURE_ROOT}/16_run_macos_ui_regression_tests.sh"
  [ "$status" -ne 0 ]
}
