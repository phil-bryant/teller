#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "06_run_macos_ui_regression_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/macos-ui"
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
    ./06_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 1 ]
}

@test "resolves against repository root for relative paths" {
  #R005
  mkdir -p "${FIXTURE_ROOT}/macos-ui/TransactionClassifierUIAutomation.xcodeproj"
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
    ${FIXTURE_ROOT}/06_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$(grep -F -- '--package-path ./macos-ui' "${CALLS_LOG}" | head -1)" != "" ]]
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
    ./06_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  grep -F "ContentViewSnapshotTests" "${CALLS_LOG}"
  : > "${CALLS_LOG}"
  run bash -c "cd '${FIXTURE_ROOT}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    RUN_SNAPSHOT_TESTS=true SNAPSHOT_RECORD=true RUN_XCUITESTS=false \
    ./06_run_macos_ui_regression_tests.sh"
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
    ./06_run_macos_ui_regression_tests.sh"
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
    ./06_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  if grep -q "xcodebuild" "${CALLS_LOG}"; then
    return 1
  fi
  [[ "$output" == *"RUN_XCUITESTS=false"* ]]
}

@test "defaults run snapshot and xcodebuild when env vars unset" {
  #R030
  touch "${FIXTURE_ROOT}/macos-ui/TransactionClassifierUIAutomation.xcodeproj/placeholder" 2>/dev/null || \
    mkdir -p "${FIXTURE_ROOT}/macos-ui/TransactionClassifierUIAutomation.xcodeproj"
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
    ./06_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  grep "swift" "${CALLS_LOG}"
  grep "xcodebuild" "${CALLS_LOG}"
}

@test "passes xcodebuild project scheme destination and derived data overrides" {
  #R035
  mkdir -p "${FIXTURE_ROOT}/macos-ui/proj.xcodeproj"
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
    XCUITEST_PROJECT=./macos-ui/proj.xcodeproj \
    XCUITEST_SCHEME=CustomScheme \
    XCUITEST_DESTINATION=platform=macOS,arch=arm64 \
    XCUITEST_DERIVED_DATA_PATH=./macos-ui/.dd-ui \
    ./06_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  grep -F -- "-project" "${CALLS_LOG}" | grep -F "macos-ui/proj.xcodeproj"
  grep -F "CustomScheme" "${CALLS_LOG}"
  grep -F "platform=macOS,arch=arm64" "${CALLS_LOG}"
  grep -F "macos-ui/.dd-ui" "${CALLS_LOG}"
}

@test "runs only selected XCUITests by numeric selectors" {
  #R040
  mkdir -p "${FIXTURE_ROOT}/macos-ui/TransactionClassifierUIAutomation.xcodeproj"
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
    ./06_run_macos_ui_regression_tests.sh 1,3,5-6"
  [ "$status" -eq 0 ]

  grep -F "testSearchFilterFindsFixtureRow" "${CALLS_LOG}"
  grep -F "testApplyCategoryFromTypeaheadUpdatesSelection" "${CALLS_LOG}"
  grep -F "testUndoRestoresPriorCategoryOnAlreadyClassifiedRow" "${CALLS_LOG}"
  grep -F "testLoadMoreAppendsRowsAndUpdatesStatusText" "${CALLS_LOG}"

  if grep -q -- "-only-testing:TransactionClassifierUITests " "${CALLS_LOG}"; then
    return 1
  fi

  : > "${CALLS_LOG}"
  run bash -c "cd '${FIXTURE_ROOT}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    RUN_SNAPSHOT_TESTS=false RUN_XCUITESTS=true \
    ./06_run_macos_ui_regression_tests.sh 13"
  [ "$status" -eq 0 ]
  grep -F "testHelpMenuListsAllHotkeys" "${CALLS_LOG}"
}

@test "fails when selector references non-existent test numbers" {
  #R045
  mkdir -p "${FIXTURE_ROOT}/macos-ui/TransactionClassifierUIAutomation.xcodeproj"
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
    ./06_run_macos_ui_regression_tests.sh 99"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown UI regression test number"* ]]

  if grep -q "xcodebuild" "${CALLS_LOG}"; then
    return 1
  fi
}

@test "optionally runs crash reporter smoke verification lane" {
  #R050
  mkdir -p "${FIXTURE_ROOT}/macos-ui/TransactionClassifierUIAutomation.xcodeproj"
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
  cat > "${FIXTURE_ROOT}/17_verify_macos_crash_reporter.sh" <<EOF
#!/usr/bin/env bash
echo crash-smoke "\$@" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/17_verify_macos_crash_reporter.sh"

  run bash -c "cd '${FIXTURE_ROOT}' && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    RUN_SNAPSHOT_TESTS=false RUN_XCUITESTS=false RUN_CRASH_REPORTER_SMOKE_TEST=true \
    ./06_run_macos_ui_regression_tests.sh"
  [ "$status" -eq 0 ]
  grep -F "crash-smoke" "${CALLS_LOG}"
}
